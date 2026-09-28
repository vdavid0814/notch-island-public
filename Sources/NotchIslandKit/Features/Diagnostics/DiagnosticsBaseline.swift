import Foundation

/// A number every report carries, compared with the developer's own Mac running the version
/// published on GitHub (the reference, `docs/diagnostics-baseline.json`).
nonisolated enum DiagnosticsMetric: String, Sendable, Codable, CaseIterable {
    case powerMW, powerOnBatteryMW, recentPowerMW, worstPowerMW, helpersPowerMW
    case cpuPercent, wakeupsPerSecond
    case memoryMB, peakMemoryMB
    case spotlightMissingPercent, gallerySeconds, appSearchSeconds
    case logErrorsPerHour, crashes, uncleanExits

    var title: String {
        switch self {
        case .powerMW: "Energy use (since launch)"
        case .powerOnBatteryMW: "Energy use on battery"
        case .recentPowerMW: "Energy use (last hour)"
        case .worstPowerMW: "Worst 10 minutes"
        case .helpersPowerMW: "Helper processes' energy"
        case .cpuPercent: "CPU"
        case .wakeupsPerSecond: "Wakeups"
        case .memoryMB: "Memory"
        case .peakMemoryMB: "Peak memory"
        case .spotlightMissingPercent: "Apps missing from Spotlight"
        case .gallerySeconds: "Siri's app list read"
        case .appSearchSeconds: "Slowest app search"
        case .logErrorsPerHour: "Errors in the log"
        case .crashes: "Crash reports (7 days)"
        case .uncleanExits: "Unclean exits"
        }
    }

    func format(_ value: Double) -> String {
        switch self {
        case .powerMW, .powerOnBatteryMW, .recentPowerMW, .worstPowerMW, .helpersPowerMW: String(format: "%.1f mW", value)
        case .cpuPercent: String(format: "%.2f%%", value)
        case .wakeupsPerSecond: String(format: "%.1f/s", value)
        case .memoryMB, .peakMemoryMB: String(format: "%.0f MB", value)
        case .spotlightMissingPercent: String(format: "%.0f%%", value)
        case .gallerySeconds, .appSearchSeconds: DiagnosticsFormat.duration(value)
        case .logErrorsPerHour: String(format: "%.1f/h", value)
        case .crashes, .uncleanExits: String(format: "%.0f", value)
        }
    }

    /// When a value counts as unusual: at least `minimum`, and more than `factor` times the
    /// reference. The reference file can override these without a new release.
    nonisolated struct Rule: Sendable, Codable, Equatable {
        var factor: Double
        var minimum: Double
    }

    var defaultRule: Rule {
        switch self {
        case .powerMW, .powerOnBatteryMW, .recentPowerMW: Rule(factor: 2.5, minimum: 25)
        case .worstPowerMW: Rule(factor: 3, minimum: 80)
        case .helpersPowerMW: Rule(factor: 3, minimum: 20)
        case .cpuPercent: Rule(factor: 2.5, minimum: 1)
        case .wakeupsPerSecond: Rule(factor: 3, minimum: 20)
        case .memoryMB: Rule(factor: 2, minimum: 250)
        case .peakMemoryMB: Rule(factor: 2, minimum: 400)
        case .spotlightMissingPercent: Rule(factor: 2, minimum: 10)
        case .gallerySeconds, .appSearchSeconds: Rule(factor: 4, minimum: 1)
        case .logErrorsPerHour: Rule(factor: 4, minimum: 5)
        case .crashes, .uncleanExits: Rule(factor: 1, minimum: 1)
        }
    }

    /// The ones a 10-minute sample can be checked on while the app runs.
    static let live: [DiagnosticsMetric] = [.recentPowerMW, .wakeupsPerSecond, .memoryMB]
}

/// The developer's reference: the numbers from their Mac for the published version.
nonisolated struct DiagnosticsBaseline: Sendable, Codable, Equatable {
    var version: String
    var build: String
    var created: Date
    var machine: String
    var uptimeHours: Double
    var metrics: [String: Double]
    /// Overrides of `DiagnosticsMetric.defaultRule`, by metric name.
    var rules: [String: DiagnosticsMetric.Rule]?
    /// The reference Mac's settings (`DiagnosticsReport.settings`), so a report can list where a
    /// user's Mac is set up differently; and when they were taken (later than the numbers when only
    /// the settings were refreshed).
    var settings: [String: String]?
    var settingsCreated: Date?

    static let repository = "vdavid0814/notch-island-public"
    static let url = URL(string: "https://raw.githubusercontent.com/\(repository)/main/docs/diagnostics-baseline.json")!
    static let latestReleaseURL = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!

    func value(_ metric: DiagnosticsMetric) -> Double? { metrics[metric.rawValue] }

    func rule(_ metric: DiagnosticsMetric) -> DiagnosticsMetric.Rule { rules?[metric.rawValue] ?? metric.defaultRule }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

/// One metric set against the reference.
nonisolated struct DiagnosticsComparison: Sendable, Equatable {
    var metric: DiagnosticsMetric
    var value: Double
    var reference: Double?
    var isUnusual: Bool

    /// "Energy use (since launch): 41.0 mW — 3.4× the reference (12.0 mW)".
    var line: String {
        let head = "\(metric.title): \(metric.format(value))"
        guard let reference else { return head }
        if reference > 0 {
            return head + String(format: " — %.1f× the reference (%@)", value / reference, metric.format(reference))
        }
        return head + " — reference \(metric.format(reference))"
    }

    static func compare(_ metrics: [DiagnosticsMetric: Double], with baseline: DiagnosticsBaseline?) -> [DiagnosticsComparison] {
        DiagnosticsMetric.allCases.compactMap { metric in
            guard let value = metrics[metric] else { return nil }
            let reference = baseline?.value(metric)
            let rule = baseline?.rule(metric) ?? metric.defaultRule
            return DiagnosticsComparison(metric: metric, value: value, reference: reference,
                                         isUnusual: isUnusual(value, reference: reference, rule: rule))
        }
    }

    /// Unusual: past the minimum and past `factor` times the reference. Without a reference only
    /// the counts (crashes, unclean exits) can be judged.
    static func isUnusual(_ value: Double, reference: Double?, rule: DiagnosticsMetric.Rule) -> Bool {
        guard value >= rule.minimum else { return false }
        guard let reference else { return rule.factor <= 1 }
        return reference <= 0 || value > reference * rule.factor
    }
}

/// The newest version on GitHub, "0.4.4" from the tag "v0.4.4".
nonisolated enum DiagnosticsVersions {
    static func normalized(_ tag: String) -> String {
        tag.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
    }

    /// True if `version` is older than `latest` ("0.4.3.1" < "0.4.4").
    static func isOlder(_ version: String, than latest: String) -> Bool {
        normalized(version).compare(normalized(latest), options: .numeric) == .orderedAscending
    }
}

/// Fetches the reference and the latest release from GitHub, at most every `lifetime`. A fetch
/// that failed is tried again after `retry`, not a whole `lifetime` later.
final class DiagnosticsReferenceStore {
    static let lifetime: TimeInterval = 3600
    static let retry: TimeInterval = 5 * 60

    private(set) var baseline: DiagnosticsBaseline?
    private(set) var latestVersion: String?
    private var fetched: Date?
    private var fetching: Task<Void, Never>?

    func refresh(force: Bool = false) async {
        if let fetching { return await fetching.value }
        if !force, let fetched, Date().timeIntervalSince(fetched) < Self.lifetime { return }
        let task = Task {
            async let baseline = Self.fetchBaseline()
            async let latest = Self.fetchLatestVersion()
            let (b, l) = await (baseline, latest)
            if let b { self.baseline = b }
            if let l { self.latestVersion = l }
            // Both came: good for a `lifetime`. Otherwise try again soon (a release published an
            // hour ago must not wait half a day to show up, as it did in v0.4.5).
            self.fetched = b != nil && l != nil ? Date() : Date().addingTimeInterval(Self.retry - Self.lifetime)
            self.fetching = nil
        }
        fetching = task
        await task.value
    }

    @concurrent nonisolated private static func fetchBaseline() async -> DiagnosticsBaseline? {
        var request = URLRequest(url: DiagnosticsBaseline.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("close", forHTTPHeaderField: "Connection")
        request.setValue("NotchIsland", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? DiagnosticsBaseline.decoder.decode(DiagnosticsBaseline.self, from: data)
    }

    @concurrent nonisolated private static func fetchLatestVersion() async -> String? {
        var request = URLRequest(url: DiagnosticsBaseline.latestReleaseURL, timeoutInterval: 20)
        // One request an hour: a connection kept open for the next one only times out (logged as
        // network errors in every report).
        request.setValue("close", forHTTPHeaderField: "Connection")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("NotchIsland", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let tag = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["tag_name"] as? String else { return nil }
        return DiagnosticsVersions.normalized(tag)
    }
}
