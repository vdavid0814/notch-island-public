import CoreGraphics
import Foundation

// The expanded island's home page is a board of widgets the user arranges (Customize Island).
//
// Everything here is pure. A widget sits on whole cells of the board's grid (`BoardGrid`); a kind
// may be on it several times, each instance with its own id and look. A widget that no longer fits
// (a smaller grid, a board saved on a larger one) is parked, never dropped, and a widget of a kind
// this build does not know is kept as it was saved, for the build that does.

/// The arrangement of the home page.
nonisolated struct WidgetBoard: Sendable, Codable, Equatable {
    /// 1 and 2 were the widgets alone; 3 adds the grid, ids, parked and foreign widgets.
    static let version = 3

    private(set) var grid: BoardGrid
    private(set) var widgets: [IslandWidget]
    /// Widgets that did not fit, in the grid's cells as they would be: the editor's "Didn't fit" tray.
    private(set) var parked: [IslandWidget]
    /// Widgets of kinds a newer build saved, verbatim: written back as they were read.
    private(set) var foreign: [JSONValue]

    /// Every widget that is free and valid goes on the board, the others are parked. An id met
    /// twice is re-derived for the later widget (`WidgetMigration.uniqueID`).
    init(widgets: [IslandWidget], grid: BoardGrid = .standard, parked: [IslandWidget] = [], foreign: [JSONValue] = []) {
        self.grid = grid
        self.widgets = []
        self.parked = []
        self.foreign = foreign
        var used = Set<WidgetID>()
        for var widget in widgets {
            widget.id = WidgetMigration.uniqueID(widget.id, used: &used)
            if isFree(widget.frame, for: widget.kind) {
                self.widgets.append(widget)
            } else {
                self.parked.append(widget)
            }
        }
        for var widget in parked {
            widget.id = WidgetMigration.uniqueID(widget.id, used: &used)
            self.parked.append(widget)
        }
    }

    /// Now Playing on the left, the timer over the shelf on the right: the page this app shipped with.
    static let standard = WidgetBoard(widgets: [
        IslandWidget(kind: .nowPlaying, frame: GridRect(column: 0, row: 0, width: 7, height: 3),
                     options: IslandWidgetKind.nowPlaying.defaultOptions),
        IslandWidget(kind: .timer, frame: GridRect(column: 7, row: 0, width: 5, height: 2),
                     options: IslandWidgetKind.timer.defaultOptions),
        IslandWidget(kind: .shelf, frame: GridRect(column: 7, row: 2, width: 5, height: 1),
                     options: IslandWidgetKind.shelf.defaultOptions),
    ])

    // MARK: Finding widgets

    /// A widget on the board (not a parked one).
    func widget(_ id: WidgetID) -> IslandWidget? { widgets.first { $0.id == id } }

    /// "The" widget of a kind, for what needs one (the timer page's units, a `widget/<kind>` link):
    /// the first on the board.
    func first(of kind: IslandWidgetKind) -> IslandWidget? { widgets.first { $0.kind == kind } }

    func instances(of kind: IslandWidgetKind) -> [IslandWidget] { widgets.filter { $0.kind == kind } }

    func contains(_ kind: IslandWidgetKind) -> Bool { widgets.contains { $0.kind == kind } }

    func contains(_ id: WidgetID) -> Bool { widgets.contains { $0.id == id } }

    // MARK: Room

    /// Inside the board, within the kind's size limits, and not over another widget (`excluding`
    /// the one being moved).
    func isFree(_ rect: GridRect, for kind: IslandWidgetKind, excluding id: WidgetID? = nil) -> Bool {
        isInBounds(rect) && grid.fits(rect.size, kind) && !widgets.contains { $0.id != id && $0.frame.intersects(rect) }
    }

    func isInBounds(_ rect: GridRect) -> Bool {
        rect.column >= 0 && rect.row >= 0 && rect.width >= 1 && rect.height >= 1
            && rect.maxColumn <= grid.columns && rect.maxRow <= grid.rows
    }

    func fits(_ size: GridSize, _ kind: IslandWidgetKind) -> Bool { grid.fits(size, kind) }

    /// The first free place, reading order, for the kind's default size, or failing that for any
    /// smaller size down to its minimum (largest area first).
    func freeSlot(for kind: IslandWidgetKind) -> GridRect? {
        for size in sizes(for: kind, upTo: grid.defaultSize(for: kind)) {
            for row in 0...(grid.rows - size.height) {
                for column in 0...(grid.columns - size.width) {
                    let rect = GridRect(column: column, row: row, width: size.width, height: size.height)
                    if isFree(rect, for: kind) { return rect }
                }
            }
        }
        return nil
    }

    /// Where the kind fits at `size`, nearest to `anchor` (usually where it is now): the anchor's
    /// own corner when that is free, otherwise the free place closest to it, same row first.
    func placement(for kind: IslandWidgetKind, size: GridSize, near anchor: GridRect, excluding id: WidgetID? = nil) -> GridRect? {
        guard grid.fits(size, kind), size.width <= grid.columns, size.height <= grid.rows else { return nil }
        var best: (rect: GridRect, distance: Int)?
        for row in 0...(grid.rows - size.height) {
            for column in 0...(grid.columns - size.width) {
                let rect = GridRect(column: column, row: row, width: size.width, height: size.height)
                guard isFree(rect, for: kind, excluding: id) else { continue }
                let distance = abs(column - anchor.column) + 3 * abs(row - anchor.row)
                if best.map({ distance < $0.distance }) ?? true { best = (rect, distance) }
            }
        }
        return best?.rect
    }

    /// The nearest place to `anchor` at its size, or at the largest smaller size that fits.
    private func placement(for kind: IslandWidgetKind, shrinkingFrom anchor: GridRect) -> GridRect? {
        for size in sizes(for: kind, upTo: anchor.size) {
            if let rect = placement(for: kind, size: size, near: anchor) { return rect }
        }
        return nil
    }

    /// Every size from `upper` down to the kind's minimum, largest area first.
    private func sizes(for kind: IslandWidgetKind, upTo upper: GridSize) -> [GridSize] {
        let lower = grid.minimum(for: kind)
        guard upper.width >= lower.width, upper.height >= lower.height else { return [] }
        var sizes: [GridSize] = []
        for width in lower.width...upper.width {
            for height in lower.height...upper.height {
                sizes.append(GridSize(width: width, height: height))
            }
        }
        return sizes.sorted { ($0.width * $0.height, $0.width) > ($1.width * $1.height, $1.width) }
    }

    // MARK: Changing it

    /// Adds a new instance of the kind where there is room; nil when nothing fits, or the kind is
    /// not built yet.
    @discardableResult
    mutating func add(_ kind: IslandWidgetKind) -> WidgetID? {
        guard kind.spec.isImplemented, let rect = freeSlot(for: kind) else { return nil }
        let widget = IslandWidget(kind: kind, frame: rect, options: kind.defaultOptions, id: WidgetID())
        widgets.append(widget)
        return widget.id
    }

    /// A copy with its own id and the same look, as near the original as there is room (smaller
    /// if it must); nil when nothing fits.
    @discardableResult
    mutating func duplicate(_ id: WidgetID) -> WidgetID? {
        guard var copy = widget(id), let rect = placement(for: copy.kind, shrinkingFrom: copy.frame) else { return nil }
        copy.id = WidgetID()
        copy.frame = rect
        widgets.append(copy)
        return copy.id
    }

    /// Takes the widget off the board, or out of the parked ones.
    mutating func remove(_ id: WidgetID) {
        widgets.removeAll { $0.id == id }
        parked.removeAll { $0.id == id }
    }

    /// Puts a parked widget back on the board: where it was when that is free, else as near as
    /// there is room, shrinking down to its minimum. False (still parked) when nothing is free.
    @discardableResult
    mutating func restore(_ id: WidgetID) -> Bool {
        guard let index = parked.firstIndex(where: { $0.id == id }) else { return false }
        var widget = parked[index]
        let size = GridSize(width: min(widget.frame.width, grid.columns), height: min(widget.frame.height, grid.rows))
        let anchor = GridRect(column: min(max(widget.frame.column, 0), grid.columns - size.width),
                              row: min(max(widget.frame.row, 0), grid.rows - size.height), width: size.width, height: size.height)
        guard let rect = isFree(anchor, for: widget.kind) ? anchor : placement(for: widget.kind, shrinkingFrom: anchor) else { return false }
        widget.frame = rect
        parked.remove(at: index)
        widgets.append(widget)
        return true
    }

    /// Moves or resizes; refused (false) when the new frame is not free.
    @discardableResult
    mutating func setFrame(_ rect: GridRect, for id: WidgetID) -> Bool {
        guard let index = widgets.firstIndex(where: { $0.id == id }),
              isFree(rect, for: widgets[index].kind, excluding: id) else { return false }
        widgets[index].frame = rect
        return true
    }

    /// Changes a widget's look (tint, plate, mirroring, style…); its id, kind and frame stay.
    mutating func update(_ id: WidgetID, _ change: (inout IslandWidget) -> Void) {
        guard let index = widgets.firstIndex(where: { $0.id == id }) else { return }
        var widget = widgets[index]
        change(&widget)
        widget.id = id
        widget.kind = widgets[index].kind
        widget.frame = widgets[index].frame
        widget.sanitize()
        widgets[index] = widget
    }

    mutating func setOption(_ option: ElementID, _ on: Bool, for id: WidgetID) {
        guard let index = widgets.firstIndex(where: { $0.id == id }), widgets[index].kind.options.contains(option) else { return }
        if on {
            widgets[index].options.insert(option)
        } else {
            widgets[index].options.remove(option)
        }
    }

    /// A new grid: every edge is scaled to it (`round(edge · new / old)`, so edges two widgets
    /// shared stay shared), each size is clamped to its kind's limits on the new grid, and
    /// collisions are resolved in reading order, each widget as near its scaled place as there is
    /// room, shrinking down to its minimum. What still does not fit is parked.
    mutating func setGrid(_ new: BoardGrid) {
        guard new != grid else { return }
        let old = grid
        grid = new
        func scaled(_ rect: GridRect, _ kind: IslandWidgetKind) -> GridRect {
            func edge(_ value: Int, _ from: Int, _ to: Int) -> Int { Int((Double(value * to) / Double(from)).rounded()) }
            let lower = new.minimum(for: kind), upper = new.maximum(for: kind)
            let column = edge(rect.column, old.columns, new.columns), row = edge(rect.row, old.rows, new.rows)
            let width = min(max(edge(rect.maxColumn, old.columns, new.columns) - column, lower.width), upper.width)
            let height = min(max(edge(rect.maxRow, old.rows, new.rows) - row, lower.height), upper.height)
            return GridRect(column: min(column, new.columns - width), row: min(row, new.rows - height), width: width, height: height)
        }
        let placedBefore = widgets
        widgets = []
        var landed: [WidgetID: GridRect] = [:]
        var left: [IslandWidget] = []
        for var widget in placedBefore.sorted(by: { ($0.frame.row, $0.frame.column) < ($1.frame.row, $1.frame.column) }) {
            widget.frame = scaled(widget.frame, widget.kind)
            if let rect = isFree(widget.frame, for: widget.kind) ? widget.frame : placement(for: widget.kind, shrinkingFrom: widget.frame) {
                widget.frame = rect
                landed[widget.id] = rect
                widgets.append(widget)
            } else {
                left.append(widget)
            }
        }
        // The board keeps its order (it is the drawing order), only the frames change.
        widgets = placedBefore.compactMap { widget in
            landed[widget.id].map { rect in
                var widget = widget
                widget.frame = rect
                return widget
            }
        }
        parked = parked.map { widget in
            var widget = widget
            widget.frame = scaled(widget.frame, widget.kind)
            return widget
        } + left
    }

    /// More or fewer cells, each widget on as many as before (Settings ▸ Widgets ▸ Size): columns
    /// come and go in pairs, one at each side, so everything stays where it is about the notch;
    /// rows at the bottom. A widget the smaller grid cuts through is moved in as near as there is
    /// room, shrinking down to its minimum; what still does not fit is parked.
    mutating func setGridKeepingCells(_ new: BoardGrid) {
        guard new != grid else { return }
        let shift = (new.columns - grid.columns) / 2
        grid = new
        let placedBefore = widgets
        widgets = []
        var landed: [WidgetID: GridRect] = [:]
        var left: [IslandWidget] = []
        // The ones still whole on the new grid first: they keep their places.
        let moved = placedBefore.map { widget in
            var widget = widget
            widget.frame.column += shift
            return widget
        }
        let order = moved.sorted { a, b in
            (isInBounds(a.frame) ? 0 : 1, a.frame.row, a.frame.column) < (isInBounds(b.frame) ? 0 : 1, b.frame.row, b.frame.column)
        }
        for var widget in order {
            let size = GridSize(width: min(widget.frame.width, new.columns), height: min(widget.frame.height, new.rows))
            let anchor = GridRect(column: min(max(widget.frame.column, 0), new.columns - size.width),
                                  row: min(max(widget.frame.row, 0), new.rows - size.height), width: size.width, height: size.height)
            if let rect = isFree(anchor, for: widget.kind) ? anchor : placement(for: widget.kind, shrinkingFrom: anchor) {
                widget.frame = rect
                landed[widget.id] = rect
                widgets.append(widget)
            } else {
                left.append(widget)
            }
        }
        // The board keeps its order (it is the drawing order), only the frames change.
        widgets = placedBefore.compactMap { widget in
            landed[widget.id].map { rect in
                var widget = widget
                widget.frame = rect
                return widget
            }
        }
        parked = parked.map { widget in
            var widget = widget
            widget.frame.column += shift
            return widget
        } + left
    }

    // MARK: Coding

    private enum CodingKeys: String, CodingKey {
        case version, grid, widgets, parked, foreign
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.version, forKey: .version)
        try container.encode(grid, forKey: .grid)
        try container.encode(widgets, forKey: .widgets)
        try container.encode(parked, forKey: .parked)
        try container.encode(foreign, forKey: .foreign)
    }

    // Decoding keeps whatever it can: one widget at a time, so a bad one (a hand-edited or older
    // plist) never loses the board; a widget that is out of bounds or over another is parked; a
    // kind this build does not know goes to `foreign`, and one it has come to know since comes
    // back from there, placed where there is room, else parked.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let grid = (try? container.decodeIfPresent(BoardGrid.self, forKey: .grid)).flatMap { $0 } ?? .standard
        let placed = (try? container.decodeIfPresent([Entry].self, forKey: .widgets)).flatMap { $0 } ?? []
        let parked = (try? container.decodeIfPresent([Entry].self, forKey: .parked)).flatMap { $0 } ?? []
        let foreign = (try? container.decodeIfPresent([Entry].self, forKey: .foreign)).flatMap { $0 } ?? []
        func sanitized(_ entries: [Entry]) -> [IslandWidget] {
            entries.compactMap(\.widget).map { widget in
                var widget = widget
                widget.sanitize()
                return widget
            }
        }
        self.init(widgets: sanitized(placed + foreign), grid: grid, parked: sanitized(parked),
                  foreign: (foreign + placed + parked).compactMap(\.foreign))
    }

    /// One saved widget: decoded, kept raw when its kind is unknown, or neither (dropped).
    private struct Entry: Decodable {
        var widget: IslandWidget?
        var foreign: JSONValue?

        private enum Key: String, CodingKey { case kind }

        init(from decoder: any Decoder) throws {
            if let widget = try? IslandWidget(from: decoder) {
                self.widget = widget
            } else if let kind = try? decoder.container(keyedBy: Key.self).decode(String.self, forKey: .kind),
                      IslandWidgetKind(rawValue: kind) == nil {
                foreign = try? JSONValue(from: decoder)
            }
        }
    }
}

/// Decodes a value, or nil where it cannot be decoded, so one bad element does not fail an array.
nonisolated struct Lossy<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: any Decoder) throws {
        value = try? Value(from: decoder)
    }
}
