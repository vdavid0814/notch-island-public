import Foundation

/// The user's home-page board, persisted as JSON under `ni2.widgetBoard`.
///
/// The board changes at once (the island and Settings redraw from it); the write follows 0.4 s
/// after the last change, so a slider drag is one write rather than one per step, and whatever is
/// still waiting is written when the app quits (`flush`).
@Observable final class WidgetStore {
    nonisolated static let key = "ni2.widgetBoard"
    nonisolated static let persistDelay: Duration = .milliseconds(400)

    private(set) var board: WidgetBoard {
        didSet { if board != oldValue { schedulePersist() } }
    }

    @ObservationIgnored private let defaults: UserDefaults
    /// The board as an earlier version stored it, backed up before it is first overwritten.
    @ObservationIgnored private var legacyData: Data?
    @ObservationIgnored private var pendingWrite: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let data = defaults.data(forKey: Self.key)
        board = data.flatMap { try? JSONDecoder().decode(WidgetBoard.self, from: $0) } ?? .standard
        if let data, WidgetMigration.version(of: data) < WidgetBoard.version { legacyData = data }
    }

    /// Whether a volume or brightness widget needs the level readers running.
    var needsLevels: Bool { board.contains(.volume) || board.contains(.brightness) }

    @discardableResult
    func add(_ kind: IslandWidgetKind) -> WidgetID? { board.add(kind) }

    @discardableResult
    func duplicate(_ id: WidgetID) -> WidgetID? { board.duplicate(id) }

    func remove(_ id: WidgetID) { board.remove(id) }

    @discardableResult
    func setFrame(_ rect: GridRect, for id: WidgetID) -> Bool { board.setFrame(rect, for: id) }

    func update(_ id: WidgetID, _ change: (inout IslandWidget) -> Void) {
        board.update(id, change)
    }

    func setOption(_ option: ElementID, _ on: Bool, for id: WidgetID) {
        board.setOption(option, on, for: id)
    }

    func setGrid(_ grid: BoardGrid) { board.setGrid(grid) }

    func reset() { board = .standard }

    /// Writes a change that is still waiting for its delay.
    func flush() {
        guard let pendingWrite else { return }
        pendingWrite.cancel()
        write()
    }

    private func schedulePersist() {
        pendingWrite?.cancel()
        pendingWrite = Task { [weak self] in
            try? await Task.sleep(for: Self.persistDelay)
            guard !Task.isCancelled else { return }
            self?.write()
        }
    }

    private func write() {
        pendingWrite = nil
        if let legacyData {
            WidgetMigration.backUp(legacyData, in: defaults)
            self.legacyData = nil
        }
        guard let data = try? JSONEncoder().encode(board) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
