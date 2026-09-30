import CoreGraphics
import Foundation

/// The panel's size while it is being dragged in Settings ▸ Widgets ▸ Size (session only).
nonisolated struct StudioDraft: Equatable, Sendable {
    var panel: PanelSettings
}

/// What the Size mode lets the board's grid be: cells stay large enough to hold a control.
nonisolated enum StudioGrid {
    /// A cell's smallest side: a mini control and a little room around it.
    static let minimumCell = BoardSizing.minimumCell

    static func cell(_ grid: BoardGrid, board: CGSize) -> CGSize { BoardSizing.cell(grid, board: board) }

    /// The column counts (even: the notch's centre line stays a cell edge) whose cells are wide
    /// enough on a board this wide.
    static func columns(board: CGSize, gap: CGFloat) -> [Int] {
        stride(from: BoardGrid.columnRange.lowerBound, through: BoardGrid.columnRange.upperBound, by: 2).filter {
            cell(BoardGrid(columns: $0, rows: BoardGrid.rowRange.lowerBound, gap: gap), board: board).width >= minimumCell
        }
    }

    static func rows(board: CGSize, gap: CGFloat) -> [Int] {
        BoardGrid.rowRange.filter {
            cell(BoardGrid(columns: BoardGrid.columnRange.lowerBound, rows: $0, gap: gap), board: board).height >= minimumCell
        }
    }

    /// Why the grid cannot take `columns` (or `rows`) on this board; nil when it can.
    static func blocked(columns: Int? = nil, rows: Int? = nil, grid: BoardGrid, board: CGSize) -> String? {
        if let columns {
            guard BoardGrid.columnRange.contains(columns) else {
                return columns < grid.columns ? String(localized: "\(BoardGrid.columnRange.lowerBound) columns is the fewest.")
                                              : String(localized: "\(BoardGrid.columnRange.upperBound) columns is the most.")
            }
            let width = cell(BoardGrid(columns: columns, rows: grid.rows, gap: grid.gap), board: board).width
            if width < minimumCell {
                return String(localized: "\(columns) columns would be \(Int(width.rounded(.down))) pt wide each. Make the panel wider first.")
            }
        }
        if let rows {
            guard BoardGrid.rowRange.contains(rows) else {
                return rows < grid.rows ? String(localized: "\(BoardGrid.rowRange.lowerBound) rows is the fewest.")
                                        : String(localized: "\(BoardGrid.rowRange.upperBound) rows is the most.")
            }
            let height = cell(BoardGrid(columns: grid.columns, rows: rows, gap: grid.gap), board: board).height
            if height < minimumCell {
                return String(localized: "\(rows) rows would be \(Int(height.rounded(.down))) pt tall each. Make the board taller first.")
            }
        }
        return nil
    }

    /// The widgets a new grid would set aside (no room for them on it), by their titles. `keepingCells`:
    /// each widget on as many cells as before (`WidgetBoard.setGridKeepingCells`), not scaled.
    static func setAside(by grid: BoardGrid, on board: WidgetBoard, keepingCells: Bool = false) -> [String] {
        var trial = board
        if keepingCells { trial.setGridKeepingCells(grid) } else { trial.setGrid(grid) }
        let before = Set(board.parked.map(\.id))
        return trial.parked.filter { !before.contains($0.id) }.map(\.kind.title)
    }
}
