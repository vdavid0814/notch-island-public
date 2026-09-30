import CoreGraphics
import Foundation

/// The open panel's size by its cells (Settings ▸ Widgets ▸ Size). The board is so many cells of
/// one size with a gap between them; the panel is as large as its board.
///
/// - The panel may be set as before (its sides dragged, its sliders), and its cells take their
///   share of it.
/// - Cells added or taken away keep their size and the gap, and the panel grows or shrinks with
///   them: columns in pairs, one at each side, rows at the bottom. Each widget keeps its cells, so
///   more cells are more room for widgets (`WidgetBoard.setGridKeepingCells`).
/// - With the size kept (`PanelSettings.keepsSize`) the panel stays as it is, and the cells and the
///   gap get smaller together, in proportion, so the new ones fit.
nonisolated enum BoardSizing {
    /// A change of the board: the panel and the grid it now has.
    struct Change: Equatable {
        var panel: PanelSettings
        var grid: BoardGrid
    }

    /// A change, or why it cannot be made.
    enum Outcome: Equatable {
        case changed(Change)
        case refused(String)

        var change: Change? {
            if case .changed(let change) = self { return change }
            return nil
        }
    }

    /// A cell's smallest side: a mini control and a little room around it.
    static let minimumCell: CGFloat = 26
    /// Its largest: past this a single cell is a widget of its own.
    static let maximumCell: CGFloat = 120
    /// Within this of the size asked, a board is that size (the island's width and height are whole
    /// points, so a cell's size comes back a fraction off).
    static let tolerance: CGFloat = 0.75

    // MARK: Measuring

    /// The widgets' board in the open island: its width inside the sides' insets, its height
    /// between the header and the bottom inset.
    static func board(_ layout: IslandLayout) -> CGSize {
        let presentation = IslandPresentation.expanded(.home)
        let island = layout.size(for: presentation)
        let split = NotchSplit(layout: layout, presentation: presentation,
                               outerInset: Metrics.Expanded.horizontalInset, clearance: Metrics.notchClearance)
        return CGSize(width: island.width - 2 * split.contentInset,
                      height: island.height - layout.notch.height - Metrics.Expanded.pageTopInset - Metrics.Expanded.pageBottomInset)
    }

    static func board(_ layout: IslandLayout, panel: PanelSettings) -> CGSize { board(layout.replacing(panel: panel.layout)) }

    /// One cell of `grid` on a board of `board`.
    static func cell(_ grid: BoardGrid, board: CGSize) -> CGSize {
        let geometry = WidgetBoardGeometry(size: board, grid: grid)
        return CGSize(width: geometry.cellWidth, height: geometry.cellHeight)
    }

    /// The board `grid`'s cells make at `cell`.
    static func board(_ grid: BoardGrid, cell: CGSize) -> CGSize {
        CGSize(width: CGFloat(grid.columns) * cell.width + CGFloat(grid.columns - 1) * grid.gap,
               height: CGFloat(grid.rows) * cell.height + CGFloat(grid.rows - 1) * grid.gap)
    }

    /// The panel whose board is `board`, the other settings kept; nil where the screen (or the
    /// proportions' ranges) stops it short of that by more than `tolerance`.
    static func panel(forBoard target: CGSize, from panel: PanelSettings, layout: IslandLayout) -> PanelSettings? {
        let current = layout.replacing(panel: panel.layout)
        let island = current.size(for: .expanded(.home)), board = board(current)
        // The insets around the board are the same at any size: the island is as much larger.
        let wanted = CGSize(width: (target.width + island.width - board.width).rounded(),
                            height: (target.height + island.height - board.height).rounded())
        let f = layout.scale.factor
        let base = max(layout.notch.width + IslandLayout.expandedExtraWidth, IslandLayout.expandedMinimumWidth) * f
        var next = panel
        next.widthFactor = PanelSettings.widthRange.clamp(Double(wanted.width / base))
        next.boardHeightFactor = PanelSettings.boardHeightRange.clamp(Double((wanted.height - layout.notch.height) / (IslandLayout.expandedPageHeight * f)))
        let reached = self.board(layout, panel: next)
        guard abs(reached.width - target.width) <= tolerance + 0.5, abs(reached.height - target.height) <= tolerance + 0.5 else { return nil }
        return next
    }

    /// How far the panel's proportions may go on this screen: their ranges, no further than the
    /// screen lets the panel grow (past that a slider would move and nothing change).
    static func factorRanges(_ layout: IslandLayout) -> (width: ClosedRange<Double>, height: ClosedRange<Double>) {
        let f = layout.scale.factor
        let base = max(layout.notch.width + IslandLayout.expandedExtraWidth, IslandLayout.expandedMinimumWidth) * f
        let limit = layout.maximumExpandedSize
        let width = min(PanelSettings.widthRange.upperBound, Double(limit.width / base))
        let height = min(PanelSettings.boardHeightRange.upperBound,
                         Double((limit.height - layout.notch.height) / (IslandLayout.expandedPageHeight * f)))
        return (PanelSettings.widthRange.lowerBound...max(width, PanelSettings.widthRange.lowerBound + 0.01),
                PanelSettings.boardHeightRange.lowerBound...max(height, PanelSettings.boardHeightRange.lowerBound + 0.01))
    }

    // MARK: Changing

    /// `columns` and `rows` instead of the grid's: the panel grows or shrinks with the cells, or,
    /// with its size kept, the cells and the gap fit themselves into it.
    static func setCounts(columns: Int, rows: Int, panel: PanelSettings, grid: BoardGrid, layout: IslandLayout) -> Outcome {
        guard BoardGrid.columnRange.contains(columns) else {
            return .refused(columns < grid.columns ? String(localized: "\(BoardGrid.columnRange.lowerBound) columns is the fewest.")
                                                   : String(localized: "\(BoardGrid.columnRange.upperBound) columns is the most."))
        }
        guard BoardGrid.rowRange.contains(rows) else {
            return .refused(rows < grid.rows ? String(localized: "\(BoardGrid.rowRange.lowerBound) rows is the fewest.")
                                             : String(localized: "\(BoardGrid.rowRange.upperBound) rows is the most."))
        }
        let board = board(layout, panel: panel)
        let cell = cell(grid, board: board)
        if !panel.keepsSize {
            let next = BoardGrid(columns: columns, rows: rows, gap: grid.gap)
            guard let resized = self.panel(forBoard: self.board(next, cell: cell), from: panel, layout: layout) else {
                return .refused(columns > grid.columns || rows > grid.rows
                    ? String(localized: "The panel can't grow any larger on this screen. Turn on Keep Panel Size to fit more cells by making them smaller.")
                    : String(localized: "The panel can't get any smaller. Turn on Keep Panel Size to make the cells larger instead."))
            }
            return .changed(Change(panel: resized, grid: next))
        }
        // The size kept: the gap in proportion to the cells, along the side that changes.
        let ratio: CGFloat
        let count: Int
        let length: CGFloat
        if columns != grid.columns {
            (ratio, count, length) = (grid.gap / max(cell.width, 1), columns, board.width)
        } else {
            (ratio, count, length) = (grid.gap / max(cell.height, 1), rows, board.height)
        }
        let side = length / (CGFloat(count) + CGFloat(count - 1) * ratio)
        let gap = (ratio * side).rounded()
        let next = BoardGrid(columns: columns, rows: rows, gap: gap)
        let fitted = self.cell(next, board: board)
        if fitted.width < minimumCell || fitted.height < minimumCell {
            return .refused(columns != grid.columns
                ? String(localized: "\(columns) columns would be \(Int(fitted.width.rounded(.down))) pt wide each. Make the panel wider first, or turn off Keep Panel Size.")
                : String(localized: "\(rows) rows would be \(Int(fitted.height.rounded(.down))) pt tall each. Make the board taller first, or turn off Keep Panel Size."))
        }
        return .changed(Change(panel: panel, grid: next))
    }

    /// Cells of `cell` (the grid and its gap kept): the panel is as large as they make it.
    static func setCell(_ cell: CGSize, panel: PanelSettings, grid: BoardGrid, layout: IslandLayout) -> Outcome {
        let cell = CGSize(width: min(max(cell.width, minimumCell), maximumCell), height: min(max(cell.height, minimumCell), maximumCell))
        guard let resized = self.panel(forBoard: board(grid, cell: cell), from: panel, layout: layout) else {
            return .refused(String(localized: "The panel can't be that large on this screen."))
        }
        return .changed(Change(panel: resized, grid: grid))
    }

    /// Another gap between the cells: the cells keep their size and the panel follows them, or,
    /// with its size kept, the cells take up the difference.
    static func setGap(_ gap: CGFloat, panel: PanelSettings, grid: BoardGrid, layout: IslandLayout) -> Outcome {
        let next = BoardGrid(columns: grid.columns, rows: grid.rows, gap: gap)
        let board = board(layout, panel: panel)
        if panel.keepsSize {
            let fitted = cell(next, board: board)
            guard min(fitted.width, fitted.height) >= minimumCell else {
                return .refused(String(localized: "A gap that wide leaves cells under \(Int(minimumCell)) pt."))
            }
            return .changed(Change(panel: panel, grid: next))
        }
        guard let resized = self.panel(forBoard: self.board(next, cell: cell(grid, board: board)), from: panel, layout: layout) else {
            return .refused(String(localized: "The panel can't grow any larger on this screen."))
        }
        return .changed(Change(panel: resized, grid: next))
    }
}
