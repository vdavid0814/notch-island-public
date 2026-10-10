import CoreGraphics
import Foundation

// A widget sits on whole cells of the board's grid, so free dragging in the editor always lands on
// cell boundaries, and every edge lines up with some other edge or with the island's centre. The
// board is centred under the notch whatever its number of columns: with an odd number, the notch's
// centre line runs through the middle of a column.

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
    func isHorizontallyCentred(in grid: BoardGrid) -> Bool { column * 2 + width == grid.columns }
    func isVerticallyCentred(in grid: BoardGrid) -> Bool { row * 2 + height == grid.rows }
}

/// The board's cells: how many, and the space between them. Owned by the board (`WidgetBoard.grid`).
nonisolated struct BoardGrid: Sendable, Codable, Hashable {
    /// Twelve columns by three rows gives near-square cells on the standard island, each row tall
    /// enough for one row of controls. It is also the reference the kinds' sizes are stated in.
    static let standard = BoardGrid(columns: 12, rows: 3, gap: 8)
    static let columnRange = PanelSettings.columnRange
    static let rowRange = PanelSettings.rowRange
    static let gapRange = CGFloat(PanelSettings.gapRange.lowerBound)...CGFloat(PanelSettings.gapRange.upperBound)

    private(set) var columns: Int
    private(set) var rows: Int
    /// Between two widgets, and the rhythm of the whole board.
    private(set) var gap: CGFloat

    init(columns: Int, rows: Int, gap: CGFloat) {
        self.columns = min(max(columns, Self.columnRange.lowerBound), Self.columnRange.upperBound)
        self.rows = min(max(rows, Self.rowRange.lowerBound), Self.rowRange.upperBound)
        self.gap = min(max(gap, Self.gapRange.lowerBound), Self.gapRange.upperBound)
    }

    // Tolerant decoding: a missing or odd value takes the standard one, clamped.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T { (try? c.decodeIfPresent(T.self, forKey: key)).flatMap { $0 } ?? fallback }
        self.init(columns: value(.columns, Self.standard.columns), rows: value(.rows, Self.standard.rows),
                  gap: value(.gap, Self.standard.gap))
    }

    /// A kind's smallest size on this grid: its reference size in cells, whatever their number —
    /// more cells are more room, not larger widgets (Settings ▸ Widgets ▸ Size) — never more than
    /// the grid.
    func minimum(for kind: IslandWidgetKind) -> GridSize {
        let reference = kind.minimumSize
        return GridSize(width: min(max(reference.width, 1), columns), height: min(max(reference.height, 1), rows))
    }

    /// A kind's largest size on this grid: its reference size, and on a larger grid as much more
    /// as the grid is larger (a widget as wide as the board stays able to be), never below its
    /// minimum.
    func maximum(for kind: IslandWidgetKind) -> GridSize {
        let reference = kind.maximumSize, lower = minimum(for: kind)
        return GridSize(width: min(max(reference.width, scaled(reference.width, of: .columns, .down), lower.width), columns),
                        height: min(max(reference.height, scaled(reference.height, of: .rows, .down), lower.height), rows))
    }

    /// The size a new widget of the kind takes.
    func defaultSize(for kind: IslandWidgetKind) -> GridSize {
        let reference = kind.defaultSize, lower = minimum(for: kind), upper = maximum(for: kind)
        return GridSize(width: min(max(reference.width, lower.width), upper.width),
                        height: min(max(reference.height, lower.height), upper.height))
    }

    func fits(_ size: GridSize, _ kind: IslandWidgetKind) -> Bool {
        let lower = minimum(for: kind), upper = maximum(for: kind)
        return (lower.width...upper.width).contains(size.width) && (lower.height...upper.height).contains(size.height)
    }

    private enum Axis { case columns, rows }

    private func scaled(_ cells: Int, of axis: Axis, _ rule: FloatingPointRoundingRule) -> Int {
        let (count, reference) = axis == .columns ? (columns, Self.standard.columns) : (rows, Self.standard.rows)
        return Int((Double(cells * count) / Double(reference)).rounded(rule))
    }
}

/// Points ↔ cells for a board drawn in `size`.
nonisolated struct WidgetBoardGeometry: Sendable, Equatable {
    let size: CGSize
    let grid: BoardGrid

    var gap: CGFloat { grid.gap }
    var cellWidth: CGFloat { (size.width - gap * CGFloat(grid.columns - 1)) / CGFloat(grid.columns) }
    var cellHeight: CGFloat { (size.height - gap * CGFloat(grid.rows - 1)) / CGFloat(grid.rows) }

    func frame(for rect: GridRect) -> CGRect {
        CGRect(
            x: CGFloat(rect.column) * (cellWidth + gap),
            y: CGFloat(rect.row) * (cellHeight + gap),
            width: CGFloat(rect.width) * cellWidth + CGFloat(rect.width - 1) * gap,
            height: CGFloat(rect.height) * cellHeight + CGFloat(rect.height - 1) * gap
        )
    }

    /// The size a widget on `rect` is laid out at on this board: its cells' size or, where the
    /// cells are smaller than the design's, the design's — the board then draws it smaller as a
    /// whole (`ZoomedWidgetView`). Whatever shows or places a widget's parts as the board does
    /// (Customize's editor, its inspector) lays it out at this size, not at `frame(for:)`'s: laid
    /// out again for the smaller room, its texts came out larger and its parts elsewhere than on
    /// the island (seen with the island at its small size, 0.8.2).
    func laidSize(for rect: GridRect) -> CGSize {
        let size = frame(for: rect).size
        let scale = WidgetZoom.scale(span: rect.size, size: size)
        guard scale < 0.999, scale > 0 else { return size }
        return CGSize(width: size.width / scale, height: size.height / scale)
    }

    /// The column whose leading edge is nearest to `x` (0…columns).
    func columnEdge(nearest x: CGFloat) -> Int {
        min(max(Int((x / (cellWidth + gap)).rounded()), 0), grid.columns)
    }

    func rowEdge(nearest y: CGFloat) -> Int {
        min(max(Int((y / (cellHeight + gap)).rounded()), 0), grid.rows)
    }

    /// A widget of `size` dragged so its top-left corner is at `origin`: the nearest whole-cell
    /// position, kept inside the board.
    func snappedMove(origin: CGPoint, size: GridSize) -> GridRect {
        GridRect(
            column: min(columnEdge(nearest: origin.x), grid.columns - size.width),
            row: min(rowEdge(nearest: origin.y), grid.rows - size.height),
            width: size.width,
            height: size.height
        )
    }

    /// A widget whose edges were dragged to `frame`: each edge snaps to the nearest cell boundary,
    /// then the size is clamped to the kind's limits, holding the edge that was not dragged.
    func snappedResize(frame: CGRect, from rect: GridRect, kind: IslandWidgetKind,
                       movesLeading: Bool, movesTop: Bool) -> GridRect {
        let lower = grid.minimum(for: kind), upper = grid.maximum(for: kind)
        var left = columnEdge(nearest: frame.minX), right = columnEdge(nearest: frame.maxX + gap)
        var top = rowEdge(nearest: frame.minY), bottom = rowEdge(nearest: frame.maxY + gap)
        if movesLeading {
            right = rect.maxColumn
            left = min(max(left, right - upper.width), right - lower.width)
            left = max(left, 0)
        } else {
            left = rect.column
            right = max(min(right, left + upper.width), left + lower.width)
            right = min(right, grid.columns)
        }
        if movesTop {
            bottom = rect.maxRow
            top = min(max(top, bottom - upper.height), bottom - lower.height)
            top = max(top, 0)
        } else {
            top = rect.row
            bottom = max(min(bottom, top + upper.height), top + lower.height)
            bottom = min(bottom, grid.rows)
        }
        return GridRect(column: left, row: top, width: right - left, height: bottom - top)
    }
}
