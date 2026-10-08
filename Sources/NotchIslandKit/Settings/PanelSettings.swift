import CoreGraphics
import Foundation

/// The open panel's board (Settings ▸ Widgets ▸ Size): square cells of one size, the space between
/// them, and how many columns and rows of them there are. The panel is exactly as large as they
/// make it (`IslandLayout.size(for: .expanded)`), times the island's own scale (`IslandScale`, the
/// ready-made sizes): a cell never changes shape, and a widget on its cells only ever grows or
/// shrinks as a whole. More columns or rows are more cells of the same size, so more widgets fit;
/// smaller cells fit more of them in the same room.
///
/// Stored as one JSON value (`ni2.panel`); a missing or out-of-range field takes its default or its
/// nearest bound. A value from before (the panel's width and height as factors) has no cells: it
/// comes back as the board's own grid at the default cell (`isFromBefore`, `AppModel`).
nonisolated struct PanelSettings: Sendable, Equatable, Codable {
    /// A cell's side, in points at the standard scale.
    var cell: Double = 40
    /// Between two cells, in points at the standard scale.
    var gap: Double = 8
    var columns: Int = 12
    var rows: Int = 3
    /// Read from a value stored before the board was set by its cells (not stored).
    private(set) var isFromBefore = false

    static let cellRange: ClosedRange<Double> = 27...60
    static let gapRange: ClosedRange<Double> = 3...24
    static let columnRange = 4...18
    static let rowRange = 1...6

    init() {}

    init(cell: Double, gap: Double, columns: Int, rows: Int) {
        self.cell = Self.cellRange.clamp(cell.rounded())
        self.gap = Self.gapRange.clamp(gap.rounded())
        self.columns = Self.columnRange.clamp(columns)
        self.rows = Self.rowRange.clamp(rows)
    }

    private enum CodingKeys: String, CodingKey { case cell, gap, columns, rows }

    // Tolerant decoding: every field optional, clamped.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PanelSettings()
        self.init(cell: c.lossy(Double.self, .cell) ?? d.cell, gap: c.lossy(Double.self, .gap) ?? d.gap,
                  columns: c.lossy(Int.self, .columns) ?? d.columns, rows: c.lossy(Int.self, .rows) ?? d.rows)
        isFromBefore = c.lossy(Double.self, .cell) == nil
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(cell, forKey: .cell)
        try c.encode(gap, forKey: .gap)
        try c.encode(columns, forKey: .columns)
        try c.encode(rows, forKey: .rows)
    }

    static func == (a: Self, b: Self) -> Bool {
        a.cell == b.cell && a.gap == b.gap && a.columns == b.columns && a.rows == b.rows
    }

    /// The boards' grid: every page's (`AppModel.syncBoards`).
    var grid: BoardGrid { BoardGrid(columns: columns, rows: rows, gap: CGFloat(gap)) }

    /// The part `IslandLayout` sizes the panel with.
    var layout: PanelLayout {
        PanelLayout(cell: CGFloat(cell), gap: CGFloat(gap), columns: columns, rows: rows)
    }
}

/// The panel's board as `IslandLayout` sizes it (`PanelSettings`).
nonisolated struct PanelLayout: Sendable, Equatable {
    var cell: CGFloat = 40
    var gap: CGFloat = 8
    var columns = 12
    var rows = 3
}

nonisolated extension ClosedRange {
    func clamp(_ value: Bound) -> Bound { Swift.min(Swift.max(value, lowerBound), upperBound) }
}

nonisolated extension KeyedDecodingContainer {
    /// The value at `key`, or nil when it is missing or cannot be read.
    func lossy<T: Decodable>(_ type: T.Type, _ key: Key) -> T? {
        (try? decodeIfPresent(type, forKey: key)).flatMap { $0 }
    }
}
