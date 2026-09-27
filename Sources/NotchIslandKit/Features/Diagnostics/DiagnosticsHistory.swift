import Foundation

/// What happened across launches (versions, launches, runs that did not end with a normal quit) and
/// what the user did since this launch (island openings, Siri, banners).
final class DiagnosticsHistory {
    nonisolated static let runningKey = "ni2.diagnostics.running"
    nonisolated static let launchesKey = "ni2.diagnostics.launches"
    nonisolated static let uncleanKey = "ni2.diagnostics.uncleanExits"
    nonisolated static let versionsKey = "ni2.diagnostics.versions"
    nonisolated static let firstLaunchKey = "ni2.diagnostics.firstLaunch"

    nonisolated struct VersionSeen: Codable, Sendable, Equatable {
        var version: String
        var firstSeen: Date
    }

    /// The previous run ended without `applicationWillTerminate`: a crash, a hang the user
    /// force-quit, a kill, or the Mac losing power.
    let previousEndedUncleanly: Bool
    let launches: Int
    let uncleanExits: Int
    let versions: [VersionSeen]
    let firstLaunch: Date
    /// Since this launch, by kind ("expanded", "assistant", "banner"…).
    private(set) var counters: [String: Int] = [:]

    private let defaults: UserDefaults

    /// Records this launch. Call once, when the app starts.
    init(defaults: UserDefaults = .standard, version: String) {
        self.defaults = defaults
        previousEndedUncleanly = defaults.bool(forKey: Self.runningKey)
        launches = defaults.integer(forKey: Self.launchesKey) + 1
        uncleanExits = defaults.integer(forKey: Self.uncleanKey) + (previousEndedUncleanly ? 1 : 0)
        firstLaunch = defaults.object(forKey: Self.firstLaunchKey) as? Date ?? Date()
        var seen = defaults.data(forKey: Self.versionsKey).flatMap { try? JSONDecoder().decode([VersionSeen].self, from: $0) } ?? []
        if seen.last?.version != version { seen.append(VersionSeen(version: version, firstSeen: Date())) }
        versions = Array(seen.suffix(20))
        defaults.set(true, forKey: Self.runningKey)
        defaults.set(launches, forKey: Self.launchesKey)
        defaults.set(uncleanExits, forKey: Self.uncleanKey)
        defaults.set(firstLaunch, forKey: Self.firstLaunchKey)
        defaults.set(try? JSONEncoder().encode(versions), forKey: Self.versionsKey)
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
        section.add("Previous run ended normally", !previousEndedUncleanly)
        section.add("Runs that did not end normally", uncleanExits)
        section.add("Versions", versions.map { "\($0.version) since \(DiagnosticsFormat.date($0.firstSeen))" }.joined(separator: "\n"))
        section.add("Since this launch", counters.isEmpty ? "nothing yet"
                    : counters.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)×" }.joined(separator: ", "))
        return section
    }
}
