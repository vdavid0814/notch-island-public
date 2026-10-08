import Foundation

/// One page's board, persisted as JSON: the home page's under `ni2.widgetBoard`, every other
/// page's under its own key (`WidgetPages`).
///
/// The board changes at once (the island and Settings redraw from it); the write follows 0.4 s
/// after the last change, so a slider drag is one write rather than one per step, and whatever is
/// still waiting is written when the app quits (`flush`).
@Observable final class WidgetStore {
    nonisolated static let key = "ni2.widgetBoard"
    nonisolated static let persistDelay: Duration = .milliseconds(400)

    private(set) var board: WidgetBoard {
        didSet {
            guard board != oldValue else { return }
            schedulePersist()
            record(oldValue)
        }
    }

    /// The boards as they were before each change, the latest last (Settings ▸ Widgets' ⌘Z), and
    /// the ones undone (⌘⇧Z).
    private(set) var undoStack: [WidgetBoard] = []
    private(set) var redoStack: [WidgetBoard] = []
    @ObservationIgnored private var isRestoring = false
    @ObservationIgnored private var lastChange: TimeInterval = 0
    /// Changes this close together are one step: a drag, a slider moved.
    static let coalescing: TimeInterval = 0.6
    static let historyLimit = 60

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored let key: String
    /// The board it starts with and is reset to.
    @ObservationIgnored let seed: WidgetBoard
    /// The board as an earlier version stored it, backed up before it is first overwritten.
    @ObservationIgnored private var legacyData: Data?
    @ObservationIgnored private var pendingWrite: Task<Void, Never>?

    init(defaults: UserDefaults = .standard, key: String = WidgetStore.key, seed: WidgetBoard = .standard) {
        self.defaults = defaults
        self.key = key
        self.seed = seed
        let data = defaults.data(forKey: key)
        board = data.flatMap { try? JSONDecoder().decode(WidgetBoard.self, from: $0) } ?? seed
        if let data, WidgetMigration.version(of: data) < WidgetBoard.version { legacyData = data }
    }

    /// Every widget of the board, the parked ones too.
    var ids: Set<WidgetID> { Set((board.widgets + board.parked).map(\.id)) }

    /// Whether a volume widget needs the level readers running.
    var needsLevels: Bool { board.contains(.volume) }

    @discardableResult
    func add(_ kind: IslandWidgetKind) -> WidgetID? { board.add(kind) }

    /// A widget dropped on the board at `anchor` (or as near as there is room).
    @discardableResult
    func add(_ kind: IslandWidgetKind, near anchor: GridRect) -> WidgetID? { board.add(kind, near: anchor) }

    // MARK: Undo

    private func record(_ old: WidgetBoard) {
        guard !isRestoring else { return }
        let now = ProcessInfo.processInfo.systemUptime
        defer { lastChange = now }
        redoStack.removeAll()
        // Part of the change still going on (a drag): the board before it is already kept.
        if now - lastChange < Self.coalescing, !undoStack.isEmpty { return }
        undoStack.append(old)
        if undoStack.count > Self.historyLimit { undoStack.removeFirst() }
    }

    /// The board as it was before the last change; false with nothing to undo.
    @discardableResult
    func undo() -> Bool {
        guard let previous = undoStack.popLast() else { return false }
        redoStack.append(board)
        restoring { board = Self.on(board.grid, previous) }
        return true
    }

    /// The change undone last, made again; false with nothing to redo.
    @discardableResult
    func redo() -> Bool {
        guard let next = redoStack.popLast() else { return false }
        undoStack.append(board)
        restoring { board = Self.on(board.grid, next) }
        return true
    }

    /// `board` on the panel's grid now (the panel may have changed since it was kept).
    private static func on(_ grid: BoardGrid, _ board: WidgetBoard) -> WidgetBoard {
        var board = board
        board.setGridKeepingCells(grid)
        return board
    }

    private func restoring(_ change: () -> Void) {
        isRestoring = true
        change()
        isRestoring = false
        // The next change is a step of its own, however soon it comes.
        lastChange = 0
    }

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

    /// More or fewer cells, each widget on as many as before (`WidgetBoard.setGridKeepingCells`).
    func setGridKeepingCells(_ grid: BoardGrid) { board.setGridKeepingCells(grid) }

    /// The panel's grid (`AppModel.setPanel`): each widget on its cells, columns added on the side
    /// dragged. Not a step to undo — the panel is not part of the board's history.
    func follow(_ grid: BoardGrid, leadingColumns: Int? = nil) {
        guard grid != board.grid else { return }
        restoring { board.setGridKeepingCells(grid, leadingColumns: leadingColumns) }
    }

    /// Another board in this one's place (a notch style opened): a change like any other, Undo
    /// takes it back.
    func load(_ board: WidgetBoard) { self.board = board }

    /// The board as it was kept before (Reset Size): like the panel, not a step to undo.
    func replace(with board: WidgetBoard) {
        guard board != self.board else { return }
        restoring { self.board = board }
    }

    /// A parked widget back on the board; false when there is no room for it.
    @discardableResult
    func restore(_ id: WidgetID) -> Bool { board.restore(id) }

    func reset() { board = seed }

    /// The board and its stored copy gone (a page the user took away).
    func erase() {
        pendingWrite?.cancel()
        pendingWrite = nil
        defaults.removeObject(forKey: key)
    }

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
        defaults.set(data, forKey: key)
    }
}
