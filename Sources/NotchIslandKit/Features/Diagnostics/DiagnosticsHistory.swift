import Foundation

/// What happened across launches (versions, launches, runs that did not end with a normal quit) and
/// what the user did since this launch (island openings, Siri, banners).
final class DiagnosticsHistory {
    nonisolated static let runningKey = "ni2.diagnostics.running"
    nonisolated static let launchesKey = "ni2.diagnostics.launches"
    nonisolated static let uncleanKey = "ni2.diagnostics.uncleanExits"
    nonisolated static let versionsKey = "ni2.diagnostics.versions"
    nonisolated static let firstLaunchKey = "ni2.diagnostics.firstLaunch"
    nonisolated static let identityKey = "ni2.diagnostics.buildIdentity"

    nonisolated struct VersionSeen: Codable, Sendable, Equatable {
        var version: String
        var firstSeen: Date
    }

    /// The previous run ended without `applicationWillTerminate`: a crash, a hang the user
    /// force-quit, a kill, or the Mac losing power.
    let previousEndedUncleanly: Bool
    /// The previous run did not quit, but the app on disk is another build now: an update or a
    /// rebuild replaced it (and stopped it) — not an unclean exit.
    let previousWasReplaced: Bool
    let launches: Int
    let uncleanExits: Int
    let versions: [VersionSeen]
    let firstLaunch: Date
    /// This launch is the first of a version other than the one that ran before (an update, or a
    /// downgrade); false on the very first launch.
    let isNewVersion: Bool
    /// Since this launch, by kind ("expanded", "assistant", "banner"…).
    private(set) var counters: [String: Int] = [:]

    private let defaults: UserDefaults

    /// This build: the executable's path and when it was written (an update or a rebuild changes it).
    nonisolated static var currentIdentity: String {
        guard let url = Bundle.main.executableURL else { return "unknown" }
        let written = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        return "\(url.path)@\(written.map { String(Int($0.timeIntervalSince1970)) } ?? "?")"
    }

    /// Records this launch. Call once, when the app starts.
    init(defaults: UserDefaults = .standard, version: String, identity: String = DiagnosticsHistory.currentIdentity) {
        self.defaults = defaults
        let didNotQuit = defaults.bool(forKey: Self.runningKey)
        let previousIdentity = defaults.string(forKey: Self.identityKey)
        previousWasReplaced = didNotQuit && previousIdentity != nil && previousIdentity != identity
        previousEndedUncleanly = didNotQuit && !previousWasReplaced
        defaults.set(identity, forKey: Self.identityKey)
        launches = defaults.integer(forKey: Self.launchesKey) + 1
        uncleanExits = defaults.integer(forKey: Self.uncleanKey) + (previousEndedUncleanly ? 1 : 0)
        firstLaunch = defaults.object(forKey: Self.firstLaunchKey) as? Date ?? Date()
        var seen = defaults.data(forKey: Self.versionsKey).flatMap { try? JSONDecoder().decode([VersionSeen].self, from: $0) } ?? []
        isNewVersion = seen.last.map { $0.version != version } ?? false
        if seen.last?.version != version { seen.append(VersionSeen(version: version, firstSeen: Date())) }
        versions = Array(seen.suffix(20))
        defaults.set(true, forKey: Self.runningKey)
        defaults.set(launches, forKey: Self.launchesKey)
        defaults.set(uncleanExits, forKey: Self.uncleanKey)
        defaults.set(firstLaunch, forKey: Self.firstLaunchKey)
        // Sorted keys: the same history reads the same in every report (reports are compared).
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        defaults.set(try? encoder.encode(versions), forKey: Self.versionsKey)
    }

    /// The app is quitting normally.
    func markCleanExit() {
        defaults.set(false, forKey: Self.runningKey)
    }

    func count(_ event: String) {
        counters[event, default: 0] += 1
    }

    /// "expanded(home)" → "expanded".
    nonisolated static func kind(of presentation: IslandPresentation) -> String {
        let text = String(describing: presentation)
        return text.split(separator: "(").first.map(String.init) ?? text
    }

    func section() -> DiagnosticsReport.Section {
        var section = DiagnosticsReport.Section("History")
        section.add("Launches", launches)
        section.add("First launch", DiagnosticsFormat.date(firstLaunch))
        section.add("Previous run ended normally", previousWasReplaced ? "stopped by an update or a new build (not a failure)"
                    : "\(!previousEndedUncleanly)")
        section.add("Runs that did not end normally", uncleanExits)
        section.add("Versions", versions.map { "\($0.version) since \(DiagnosticsFormat.date($0.firstSeen))" }.joined(separator: "\n"))
        section.add("Since this launch", counters.isEmpty ? "nothing yet"
                    : counters.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)×" }.joined(separator: ", "))
        return section
    }
}
