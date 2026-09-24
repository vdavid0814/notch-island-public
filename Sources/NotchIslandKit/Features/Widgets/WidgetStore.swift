import Foundation

/// The user's home-page board, persisted as JSON under `ni2.widgetBoard`.
///
/// The editor changes it only when a drag or a resize ends, so every write is one deliberate edit.
@Observable final class WidgetStore {
    nonisolated static let key = "ni2.widgetBoard"

    private(set) var board: WidgetBoard {
        didSet {
            guard board != oldValue, let data = try? JSONEncoder().encode(board) else { return }
            defaults.set(data, forKey: Self.key)
        }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        board = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(WidgetBoard.self, from: $0) }
            ?? .standard
    }

    /// Whether a volume or brightness widget needs the level readers running.
    var needsLevels: Bool { board.contains(.volume) || board.contains(.brightness) }

    @discardableResult
    func add(_ kind: IslandWidgetKind) -> Bool { board.add(kind) }

    func remove(_ kind: IslandWidgetKind) { board.remove(kind) }

    @discardableResult
    func setFrame(_ rect: GridRect, for kind: IslandWidgetKind) -> Bool { board.setFrame(rect, for: kind) }

    func update(_ kind: IslandWidgetKind, _ change: (inout IslandWidget) -> Void) {
        board.update(kind, change)
    }

    func setOption(_ option: WidgetOption, _ on: Bool, for kind: IslandWidgetKind) {
        board.setOption(option, on, for: kind)
    }

    func reset() { board = .standard }
}
