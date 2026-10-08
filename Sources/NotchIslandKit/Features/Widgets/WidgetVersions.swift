import Foundation
import Observation

/// A widget's look saved in Customize to come back to: everything about it (background, parts,
/// positions, text styles) under a name.
nonisolated struct WidgetVersion: Sendable, Codable, Hashable, Identifiable {
    let id: UUID
    var name: String
    let date: Date
    /// The widget as it was saved; its id and its place on the board are not taken back.
    let widget: IslandWidget

    init(name: String, widget: IslandWidget, date: Date = .now, id: UUID = UUID()) {
        self.id = id
        self.name = name
        self.date = date
        self.widget = widget
    }

    /// `widget` with this version's look: it stays the same widget, where and as large as it is.
    func applied(to widget: IslandWidget) -> IslandWidget {
        var applied = self.widget
        applied.id = widget.id
        applied.frame = widget.frame
        applied.sanitize()
        return applied
    }
}

/// Every saved version, of every kind, as JSON under `ni2.widgetVersions`. Written at once: a save,
/// a rename or a delete is one click, never a stream of them.
@Observable final class WidgetVersionStore {
    nonisolated static let key = "ni2.widgetVersions"
    /// Of one kind, the oldest go past this.
    static let limit = 50

    private(set) var versions: [WidgetVersion]

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        versions = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode([WidgetVersion].self, from: $0) } ?? []
    }

    /// The versions of `kind`, newest first.
    func versions(of kind: IslandWidgetKind) -> [WidgetVersion] {
        versions.filter { $0.widget.kind == kind }.sorted { $0.date > $1.date }
    }

    /// The next name for one of `kind`: "Version 1", "Version 2"… past the highest one taken.
    func nextName(for kind: IslandWidgetKind) -> String {
        let numbers = versions(of: kind).compactMap { version -> Int? in
            guard version.name.hasPrefix("Version ") else { return nil }
            return Int(version.name.dropFirst("Version ".count))
        }
        return "Version \((numbers.max() ?? 0) + 1)"
    }

    @discardableResult
    func save(_ widget: IslandWidget, name: String? = nil, date: Date = .now) -> WidgetVersion {
        let version = WidgetVersion(name: name ?? nextName(for: widget.kind), widget: widget, date: date)
        versions.append(version)
        let ofKind = versions(of: widget.kind)
        if ofKind.count > Self.limit {
            let dropped = Set(ofKind.dropFirst(Self.limit).map(\.id))
            versions.removeAll { dropped.contains($0.id) }
        }
        persist()
        return version
    }

    /// Renamed; an empty name keeps the old one.
    func rename(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = versions.firstIndex(where: { $0.id == id }), versions[index].name != trimmed else { return }
        versions[index].name = trimmed
        persist()
    }

    func delete(_ id: UUID) {
        versions.removeAll { $0.id == id }
        persist()
    }

    func deleteAll(of kind: IslandWidgetKind) {
        versions.removeAll { $0.widget.kind == kind }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(versions) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
