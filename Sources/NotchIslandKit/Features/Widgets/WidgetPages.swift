import Foundation

/// Every page's board: home's (`AppModel.widgets`, under `ni2.widgetBoard`), the timer's and the
/// battery's, and each page the user added (`CustomPage`), each under its own key.
///
/// The timer's and the battery's start as the pages were drawn before they were boards: the timer
/// over the whole page; the battery's level, health, cycles and charger beside the day's chart. A
/// page the user adds starts empty. The widgets' data is kept for every page's widgets together.
@MainActor final class WidgetPages {
    let home: WidgetStore
    private let defaults: UserDefaults
    private var stores: [ExpandedPage: WidgetStore] = [:]
    private var instances: WidgetInstanceStore?

    nonisolated static func key(for page: ExpandedPage) -> String {
        page == .home ? WidgetStore.key : WidgetStore.key + "." + page.rawValue
    }

    init(home: WidgetStore, defaults: UserDefaults = .standard) {
        self.home = home
        self.defaults = defaults
        stores[.home] = home
        home.keeping = { [weak self] in self?.allIDs ?? home.ids }
    }

    /// The page's board; home's for a page drawn otherwise (the shelf).
    func store(for page: ExpandedPage) -> WidgetStore {
        guard page.isBoard else { return home }
        if let store = stores[page] { return store }
        let store = WidgetStore(defaults: defaults, instances: instances, key: Self.key(for: page),
                                seed: Self.seed(for: page, grid: home.board.grid))
        store.keeping = { [weak self] in self?.allIDs ?? store.ids }
        stores[page] = store
        return store
    }

    /// The board a widget is on, among the pages made so far.
    func store(containing id: WidgetID) -> WidgetStore? {
        stores.values.first { $0.board.contains(id) || $0.board.parked.contains { $0.id == id } }
    }

    /// The page a widget is on.
    func page(containing id: WidgetID) -> ExpandedPage? {
        stores.first { $0.value.board.contains(id) || $0.value.board.parked.contains { $0.id == id } }?.key
    }

    /// Makes the boards of `pages` (so a widget on them is found by id) and deletes those of the
    /// user's pages that are gone.
    func sync(_ pages: [ExpandedPage]) {
        for page in pages where page.isBoard { _ = store(for: page) }
        for (page, store) in stores where page.isCustom && !pages.contains(page) {
            store.erase()
            stores[page] = nil
        }
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(WidgetStore.key + ".page.") {
            if !pages.contains(where: { Self.key(for: $0) == key }) { defaults.removeObject(forKey: key) }
        }
    }

    /// Keeps each widget's data in `store` from now on; removes what belongs to no page's widget.
    func attach(_ store: WidgetInstanceStore) {
        instances = store
        for board in stores.values { board.attach(store) }
    }

    /// Whether any board has a volume or brightness widget (the level readers run for it).
    var needsLevels: Bool { stores.values.contains { $0.needsLevels } }

    /// Writes what is still waiting, on every board.
    func flush() { stores.values.forEach { $0.flush() } }

    private var allIDs: Set<WidgetID> { stores.values.reduce(into: Set()) { $0.formUnion($1.ids) } }

    // MARK: Starting boards

    /// What a page's board starts with, on `grid` (home's).
    nonisolated static func seed(for page: ExpandedPage, grid: BoardGrid) -> WidgetBoard {
        switch page {
        case .timer: timerSeed(grid: grid)
        case .battery: batterySeed(grid: grid)
        default: WidgetBoard(widgets: [], grid: grid)
        }
    }

    /// The timer over the whole page, with its ruler, readout and +1 minute, as the page drew it.
    nonisolated static func timerSeed(grid: BoardGrid) -> WidgetBoard {
        let kind = IslandWidgetKind.timer
        let width = min(grid.columns, kind.spec.maximumSize.width), height = min(grid.rows, kind.spec.maximumSize.height)
        let timer = IslandWidget(kind: kind, frame: GridRect(column: (grid.columns - width) / 2, row: 0, width: width, height: height),
                                 options: kind.defaultOptions.union([.ruler, .readout, .addMinute]),
                                 id: WidgetID(name: "notchisland.page.timer.timer"))
        return WidgetBoard(widgets: [timer], grid: grid)
    }

    /// The battery page as it was: its level and time left, health and cycles, the charger down the
    /// left; the day's chart over the rest.
    nonisolated static func batterySeed(grid: BoardGrid) -> WidgetBoard {
        func widget(_ kind: IslandWidgetKind, _ column: Int, _ row: Int, _ width: Int, _ height: Int) -> IslandWidget {
            IslandWidget(kind: kind, frame: GridRect(column: column, row: row, width: width, height: height), options: kind.defaultOptions,
                         id: WidgetID(name: "notchisland.page.battery." + kind.rawValue))
        }
        let left = 4
        let chartHeight = min(grid.rows, IslandWidgetKind.batteryChart.spec.maximumSize.height)
        var widgets = [
            widget(.battery, 0, 0, left, 1),
            widget(.batteryHealth, 0, 1, left / 2, 1),
            widget(.batteryCycles, left / 2, 1, left / 2, 1),
            widget(.batteryChart, left, 0, min(grid.columns - left, IslandWidgetKind.batteryChart.spec.maximumSize.width), chartHeight),
        ]
        if grid.rows >= 3 { widgets.append(widget(.charger, 0, 2, left, 1)) }
        return WidgetBoard(widgets: widgets, grid: grid)
    }
}
