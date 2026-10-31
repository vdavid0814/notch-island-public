import Foundation
import Observation

/// Every setting of the app as it stood, saved to come back to (General's Save App Settings): the
/// `ni2.` defaults that are choices of the user's, boards and top bar included, under a name.
nonisolated struct SavedAppSettings: Sendable, Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    let date: Date
    /// The values, as a property list.
    let values: Data
    /// Kept by itself before another was opened, to come back from it.
    var isAutomatic = false
}

/// The saved settings, as JSON under `ni2.appSettings`. Opening one quits the app: every part reads
/// its settings as it starts, so they are put in place at the next launch, before anything has read
/// them (`applyPending`).
@Observable final class AppSettingsStore {
    nonisolated static let key = "ni2.appSettings"
    /// What the next launch is to open.
    nonisolated static let pendingKey = "ni2.appSettings.pending"
    /// The oldest go past this.
    static let limit = 30

    private(set) var saved: [SavedAppSettings]

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        saved = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode([SavedAppSettings].self, from: $0) } ?? []
    }

    /// What is kept in the defaults but is no setting: lists saved on purpose, records, what the app
    /// remembers for itself. Opening saved settings leaves these as they are.
    nonisolated private static let notSettings: Set<String> = [
        key, pendingKey, NotchStyleStore.key, "ni2.widgetVersions", "ni2.battery", "ni2.battery.maximumCapacity", "ni2.shelf",
        "ni2.airpods.last", "ni2.anchor.memory", "ni2.lastAppearanceDark", "ni2.settings.pane", "ni2.settings.section",
        "ni2.siriAppsElsewhere", "ni2.levels.volumeCard", "ni2.studio.topBarHintHidden",
    ]

    nonisolated static func isSetting(_ key: String) -> Bool {
        guard key.hasPrefix("ni2."), !notSettings.contains(key), !key.hasSuffix("backup") else { return false }
        if key == "ni2.diagnostics.detailed" { return true }
        return !key.hasPrefix("ni2.diagnostics") && !key.hasPrefix("ni2.telemetry")
    }

    nonisolated private static func current(in defaults: UserDefaults) -> [String: Any] {
        defaults.dictionaryRepresentation().filter { isSetting($0.key) }
    }

    nonisolated private static func decoded(_ values: Data) -> [String: Any]? {
        try? PropertyListSerialization.propertyList(from: values, format: nil) as? [String: Any]
    }

    /// Newest first.
    var newestFirst: [SavedAppSettings] { saved.sorted { $0.date > $1.date } }

    /// The next name: "Settings 1", "Settings 2"… past the highest one taken.
    var nextName: String {
        let numbers = saved.compactMap { $0.name.hasPrefix("Settings ") ? Int($0.name.dropFirst("Settings ".count)) : nil }
        return "Settings \((numbers.max() ?? 0) + 1)"
    }

    /// The settings as they are now, kept.
    @discardableResult func save(name: String? = nil, isAutomatic: Bool = false, now: Date = .now) -> SavedAppSettings? {
        guard let values = try? PropertyListSerialization.data(fromPropertyList: Self.current(in: defaults), format: .binary, options: 0) else { return nil }
        let new = SavedAppSettings(id: UUID(), name: name ?? nextName, date: now, values: values, isAutomatic: isAutomatic)
        saved.append(new)
        if saved.count > Self.limit {
            let dropped = Set(newestFirst.dropFirst(Self.limit).map(\.id))
            saved.removeAll { dropped.contains($0.id) }
        }
        persist()
        return new
    }

    /// The app's settings are these now: nothing to open.
    func isCurrent(_ settings: SavedAppSettings) -> Bool {
        guard let values = Self.decoded(settings.values) else { return false }
        return NSDictionary(dictionary: values).isEqual(to: Self.current(in: defaults))
    }

    /// Renamed; an empty name keeps the old one.
    func rename(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = saved.firstIndex(where: { $0.id == id }), saved[index].name != trimmed else { return }
        saved[index].name = trimmed
        saved[index].isAutomatic = false
        persist()
    }

    func delete(_ id: UUID) {
        saved.removeAll { $0.id == id }
        persist()
    }

    func deleteAll() {
        saved.removeAll()
        persist()
    }

    /// `settings` to be opened at the next launch; what is set now is kept first, in the place of the
    /// last one kept so, to come back to.
    func openAtNextLaunch(_ settings: SavedAppSettings) {
        saved.removeAll { $0.isAutomatic && $0.id != settings.id }
        if !isCurrent(settings) { save(name: String(localized: "Before \(settings.name)"), isAutomatic: true) }
        defaults.set(settings.id.uuidString, forKey: Self.pendingKey)
        persist()
        defaults.synchronize()
    }

    /// At launch, before anything has read a setting: the settings asked for are put in place, those
    /// they don't have taken away (back to their defaults).
    nonisolated static func applyPending(defaults: UserDefaults = .standard) {
        guard let pending = defaults.string(forKey: pendingKey) else { return }
        defaults.removeObject(forKey: pendingKey)
        guard let data = defaults.data(forKey: key),
              let list = try? JSONDecoder().decode([SavedAppSettings].self, from: data),
              let settings = list.first(where: { $0.id.uuidString == pending }),
              let values = decoded(settings.values) else { return }
        for key in current(in: defaults).keys where values[key] == nil { defaults.removeObject(forKey: key) }
        for (key, value) in values where isSetting(key) { defaults.set(value, forKey: key) }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(saved) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
