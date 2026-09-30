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
        didSet { if board != oldValue { schedulePersist() } }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored let key: String
    /// The board it starts with and is reset to.
    @ObservationIgnored let seed: WidgetBoard
    /// The widgets whose data is kept when the orphans are removed: every page's, once the pages
    /// are several (`WidgetPages`); by default this board's.
    @ObservationIgnored var keeping: (() -> Set<WidgetID>)?
    /// The board as an earlier version stored it, backed up before it is first overwritten.
    @ObservationIgnored private var legacyData: Data?
    @ObservationIgnored private var pendingWrite: Task<Void, Never>?
    /// Each instance's larger data (`WidgetInstanceStore`). Nil until the app starts (`AppModel.start`),
    /// so a test's store never touches the user's folders.
    @ObservationIgnored private(set) var instances: WidgetInstanceStore?

    init(defaults: UserDefaults = .standard, instances: WidgetInstanceStore? = nil, key: String = WidgetStore.key,
         seed: WidgetBoard = .standard) {
        self.defaults = defaults
        self.instances = instances
        self.key = key
        self.seed = seed
        let data = defaults.data(forKey: key)
        board = data.flatMap { try? JSONDecoder().decode(WidgetBoard.self, from: $0) } ?? seed
        if let data, WidgetMigration.version(of: data) < WidgetBoard.version { legacyData = data }
    }

    /// Every widget of the board, the parked ones too.
    var ids: Set<WidgetID> { Set((board.widgets + board.parked).map(\.id)) }

    /// Keeps each instance's data in `store` from now on, and removes what belongs to no widget.
    func attach(_ store: WidgetInstanceStore) {
        instances = store
        purgeOrphanedInstanceData()
    }

    /// Removes the folders of widgets that are gone, at background priority.
    func purgeOrphanedInstanceData() {
        guard let instances else { return }
        let ids = keeping?() ?? ids
        Task.detached(priority: .background) { instances.purge(keeping: ids) }
    }

    /// Whether a volume or brightness widget needs the level readers running.
    var needsLevels: Bool { board.contains(.volume) || board.contains(.brightness) }

    @discardableResult
    func add(_ kind: IslandWidgetKind) -> WidgetID? { board.add(kind) }

    @discardableResult
    func duplicate(_ id: WidgetID) -> WidgetID? {
        let copy = board.duplicate(id)
        if let copy, let instances { Task.detached(priority: .utility) { instances.copy(from: id, to: copy) } }
        return copy
    }

    func remove(_ id: WidgetID) {
        board.remove(id)
        if let instances { Task.detached(priority: .utility) { instances.purge(id) } }
    }

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

    /// A parked widget back on the board; false when there is no room for it.
    @discardableResult
    func restore(_ id: WidgetID) -> Bool { board.restore(id) }

    func reset() {
        board = seed
        purgeOrphanedInstanceData()
    }

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
