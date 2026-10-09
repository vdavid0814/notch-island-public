import Foundation
import MetricKit
import Sentry

/// Crashes, errors and health numbers to Sentry and Mixpanel (EU), in place of the Discord reports.
/// Only while the user allows diagnostics (About ▸ Diagnostics): `start` and `stop` follow the
/// switch. `DiagnosticsCenter` still collects, compares and reads the reports; this sends what
/// they found, in one of two modes:
///
/// - **Standard** (the default): nothing of Sentry's runs between reports. Each report starts the
///   SDK, sends and closes it again. Crashes and hangs come from macOS's own records (crash
///   reporter `.ips`, MetricKit), rebuilt as native Sentry events (`NativeCrash`) that Sentry
///   symbolicates with the build's dSYM, so no crash handler has to run. At rest the app costs what
///   it cost before Sentry (0.2 wakeups a second, docs/ENERGY-LOG.md).
/// - **Detailed** (About ▸ Detailed Diagnostics): the SDK runs all the time, with its crash
///   handler (the crash with the app's own state and the steps before it), its App Hang watcher,
///   the system's events as breadcrumbs and the user's flow with what was typed; the whole report
///   goes every hour.
///
/// In both: every likely cause as an issue of its own (grouped by the check's id across Macs),
/// NotchIsland's own error lines, the whole report when asked for or something happened, bug
/// reports and requests as user feedback, and Mixpanel's numbers per report.
@MainActor final class Telemetry {
    nonisolated enum Mode: String, Sendable { case standard, detailed }

    let config: TelemetryConfig
    private let defaults: UserDefaults
    private let queueFile: URL?
    private(set) var mixpanel: MixpanelClient?
    private(set) var isRunning = false
    private(set) var mode: Mode = .standard
    /// The steps before a report (`DiagnosticsFlow`): breadcrumbs of the events a standard-mode
    /// delivery sends, as the SDK is not there to collect them meanwhile.
    var flow: () -> [String] = { [] }
    private var identity: (installID: String, sender: String, version: String, build: String)?

    /// A likely cause or an error line goes to Sentry at most once in this long per Mac: Sentry
    /// counts the Macs it is on, not the hours.
    static let resendGap: TimeInterval = 24 * 3600
    static let sentKey = "ni2.telemetry.sent"
    /// How long a standard-mode delivery waits for Sentry to take its events before closing.
    static let flushTimeout: TimeInterval = 15

    init(config: TelemetryConfig = .from(info: Bundle.main.infoDictionary), defaults: UserDefaults = .standard,
         queueFile: URL? = DiagnosticsCenter.supportFolder?.appendingPathComponent("Mixpanel/queue.json")) {
        self.config = config
        self.defaults = defaults
        self.queueFile = queueFile
    }

    var isConfigured: Bool { config.isConfigured }
    /// Sentry runs between reports (detailed mode).
    var keepsSentryRunning: Bool { isRunning && mode == .detailed && SentrySDK.isEnabled }

    // MARK: Lifecycle

    /// Diagnostics allowed: Mixpanel's queue opens; in detailed mode Sentry starts and stays.
    func start(installID: String, sender: String, version: String, build: String, mode: Mode) {
        guard config.isConfigured else { return }
        identity = (installID, sender, version, build)
        if isRunning, mode == self.mode { return }
        if isRunning { stopSentry() }
        isRunning = true
        self.mode = mode
        if mode == .detailed { startSentry(detailed: true) }
        if mixpanel == nil, let token = config.mixpanelToken, config.hasMixpanel {
            mixpanel = MixpanelClient(token: token, host: config.mixpanelHost, distinctID: installID, common: [
                "app_version": .string(version), "app_build": .string(build),
                "os_version": .string(ProcessInfo.processInfo.operatingSystemVersionString),
                "environment": .string(config.environment), "diagnostics_mode": .string(mode.rawValue),
            ], file: queueFile)
        }
        Log.app.notice("telemetry on (\(mode.rawValue, privacy: .public)): sentry \(self.config.hasSentry, privacy: .public), mixpanel \(self.config.hasMixpanel, privacy: .public)")
    }

    /// Diagnostics turned off: Sentry closes and what Mixpanel had not sent is forgotten.
    func stop() {
        guard isRunning else { return }
        isRunning = false
        stopSentry()
        mixpanel = nil
        if let queueFile { try? FileManager.default.removeItem(at: queueFile) }
        Log.app.notice("telemetry off")
    }

    /// The name the user gave (About), so the developer knows who wrote; the install's id otherwise.
    func setSender(_ sender: String, installID: String) {
        if let identity { self.identity = (installID, sender, identity.version, identity.build) }
        guard SentrySDK.isEnabled else { return }
        applyUser()
    }

    private func applyUser() {
        guard let identity else { return }
        let user = User(userId: identity.installID)
        if identity.sender != "Anonymous" { user.username = identity.sender }
        // Not the connection's address: Sentry would store it and place the user on a map from it
        // ("Lovasberény", seen with the first real event). No address is a stand-in it ignores.
        user.ipAddress = "0.0.0.0"
        SentrySDK.setUser(user)
    }

    /// Detailed: everything that watches. Standard (one delivery): nothing that watches.
    private func startSentry(detailed: Bool) {
        guard let dsn = config.sentryDSN, config.hasSentry, let identity else { return }
        let environment = config.environment
        SentrySDK.start { options in
            options.dsn = dsn
            options.releaseName = "com.davidvarga.notchisland@\(identity.version)+\(identity.build)"
            options.dist = identity.build
            options.environment = environment
            options.sendDefaultPii = false
            options.enableCrashHandler = detailed
            options.enableAppHangTracking = detailed
            options.appHangTimeoutInterval = 2
            options.enableAutoSessionTracking = detailed
            options.enableAutoBreadcrumbTracking = detailed
            // MetricKit's diagnostics come through `NativeCrash` in both modes (the SDK would only
            // see them while it runs).
            options.enableMetricKit = false
            options.tracesSampleRate = nil
            options.enableAutoPerformanceTracing = false
            options.enableNetworkTracking = false
            options.enableFileIOTracing = false
            options.enableCoreDataTracing = false
            options.enableSwizzling = false
            options.enableNetworkBreadcrumbs = false
            options.enableCaptureFailedRequests = false
            options.maxBreadcrumbs = 100
            options.beforeSend = { event in
                // The Mac's name is the user's ("David's MacBook Air").
                event.serverName = nil
                return event
            }
        }
        applyUser()
    }

    private func stopSentry() {
        if SentrySDK.isEnabled { SentrySDK.close() }
    }

    /// `body` with Sentry started: the running SDK in detailed mode; in standard mode one started
    /// for it, given the steps before as breadcrumbs, flushed and closed after.
    private func withSentry(_ body: () -> Void) {
        guard config.hasSentry else { return }
        if keepsSentryRunning {
            body()
            return
        }
        startSentry(detailed: false)
        guard SentrySDK.isEnabled else { return }
        for step in flow().suffix(60) {
            let crumb = Breadcrumb(level: .info, category: "flow")
            crumb.message = TelemetryMapping.redacted(step)
            SentrySDK.addBreadcrumb(crumb)
        }
        body()
        SentrySDK.flush(timeout: Self.flushTimeout)
        SentrySDK.close()
    }

    // MARK: As it happens

    /// A step of the user's flow (`DiagnosticsFlow`): live in detailed mode, with what was typed;
    /// in standard mode the steps go with the next delivery, without it.
    func breadcrumb(_ step: String) {
        guard keepsSentryRunning else { return }
        let crumb = Breadcrumb(level: .info, category: "flow")
        crumb.message = step
        SentrySDK.addBreadcrumb(crumb)
    }

    func track(_ event: String, _ properties: [String: TelemetryValue] = [:]) {
        guard isRunning else { return }
        mixpanel?.track(event, properties)
    }

    func flush() async {
        guard isRunning, let mixpanel else { return }
        await mixpanel.flush()
    }

    // MARK: Reports

    /// An automatic report (launch, hourly, crash, anomaly, problem, by hand): its numbers to
    /// Mixpanel, its new causes, own errors and macOS's crash and hang records to Sentry, and —
    /// when asked for, when something happened, or every hour in detailed mode — the whole report
    /// as an event with its files. True when it could go.
    @discardableResult
    func deliver(report: DiagnosticsReport, envelope: DiagnosticsEnvelope, reason: DiagnosticsReason?, light: Bool) async -> Bool {
        guard isRunning else { return false }
        var snapshot = TelemetryMapping.snapshot(report, verdict: envelope.verdict, reason: reason, light: light)
        snapshot["diagnostics_mode"] = .string(mode.rawValue)
        mixpanel?.track(reason == .launch ? "Launch Report" : "Health Snapshot", snapshot)
        let detailed = mode == .detailed
        withSentry {
            let tags = ["reason": reason?.rawValue ?? "feedback", "kind": envelope.kind.rawValue, "diagnostics_mode": mode.rawValue]
            // macOS's records first, crash reporter before MetricKit (the same crash comes from
            // both; the `.ips` has the thread names and the symbols macOS already knew).
            let systemReports = report.attachments.filter { $0.name != "log.txt" }
                .sorted { $0.isCrashReport && !$1.isCrashReport }
            var native = false
            for attachment in systemReports {
                native = captureSystemReport(attachment, crashCaughtBySDK: detailed && SentrySDK.crashedLastRun) || native
            }
            // A crash or hang that went as a native event is not also an issue of its own.
            let causes = TelemetryMapping.causes(envelope.verdict)
                .filter { !native || !($0.id.hasPrefix("crash.") || $0.id.hasPrefix("system.") || $0.id == "app.uncleanExit") }
            for cause in causes where isDue("cause:" + cause.id) {
                SentrySDK.capture(message: cause.message) { scope in
                    scope.setLevel(cause.isIssue ? .error : .warning)
                    scope.setFingerprint(cause.fingerprint)
                    scope.setTag(value: cause.feature, key: "feature")
                    scope.setTag(value: cause.confidence, key: "confidence")
                    for (key, value) in tags { scope.setTag(value: value, key: key) }
                    scope.setContext(value: ["cause": cause.cause, "action": cause.action, "id": cause.id], key: "likely cause")
                }
            }
            for error in TelemetryMapping.ownErrors(report) where isDue("log:" + error.fingerprint.joined(separator: "|")) {
                SentrySDK.capture(message: error.message) { scope in
                    scope.setLevel(.error)
                    scope.setFingerprint(error.fingerprint)
                    scope.setTag(value: error.category, key: "log_category")
                    scope.setContext(value: ["count in report": error.count], key: "log")
                }
            }
            if TelemetryMapping.sendsWholeReport(reason, detailed: detailed) {
                SentrySDK.capture(message: "Diagnostics report: \(reason?.title ?? envelope.kind.rawValue)") { scope in
                    scope.setLevel(envelope.kind == .crash ? .error : .info)
                    scope.setFingerprint(["notchisland-report", reason?.rawValue ?? envelope.kind.rawValue])
                    for (key, value) in tags { scope.setTag(value: value, key: key) }
                    scope.setContext(value: ["findings": envelope.findings], key: "report")
                    for file in envelope.files where !Self.isSystemReport(file.name, in: systemReports) {
                        scope.addAttachment(Attachment(data: Data(file.text.utf8), filename: file.name))
                    }
                }
            }
        }
        await mixpanel?.flush()
        return true
    }

    /// A crash reporter `.ips` or a MetricKit diagnostic: a native event Sentry symbolicates (the
    /// report itself attached), or the file alone when it cannot be read. A crash the SDK's own
    /// handler caught (detailed mode) already went: its `.ips` is attached only.
    /// True when it went as a native event.
    @discardableResult
    private func captureSystemReport(_ attachment: DiagnosticsReport.Attachment, crashCaughtBySDK: Bool) -> Bool {
        let file = Attachment(data: Data(attachment.text.utf8), filename: attachment.name)
        let native: NativeCrash? = attachment.isCrashReport
            ? NativeCrash.ips(attachment.text)
            : (try? DiagnosticsSystemReports.decoder.decode(DiagnosticReport.self, from: Data(attachment.text.utf8)))
                .flatMap { NativeCrash.metricKit($0) }
        guard let native else {
            SentrySDK.capture(message: "macOS report: \(attachment.name)") { scope in
                scope.setLevel(attachment.isCrashReport ? .fatal : .warning)
                scope.setFingerprint(["notchisland-macos-report", attachment.isCrashReport ? "crash" : "system"])
                scope.setTag(value: "macOS", key: "source")
                scope.addAttachment(file)
            }
            return false
        }
        // A crash the SDK's handler sent already (detailed mode), or the same crash from the crash
        // reporter and from MetricKit: the first one goes.
        if native.kind == .crash, crashCaughtBySDK { return true }
        if native.kind == .crash, let date = native.date, !isNewCrash(at: date) { return true }
        SentrySDK.capture(event: Self.event(native)) { scope in
            scope.setTag(value: native.source, key: "source")
            scope.setTag(value: native.kind.rawValue, key: "diagnostic")
            scope.addAttachment(file)
        }
        return true
    }

    static let crashTimesKey = "ni2.telemetry.crashTimes"
    /// Within this of one already sent, a crash is that one.
    static let sameCrashWindow: TimeInterval = 600

    /// Whether a crash at `date` was not sent yet; remembers it when not.
    private func isNewCrash(at date: Date) -> Bool {
        var times = (defaults.array(forKey: Self.crashTimesKey) as? [Date] ?? [])
            .filter { Date().timeIntervalSince($0) < 7 * 86400 }
        guard !times.contains(where: { abs($0.timeIntervalSince(date)) < Self.sameCrashWindow }) else { return false }
        times.append(date)
        defaults.set(times, forKey: Self.crashTimesKey)
        return true
    }

    /// The Sentry event for a crash or hang macOS recorded: its exception, its threads (outermost
    /// frame first, as Sentry wants them) and the binaries they ran in.
    static func event(_ crash: NativeCrash) -> Event {
        let event = Event(level: crash.kind == .crash ? .fatal : .error)
        if let date = crash.date { event.timestamp = date }
        if let version = crash.appVersion {
            event.releaseName = "com.davidvarga.notchisland@\(version)" + (crash.appBuild.map { "+\($0)" } ?? "")
        }
        event.dist = crash.appBuild
        event.platform = "cocoa"
        let threads: [SentryThread] = crash.threads.map { thread in
            let sentryThread = SentryThread(threadId: NSNumber(value: thread.id))
            sentryThread.name = thread.name
            sentryThread.crashed = NSNumber(value: thread.crashed)
            sentryThread.current = NSNumber(value: false)
            let frames: [Frame] = thread.frames.reversed().map { frame in
                let sentryFrame = Frame()
                sentryFrame.instructionAddress = hex(frame.instructionAddress)
                if let image = crash.images.first(where: { $0.uuid == frame.imageUUID }) {
                    sentryFrame.imageAddress = hex(image.address)
                    sentryFrame.package = image.path
                    sentryFrame.inApp = NSNumber(value: image.name == "NotchIsland")
                }
                if let symbol = frame.symbol { sentryFrame.function = symbol }
                return sentryFrame
            }
            sentryThread.stacktrace = SentryStacktrace(frames: frames, registers: [:])
            return sentryThread
        }
        event.threads = threads
        let exception = Exception(value: crash.value, type: crash.type)
        let mechanism = Mechanism(type: crash.kind == .crash ? "mach" : "AppHang")
        mechanism.handled = NSNumber(value: false)
        mechanism.desc = "From \(crash.source)"
        exception.mechanism = mechanism
        if let crashed = crash.threads.firstIndex(where: \.crashed) {
            exception.threadId = NSNumber(value: crash.threads[crashed].id)
            exception.stacktrace = threads[crashed].stacktrace
        }
        event.exceptions = [exception]
        event.debugMeta = crash.usedImages.map { image in
            let meta = DebugMeta()
            meta.type = "macho"
            meta.debugID = image.uuid
            meta.imageAddress = hex(image.address)
            if image.size > 0 { meta.imageSize = NSNumber(value: image.size) }
            meta.codeFile = image.path
            return meta
        }
        return event
    }

    private static func hex(_ value: UInt64) -> String { "0x" + String(value, radix: 16) }

    /// A bug report or request as Sentry user feedback, with its report's files.
    func feedback(_ feedback: DiagnosticsFeedback, envelope: DiagnosticsEnvelope, sender: String) -> Bool {
        guard isRunning, config.hasSentry else { return false }
        var message = "[\(feedback.kind == .bug ? "Bug" : "Request")] \(feedback.title)"
        for part in [feedback.details, feedback.expected, feedback.steps] where !part.isEmpty { message += "\n\n" + part }
        let attachments = envelope.files.map { Attachment(data: Data($0.text.utf8), filename: $0.name) }
        withSentry {
            SentrySDK.capture(feedback: SentryFeedback(message: message, name: sender == "Anonymous" ? nil : sender, email: nil,
                                                       source: .custom, associatedEventId: nil, attachments: attachments))
        }
        mixpanel?.track(feedback.kind == .bug ? "Bug Reported" : "Feature Requested")
        return true
    }

    /// Whether `key` may go again (not within `resendGap`); marks it sent when it may.
    private func isDue(_ key: String, now: Date = Date()) -> Bool {
        // Per destination: what went to another project (a test server, an old DSN) is not sent.
        let destination = config.sentryDSN.map { "\($0.split(separator: "@").last ?? "")" } ?? "none"
        let storeKey = Self.sentKey + "." + destination
        var sent = defaults.dictionary(forKey: storeKey) as? [String: Date] ?? [:]
        sent = sent.filter { now.timeIntervalSince($0.value) < Self.resendGap }
        let due = sent[key] == nil
        if due { sent[key] = now }
        defaults.set(sent, forKey: storeKey)
        return due
    }

    private static func isSystemReport(_ name: String, in reports: [DiagnosticsReport.Attachment]) -> Bool {
        reports.contains { $0.name == name }
    }
}
