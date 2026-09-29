import Foundation

/// The report read for the developer in one place: how many things are wrong, how many only look
/// off and how many work, the most likely cause with what fixes it, the features it touches, and
/// what changed since the previous report. Built from the report's own lines (feature health,
/// permissions, crashes, macOS's reports, the comparison with the reference, Siri's searches, the
/// log's own errors), so it costs nothing to collect.
///
/// A bug report's text steers it: the checks of the feature the user complains about come first
/// ("Siri does not bring up my apps" → Siri), so the cause answers the complaint.
nonisolated struct DiagnosticsVerdict: Sendable, Codable, Equatable {
    nonisolated enum Severity: String, Sendable, Codable, Comparable {
        case issue, warning, healthy

        static func < (a: Severity, b: Severity) -> Bool { a.rank < b.rank }
        private var rank: Int { switch self { case .issue: 0; case .warning: 1; case .healthy: 2 } }

        var icon: String { switch self { case .issue: "🟠"; case .warning: "🟡"; case .healthy: "🟢" } }
    }

    nonisolated enum Confidence: String, Sendable, Codable {
        /// A direct sign: a permission missing, a crash, no app found.
        case high
        /// Read from something else: energy past the reference, an exit without a report.
        case medium
    }

    nonisolated struct Check: Sendable, Codable, Equatable {
        /// Stable across reports ("feature.Now Playing", "siri.noApp"): what is new or resolved.
        var id: String
        var severity: Severity
        var feature: String
        var title: String
        var cause: String = ""
        var action: String = ""
        var confidence: Confidence = .high
        /// Among checks of one severity, the higher first.
        var weight = 0

        var line: String {
            "\(severity.icon) [\(feature)] \(title)" + (cause.isEmpty ? "" : " — \(cause)") + (action.isEmpty ? "" : " → \(action)")
        }
    }

    var checks: [Check] = []
    /// NotchIsland's own errors in the log, or why they were not read.
    var ownErrors = "0"
    /// The feature the user's complaint points at, if it does.
    var focus: String?
    /// Problems new since the previous report, and the ones gone (their titles).
    var new: [String] = []
    var resolved: [String] = []

    var problems: [Check] { checks.filter { $0.severity != .healthy } }
    var issues: Int { checks.count { $0.severity == .issue } }
    var warnings: Int { checks.count { $0.severity == .warning } }
    var healthy: Int { checks.count { $0.severity == .healthy } }

    /// The complaint's feature first if something is wrong there, else the gravest.
    var mostLikely: Check? {
        if let focus, let match = problems.first(where: { $0.feature == focus }) { return match }
        return problems.first
    }

    var affectedFeatures: [String] {
        var seen = Set<String>()
        return problems.map(\.feature).filter { seen.insert($0).inserted }
    }

    /// Problems by id, stored after a report went out (`previous` of the next one).
    var remembered: [String: String] {
        Dictionary(problems.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
    }

    var counts: String { "🟠 \(issues) · 🟡 \(warnings) · 🟢 \(healthy)" }

    /// One line for the top of report.txt.
    var headline: String {
        "Verdict: \(counts)" + (mostLikely.map { " — most likely: [\($0.feature)] \($0.title)" } ?? " — nothing wrong found")
    }

    /// The summary at the end of the report.
    var section: DiagnosticsReport.Section {
        var section = DiagnosticsReport.Section(Self.title)
        section.add("🟠 Issues", issues)
        section.add("🟡 Warnings", warnings)
        section.add("🟢 Healthy", healthy)
        if let focus { section.add("The complaint points at", focus) }
        if let top = mostLikely {
            section.add(Self.causeKey, "[\(top.feature)] \(top.title)" + (top.cause.isEmpty ? "" : " — \(top.cause)")
                        + " (confidence: \(top.confidence.rawValue))")
        } else {
            section.add(Self.causeKey, "nothing wrong found")
        }
        section.add("Affected features", affectedFeatures.isEmpty ? "none" : affectedFeatures.joined(separator: ", "))
        section.add("NotchIsland-owned errors", ownErrors)
        section.add(Self.actionKey, mostLikely.map { $0.action.isEmpty ? "—" : $0.action } ?? "nothing to do")
        if !new.isEmpty { section.add("New since the last report", new.joined(separator: "\n")) }
        if !resolved.isEmpty { section.add("Resolved since the last report", resolved.joined(separator: "\n")) }
        if !problems.isEmpty { section.add("All problems", problems.map(\.line).joined(separator: "\n")) }
        let working = checks.filter { $0.severity == .healthy }.map(\.feature)
        if !working.isEmpty { section.add("Working", working.joined(separator: ", ")) }
        return section
    }

    /// The problems with their causes and fixes, near the top of the report.
    var causesSection: DiagnosticsReport.Section {
        var section = DiagnosticsReport.Section("Likely causes")
        section.add("Causes", problems.isEmpty ? "nothing stands out"
                    : problems.map { "• [\($0.feature)] \($0.title)" + ($0.cause.isEmpty ? "" : ": \($0.cause)")
                        + ($0.action.isEmpty ? "" : " → \($0.action)") }.joined(separator: "\n"))
        return section
    }

    /// The embed's first field.
    var embedText: String {
        var lines = [counts]
        if let top = mostLikely {
            lines.append("**Most likely:** [\(top.feature)] \(top.title)" + (top.cause.isEmpty ? "" : " — \(top.cause)"))
            if !top.action.isEmpty { lines.append("**Do:** \(top.action)") }
        } else {
            lines.append("✅ Nothing wrong found")
        }
        if affectedFeatures.count > 1 { lines.append("**Affected:** " + affectedFeatures.joined(separator: ", ")) }
        lines.append("**Own errors:** \(ownErrors)")
        if !new.isEmpty { lines.append("**New:** " + new.joined(separator: "; ")) }
        if !resolved.isEmpty { lines.append("**Resolved:** " + resolved.joined(separator: "; ")) }
        return lines.joined(separator: "\n")
    }

    static let title = "Summary"
    static let causeKey = "Most likely cause"
    static let actionKey = "Recommended action"
    static let rememberedKey = "ni2.diagnostics.lastVerdict"
}

// MARK: - Reading a report

nonisolated extension DiagnosticsVerdict {
    enum Feature {
        static let app = "App"
        static let siri = "Siri"
        static let keys = "Volume/brightness keys"
        static let nowPlaying = "Now Playing"
        static let liquid = "Liquid volume card"
        static let energy = "Energy"
        static let memory = "Memory"
        static let install = "Installation"
        static let battery = "Battery notices"
        static let timers = "Timers"
        static let shelf = "Shelf"
        static let island = "Island"
        static let airPods = "AirPods"
    }

    static func make(report: DiagnosticsReport, metrics: [DiagnosticsMetric: Double], comparisons: [DiagnosticsComparison],
                     crashes: Int, complaint: String? = nil, outdated: String? = nil,
                     previous: [String: String]? = nil) -> DiagnosticsVerdict {
        var checks: [Check] = []
        checks += featureHealth(report)
        checks += permissions(report)
        checks += crashChecks(report, crashes: crashes, metrics: metrics)
        checks += systemReports(report)
        checks += energy(comparisons, metrics: metrics)
        checks += siri(report)
        checks += installation(report, outdated: outdated)
        let own = ownErrors(report)
        checks += own.checks

        var verdict = DiagnosticsVerdict()
        verdict.focus = complaint.flatMap(focus)
        let focus = verdict.focus
        verdict.checks = checks.sorted { a, b in
            if a.severity != b.severity { return a.severity < b.severity }
            let fa = a.feature == focus, fb = b.feature == focus
            if fa != fb { return fa }
            return a.weight > b.weight
        }
        verdict.ownErrors = own.summary
        if let previous {
            let now = verdict.remembered
            verdict.new = verdict.problems.filter { previous[$0.id] == nil }.map { "[\($0.feature)] \($0.title)" }
            verdict.resolved = previous.filter { now[$0.key] == nil }.map(\.value).sorted()
        }
        return verdict
    }

    /// Feature health's lines: running is healthy, wanted but not running an issue.
    static func featureHealth(_ report: DiagnosticsReport) -> [Check] {
        let entries = report.sections.first { $0.title == "Feature health" }?.entries ?? []
        return entries.compactMap { entry in
            let detail = entry.value.components(separatedBy: " — ").dropFirst().joined(separator: " — ")
            if entry.value.hasPrefix("✅") {
                return Check(id: "feature.\(entry.key)", severity: .healthy, feature: entry.key, title: "running")
            }
            guard entry.value.contains("wanted but not running") else { return nil }
            // Not registered is common in a copy outside /Applications; the rest stops a feature.
            let severity: Severity = entry.key == "Launch at login" ? .warning : .issue
            return Check(id: "feature.\(entry.key)", severity: severity, feature: feature(forHealth: entry.key),
                         title: "\(entry.key) is on but not running", cause: detail, action: action(forHealth: entry.key), weight: 50)
        }
    }

    static func feature(forHealth name: String) -> String {
        switch name {
        case "⌘Space for Siri", "Siri's files": Feature.siri
        case "Volume/brightness keys", "Accessibility": Feature.keys
        default: name
        }
    }

    static func action(forHealth name: String) -> String {
        switch name {
        case "Accessibility", "Volume/brightness keys", "⌘Space for Siri":
            "Allow NotchIsland in System Settings ▸ Privacy & Security ▸ Accessibility (and Input Monitoring), then quit and reopen it"
        case "Now Playing":
            "Allow NotchIsland to control Music and Spotify in System Settings ▸ Privacy & Security ▸ Automation; reopen it"
        case "Launch at login":
            "Turn it on in Settings ▸ General; NotchIsland must run from /Applications"
        case "Siri's files":
            "Allow the folders when macOS asks, or in System Settings ▸ Privacy & Security ▸ Files and Folders"
        default:
            "Quit and reopen NotchIsland; if it stays so, send a bug report"
        }
    }

    static func permissions(_ report: DiagnosticsReport) -> [Check] {
        ["Music", "Spotify"].compactMap { player in
            guard report.value("Automation: \(player)", in: "Permissions") == "DENIED" else { return nil }
            return Check(id: "permission.automation.\(player)", severity: .warning, feature: Feature.nowPlaying,
                         title: "Automation of \(player) is denied", cause: "the island cannot read or control \(player)",
                         action: action(forHealth: "Now Playing"), weight: 30)
        }
    }

    /// Crash reports (the feature from the crashed thread's own frames), an exit without one.
    static func crashChecks(_ report: DiagnosticsReport, crashes: Int, metrics: [DiagnosticsMetric: Double]) -> [Check] {
        var checks: [Check] = []
        for entry in report.sections.first(where: { $0.title == "Crash analysis" })?.entries ?? [] {
            let lines = entry.value.components(separatedBy: "\n")
            let own = lines.filter { $0.contains(" NotchIsland") && !$0.contains("offset ") }
            let feature = own.lazy.compactMap(featureFromCode).first ?? Feature.app
            let what = lines.first { $0.hasPrefix("exception:") || $0.hasPrefix("termination:") } ?? lines.first ?? ""
            let frame = own.first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
            checks.append(Check(id: "crash.\(feature)", severity: .issue, feature: feature, title: "NotchIsland crashed",
                                cause: [what, frame].filter { !$0.isEmpty }.joined(separator: "; at "),
                                action: "Update to the newest version; if it still crashes, the attached report shows where",
                                weight: 100))
        }
        if crashes == 0, metrics[.uncleanExits] == 1 {
            checks.append(Check(id: "app.uncleanExit", severity: .warning, feature: Feature.app,
                                title: "The last run ended without quitting and without a crash report",
                                cause: "force quit, a kill (an update replacing the app), a hang or the Mac shutting down",
                                action: "If NotchIsland froze, a hang shows under macOS's own reports next time",
                                confidence: .medium, weight: 10))
        }
        return checks
    }

    /// Which feature a symbol belongs to ("LiquidCard.hide()" → the liquid card).
    static func featureFromCode(_ text: String) -> String? {
        let table: [(String, String)] = [
            ("Liquid", Feature.liquid), ("SystemVolumeCard", Feature.liquid), ("Assistant", Feature.siri),
            ("CommandSpace", Feature.siri), ("MediaKey", Feature.keys), ("Levels", Feature.keys), ("Volume", Feature.keys),
            ("Brightness", Feature.keys), ("Media", Feature.nowPlaying), ("Spectrum", Feature.nowPlaying),
            ("Equalizer", Feature.nowPlaying), ("AirPods", Feature.airPods), ("Timer", Feature.timers),
            ("Shelf", Feature.shelf), ("Battery", Feature.battery), ("Power", Feature.battery), ("Diagnostics", Feature.app),
            ("Island", Feature.island), ("Banner", Feature.island),
        ]
        return table.first { text.contains($0.0) }?.1
    }

    /// macOS's own reports (MetricKit): hangs and crashes are issues, CPU and disk exceptions warnings.
    static func systemReports(_ report: DiagnosticsReport) -> [Check] {
        let entries = report.sections.first { $0.title == DiagnosticsSystemReports.title }?.entries ?? []
        return entries.filter { $0.key.hasPrefix(DiagnosticsSystemReports.prefix) }.map { entry in
            let headline = entry.value.components(separatedBy: "\n").first ?? entry.value
            let isHang = headline.hasPrefix("Main thread hung"), isCrash = headline.hasPrefix("Crash")
            return Check(id: "system.\(isHang ? "hang" : isCrash ? "crash" : "exception")",
                         severity: isHang || isCrash ? .issue : .warning,
                         feature: isHang ? Feature.island : isCrash ? Feature.app : Feature.energy,
                         title: headline, cause: "macOS's own report, with the call stacks it sampled",
                         action: "The attached system-*.json locates it (NotchIsland's offsets symbolicate against the build)",
                         weight: isCrash ? 90 : 60)
        }
    }

    /// Energy, wakeups and memory well past the reference Mac's.
    static func energy(_ comparisons: [DiagnosticsComparison], metrics: [DiagnosticsMetric: Double]) -> [Check] {
        var checks = comparisons.filter { $0.isUnusual && $0.metric != .crashes && $0.metric != .uncleanExits }.map { comparison in
            let memory = comparison.metric == .memoryMB || comparison.metric == .peakMemoryMB
            let siri = comparison.metric == .spotlightMissingPercent || comparison.metric == .gallerySeconds
                || comparison.metric == .appSearchSeconds
            let errors = comparison.metric == .logErrorsPerHour
            return Check(id: "metric.\(comparison.metric.rawValue)", severity: .warning,
                         feature: memory ? Feature.memory : siri ? Feature.siri : errors ? Feature.app : Feature.energy,
                         title: comparison.metric.title + " past the reference", cause: comparison.line,
                         action: memory ? "Compare Windows and Island internals with the reference; a surface left open holds memory"
                             : errors ? "See Errors by source: mostly the system's, unless NotchIsland's own are listed"
                             : "See the Energy timeline and Top energy users: a browser tab reporting playback is the usual cause",
                         // The log's rate is mostly the system's noise: last among the warnings.
                         confidence: .medium, weight: errors ? 2 : 20)
        }
        if let power = metrics[.powerMW], let helpers = metrics[.helpersPowerMW], helpers > power * 0.5, helpers > 5 {
            checks.append(Check(id: "energy.helpers", severity: .warning, feature: Feature.nowPlaying,
                                title: "Most of the energy is the helper processes",
                                cause: String(format: "%.1f of %.1f mW: the MediaRemote adapter for browser media", helpers, power + helpers),
                                action: "A browser tab kept reporting playback: turn off browser playback in Live Activities if it stays",
                                confidence: .medium, weight: 25))
        }
        return checks
    }

    /// Siri's app list and searches: no apps at all, apps missing from Spotlight, and searches the
    /// user made that found no app (from the user's steps).
    static func siri(_ report: DiagnosticsReport) -> [Check] {
        var checks: [Check] = []
        let spotlight = DiagnosticsProbes.spotlightTitle
        if let gallery = report.value(DiagnosticsProbes.galleryKey, in: spotlight), gallery.hasPrefix("0 apps") {
            checks.append(Check(id: "siri.noGallery", severity: .issue, feature: Feature.siri, title: "Siri's app list is empty",
                                cause: "neither Spotlight nor the app folders gave any app",
                                action: "Re-index Spotlight (`sudo mdutil -E /`) and check the app folders are readable", weight: 80))
        }
        if let missing = report.value(DiagnosticsProbes.missingKey, in: spotlight).flatMap(Int.init), missing > 0 {
            // Not a problem for Siri: it reads the app folders too (only macOS's Spotlight misses them).
            checks.append(Check(id: "siri.findsWhatSpotlightMisses", severity: .healthy, feature: Feature.siri,
                                title: "finds the \(missing) app\(missing == 1 ? "" : "s") Spotlight's index misses"))
        }
        let elsewhere = report.value(DiagnosticsProbes.elsewhereKey, in: spotlight).flatMap { $0 == "none" ? nil : $0 }
        let misses = searchesWithoutApps(report)
        if !misses.isEmpty {
            let names = elsewhere?.lowercased() ?? ""
            let outside = misses.filter { query in names.contains("/" + query.lowercased()) || names.contains(query.lowercased() + ".app") }
            let quoted = misses.map { "\"\($0)\"" }.joined(separator: ", ")
            if !outside.isEmpty {
                checks.append(Check(id: "siri.appOutsideFolders", severity: .issue, feature: Feature.siri,
                                    title: "Siri found no app for \(outside.map { "\"\($0)\"" }.joined(separator: ", "))",
                                    cause: "the app lies outside the app folders: \(elsewhere ?? "")",
                                    action: "Update to v0.4.10 or later (it finds apps anywhere Spotlight does), or move the app to /Applications",
                                    weight: 70))
            } else {
                checks.append(Check(id: "siri.noAppFound", severity: .warning, feature: Feature.siri,
                                    title: "Siri found no app for \(quoted)",
                                    cause: "no installed app by that name, as far as Spotlight and the app folders know (or those were file searches)",
                                    action: "Compare with the app gallery (⌘1) and Spotlight; the steps show what came back",
                                    confidence: .medium, weight: 15))
            }
        }
        return checks
    }

    /// Siri searches in the user's steps that found no app, newest last, at most five (from
    /// `siri: "xcode" in root → 0 apps, 3 files (anywhere)`). Only words of three letters or more:
    /// "a", "ne" are the start of typing.
    static func searchesWithoutApps(_ report: DiagnosticsReport) -> [String] {
        let flow = report.value("Flow", in: "User flow") ?? ""
        var found: [String] = []
        for line in flow.split(separator: "\n") {
            guard let match = line.firstMatch(of: /siri: "(.+)" in (\w+) → (\d+) apps/), match.3 == "0" else { continue }
            let text = String(match.1).trimmingCharacters(in: .whitespaces)
            guard text.count >= 3, !text.contains("?"), text.rangeOfCharacter(from: .letters) != nil else { continue }
            // "xco", "xcod", "xcode": the longest of a typed word stands for it.
            found.removeAll { text.lowercased().hasPrefix($0.lowercased()) }
            if !found.contains(where: { $0.lowercased().hasPrefix(text.lowercased()) }) { found.append(text) }
        }
        return Array(found.suffix(5))
    }

    static func installation(_ report: DiagnosticsReport, outdated: String?) -> [Check] {
        var checks: [Check] = []
        if let instances = report.value(DiagnosticsAppStateKeys.instances, in: DiagnosticsAppStateKeys.copies).flatMap(Int.init), instances > 1 {
            checks.append(Check(id: "install.instances", severity: .issue, feature: Feature.install,
                                title: "\(instances) copies of NotchIsland run at once",
                                cause: "they fight over the notch, the keys and ⌘Space",
                                action: "Quit all, keep only /Applications/NotchIsland.app, open it again", weight: 85))
        }
        if report.value("Translocated", in: "App") == "true" {
            checks.append(Check(id: "install.translocated", severity: .issue, feature: Feature.install,
                                title: "Runs translocated", cause: "it was opened where it was downloaded",
                                action: "Move NotchIsland to /Applications and open it from there", weight: 75))
        } else if report.value("Run from a disk image", in: "App") == "true" {
            checks.append(Check(id: "install.diskImage", severity: .issue, feature: Feature.install,
                                title: "Runs from the disk image", cause: "not copied to /Applications",
                                action: "Drag it to Applications, eject the disk image and open it from Applications", weight: 75))
        }
        if let signature = report.value("Signature", in: "App"), signature.contains("INVALID") {
            checks.append(Check(id: "install.signature", severity: .issue, feature: Feature.install,
                                title: "The code signature is invalid", cause: signature,
                                action: "Download the DMG again and replace the app", weight: 70))
        }
        if let copies = report.value("Copies", in: DiagnosticsAppStateKeys.copies), copies.contains("/Volumes/") {
            checks.append(Check(id: "install.mountedCopy", severity: .warning, feature: Feature.install,
                                title: "A copy of NotchIsland is on a mounted disk image",
                                cause: "an old DMG is still mounted; Launch Services may pick it",
                                action: "Eject it in Finder", weight: 8))
        }
        if let others = report.value(DiagnosticsAppStateKeys.otherNotchApps, in: "Running apps"), others != "none" {
            checks.append(Check(id: "install.otherNotchApp", severity: .warning, feature: Feature.island,
                                title: "Another notch app is running: \(others)", cause: "it can hide or double the island's banners",
                                action: "Quit it while testing NotchIsland", weight: 40))
        }
        if let outdated {
            checks.append(Check(id: "install.outdated", severity: .warning, feature: Feature.install, title: outdated,
                                cause: "a fix may already be out", action: "Install the newest DMG from GitHub", weight: 35))
        }
        return checks
    }

    /// NotchIsland's own errors in the log by category, each a warning on its feature.
    static func ownErrors(_ report: DiagnosticsReport) -> (checks: [Check], summary: String) {
        if report.value("Report depth", in: "App")?.hasPrefix("light") == true {
            return ([], "not read (the hourly report; the full one every 6 hours reads the log)")
        }
        guard let own = report.value("NotchIsland's own", in: "Errors by source") else { return ([], "not read") }
        guard own != "none" else { return ([], "0") }
        var total = 0
        var parts: [String] = []
        var checks: [Check] = []
        for match in own.matches(of: /\[com\.davidvarga\.notchisland:(\w+)\] (\d+)×/) {
            let category = String(match.1), count = Int(match.2) ?? 0
            total += count
            parts.append("\(category) \(count)")
            let feature = featureFromCategory(category)
            checks.append(Check(id: "errors.\(category)", severity: .warning, feature: feature,
                                title: "\(count) error\(count == 1 ? "" : "s") logged by NotchIsland (\(category))",
                                cause: "see Errors by source and the log for the lines",
                                action: "The developer reads them in log.txt", weight: min(count, 30)))
        }
        return (checks, total == 0 ? own : "\(total) (\(parts.joined(separator: ", ")))")
    }

    static func featureFromCategory(_ category: String) -> String {
        switch category {
        case "levels": Feature.keys
        case "media": Feature.nowPlaying
        case "power": Feature.battery
        case "shelf": Feature.shelf
        case "timers": Feature.timers
        case "island", "window": Feature.island
        default: Feature.app
        }
    }

    /// The feature a user's complaint is about, from its words (English and Hungarian, accents
    /// ignored).
    static func focus(_ complaint: String) -> String? {
        let text = complaint.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let table: [(String, [String])] = [
            (Feature.siri, ["siri", "spotlight", "keres", "search", "alkalmaz", "gallery", "galeria", "cmd space", "⌘space", "talal"]),
            (Feature.liquid, ["kartya", "card", "folyik", "liquid"]),
            (Feature.keys, ["hangero", "volume", "fenyero", "brightness", "hud", "billenty", "keys"]),
            (Feature.airPods, ["airpods", "fulhallgato", "headphone", "bluetooth"]),
            (Feature.nowPlaying, ["zene", "music", "spotify", "lejatsz", "playing", "youtube", "video", "cover", "borito"]),
            (Feature.battery, ["akku", "battery", "tolt", "charg"]),
            (Feature.timers, ["timer", "idozit", "stopper"]),
            (Feature.shelf, ["shelf", "polc", "fajl huz", "drag"]),
            (Feature.energy, ["energ", "merul", "drain", "cpu", "lassu", "slow", "meleg", "hot", "fogyaszt"]),
            (Feature.memory, ["memoria", "memory", "ram"]),
        ]
        return table.max { a, b in
            a.1.count(where: text.contains) < b.1.count(where: text.contains)
        }.flatMap { $0.1.contains(where: text.contains) ? $0.0 : nil }
    }
}
