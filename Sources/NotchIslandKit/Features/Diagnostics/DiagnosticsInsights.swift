import Foundation

/// What the user did, step by step, for the report: the island opening and closing, banners,
/// Siri's queries with what they found and what was picked, the liquid cards. A ring of the last
/// `capacity` steps in memory (no log read needed), so a report shows how the user got to where
/// something went wrong ("Siri does not bring up my apps": what was typed, what came back).
@MainActor enum DiagnosticsFlow {
    static let capacity = 300
    private(set) static var steps: [String] = []
    private static let clock = Date.ISO8601FormatStyle(includingFractionalSeconds: true).time(includingFractionalSeconds: true)

    static func record(_ step: String) {
        steps.append("\(Date().formatted(clock)) \(step)")
        if steps.count > capacity { steps.removeFirst(steps.count - capacity) }
    }

    static func section() -> DiagnosticsReport.Section {
        var section = DiagnosticsReport.Section("User flow")
        section.add("Steps", steps.isEmpty ? "none since launch" : "\(steps.count) (last \(capacity) kept)")
        if !steps.isEmpty { section.add("Flow", steps.joined(separator: "\n")) }
        return section
    }
}

/// The deeper reading of a report: crash reports taken apart, the log's errors by where they come
/// from, and the likely cause of each finding with what fixes it.
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
    static func errorSection(_ log: String) -> DiagnosticsReport.Section {
        var counts: [String: (count: Int, example: Substring)] = [:]
        for line in DiagnosticsProbes.errorLines(in: log) {
            let source = line.firstRange(of: /\[[A-Za-z][^\]\s]*:[^\]]*\]/).map { String(line[$0]) }
                ?? (line.contains("(CoreAudio)") ? "(CoreAudio)" : "(other)")
            let entry = counts[source]
            counts[source] = ((entry?.count ?? 0) + 1, entry?.example ?? line)
        }
        var section = DiagnosticsReport.Section("Errors by source")
        let sorted = counts.sorted { $0.value.count > $1.value.count }
        let own = sorted.filter { $0.key.contains("com.davidvarga.notchisland") }
        section.add("NotchIsland's own", own.isEmpty ? "none" : own.map { "\($0.key) \($0.value.count)×" }.joined(separator: ", "))
        for (source, value) in sorted.prefix(12) {
            section.add("\(value.count)× \(source)", String(value.example.suffix(220)))
        }
        return section
    }

    // MARK: Likely causes

    /// For each thing that looks wrong, what most likely causes it and what fixes it, read from the
    /// report's own lines.
    static func causes(_ report: DiagnosticsReport, metrics: [DiagnosticsMetric: Double]) -> [String] {
        var causes: [String] = []
        let spotlight = DiagnosticsProbes.spotlightTitle
        if let missing = report.value(DiagnosticsProbes.missingKey, in: spotlight).flatMap(Int.init), missing > 0 {
            causes.append("\(missing) app(s) missing from Spotlight → the index is incomplete (usually after a migration or restore). Siri reads the app folders itself, so apps still show; macOS's Spotlight re-indexes with `sudo mdutil -E /`.")
        }
        if let copies = report.value("Copies", in: DiagnosticsAppStateKeys.copies), copies.contains("/Volumes/") {
            causes.append("Copies of NotchIsland on mounted disk images → an old DMG is still mounted; eject it in Finder (harmless, but Launch Services may pick the wrong copy).")
        }
        if metrics[.uncleanExits] == 1, (metrics[.crashes] ?? 0) == 0 {
            causes.append("The last run ended without quitting and without a crash report → force quit, a kill (an update or rebuild replacing the app), or the Mac shutting down; a hang would leave a .hang report.")
        }
        if let login = report.value("Launch at login", in: DiagnosticsAppStateKeys.features), login.contains("not found") {
            causes.append("Launch at login is not registered → turn it on in Settings ▸ General (the app must run from /Applications).")
        }
        if let keys = report.value("Key interception", in: DiagnosticsAppStateKeys.features), keys.hasPrefix("failed") {
            causes.append("The volume/brightness keys are not intercepted → Accessibility or Input Monitoring was withdrawn; allow NotchIsland again in System Settings ▸ Privacy & Security.")
        }
        if let power = metrics[.powerMW], let helpers = metrics[.helpersPowerMW], helpers > power * 0.5, helpers > 5 {
            causes.append("Most of the energy is the helper processes (the MediaRemote adapter for browser media) → a browser tab kept reporting playback.")
        }
        if let interfering = report.value(DiagnosticsEnvironment.interferingKey, in: DiagnosticsEnvironment.appsTitle), interfering != "none" {
            causes.append("Installed apps that may take the notch, the HUD or the keys: \(interfering) → if one runs, it can hide or duplicate the island's banners.")
        }
        if report.value("Accessibility", in: "Permissions") == "false" {
            causes.append("Accessibility is off → ⌘Space for Siri and the volume/brightness keys cannot work; allow it in System Settings ▸ Privacy & Security ▸ Accessibility.")
        }
        return causes
    }
}
