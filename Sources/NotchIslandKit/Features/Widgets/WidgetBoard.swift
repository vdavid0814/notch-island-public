import CoreGraphics
import Foundation

// The expanded island's home page is a board of widgets the user arranges (Customize Island).
//
// Everything here is pure: a widget sits on whole cells of a fixed grid, so free dragging in the
// editor always lands on cell boundaries, and every edge lines up with some other edge or with the
// island's centre. The grid has an even number of columns, so a widget of even width can sit exactly
// on the notch's centre line.

/// What a widget shows.
nonisolated enum IslandWidgetKind: String, Sendable, Codable, CaseIterable, Identifiable {
    case nowPlaying
    case timer
    case stopwatch
    case shelf
    case battery
    case volume
    case brightness
    case assistant

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nowPlaying: "Now Playing"
        case .timer: "Timer"
        case .stopwatch: "Stopwatch"
        case .shelf: "Shelf"
        case .battery: "Battery"
        case .volume: "Volume"
        case .brightness: "Brightness"
        case .assistant: "Siri"
        }
    }

    /// One line for the gallery card.
    var summary: String {
        switch self {
        case .nowPlaying: "Artwork, track and playback controls for any player."
        case .timer: "Scroll the ruler to a length and start it."
        case .stopwatch: "Start, pause and reset a stopwatch."
        case .shelf: "Files dropped on the notch, ready to drag out."
        case .battery: "Charge level and time remaining."
        case .volume: "The output volume as a slider."
        case .brightness: "The display brightness as a slider."
        case .assistant: "Search apps and files, or ask Apple Intelligence, right in the notch."
        }
    }

    var systemImage: String {
        switch self {
        case .nowPlaying: "play.circle.fill"
        case .timer: "timer"
        case .stopwatch: "stopwatch.fill"
        case .shelf: "tray.full.fill"
        case .battery: "battery.75percent"
        case .volume: "speaker.wave.2.fill"
        case .brightness: "sun.max.fill"
        case .assistant: "siri"
        }
    }

    var minimumSize: GridSize {
        switch self {
        case .nowPlaying: GridSize(width: 4, height: 1)
        case .timer: GridSize(width: 4, height: 1)
        case .stopwatch: GridSize(width: 3, height: 1)
        case .shelf: GridSize(width: 3, height: 1)
        case .battery: GridSize(width: 2, height: 1)
        case .volume, .brightness: GridSize(width: 3, height: 1)
        case .assistant: GridSize(width: 2, height: 1)
        }
    }

    var maximumSize: GridSize {
        switch self {
        case .battery, .assistant: GridSize(width: 6, height: 3)
        case .volume, .brightness, .stopwatch: GridSize(width: 12, height: 2)
        default: GridSize(width: WidgetBoard.columns, height: WidgetBoard.rows)
        }
    }

    var defaultSize: GridSize {
        switch self {
        case .nowPlaying: GridSize(width: 7, height: 3)
        case .timer: GridSize(width: 5, height: 2)
        case .stopwatch: GridSize(width: 4, height: 1)
        case .shelf: GridSize(width: 5, height: 1)
        case .battery: GridSize(width: 3, height: 1)
        case .volume, .brightness: GridSize(width: 5, height: 1)
        case .assistant: GridSize(width: 2, height: 1)
        }
    }

    /// The controls the user may switch on or off for this widget, in inspector order.
    var options: [WidgetOption] {
        switch self {
        case .nowPlaying: [.artwork, .trackInfo, .progress, .skipButtons]
        case .timer: [.ruler, .readout, .addMinute]
        case .stopwatch: [.resetButton]
        case .shelf: [.previews, .shelfActions]
        case .battery: [.percentage, .timeRemaining]
        case .volume, .brightness: [.levelIcon, .levelValue]
        case .assistant: []
        }
    }

    var defaultOptions: Set<WidgetOption> {
        switch self {
        case .timer: [.ruler, .readout]
        default: Set(options)
        }
    }
}

/// A control a widget can show or hide.
nonisolated enum WidgetOption: String, Sendable, Codable, CaseIterable, Identifiable {
    case artwork, trackInfo, progress, skipButtons
    case ruler, readout, addMinute
    case resetButton
    case previews, shelfActions
    case percentage, timeRemaining
    case levelIcon, levelValue

    var id: String { rawValue }

    var title: String {
        switch self {
        case .artwork: "Artwork"
        case .trackInfo: "Title and artist"
        case .progress: "Progress bar"
        case .skipButtons: "Previous and next buttons"
        case .ruler: "Ruler"
        case .readout: "Time"
        case .addMinute: "+1 minute button"
        case .resetButton: "Reset button"
        case .previews: "File previews"
        case .shelfActions: "AirDrop and Clear buttons"
        case .percentage: "Percentage"
        case .timeRemaining: "Time remaining"
        case .levelIcon: "Symbol"
        case .levelValue: "Value"
        }
    }
}

nonisolated struct GridSize: Sendable, Codable, Hashable {
    var width: Int
    var height: Int
}

/// Whole cells: column and row of the top-left cell, and the size in cells.
nonisolated struct GridRect: Sendable, Codable, Hashable {
    var column: Int
    var row: Int
    var width: Int
    var height: Int

    var size: GridSize { GridSize(width: width, height: height) }
    var maxColumn: Int { column + width }
    var maxRow: Int { row + height }

    func intersects(_ other: GridRect) -> Bool {
        column < other.maxColumn && other.column < maxColumn && row < other.maxRow && other.row < maxRow
    }

    /// Centred on the board's vertical centre line (the notch).
    var isHorizontallyCentred: Bool { column * 2 + width == WidgetBoard.columns }
    var isVerticallyCentred: Bool { row * 2 + height == WidgetBoard.rows }
}

nonisolated struct IslandWidget: Sendable, Codable, Hashable, Identifiable {
    var kind: IslandWidgetKind
    var frame: GridRect
    var options: Set<WidgetOption>

    /// One widget per kind: the kind is the identity.
    var id: IslandWidgetKind { kind }

    func shows(_ option: WidgetOption) -> Bool { options.contains(option) }
}

/// The arrangement of the home page.
nonisolated struct WidgetBoard: Sendable, Codable, Equatable {
    /// Twelve columns by three rows gives near-square cells on the standard island, each row tall
    /// enough for one row of controls.
    static let columns = 12
    static let rows = 3

    private(set) var widgets: [IslandWidget]

    init(widgets: [IslandWidget]) {
        self.widgets = []
        for widget in widgets where !contains(widget.kind) && isFree(widget.frame, for: widget.kind) {
            self.widgets.append(widget)
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

    func contains(_ kind: IslandWidgetKind) -> Bool { widgets.contains { $0.kind == kind } }

    func widget(_ kind: IslandWidgetKind) -> IslandWidget? { widgets.first { $0.kind == kind } }

    /// Inside the board, within the kind's size limits, and not over another widget.
    func isFree(_ rect: GridRect, for kind: IslandWidgetKind) -> Bool {
        isInBounds(rect) && fits(rect.size, kind) && !widgets.contains { $0.kind != kind && $0.frame.intersects(rect) }
    }

    func isInBounds(_ rect: GridRect) -> Bool {
        rect.column >= 0 && rect.row >= 0 && rect.width >= 1 && rect.height >= 1
            && rect.maxColumn <= Self.columns && rect.maxRow <= Self.rows
    }

    func fits(_ size: GridSize, _ kind: IslandWidgetKind) -> Bool {
        let lower = kind.minimumSize, upper = kind.maximumSize
        return (lower.width...upper.width).contains(size.width) && (lower.height...upper.height).contains(size.height)
    }

    /// The first free place, reading order, for the kind's default size, or failing that for any
    /// smaller size down to its minimum (largest area first).
    func freeSlot(for kind: IslandWidgetKind) -> GridRect? {
        let lower = kind.minimumSize, preferred = kind.defaultSize
        var sizes: [GridSize] = []
        for width in lower.width...preferred.width {
            for height in lower.height...preferred.height {
                sizes.append(GridSize(width: width, height: height))
            }
        }
        sizes.sort { ($0.width * $0.height, $0.width) > ($1.width * $1.height, $1.width) }
        for size in sizes {
            for row in 0...(Self.rows - size.height) {
                for column in 0...(Self.columns - size.width) {
                    let rect = GridRect(column: column, row: row, width: size.width, height: size.height)
                    if isFree(rect, for: kind) { return rect }
                }
            }
        }
        return nil
    }

    /// Adds the kind where there is room. False when it is already there or nothing fits.
    @discardableResult
    mutating func add(_ kind: IslandWidgetKind) -> Bool {
        guard !contains(kind), let rect = freeSlot(for: kind) else { return false }
        widgets.append(IslandWidget(kind: kind, frame: rect, options: kind.defaultOptions))
        return true
    }

    mutating func remove(_ kind: IslandWidgetKind) {
        widgets.removeAll { $0.kind == kind }
    }

    /// Moves or resizes; refused (false) when the new frame is not free.
    @discardableResult
    mutating func setFrame(_ rect: GridRect, for kind: IslandWidgetKind) -> Bool {
        guard let index = widgets.firstIndex(where: { $0.kind == kind }), isFree(rect, for: kind) else { return false }
        widgets[index].frame = rect
        return true
    }

    mutating func setOption(_ option: WidgetOption, _ on: Bool, for kind: IslandWidgetKind) {
        guard let index = widgets.firstIndex(where: { $0.kind == kind }), kind.options.contains(option) else { return }
        if on {
            widgets[index].options.insert(option)
        } else {
            widgets[index].options.remove(option)
        }
    }

    // Decoding drops anything invalid (a hand-edited or older plist), keeping the rest.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decoded = (try? container.decode([IslandWidget].self, forKey: .widgets)) ?? []
        self.init(widgets: decoded.map { widget in
            var widget = widget
            widget.options = widget.options.intersection(widget.kind.options)
            return widget
        })
    }
}

/// Points ↔ cells for a board drawn in `size` with `gap` between cells.
nonisolated struct WidgetBoardGeometry: Sendable, Equatable {
    let size: CGSize
    let gap: CGFloat

    var cellWidth: CGFloat { (size.width - gap * CGFloat(WidgetBoard.columns - 1)) / CGFloat(WidgetBoard.columns) }
    var cellHeight: CGFloat { (size.height - gap * CGFloat(WidgetBoard.rows - 1)) / CGFloat(WidgetBoard.rows) }

    func frame(for rect: GridRect) -> CGRect {
        CGRect(
            x: CGFloat(rect.column) * (cellWidth + gap),
            y: CGFloat(rect.row) * (cellHeight + gap),
            width: CGFloat(rect.width) * cellWidth + CGFloat(rect.width - 1) * gap,
            height: CGFloat(rect.height) * cellHeight + CGFloat(rect.height - 1) * gap
        )
    }

    /// The column whose leading edge is nearest to `x` (0…columns).
    func columnEdge(nearest x: CGFloat) -> Int {
        min(max(Int((x / (cellWidth + gap)).rounded()), 0), WidgetBoard.columns)
    }

    func rowEdge(nearest y: CGFloat) -> Int {
        min(max(Int((y / (cellHeight + gap)).rounded()), 0), WidgetBoard.rows)
    }

    /// A widget of `size` dragged so its top-left corner is at `origin`: the nearest whole-cell
    /// position, kept inside the board.
    func snappedMove(origin: CGPoint, size: GridSize) -> GridRect {
        GridRect(
            column: min(columnEdge(nearest: origin.x), WidgetBoard.columns - size.width),
            row: min(rowEdge(nearest: origin.y), WidgetBoard.rows - size.height),
            width: size.width,
            height: size.height
        )
    }

    /// A widget whose edges were dragged to `frame`: each edge snaps to the nearest cell boundary,
    /// then the size is clamped to the kind's limits, holding the edge that was not dragged.
    func snappedResize(frame: CGRect, from rect: GridRect, kind: IslandWidgetKind,
                       movesLeading: Bool, movesTop: Bool) -> GridRect {
        let lower = kind.minimumSize, upper = kind.maximumSize
        var left = columnEdge(nearest: frame.minX), right = columnEdge(nearest: frame.maxX + gap)
        var top = rowEdge(nearest: frame.minY), bottom = rowEdge(nearest: frame.maxY + gap)
        if movesLeading {
            right = rect.maxColumn
            left = min(max(left, right - upper.width), right - lower.width)
            left = max(left, 0)
        } else {
            left = rect.column
            right = max(min(right, left + upper.width), left + lower.width)
            right = min(right, WidgetBoard.columns)
        }
        if movesTop {
            bottom = rect.maxRow
            top = min(max(top, bottom - upper.height), bottom - lower.height)
            top = max(top, 0)
        } else {
            top = rect.row
            bottom = max(min(bottom, top + upper.height), top + lower.height)
            bottom = min(bottom, WidgetBoard.rows)
        }
        return GridRect(column: left, row: top, width: right - left, height: bottom - top)
    }
}
