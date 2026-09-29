import AppKit
import Observation

/// Sends the developer diagnostics reports (when the user turned them on in About) and the user's
/// bug reports and feature requests (always possible).
///
/// Reports go at launch (after a pause, so the launch itself is not slowed; sooner after a crash or
/// an update), every `periodicInterval` while the app runs, when a new crash report turns up, when a
/// 10-minute energy sample is well past the developer's reference twice in a row, when something
/// breaks while running (`watchProblems`), and on request. Every number is set
/// against the reference (`DiagnosticsBaseline`, from GitHub). A delivery that fails is kept in the
/// outbox and sent before the next one.
@Observable final class DiagnosticsCenter {
    nonisolated static let enabledKey = "ni2.diagnostics"
    nonisolated static let nameKey = "ni2.diagnostics.name"
    nonisolated static let installKey = "ni2.diagnostics.install"
    nonisolated static let lastSentKey = "ni2.diagnostics.lastSent"
    nonisolated static let crashesSeenKey = "ni2.diagnostics.crashesSeen"
    nonisolated static let userThreadKey = "ni2.diagnostics.userThread"
    nonisolated static let lastAnomalyKey = "ni2.diagnostics.lastAnomaly"
    /// Set on the developer's Mac only (`Scripts/publish-baseline.sh`): it may write the reference.
    nonisolated static let referenceKey = "ni2.diagnostics.reference"
    /// Set by `Scripts/publish-baseline.sh --replace`: the next reference replaces every number.
    nonisolated static let referenceReplaceKey = "ni2.diagnostics.referenceReplace"

    static let launchDelay: Duration = .seconds(90)
    /// After a crash or unclean exit, and on a new version's first launch.
    static let urgentLaunchDelay: Duration = .seconds(25)
    static let periodicInterval: Duration = .seconds(3600)
    /// Hours of log in an automatic report, in the hourly one, and in a bug report.
    static let reportLogHours = 6

    /// Where an automatic report's log starts: at the previous full report (a minute before, to
    /// overlap), at most `reportLogHours` back — what came before was sent. By hand: all of it.
    static func logStart(for reason: DiagnosticsReason, lastFull: Date, now: Date = Date()) -> Date {
        let earliest = now.addingTimeInterval(-Double(reportLogHours) * 3600)
        guard reason != .manual else { return earliest }
        return max(earliest, lastFull.addingTimeInterval(-60))
    }
    /// The hourly report is light (what changes by the hour: energy, the app's state, the user's
    /// flow, this run's log read in-process); a full one (the Mac's setup, installed apps, Spotlight,
    /// hardware, `log show` over earlier runs) goes at most this often, and at launch, after an
    /// update or a crash, by hand, with a bug report or an anomaly. A full report and its tools
    /// cost ~21 J (measured, coalition): hourly that was ten times the app's own energy.
    static let fullReportInterval: TimeInterval = 6 * 3600
    nonisolated static let lastFullKey = "ni2.diagnostics.lastFull"

    static let bugLogHours = 24
    /// A second Send Report Now this soon after a report sends nothing (four in six seconds were
    /// seen, v0.4.5).
    static let manualGap: TimeInterval = 60
    /// How often the running app is checked for something broken, and at most one report per
    /// kind of problem in `problemGap`.
    static let problemCheck: Duration = .seconds(60)
    static let problemGap: TimeInterval = 3600
    nonisolated static let logLimit = 2_500_000
    static let outboxLimit = 8
    /// At most one anomaly report in this long.
    static let anomalyGap: TimeInterval = 6 * 3600
    /// Samples in a row past the reference before an anomaly is reported.
    static let anomalyRun = 2

    nonisolated enum SendState: Equatable, Sendable {
        case idle
        case sending
        case sent(Date)
        case failed(String)
    }

    /// Automatic reports are on (About ▸ Diagnostics).
    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            defaults.set(isEnabled, forKey: Self.enabledKey)
            Log.app.notice("diagnostics \(self.isEnabled ? "on" : "off", privacy: .public)")
            guard model != nil else { return }
            if isEnabled { energy.start() } else { energy.stop() }
            reschedule(firstDelay: .seconds(2), firstReason: .enabled)
        }
    }
    /// The name the user gave so the developer knows who wrote; empty is anonymous.
    var name: String { didSet { defaults.set(name, forKey: Self.nameKey) } }
    private(set) var state: SendState = .idle
    private(set) var lastSent: Date?
    /// Deliveries waiting in the outbox.
    private(set) var pending = 0
    /// For About: NotchIsland's average draw since launch, the reference's, and the newest version.
    private(set) var ownPowerMW: Double?
    private(set) var referencePowerMW: Double?
    private(set) var latestVersion: String?

    /// Where deliveries go; empty in a build made without them (sending is then disabled).
    let destinations: DiagnosticsDestinations
    var isConfigured: Bool { destinations.isConfigured }
    let installID: String
    let launchedAt = Date()
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let outbox: URL?
    @ObservationIgnored private weak var model: AppModel?
    @ObservationIgnored private var schedule: Task<Void, Never>?
    @ObservationIgnored private var isSending = false
    @ObservationIgnored private(set) var energy: EnergyMeter!
    @ObservationIgnored let references = DiagnosticsReferenceStore()
    @ObservationIgnored private(set) var history: DiagnosticsHistory?
    @ObservationIgnored private var hasInstalledCounter = false
    /// Consecutive samples past the reference, by metric.
    @ObservationIgnored private var unusualRuns: [DiagnosticsMetric: Int] = [:]
    /// What set off the anomaly report being sent.
    @ObservationIgnored private var liveTrigger: [String] = []
    @ObservationIgnored private var problemWatch: Task<Void, Never>?
    /// Problems seen on the last check, and when each was last reported.
    @ObservationIgnored private var problems: Set<String> = []
    @ObservationIgnored private var problemsReported: [String: Date] = [:]
    /// Waits for macOS's own reports on the app (`DiagnosticsSystemReports`).
    @ObservationIgnored private var systemWatch: Task<Void, Never>?

    init(defaults: UserDefaults = .standard,
         destinations: DiagnosticsDestinations = .from(info: Bundle.main.infoDictionary),
         outbox: URL? = DiagnosticsCenter.defaultOutbox) {
        self.defaults = defaults
        self.destinations = destinations
        self.outbox = outbox
        isEnabled = defaults.bool(forKey: Self.enabledKey)
        name = defaults.string(forKey: Self.nameKey) ?? ""
        lastSent = defaults.object(forKey: Self.lastSentKey) as? Date
        if let id = defaults.string(forKey: Self.installKey) {
            installID = id
        } else {
            installID = UUID().uuidString.lowercased()
            defaults.set(installID, forKey: Self.installKey)
        }
        pending = outbox.map(Self.outboxFiles)?.count ?? 0
        energy = EnergyMeter(launchedAt: launchedAt) { [weak self] in self?.model?.power.state ?? .unknown }
        energy.onSample = { [weak self] interval in self?.liveCheck(interval) }
    }

    nonisolated static var defaultOutbox: URL? {
        supportFolder?.appendingPathComponent("DiagnosticsOutbox", isDirectory: true)
    }

    nonisolated static var supportFolder: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("NotchIsland", isDirectory: true)
    }

    var sender: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Anonymous" : String(trimmed.prefix(60))
    }

    var isReferenceMac: Bool { defaults.bool(forKey: Self.referenceKey) }

    // MARK: Lifecycle

    func start(model: AppModel) {
        self.model = model
        if history == nil { history = DiagnosticsHistory(defaults: defaults, version: "\(version) (\(build))") }
        installCounter(model)
        if isEnabled { energy.start() }
        if systemWatch == nil {
            systemWatch = DiagnosticsSystemReports.watch { [weak self] line in self?.systemReportArrived(line) }
        }
        let first = Self.firstReport(history: history, newCrash: DiagnosticsProbes.crashCount(since: crashesSince) > 0)
        reschedule(firstDelay: first.delay, firstReason: first.reason)
    }

    /// The first report of this launch: soon after a crash, an unclean exit or an update, else
    /// after `launchDelay`.
    static func firstReport(history: DiagnosticsHistory?, newCrash: Bool) -> (reason: DiagnosticsReason, delay: Duration) {
        if newCrash || history?.previousEndedUncleanly == true { return (.crash, urgentLaunchDelay) }
        if history?.isNewVersion == true { return (.update, urgentLaunchDelay) }
        return (.launch, launchDelay)
    }

    private var crashesSince: Date {
        defaults.object(forKey: Self.crashesSeenKey) as? Date ?? Date().addingTimeInterval(-7 * 86400)
    }

    /// The app is quitting: the run ended normally.
    func stop() {
        schedule?.cancel()
        schedule = nil
        problemWatch?.cancel()
        problemWatch = nil
        energy.stop()
        history?.markCleanExit()
    }

    /// Counts the island's presentations (panel, Siri, banners, Settings) since launch.
    private func installCounter(_ model: AppModel) {
        guard !hasInstalledCounter else { return }
        hasInstalledCounter = true
        let previous = model.island.didTransition
        model.island.didTransition = { [weak self] from, to in
            previous?(from, to)
            let kind = DiagnosticsHistory.kind(of: to)
            if kind != DiagnosticsHistory.kind(of: from) { self?.history?.count(kind) }
            DiagnosticsFlow.record("island \(from) → \(to)")
        }
    }

    /// The launch report, then one every `periodicInterval`; nothing while turned off.
    private func reschedule(firstDelay: Duration, firstReason: DiagnosticsReason) {
        schedule?.cancel()
        schedule = nil
        problemWatch?.cancel()
        problemWatch = nil
        guard isEnabled, isConfigured, model != nil else { return }
        watchProblems()
        schedule = Task { [weak self] in
            var delay = firstDelay
            var reason = firstReason
            while !Task.isCancelled {
                do { try await Task.sleep(for: delay, tolerance: delay / 10) } catch { return }
                guard let self else { return }
                await self.sendReport(reason)
                delay = Self.periodicInterval
                reason = .periodic
            }
        }
    }

    // MARK: Watching

    /// Each 10-minute sample against the reference: two in a row past it sends a report at once.
    private func liveCheck(_ interval: EnergyInterval) {
        // A report being collected is not the app misbehaving.
        guard isEnabled, let baseline = references.baseline, !energy.isCollection(interval) else { return }
        let values: [DiagnosticsMetric: Double] = [
            .recentPowerMW: interval.ownMW, .wakeupsPerSecond: interval.wakeupsPerSecond, .memoryMB: interval.footprintMB,
        ]
        var triggered: [String] = []
        for comparison in DiagnosticsComparison.compare(values, with: baseline) {
            unusualRuns[comparison.metric] = comparison.isUnusual ? unusualRuns[comparison.metric, default: 0] + 1 : 0
            if unusualRuns[comparison.metric, default: 0] >= Self.anomalyRun {
                triggered.append(comparison.line + " (\(Self.anomalyRun) readings of 10 minutes in a row)")
            }
        }
        guard !triggered.isEmpty else { return }
        // Counted again from zero: the next report needs two more readings in a row.
        unusualRuns = [:]
        if let last = defaults.object(forKey: Self.lastAnomalyKey) as? Date, Date().timeIntervalSince(last) < Self.anomalyGap { return }
        defaults.set(Date(), forKey: Self.lastAnomalyKey)
        Log.app.notice("diagnostics: unusual \(triggered.joined(separator: "; "), privacy: .public)")
        liveTrigger = triggered
        Task { await self.sendReport(.anomaly) }
    }

    /// Every `problemCheck`: Accessibility taken away, the key interception failed, or the ⌘Space
    /// tap stopped while wanted. A problem that newly appears sends a report at once (one per kind
    /// per `problemGap`).
    private func watchProblems() {
        problemWatch = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: Self.problemCheck, tolerance: .seconds(15)) } catch { return }
                self?.checkProblems()
            }
        }
    }

    private func checkProblems() {
        guard isEnabled, let model else { return }
        var found: [String: String] = [:]
        if !model.permissions.accessibilityTrusted {
            found["accessibility"] = "Accessibility is not allowed (any more)"
        }
        let keys = String(describing: model.levels.interception)
        if keys.hasPrefix("failed") { found["keys"] = "The volume/brightness key interception failed: \(keys)" }
        if model.diagnosticsCommandSpaceWanted, !model.diagnosticsCommandSpaceTapRunning {
            found["commandSpace"] = "The ⌘Space tap is wanted but not running"
        }
        let new = Set(found.keys).subtracting(problems)
        problems = Set(found.keys)
        let due = new.filter { problemsReported[$0].map { Date().timeIntervalSince($0) >= Self.problemGap } ?? true }
        guard !due.isEmpty else { return }
        for kind in due { problemsReported[kind] = Date() }
        let lines = due.sorted().compactMap { found[$0] }
        Log.app.notice("diagnostics: problem \(lines.joined(separator: "; "), privacy: .public)")
        liveTrigger = lines
        Task { await self.sendReport(.problem) }
    }

    /// macOS handed over a report of its own (a hang, a crash, a CPU or disk-write exception): a
    /// report goes at once, one per `problemGap` (the system may hand several over together).
    private func systemReportArrived(_ line: String) {
        Log.app.notice("diagnostics: system report \(line, privacy: .public)")
        DiagnosticsFlow.record("system report: \(line)")
        guard isEnabled, isConfigured else { return }
        if let last = problemsReported["system"], Date().timeIntervalSince(last) < Self.problemGap { return }
        problemsReported["system"] = Date()
        liveTrigger.append("macOS reported: \(line)")
        Task {
            // Others of the same delivery arrive together: wait a moment and send them in one.
            try? await Task.sleep(for: .seconds(5))
            await self.sendReport(.problem)
        }
    }

    /// The system reports a delivered report carried (listed in its section) go.
    nonisolated static func markSystemReportsSent(_ report: DiagnosticsReport) {
        let names = report.sections.first { $0.title == DiagnosticsSystemReports.title }?.entries.map(\.key) ?? []
        DiagnosticsSystemReports.markSent(names)
    }

    /// For About: fresh numbers for the energy and version lines.
    func refreshStatus() async {
        await references.refresh()
        let now = EnergySample.now(onBattery: false, batteryLevel: nil)
        ownPowerMW = EnergyInterval(from: energy.launch, to: now)?.ownMW
        referencePowerMW = references.baseline?.value(.powerMW)
        latestVersion = references.latestVersion
    }

    // MARK: Sending

    /// A diagnostics report. A new crash report makes it a crash report.
    @discardableResult
    func sendReport(_ reason: DiagnosticsReason) async -> Bool {
        if reason == .manual, let lastSent, Date().timeIntervalSince(lastSent) < Self.manualGap {
            Log.app.notice("diagnostics: sent \(Int(Date().timeIntervalSince(lastSent)), privacy: .public) s ago, not again")
            return true
        }
        // By hand: the newest version and reference, not an hour-old answer.
        await references.refresh(force: reason == .manual)
        let lastFull = defaults.object(forKey: Self.lastFullKey) as? Date ?? .distantPast
        let light = reason == .periodic && Date().timeIntervalSince(lastFull) < Self.fullReportInterval
        // The 6-hourly full report reads the log back to the previous full one (the hourly ones
        // bring none): 1 hour of it left five hours of errors unseen.
        let report = await makeReport(logHours: Self.reportLogHours, crashesSince: crashesSince, light: light,
                                      logSince: Self.logStart(for: reason, lastFull: lastFull))
        if !light { defaults.set(Date(), forKey: Self.lastFullKey) }
        let crashes = report.attachments.count(where: \.isCrashReport)
        let kind: DiagnosticsEnvelope.Kind = crashes > 0 ? .crash : reason == .anomaly ? .anomaly : .report
        let delivered = await deliver(envelope(kind: kind, reason: reason, report: report, feedback: nil))
        if delivered {
            defaults.set(Date(), forKey: Self.crashesSeenKey)
            Self.markSystemReportsSent(report)
        }
        liveTrigger = []
        return delivered
    }

    /// A bug report or feature request, with a diagnostics report attached if the user allowed it.
    func sendFeedback(_ feedback: DiagnosticsFeedback, attachDiagnostics: Bool,
                      media: [DiagnosticsMediaFile] = []) async -> Bool {
        let report: DiagnosticsReport
        if attachDiagnostics {
            report = await feedbackReport(for: feedback.kind)
        } else {
            report = await makeReport(logHours: 0, crashesSince: nil, basicOnly: true)
        }
        preparedFeedback = nil
        let kind: DiagnosticsEnvelope.Kind = feedback.kind == .bug ? .bug : .feature
        var envelope = envelope(kind: kind, reason: nil, report: report, feedback: feedback)
        if !media.isEmpty { envelope.media = media }
        return await deliver(envelope)
    }

    /// The report a bug report or request carries, started as the form opens
    /// (`prepareFeedback`): its day of log takes ~12 s to read (measured), which the user then
    /// spends typing instead of waiting after Send.
    @ObservationIgnored private var preparedFeedback: (kind: DiagnosticsFeedback.Kind, started: Date, report: Task<DiagnosticsReport, Never>)?
    static let preparedLifetime: TimeInterval = 10 * 60

    /// The form was opened: collect its report in the background.
    func prepareFeedback(_ kind: DiagnosticsFeedback.Kind) {
        if let preparedFeedback, preparedFeedback.kind == kind,
           Date().timeIntervalSince(preparedFeedback.started) < Self.preparedLifetime { return }
        preparedFeedback?.report.cancel()
        let task = Task { [weak self] () -> DiagnosticsReport in
            guard let self else { return DiagnosticsReport() }
            return await self.collectFeedbackReport(kind)
        }
        preparedFeedback = (kind, Date(), task)
    }

    /// The form was closed without sending.
    func discardPreparedFeedback() {
        preparedFeedback?.report.cancel()
        preparedFeedback = nil
    }

    private func feedbackReport(for kind: DiagnosticsFeedback.Kind) async -> DiagnosticsReport {
        if let preparedFeedback, preparedFeedback.kind == kind,
           Date().timeIntervalSince(preparedFeedback.started) < Self.preparedLifetime {
            return await preparedFeedback.report.value
        }
        return await collectFeedbackReport(kind)
    }

    private func collectFeedbackReport(_ kind: DiagnosticsFeedback.Kind) async -> DiagnosticsReport {
        await references.refresh(force: true)
        let hours = kind == .bug ? Self.bugLogHours : Self.reportLogHours
        return await makeReport(logHours: hours, crashesSince: Date().addingTimeInterval(-3 * 86400))
    }

    private func envelope(kind: DiagnosticsEnvelope.Kind, reason: DiagnosticsReason?, report: DiagnosticsReport,
                          feedback: DiagnosticsFeedback?) -> DiagnosticsEnvelope {
        let crashCount = report.attachments.count(where: \.isCrashReport)
        let comparisons = DiagnosticsComparison.compare(report.metrics, with: references.baseline)
        var findings = liveTrigger.map { "Live: \($0)" }
        findings += DiagnosticsFindings.findings(report, crashes: crashCount)
        findings += DiagnosticsFindings.anomalies(comparisons, metrics: report.metrics, crashes: crashCount)
        if let latest = references.latestVersion, DiagnosticsVersions.isOlder(version, than: latest) {
            findings.append("Outdated: runs \(version), \(latest) is on GitHub")
        }
        var files: [DiagnosticsEnvelope.File] = []
        if !report.sections.isEmpty {
            files.append(.init(name: "report.txt", text: header(kind: kind, reason: reason, findings: findings) + report.text))
            let meta = ["kind": kind.rawValue, "reason": reason?.rawValue ?? "", "sender": sender, "install": installID,
                        "written": DiagnosticsFormat.date(Date()), "version": version, "build": build,
                        "reference": references.baseline.map { "v\($0.version) (\($0.build)) on \($0.machine)" } ?? "",
                        "latestOnGitHub": references.latestVersion ?? ""]
            files.append(.init(name: "report.json", text: report.json(meta: meta, findings: findings, comparisons: comparisons)))
        }
        files += report.attachments.map { .init(name: $0.name, text: $0.text) }
        var facts = DiagnosticsFindings.facts(report)
        if let power = report.metrics[.powerMW] {
            let reference = references.baseline?.value(.powerMW).map { String(format: " (ref %.1f)", $0) } ?? ""
            facts.append(.init(name: "Energy", value: String(format: "%.1f mW%@", power, reference)))
        }
        if let latest = references.latestVersion {
            facts.append(.init(name: "Latest on GitHub", value: DiagnosticsVersions.isOlder(version, than: latest) ? "\(latest) ⚠️" : "\(latest) ✅"))
        }
        return DiagnosticsEnvelope(
            kind: kind, reason: reason, sender: sender, installID: installID,
            facts: facts, findings: findings, feedback: feedback, files: files,
            comparison: DiagnosticsFindings.comparisonLines(comparisons),
            reference: references.baseline.map { "v\($0.version) on \($0.machine)" }
        )
    }

    private func header(kind: DiagnosticsEnvelope.Kind, reason: DiagnosticsReason?, findings: [String]) -> String {
        let diagnosis = findings.isEmpty ? "  nothing stands out" : findings.map { "  ⚠︎ \($0)" }.joined(separator: "\n")
        return "NotchIsland diagnostics · \(kind.rawValue)\(reason.map { " · \($0.title)" } ?? "")\n"
            + "From: \(sender) · install \(installID)\nWritten: \(DiagnosticsFormat.date(Date()))\n\n"
            + "Quick diagnosis:\n\(diagnosis)\n\n"
    }

    /// Sends what waits in the outbox, then `envelope`; a failure keeps it in the outbox.
    private func deliver(_ envelope: DiagnosticsEnvelope) async -> Bool {
        guard isConfigured else {
            state = .failed("This build has no diagnostics address.")
            return false
        }
        // One delivery at a time: two reports in a row must not race over the outbox.
        while isSending {
            try? await Task.sleep(for: .milliseconds(300))
        }
        isSending = true
        defer { isSending = false }
        state = .sending
        await flushOutbox()
        do {
            try await route(envelope)
            DiagnosticsMedia.discard(envelope.media ?? [])
            Log.app.notice("diagnostics sent: \(envelope.kind.rawValue, privacy: .public)")
            markSent()
            return true
        } catch {
            Log.app.error("diagnostics failed: \(String(describing: error), privacy: .public)")
            save(envelope)
            state = .failed("\(error.localizedDescription). It will be sent again later.")
            return false
        }
    }

    /// Reports into the install's own forum post; bugs and requests into their forums with a pointer
    /// in the install's post; a line in the alerts channel for anything that needs a look.
    private func route(_ envelope: DiagnosticsEnvelope) async throws {
        let destinations = destinations
        guard destinations.users != nil else {
            guard let fallback = destinations.fallback else { return }
            _ = try await DiagnosticsUploader.post(DiagnosticsUploader.payload(for: envelope), files: envelope.files, to: fallback)
            await postMedia(envelope.media, to: fallback, threadID: nil)
            return
        }
        let detail: DiagnosticsUploader.Posted
        let forum = envelope.kind == .bug ? destinations.bugs : envelope.kind == .feature ? destinations.features : nil
        if let forum {
            var payload = DiagnosticsUploader.payload(for: envelope)
            payload["thread_name"] = DiagnosticsUploader.feedbackThreadName(envelope)
            if let tag = envelope.kind == .bug ? destinations.bugTag : destinations.featureTag { payload["applied_tags"] = [tag] }
            detail = try await DiagnosticsUploader.post(payload, files: envelope.files, to: forum)
            await postMedia(envelope.media, to: forum, threadID: detail.channelID)
            let link = destinations.link(channel: detail.channelID, message: detail.id)
            _ = try? await postToUserThread(DiagnosticsUploader.pointerPayload(for: envelope, link: link), files: [])
        } else {
            detail = try await postToUserThread(DiagnosticsUploader.payload(for: envelope), files: envelope.files)
        }
        if envelope.isAlert, shouldAlert(envelope), let alerts = destinations.alerts {
            let link = destinations.link(channel: detail.channelID, message: detail.id)
            _ = try? await DiagnosticsUploader.post(DiagnosticsUploader.alertPayload(for: envelope, link: link), to: alerts)
        }
    }

    /// The screenshots and videos, one message each, under the report. The report itself is already
    /// posted: a video that fails is retried (a rate limit waited out) rather than the whole report
    /// sent again, and one that still fails is left out.
    private func postMedia(_ media: [DiagnosticsMediaFile]?, to webhook: URL, threadID: String?) async {
        guard let media, !media.isEmpty else { return }
        for (index, file) in media.enumerated() {
            for attempt in 0..<3 {
                do {
                    try await DiagnosticsUploader.postMedia(file, index: index, of: media.count, to: webhook, threadID: threadID)
                    break
                } catch DiagnosticsUploader.Failure.rateLimited(let after) {
                    try? await Task.sleep(for: .seconds(min(after, 30)))
                } catch {
                    Log.app.error("diagnostics media \(index + 1) failed (attempt \(attempt + 1)): \(String(describing: error), privacy: .public)")
                    try? await Task.sleep(for: .seconds(2))
                }
            }
        }
    }

    /// The same findings in a plain report alert once a day at most (reports go every hour and a
    /// lasting finding, a second copy on disk, would post the same alert each time). Crashes,
    /// anomalies, problems and feedback always alert.
    nonisolated static let lastAlertKey = "ni2.diagnostics.lastAlert"
    static let repeatAlertAfter: TimeInterval = 24 * 3600

    private func shouldAlert(_ envelope: DiagnosticsEnvelope) -> Bool {
        guard envelope.kind == .report else { return true }
        // Each finding by its words (numbers change every time, "589 mW"); alert when one has not
        // alerted in the last day. The light report lacks some of the full one's findings, so a
        // whole-list comparison would alert at every change of depth.
        let now = Date()
        var alerted = (defaults.dictionary(forKey: Self.lastAlertKey) as? [String: Date] ?? [:])
            .filter { now.timeIntervalSince($0.value) < Self.repeatAlertAfter }
        let keys = envelope.findings.map { $0.filter { !$0.isNumber } }
        let fresh = keys.filter { alerted[$0] == nil }
        guard !fresh.isEmpty else { return false }
        for key in keys { alerted[key] = now }
        defaults.set(alerted, forKey: Self.lastAlertKey)
        return true
    }

    func shouldAlertForTests(_ envelope: DiagnosticsEnvelope) -> Bool { envelope.isAlert && shouldAlert(envelope) }

    /// Into this install's forum post, made on the first delivery (and again if it was deleted).
    private func postToUserThread(_ payload: [String: Any], files: [DiagnosticsEnvelope.File]) async throws -> DiagnosticsUploader.Posted {
        guard let users = destinations.users else { throw DiagnosticsUploader.Failure.status(0, "no users forum") }
        if let thread = defaults.string(forKey: Self.userThreadKey) {
            do {
                return try await DiagnosticsUploader.post(payload, files: files, to: users, threadID: thread)
            } catch let failure as DiagnosticsUploader.Failure where failure.isUnknownChannel {
                defaults.removeObject(forKey: Self.userThreadKey)
            }
        }
        var creating = payload
        creating["thread_name"] = DiagnosticsUploader.userThreadName(sender: sender, installID: installID)
        let posted = try await DiagnosticsUploader.post(creating, files: files, to: users)
        defaults.set(posted.channelID, forKey: Self.userThreadKey)
        return posted
    }

    private func markSent() {
        let now = Date()
        lastSent = now
        defaults.set(now, forKey: Self.lastSentKey)
        state = .sent(now)
    }

    // MARK: Outbox

    nonisolated private static func outboxFiles(_ folder: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func save(_ envelope: DiagnosticsEnvelope) {
        guard let outbox, let data = try? JSONEncoder().encode(envelope) else { return }
        try? FileManager.default.createDirectory(at: outbox, withIntermediateDirectories: true)
        let stamp = Int(envelope.created.timeIntervalSince1970)
        try? data.write(to: outbox.appendingPathComponent("\(stamp)-\(envelope.id.uuidString).json"), options: .atomic)
        // The oldest go first once the outbox is full.
        let files = Self.outboxFiles(outbox)
        for file in files.dropLast(Self.outboxLimit) {
            if let data = try? Data(contentsOf: file), let old = try? JSONDecoder().decode(DiagnosticsEnvelope.self, from: data) {
                DiagnosticsMedia.discard(old.media ?? [])
            }
            try? FileManager.default.removeItem(at: file)
        }
        pending = min(files.count, Self.outboxLimit)
    }

    private func flushOutbox() async {
        guard let outbox else { return }
        for file in Self.outboxFiles(outbox) {
            guard let data = try? Data(contentsOf: file),
                  let envelope = try? JSONDecoder().decode(DiagnosticsEnvelope.self, from: data) else {
                try? FileManager.default.removeItem(at: file)
                continue
            }
            do {
                try await route(envelope)
                DiagnosticsMedia.discard(envelope.media ?? [])
                try? FileManager.default.removeItem(at: file)
            } catch {
                break
            }
        }
        pending = Self.outboxFiles(outbox).count
    }

    // MARK: The report

    /// The whole report: the app's state and energy here, everything else off the main actor.
    func makeReport(logHours: Int, crashesSince: Date?, basicOnly: Bool = false, light: Bool = false,
                    logSince: Date? = nil) async -> DiagnosticsReport {
        var appSections: [DiagnosticsReport.Section] = []
        var metrics: [DiagnosticsMetric: Double] = [:]
        if !basicOnly {
            let (energySection, energyMetrics) = energyReport()
            appSections = [energySection] + (history.map { [$0.section()] } ?? []) + (model.map(DiagnosticsAppState.sections) ?? [])
            metrics = energyMetrics
            if let history { metrics[.uncleanExits] = history.previousEndedUncleanly ? 1 : 0 }
        }
        // The tools the collection starts count as NotchIsland's helpers: that stretch is not judged.
        energy.beginCollecting()
        let background = await Self.collect(launchedAt: launchedAt, logHours: logHours, logSince: logSince,
                                            crashesSince: crashesSince, basicOnly: basicOnly,
                                            light: light)
        energy.endCollecting()
        metrics.merge(background.metrics) { $1 }
        var report = DiagnosticsReport()
        report.sections = Array(background.sections.prefix(3)) + appSections + background.sections.dropFirst(3)
        report.attachments = background.attachments
        if !basicOnly {
            report.sections.insert(referenceSection(metrics), at: min(3, report.sections.count))
            if !light { report.sections.insert(differencesSection(report.settings), at: min(4, report.sections.count)) }
            var causes = DiagnosticsReport.Section("Likely causes")
            let found = DiagnosticsInsights.causes(report, metrics: metrics)
            causes.add("Causes", found.isEmpty ? "nothing stands out" : found.map { "• \($0)" }.joined(separator: "\n"))
            report.sections.insert(causes, at: min(3, report.sections.count))
            var extra: [DiagnosticsReport.Section] = [DiagnosticsFlow.section()]
            // macOS's own reports (hangs, exceptions) next to the crash analysis.
            if let index = report.sections.firstIndex(where: { $0.title == DiagnosticsSystemReports.title }) {
                extra.insert(report.sections.remove(at: index), at: 0)
            }
            if let crash = DiagnosticsInsights.crashSection(report.attachments) { extra.insert(crash, at: 0) }
            if let log = report.attachments.first(where: { $0.name == "log.txt" }) {
                extra.append(DiagnosticsInsights.errorSection(log.text))
            }
            report.sections.insert(contentsOf: extra, at: min(6, report.sections.count))
        }
        report.metrics = metrics
        return report
    }

    /// How long a stretch must be before its energy is set against the reference.
    static let energyJudgedAfter: TimeInterval = 5 * 60

    /// NotchIsland's energy: since launch, the last hour, on battery and on the charger, the worst
    /// 10 minutes, and a timeline of the samples.
    private func energyReport() -> (DiagnosticsReport.Section, [DiagnosticsMetric: Double]) {
        var section = DiagnosticsReport.Section("Energy")
        var metrics: [DiagnosticsMetric: Double] = [:]
        let now = energy.isRunning ? energy.take() : EnergySample.now(onBattery: false, batteryLevel: nil)
        if let total = EnergyInterval(from: energy.launch, to: now), let summary = EnergySummary([total]) {
            section.add("Since launch", summary.line)
            // A few seconds after launch is the launch itself (and Settings, opened to send the report):
            // 21 s at 290 mW was flagged 6× the reference (seen, v0.4.5). Judged only once it has run.
            if summary.seconds >= Self.energyJudgedAfter {
                metrics[.powerMW] = total.ownMW
                metrics[.helpersPowerMW] = total.helpersMW
                metrics[.cpuPercent] = total.cpuPercent
                metrics[.wakeupsPerSecond] = total.wakeupsPerSecond
            }
        }
        metrics[.memoryMB] = Double(now.own.footprint) / 1_048_576
        metrics[.peakMemoryMB] = Double(now.own.peakFootprint) / 1_048_576
        section.add("Memory", "\(DiagnosticsFormat.bytes(now.own.footprint)), peak \(DiagnosticsFormat.bytes(now.own.peakFootprint)); helpers \(DiagnosticsFormat.bytes(now.helpers.footprint))")
        section.add("Disk written", DiagnosticsFormat.bytes(now.own.diskWritten))
        let intervals = energy.intervals
        if let hour = EnergySummary(intervals.filter { $0.end > now.date.addingTimeInterval(-3600) }) {
            section.add("Last hour", hour.line)
            if hour.seconds >= Self.energyJudgedAfter { metrics[.recentPowerMW] = hour.ownMW }
        }
        if let battery = EnergySummary(intervals.filter(\.onBattery)) {
            section.add("On battery", battery.line)
            metrics[.powerOnBatteryMW] = battery.ownMW
        }
        if let charger = EnergySummary(intervals.filter { !$0.onBattery }) {
            section.add("On the charger", charger.line)
        }
        // Only whole stretches without a report being collected in them: a few seconds of the
        // report's own tools read as hundreds of milliwatts.
        let judged = intervals.filter { $0.seconds >= Self.energyJudgedAfter && !energy.isCollection($0) }
        if let worst = judged.max(by: { $0.ownMW < $1.ownMW }) {
            section.add("Worst 10 minutes", String(format: "%.1f mW, CPU %.2f%%, %.1f wakeups/s, ending %@",
                                                   worst.ownMW, worst.cpuPercent, worst.wakeupsPerSecond, DiagnosticsFormat.date(worst.end)))
            metrics[.worstPowerMW] = worst.ownMW
        }
        let timeline = intervals.suffix(24).map { interval in
            String(format: "%@  %6.1f mW  helpers %5.1f  CPU %5.2f%%  %6.1f wk/s  %4.0f MB  %@%@%@",
                   interval.end.formatted(date: .omitted, time: .shortened), interval.ownMW, interval.helpersMW,
                   interval.cpuPercent, interval.wakeupsPerSecond, interval.footprintMB,
                   interval.onBattery ? "battery" : "charger",
                   interval.drainPerHour.map { String(format: " −%.1f%%/h", $0) } ?? "",
                   energy.isCollection(interval) ? "  (a report was collected)" : "")
        }
        section.add("Samples", energy.isRunning ? "\(energy.samples.count), every 10 minutes" : "not sampling (diagnostics are off)")
        if !timeline.isEmpty { section.add("Timeline (10-minute steps)", timeline.joined(separator: "\n")) }
        return (section, metrics)
    }

    private func referenceSection(_ metrics: [DiagnosticsMetric: Double]) -> DiagnosticsReport.Section {
        var section = DiagnosticsReport.Section("Compared with the reference")
        if let baseline = references.baseline {
            section.add("Reference", "v\(baseline.version) (\(baseline.build)) on \(baseline.machine), \(String(format: "%.1f", baseline.uptimeHours)) h of running, \(DiagnosticsFormat.date(baseline.created))")
        } else {
            section.add("Reference", "not available (none published, or GitHub unreachable)")
        }
        section.add("Latest version on GitHub", references.latestVersion ?? "unknown")
        for comparison in DiagnosticsComparison.compare(metrics, with: references.baseline) {
            section.add(comparison.isUnusual ? "⚠︎ \(comparison.metric.rawValue)" : comparison.metric.rawValue, comparison.line)
        }
        return section
    }

    /// Where this Mac is set up differently from the reference Mac.
    private func differencesSection(_ settings: [String: String]) -> DiagnosticsReport.Section {
        var section = DiagnosticsReport.Section("Differs from the reference Mac")
        guard let reference = references.baseline?.settings else {
            section.add("Differences", "the reference has no settings to compare with")
            return section
        }
        let lines = DiagnosticsReport.differences(settings, from: reference)
        section.add("Differences", lines.count)
        if !lines.isEmpty { section.add("Settings", lines.prefix(150).joined(separator: "\n")) }
        return section
    }

    @concurrent nonisolated private static func collect(launchedAt: Date, logHours: Int, logSince: Date? = nil, crashesSince: Date?,
                                                         basicOnly: Bool, light: Bool = false) async -> DiagnosticsReport {
        var report = DiagnosticsReport()
        var app = DiagnosticsProbes.bundle(launchedAt: launchedAt)
        app.add("Crash reports kept", DiagnosticsProbes.crashSummary())
        app.add("Report depth", light ? "light (hourly: the Mac's setup, apps and Spotlight are in the full report every 6 h)" : "full")
        report.sections = [app, DiagnosticsProbes.system(), DiagnosticsProbes.permissions()]
        guard !basicOnly else { return report }
        if light {
            report.sections.append(BatteryProbe.section())
            report.metrics[.crashes] = Double(DiagnosticsProbes.crashCount(days: 7))
            // No log: reading it (`log show`, or even this process's own through OSLogStore) waits on
            // the log daemon, whose work is billed to the app (~1.3 s a read, measured). The user's
            // flow and the app's state say what happened; the full report brings the log.
            var section = DiagnosticsReport.Section("Log")
            section.add("Log", "in the full report (every 6 hours, at launch, by hand and with a bug report)")
            report.sections.append(section)
            if let crashesSince {
                report.attachments += DiagnosticsProbes.crashReports(since: crashesSince, limit: 4, perFile: 600_000)
            }
            addSystemReports(to: &report)
            return report
        }
        report.sections += [BatteryProbe.section(), BatteryProbe.topUsers()]
        let spotlight = await DiagnosticsProbes.spotlight()
        report.sections += spotlight.sections
        report.metrics = spotlight.metrics
        report.sections.append(DiagnosticsProbes.hardware())
        report.sections += DiagnosticsEnvironment.sections()
        report.metrics[.crashes] = Double(DiagnosticsProbes.crashCount(days: 7))
        if logHours > 0 {
            let start = logSince ?? Date().addingTimeInterval(-Double(logHours) * 3600)
            let log = DiagnosticsProbes.log(since: start, limit: logLimit)
            let errors = DiagnosticsProbes.errorLines(in: log.text)
            // The log spans earlier runs too, so the rate is over its whole window (an hour at
            // least: a launch's one or two errors over ten minutes are not ten an hour).
            let hours = max(1, Date().timeIntervalSince(start) / 3600)
            report.metrics[.logErrorsPerHour] = Double(errors.count) / hours
            var section = DiagnosticsReport.Section("Log")
            section.add("Errors and faults", "\(errors.count) since \(DiagnosticsFormat.date(start))")
            section.add("Last errors", errors.suffix(15).joined(separator: "\n"))
            report.sections.append(section)
            report.attachments.append(log)
            report.sections.append(DiagnosticsEnvironment.trail(fromLog: log.text))
        }
        if let crashesSince {
            report.attachments += DiagnosticsProbes.crashReports(since: crashesSince, limit: 4, perFile: 600_000)
        }
        addSystemReports(to: &report)
        return report
    }

    nonisolated private static func addSystemReports(to report: inout DiagnosticsReport) {
        let system = DiagnosticsSystemReports.collect()
        report.sections.append(system.section)
        report.attachments += system.attachments
    }

    // MARK: Reference and preview

    /// The developer's Mac: its numbers become the reference for this version
    /// (`docs/diagnostics-baseline.json`, written by `Scripts/publish-baseline.sh`).
    func publishBaseline() async {
        guard isReferenceMac else {
            Log.app.notice("diagnostics/baseline ignored: not the reference Mac")
            return
        }
        state = .sending
        await references.refresh(force: true)
        let report = await makeReport(logHours: Self.reportLogHours, crashesSince: nil)
        // Crashes and unclean exits are judged on their own (any is unusual), never against the
        // developer's Mac, where rebuilds kill the app all the time.
        let judged = report.metrics.filter { $0.key != .crashes && $0.key != .uncleanExits }
        let machine = [report.value("Model", in: "Mac"), report.value("Chip", in: "Mac")].compactMap { $0 }.joined(separator: " · ")
        let replace = defaults.bool(forKey: Self.referenceReplaceKey)
        defaults.removeObject(forKey: Self.referenceReplaceKey)
        let baseline = Self.mergedBaseline(
            DiagnosticsBaseline(
                version: version, build: build, created: Date(), machine: machine,
                uptimeHours: (Date().timeIntervalSince(launchedAt) / 360).rounded() / 10,
                metrics: Dictionary(uniqueKeysWithValues: judged.map { ($0.key.rawValue, ($0.value * 100).rounded() / 100) }),
                rules: references.baseline?.rules, settings: report.settings, settingsCreated: Date()),
            over: replace ? nil : references.baseline)
        guard let data = try? DiagnosticsBaseline.encoder.encode(baseline), let folder = Self.supportFolder else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: folder.appendingPathComponent("diagnostics-baseline.json"), options: .atomic)
        Log.app.notice("diagnostics baseline written")
        if let channel = destinations.baseline {
            let lines = DiagnosticsMetric.allCases.compactMap { metric in baseline.value(metric).map { "\(metric.title): **\(metric.format($0))**" } }
            let payload: [String: Any] = [
                "embeds": [[
                    "title": "📌 Reference for v\(version) (\(build))",
                    "description": DiagnosticsUploader.clipped(lines.joined(separator: "\n"), DiagnosticsUploader.descriptionLimit),
                    "color": 0x8E8E93,
                    "footer": ["text": "\(machine) · \(baseline.uptimeHours) h of running"],
                    "timestamp": Date().formatted(.iso8601),
                ] as [String: Any]],
            ]
            let files = [DiagnosticsEnvelope.File(name: "diagnostics-baseline.json", text: String(decoding: data, as: UTF8.self)),
                         .init(name: "report.txt", text: report.text)]
            _ = try? await DiagnosticsUploader.post(payload, files: files, to: channel)
        }
        state = lastSent.map { .sent($0) } ?? .idle
    }

    /// A new reference over the published one: when this run is shorter than the one the published
    /// numbers come from, on the same Mac, those numbers stay (hours of normal use say more than
    /// minutes after a rebuild) and only the settings, and numbers it lacks, are taken.
    nonisolated static func mergedBaseline(_ new: DiagnosticsBaseline, over old: DiagnosticsBaseline?) -> DiagnosticsBaseline {
        guard let old, old.machine == new.machine, old.uptimeHours > new.uptimeHours else { return new }
        var merged = old
        merged.metrics.merge(new.metrics) { kept, _ in kept }
        merged.settings = new.settings
        merged.settingsCreated = new.settingsCreated
        merged.rules = new.rules ?? old.rules
        return merged
    }

    /// The report as it would be sent, in a folder of its own, opened for the user to read.
    func preview() async {
        state = .sending
        await references.refresh()
        let report = await makeReport(logHours: Self.reportLogHours, crashesSince: Date().addingTimeInterval(-7 * 86400))
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotchIsland Diagnostics \(Int(Date().timeIntervalSince1970))", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let main = folder.appendingPathComponent("report.txt")
        let preview = envelope(kind: .report, reason: .manual, report: report, feedback: nil)
        for file in preview.files {
            try? file.text.write(to: folder.appendingPathComponent(file.name), atomically: true, encoding: .utf8)
        }
        state = lastSent.map { .sent($0) } ?? .idle
        NSWorkspace.shared.activateFileViewerSelecting([main])
        NSWorkspace.shared.open(main)
    }
}

/// The embed's facts and the "quick diagnosis": what looks wrong, read from a report.
nonisolated enum DiagnosticsFindings {
    static func facts(_ report: DiagnosticsReport) -> [DiagnosticsEnvelope.Fact] {
        var facts: [DiagnosticsEnvelope.Fact] = []
        func add(_ name: String, _ value: String?) {
            if let value, !value.isEmpty { facts.append(.init(name: name, value: value)) }
        }
        let version = report.value("Version", in: "App")
        let build = report.value("Build", in: "App")
        add("Version", version.map { v in build.map { "\(v) (\($0))" } ?? v })
        add("macOS", report.value("macOS", in: "Mac")?.replacingOccurrences(of: "Version ", with: ""))
        add("Mac", report.value("Model", in: "Mac"))
        add("Chip", report.value("Chip", in: "Mac"))
        add("Runs from", runsFrom(report))
        add("Accessibility", report.value("Accessibility", in: "Permissions").map { $0 == "true" ? "✅ allowed" : "❌ not allowed" })
        return facts
    }

    static func runsFrom(_ report: DiagnosticsReport) -> String? {
        if report.value("Translocated", in: "App") == "true" { return "Translocated (App Translocation)" }
        if report.value("Run from a disk image", in: "App") == "true" { return "The disk image" }
        if report.value("In /Applications", in: "App") == "true" { return "/Applications" }
        return report.value("Path", in: "App")
    }

    static func findings(_ report: DiagnosticsReport, crashes: Int) -> [String] {
        var found: [String] = []
        if crashes > 0 { found.append("\(crashes) new crash report\(crashes == 1 ? "" : "s") attached") }
        if report.value("Accessibility", in: "Permissions") == "false" {
            found.append("Accessibility is not allowed: ⌘Space for Siri and the volume/brightness keys cannot work")
        }
        if report.value("Translocated", in: "App") == "true" {
            found.append("Runs translocated: it was opened where it was downloaded, not from /Applications")
        } else if report.value("Run from a disk image", in: "App") == "true" {
            found.append("Runs from the disk image instead of /Applications")
        }
        if let signature = report.value("Signature", in: "App"), signature.contains("INVALID") {
            found.append("The code signature is invalid")
        }
        let spotlight = DiagnosticsProbes.spotlightTitle
        if let missing = report.value(DiagnosticsProbes.missingKey, in: spotlight).flatMap(Int.init), missing > 0 {
            found.append("\(missing) app\(missing == 1 ? " is" : "s are") on disk but missing from Spotlight (Siri cannot find them)")
        }
        if let gallery = report.value(DiagnosticsProbes.galleryKey, in: spotlight), gallery.hasPrefix("0 apps") {
            found.append("Siri's app gallery gets no apps from Spotlight")
        }
        let indexing = (report.value("mdutil -s /", in: spotlight) ?? "") + (report.value("mdutil -s /System/Volumes/Data", in: spotlight) ?? "")
        if indexing.localizedCaseInsensitiveContains("disabled") {
            found.append("Spotlight indexing is disabled")
        }
        if let instances = report.value(DiagnosticsAppStateKeys.instances, in: DiagnosticsAppStateKeys.copies).flatMap(Int.init), instances > 1 {
            found.append("\(instances) copies of NotchIsland are running at once")
        }
        if let copies = report.value(DiagnosticsAppStateKeys.copiesOnDisk, in: DiagnosticsAppStateKeys.copies).flatMap(Int.init), copies > 1 {
            found.append("\(copies) copies of NotchIsland on disk")
        }
        if let others = report.value(DiagnosticsAppStateKeys.otherNotchApps, in: "Running apps"), others != "none" {
            found.append("Another notch app is running: \(others)")
        }
        for player in ["Music", "Spotify"] where report.value("Automation: \(player)", in: "Permissions") == "DENIED" {
            found.append("Automation of \(player) is denied")
        }
        if let keys = report.value("Key interception", in: DiagnosticsAppStateKeys.features), keys.hasPrefix("failed") {
            found.append("Volume/brightness key interception failed: \(keys)")
        }
        if report.value("Low Power Mode", in: "Mac") == "true" { found.append("Low Power Mode is on") }
        if let kinds = report.value(DiagnosticsSystemReports.kindsKey, in: DiagnosticsSystemReports.title) {
            found.append("macOS itself reported: \(kinds) (\(DiagnosticsSystemReports.title))")
        }
        // Features the user wants on that are not running (Feature health).
        for entry in report.sections.first(where: { $0.title == "Feature health" })?.entries ?? []
        where entry.value.contains("wanted but not running") && entry.key != "Launch at login" {
            found.append("\(entry.key) is on but not running\(entry.value.components(separatedBy: " — ").dropFirst().first.map { ": \($0)" } ?? "")")
        }
        return found
    }

    /// Findings from the comparison with the reference. Crashes are already reported by the files
    /// attached; an unclean exit without a crash report is spelled out.
    static func anomalies(_ comparisons: [DiagnosticsComparison], metrics: [DiagnosticsMetric: Double], crashes: Int) -> [String] {
        var found = comparisons.filter { $0.isUnusual && $0.metric != .crashes && $0.metric != .uncleanExits }.map(\.line)
        if metrics[.uncleanExits] == 1, crashes == 0 {
            found.append("The previous run did not end normally (force quit, hang, kill or power loss) and left no crash report")
        }
        return found
    }

    /// The embed's comparison: unusual ones first, then the key numbers.
    static func comparisonLines(_ comparisons: [DiagnosticsComparison]) -> [String] {
        let key: [DiagnosticsMetric] = [.powerMW, .recentPowerMW, .powerOnBatteryMW, .cpuPercent, .wakeupsPerSecond, .memoryMB, .spotlightMissingPercent]
        let unusual = comparisons.filter(\.isUnusual)
        let normal = comparisons.filter { !$0.isUnusual && key.contains($0.metric) }
        return unusual.map { "⚠️ \($0.line)" } + normal.map { "✅ \($0.line)" }
    }
}

/// `DiagnosticsAppState`'s section titles and keys, readable off the main actor.
nonisolated enum DiagnosticsAppStateKeys {
    static let copies = "Copies"
    static let features = "Features"
    static let instances = "Instances running"
    static let copiesOnDisk = "Copies on disk"
    static let otherNotchApps = "Other notch apps running"
}
