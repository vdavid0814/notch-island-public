import Foundation
import Sentry

/// Crashes, errors and health numbers to Sentry and Mixpanel (EU), in place of the Discord reports.
/// Only while the user allows diagnostics (About ▸ Diagnostics): `start` and `stop` follow the
/// switch. `DiagnosticsCenter` still collects, compares and reads the reports; this sends what
/// they found:
///
/// - Sentry: crashes and hangs as they happen (its crash handler, MetricKit's diagnostics), every
///   likely cause as an issue of its own (grouped by the check's id across Macs), NotchIsland's
///   own error lines, macOS's crash and hang reports as attachments, the whole report when it was
///   asked for or something happened, the user's flow as breadcrumbs (without what was typed),
///   and bug reports and requests as user feedback.
/// - Mixpanel: one event per report with the measured numbers and each feature's state (the
///   hourly "Health Snapshot"), the launch and the update.
///
/// Sentry's options keep to what costs nothing at rest: no tracing, no swizzling, no automatic
/// breadcrumbs, no App Hang watcher thread (`appHangsKey`).
@MainActor final class Telemetry {
    let config: TelemetryConfig
    private let defaults: UserDefaults
    private let queueFile: URL?
    private(set) var mixpanel: MixpanelClient?
    private(set) var isRunning = false

    /// A likely cause or an error line goes to Sentry at most once in this long per Mac: Sentry
    /// counts the Macs it is on, not the hours.
    static let resendGap: TimeInterval = 24 * 3600
    static let sentKey = "ni2.telemetry.sent"
    /// The SDK's App Hang watcher, off unless turned on here (`defaults write … ni2.telemetry.appHangs
    /// -bool YES`): at rest it took the app from 1.2 to 3.7 wakeups a second and 0.06 to 0.25 ms of
    /// CPU a second (measured, October 9). Hangs still come, from MetricKit's diagnostics, which
    /// cost nothing while the app runs; Sentry deprecates the watcher for them anyway.
    static let appHangsKey = "ni2.telemetry.appHangs"
    /// Sentry's own crash handler, on unless turned off here (`… ni2.telemetry.crashHandler -bool
    /// NO`). It is what makes a crash a symbolicated Sentry event, and its one cost at rest is a
    /// thread that sleeps a second at a time between its minute-long refreshes: about one wakeup a
    /// second (0.2 → 1.3/s at rest, measured October 9). Off, crashes still come as macOS's own
    /// reports, attached to the next report.
    static let crashHandlerKey = "ni2.telemetry.crashHandler"

    init(config: TelemetryConfig = .from(info: Bundle.main.infoDictionary), defaults: UserDefaults = .standard,
         queueFile: URL? = DiagnosticsCenter.supportFolder?.appendingPathComponent("Mixpanel/queue.json")) {
        self.config = config
        self.defaults = defaults
        self.queueFile = queueFile
    }

    var isConfigured: Bool { config.isConfigured }

    // MARK: Lifecycle

    /// Diagnostics allowed: Sentry's handlers go in and Mixpanel's queue opens.
    func start(installID: String, sender: String, version: String, build: String) {
        guard !isRunning, config.isConfigured else { return }
        isRunning = true
        if let dsn = config.sentryDSN, config.hasSentry {
            let crashHandler = defaults.object(forKey: Self.crashHandlerKey) as? Bool ?? true
            let environment = config.environment
            let appHangs = defaults.bool(forKey: Self.appHangsKey)
            SentrySDK.start { options in
                options.dsn = dsn
                options.releaseName = "com.davidvarga.notchisland@\(version)+\(build)"
                options.dist = build
                options.environment = environment
                options.sendDefaultPii = false
                options.enableCrashHandler = crashHandler
                // Hangs: the system's own diagnostics (no thread of ours); the SDK's watcher only
                // when turned on (`appHangsKey`).
                options.enableMetricKit = true
                options.enableAppHangTracking = appHangs
                options.appHangTimeoutInterval = 2
                options.enableAutoSessionTracking = true
                // Nothing that runs, swizzles or listens at rest.
                options.tracesSampleRate = nil
                options.enableAutoPerformanceTracing = false
                options.enableNetworkTracking = false
                options.enableFileIOTracing = false
                options.enableCoreDataTracing = false
                options.enableSwizzling = false
                options.enableAutoBreadcrumbTracking = false
                options.enableNetworkBreadcrumbs = false
                options.enableCaptureFailedRequests = false
                options.maxBreadcrumbs = 100
                options.beforeSend = { event in
                    // The Mac's name is the user's ("David's MacBook Air").
                    event.serverName = nil
                    return event
                }
            }
        }
        setSender(sender, installID: installID)
        if let token = config.mixpanelToken, config.hasMixpanel {
            mixpanel = MixpanelClient(token: token, host: config.mixpanelHost, distinctID: installID, common: [
                "app_version": .string(version), "app_build": .string(build),
                "os_version": .string(ProcessInfo.processInfo.operatingSystemVersionString),
                "environment": .string(config.environment),
            ], file: queueFile)
        }
        Log.app.notice("telemetry on: sentry \(self.config.hasSentry, privacy: .public), mixpanel \(self.config.hasMixpanel, privacy: .public)")
    }

    /// Diagnostics turned off: Sentry closes and what Mixpanel had not sent is forgotten.
    func stop() {
        guard isRunning else { return }
        isRunning = false
        if SentrySDK.isEnabled { SentrySDK.close() }
        mixpanel = nil
        if let queueFile { try? FileManager.default.removeItem(at: queueFile) }
        Log.app.notice("telemetry off")
    }

    /// The name the user gave (About), so the developer knows who wrote; the install's id otherwise.
    func setSender(_ sender: String, installID: String) {
        guard isRunning, SentrySDK.isEnabled else { return }
        let user = User(userId: installID)
        if sender != "Anonymous" { user.username = sender }
        // Not the connection's address: Sentry would store it and place the user on a map from it
        // ("Lovasberény", seen with the first real event). No address is a stand-in it ignores.
        user.ipAddress = "0.0.0.0"
        SentrySDK.setUser(user)
    }

    // MARK: As it happens

    /// A step of the user's flow (`DiagnosticsFlow`), without what was typed.
    func breadcrumb(_ step: String) {
        guard isRunning, SentrySDK.isEnabled else { return }
        let crumb = Breadcrumb(level: .info, category: "flow")
        crumb.message = TelemetryMapping.redacted(step)
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
    /// Mixpanel, its new causes and own errors to Sentry, macOS's reports and — when asked for or
    /// something happened — the whole report as an event with its files. True when it could go.
    @discardableResult
    func deliver(report: DiagnosticsReport, envelope: DiagnosticsEnvelope, reason: DiagnosticsReason?, light: Bool) async -> Bool {
        guard isRunning else { return false }
        mixpanel?.track(reason == .launch ? "Launch Report" : "Health Snapshot",
                        TelemetryMapping.snapshot(report, verdict: envelope.verdict, reason: reason, light: light))
        if SentrySDK.isEnabled {
            let tags = ["reason": reason?.rawValue ?? "feedback", "kind": envelope.kind.rawValue]
            for cause in TelemetryMapping.causes(envelope.verdict) where isDue("cause:" + cause.id) {
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
            let systemReports = report.attachments.filter { $0.name != "log.txt" }
            for attachment in systemReports {
                SentrySDK.capture(message: "macOS report: \(attachment.name)") { scope in
                    scope.setLevel(attachment.isCrashReport ? .fatal : .warning)
                    scope.setFingerprint(["notchisland-macos-report", attachment.isCrashReport ? "crash" : "system"])
                    scope.setTag(value: "macOS", key: "source")
                    scope.addAttachment(Attachment(data: Data(attachment.text.utf8), filename: attachment.name))
                }
            }
            if TelemetryMapping.sendsWholeReport(reason) {
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

    /// A bug report or request as Sentry user feedback, with its report's files.
    func feedback(_ feedback: DiagnosticsFeedback, envelope: DiagnosticsEnvelope, sender: String) -> Bool {
        guard isRunning, SentrySDK.isEnabled else { return false }
        var message = "[\(feedback.kind == .bug ? "Bug" : "Request")] \(feedback.title)"
        for part in [feedback.details, feedback.expected, feedback.steps] where !part.isEmpty { message += "\n\n" + part }
        let attachments = envelope.files.map { Attachment(data: Data($0.text.utf8), filename: $0.name) }
        SentrySDK.capture(feedback: SentryFeedback(message: message, name: sender == "Anonymous" ? nil : sender, email: nil,
                                                   source: .custom, associatedEventId: nil, attachments: attachments))
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
