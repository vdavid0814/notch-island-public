import Foundation

/// Every page's board: home's (`AppModel.widgets`, under `ni2.widgetBoard`), the timer's and the
/// battery's, and each page the user added (`CustomPage`), each under its own key. Every page but
/// home starts empty.
@MainActor final class WidgetPages {
    let home: WidgetStore
    private let defaults: UserDefaults
    private var stores: [ExpandedPage: WidgetStore] = [:]

    nonisolated static func key(for page: ExpandedPage) -> String {
        page == .home ? WidgetStore.key : WidgetStore.key + "." + page.rawValue
    }

    init(home: WidgetStore, defaults: UserDefaults = .standard) {
        self.home = home
        self.defaults = defaults
        stores[.home] = home
    }

    /// The page's board; home's for a page drawn otherwise (the shelf).
    func store(for page: ExpandedPage) -> WidgetStore {
        guard page.isBoard else { return home }
        if let store = stores[page] { return store }
        let store = WidgetStore(defaults: defaults, key: Self.key(for: page), seed: WidgetBoard(widgets: [], grid: home.board.grid))
        // Every page on the panel's grid (a board stored before may have its own).
        store.follow(home.board.grid)
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

    /// Every board made so far on `grid` (the panel's), each widget on its cells.
    func follow(_ grid: BoardGrid, leadingColumns: Int? = nil) {
        home.follow(grid, leadingColumns: leadingColumns)
        for store in stores.values where store !== home { store.follow(grid, leadingColumns: leadingColumns) }
    }

    /// Every board made so far, as it is now.
    func snapshot() -> [ExpandedPage: WidgetBoard] { stores.mapValues(\.board) }

    /// The boards as `snapshot` had them; one made since then on `grid`, each widget on its cells.
    func restore(_ snapshot: [ExpandedPage: WidgetBoard], grid: BoardGrid) {
        for (page, store) in stores {
            if let board = snapshot[page] { store.replace(with: board) } else { store.follow(grid) }
        }
    }

    /// Whether any board has a volume widget (the level readers run for it).
    var needsLevels: Bool { stores.values.contains { $0.needsLevels } }

    /// Writes what is still waiting, on every board.
    func flush() { stores.values.forEach { $0.flush() } }
}
