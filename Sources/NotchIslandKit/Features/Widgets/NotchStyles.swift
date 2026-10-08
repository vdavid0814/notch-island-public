import Foundation
import Observation

/// The whole island as it looks, saved to come back to: every page's board with its widgets (each
/// with its look, parts and place), the top bar and its pages, the panel's cells and the
/// ready-made size, and the island's own look — its surface, its colour, the music bars and the
/// volume's level — under a name.
nonisolated struct NotchStyle: Sendable, Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    let date: Date
    let panel: PanelSettings
    let scale: IslandScale
    let header: HeaderLayout
    /// Each board's page by its name (`ExpandedPage.rawValue`), and the board.
    let boards: [String: WidgetBoard]
    /// The island's own look (General ▸ Appearance); nil in a style saved without it: left as it is.
    var look: Look?

    nonisolated struct Look: Sendable, Codable, Equatable {
        var glassStyle: IslandGlassStyle
        var theme: IslandTheme
        /// `MusicBarsStyle` and `LevelHUDStyle` by their names.
        var musicBars: String
        var musicBarsOnPower: String
        var levelStyle: String
    }

    init(name: String, panel: PanelSettings, scale: IslandScale, header: HeaderLayout, boards: [String: WidgetBoard],
         look: Look? = nil, date: Date = .now, id: UUID = UUID()) {
        self.id = id
        self.name = name
        self.date = date
        self.panel = panel
        self.scale = scale
        self.header = header
        self.boards = boards
        self.look = look
    }

    /// The widgets on its boards, all pages together.
    var widgetCount: Int { boards.values.reduce(0) { $0 + $1.widgets.count } }
}

/// Every saved notch style, as JSON under `ni2.notchStyles`. Written at once: a save, a rename or
/// a delete is one click, never a stream of them.
@Observable final class NotchStyleStore {
    nonisolated static let key = "ni2.notchStyles"
    /// The oldest go past this.
    static let limit = 50

    private(set) var styles: [NotchStyle]

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        styles = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode([NotchStyle].self, from: $0) } ?? []
    }

    /// Newest first.
    var newestFirst: [NotchStyle] { styles.sorted { $0.date > $1.date } }

    /// The next name: "Style 1", "Style 2"… past the highest one taken.
    var nextName: String {
        let numbers = styles.compactMap { style -> Int? in
            guard style.name.hasPrefix("Style ") else { return nil }
            return Int(style.name.dropFirst("Style ".count))
        }
        return "Style \((numbers.max() ?? 0) + 1)"
    }

    /// `style` kept, under the next name unless it has one of its own.
    @discardableResult
    func save(_ style: NotchStyle) -> NotchStyle {
        var style = style
        if style.name.isEmpty { style.name = nextName }
        styles.append(style)
        if styles.count > Self.limit {
            let dropped = Set(newestFirst.dropFirst(Self.limit).map(\.id))
            styles.removeAll { dropped.contains($0.id) }
        }
        persist()
        return style
    }

    /// Renamed; an empty name keeps the old one.
    func rename(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = styles.firstIndex(where: { $0.id == id }), styles[index].name != trimmed else { return }
        styles[index].name = trimmed
        persist()
    }

    func delete(_ id: UUID) {
        styles.removeAll { $0.id == id }
        persist()
    }

    func deleteAll() {
        styles.removeAll()
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(styles) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
