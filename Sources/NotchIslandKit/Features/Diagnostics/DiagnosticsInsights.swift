import Foundation

/// What the user did, step by step, for the report: the island opening and closing, banners,
/// Siri's queries with what they found and what was picked, the liquid cards. A ring of the last
/// `capacity` steps in memory (no log read needed), so a report shows how the user got to where
/// something went wrong ("Siri does not bring up my apps": what was typed, what came back).
@MainActor enum DiagnosticsFlow {
    static let capacity = 300
    private(set) static var steps: [String] = []
    private static let clock = Date.ISO8601FormatStyle(includingFractionalSeconds: true).time(includingFractionalSeconds: true)

    /// Each step as it is recorded (`Telemetry`'s breadcrumbs, while diagnostics are on).
    static var onRecord: ((String) -> Void)?

    static func record(_ step: String) {
        steps.append("\(Date().formatted(clock)) \(step)")
        if steps.count > capacity { steps.removeFirst(steps.count - capacity) }
        onRecord?(step)
    }

    static func section() -> DiagnosticsReport.Section {
        var section = DiagnosticsReport.Section("User flow")
        section.add("Steps", steps.isEmpty ? "none since launch" : "\(steps.count) (last \(capacity) kept)")
        if !steps.isEmpty { section.add("Flow", steps.joined(separator: "\n")) }
        return section
    }
}

/// The deeper reading of a report: crash reports taken apart and the log's errors by where they
/// come from (the likely causes are `DiagnosticsVerdict`'s).
nonisolated enum DiagnosticsInsights {
    // MARK: Crashes

    /// Each crash, hang or resource report attached: what happened and where (the crashed thread's
    /// top frames), read from the `.ips` JSON.
    static func crashSection(_ attachments: [DiagnosticsReport.Attachment]) -> DiagnosticsReport.Section? {
        let reports = attachments.filter(\.isCrashReport)
        guard !reports.isEmpty else { return nil }
        var section = DiagnosticsReport.Section("Crash analysis")
        for report in reports {
            section.add(report.name, crashSummary(report.text))
        }
        return section
    }

    static func crashSummary(_ text: String) -> String {
        // An .ips file: a one-line JSON header, then the JSON body.
        let parts = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2,
              let header = try? JSONSerialization.jsonObject(with: Data(parts[0].utf8)) as? [String: Any],
              let body = try? JSONSerialization.jsonObject(with: Data(parts[1].utf8)) as? [String: Any] else {
            return String(text.prefix(600))
        }
        var lines: [String] = []
        lines.append("\(header["bug_type"].map { "type \($0)" } ?? "report"), app \(header["app_version"] ?? "?") (\(header["build_version"] ?? "?")), \(header["timestamp"] ?? "")")
        if let exception = body["exception"] as? [String: Any] {
            lines.append("exception: \(exception["type"] ?? "?") \(exception["signal"] ?? "") \(exception["subtype"] ?? "")")
        }
        if let termination = body["termination"] as? [String: Any] {
            lines.append("termination: \(termination["namespace"] ?? "?") \(termination["indicator"] ?? termination["code"] ?? "")")
        }
        if let asi = body["asi"] as? [String: Any], !asi.isEmpty {
            lines.append("message: " + asi.values.compactMap { ($0 as? [String])?.joined(separator: " ") }.joined(separator: " | "))
        }
        let images = (body["usedImages"] as? [[String: Any]])?.map { $0["name"] as? String ?? "?" } ?? []
        let threads = body["threads"] as? [[String: Any]] ?? []
        if let crashed = threads.firstIndex(where: { $0["triggered"] as? Bool == true }) {
            let frames = (threads[crashed]["frames"] as? [[String: Any]] ?? []).prefix(10)
            lines.append("crashed thread \(crashed)\((threads[crashed]["queue"] as? String).map { " (\($0))" } ?? ""):")
            for (index, frame) in frames.enumerated() {
                let image = (frame["imageIndex"] as? Int).flatMap { images.indices.contains($0) ? images[$0] : nil } ?? "?"
                let symbol = frame["symbol"] as? String ?? "offset \(frame["imageOffset"] ?? "?")"
                lines.append("  \(index) \(image)  \(symbol)")
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Errors by source

    /// The log's errors and faults counted by subsystem and category (NotchIsland's own by
    /// feature), the most frequent first, with one example each.
    ///
    /// NotchIsland's own are this run's only (`pid`): the log reaches back over earlier runs, and
    /// theirs became this run's findings and Sentry issues under this version (0.8.2's three
    /// refused key taps, two hours and an update earlier, as 0.8.3's). Earlier runs' are listed
    /// apart, uncounted; their lines are in log.txt.
    static func errorSection(_ log: String, pid: Int32 = ProcessInfo.processInfo.processIdentifier) -> DiagnosticsReport.Section {
        var counts: [String: (count: Int, example: Substring)] = [:]
        var earlier: [String: (count: Int, last: Substring)] = [:]
        let thisRun = "NotchIsland[\(pid):"
        let own = "[\(Log.subsystem):"
        // The system's known messages are not errors: they have a section of their own.
        for line in DiagnosticsProbes.errorLines(in: log) where !DiagnosticsProbes.isKnownNoise(line) {
            let found = line.firstRange(of: /\[[A-Za-z][^\]\s]*:[^\]]*\]/).map { String(line[$0]) }
                ?? (line.contains("(CoreAudio)") ? "(CoreAudio)" : "(other)")
            let source = found
            if source.hasPrefix(own), !line.contains(thisRun) {
                earlier[source] = ((earlier[source]?.count ?? 0) + 1, line)
                continue
            }
            let entry = counts[source]
            counts[source] = ((entry?.count ?? 0) + 1, entry?.example ?? line)
        }
        var section = DiagnosticsReport.Section("Errors by source")
        let sorted = counts.sorted { $0.value.count > $1.value.count }
        let ownSources = sorted.filter { $0.key.hasPrefix(own) }
        section.add("NotchIsland's own", ownSources.isEmpty ? "none" : ownSources.map { "\($0.key) \($0.value.count)×" }.joined(separator: ", "))
        if !earlier.isEmpty {
            // "…:levels] 3× (last 2026-10-10 10:40:12)"
            section.add(earlierRunsKey, earlier.sorted { $0.value.count > $1.value.count }
                .map { "\($0.key) \($0.value.count)× (last \($0.value.last.prefix(19)))" }.joined(separator: ", "))
        }
        for (source, value) in sorted.prefix(12) {
            section.add("\(value.count)× \(source)", example(value.example, source: source))
        }
        return section
    }

    static let earlierRunsKey = "NotchIsland's own, earlier runs (not counted)"

    /// When, where and what the message starts with: the line's end alone ("…face alpha 1.0") told
    /// nothing, and became a Sentry issue's title.
    static func example(_ line: Substring, source: String) -> String {
        guard let range = line.range(of: source) else { return String(line.prefix(220)) }
        let when = line.prefix(23)
        let message = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
        return "\(when) \(source) \(message.prefix(200))"
    }
}
