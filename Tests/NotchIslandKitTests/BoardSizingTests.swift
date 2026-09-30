import CoreGraphics
import Foundation
import Testing
@testable import NotchIslandKit

/// Settings ▸ Widgets ▸ Size by cells (`BoardSizing`): cells added keep their size and the panel
/// grows with them, or, with the size kept, they and the gap get smaller; every widget keeps its
/// cells and its place about the notch.
@Suite struct BoardSizingTests {
    let layout = IslandLayout(notch: CGSize(width: 185, height: 32), scale: .standard, screen: CGSize(width: 1728, height: 1117))

    private func cell(_ panel: PanelSettings, _ grid: BoardGrid) -> CGSize {
        BoardSizing.cell(grid, board: BoardSizing.board(layout, panel: panel))
    }

    private func near(_ a: CGSize, _ b: CGSize) -> Bool {
        abs(a.width - b.width) <= BoardSizing.tolerance && abs(a.height - b.height) <= BoardSizing.tolerance
    }

    @Test func columnsAddedInPairsKeepTheCellsAndWidenThePanel() throws {
        let panel = PanelSettings(), grid = BoardGrid.standard
        let before = cell(panel, grid)
        let change = try #require(BoardSizing.setCounts(columns: 14, rows: 3, panel: panel, grid: grid, layout: layout).change)
        #expect(change.grid.columns == 14 && change.grid.rows == 3 && change.grid.gap == grid.gap)
        #expect(near(cell(change.panel, change.grid), before), "\(cell(change.panel, change.grid)) was \(before)")
        let widths = (BoardSizing.board(layout, panel: panel).width, BoardSizing.board(layout, panel: change.panel).width)
        // Two cells and two gaps wider.
        #expect(abs(widths.1 - widths.0 - 2 * (before.width + grid.gap)) <= 1)
        // Taken away again: the panel it was.
        let back = try #require(BoardSizing.setCounts(columns: 12, rows: 3, panel: change.panel, grid: change.grid, layout: layout).change)
        #expect(abs(back.panel.widthFactor - panel.widthFactor) < 0.002 && back.grid == grid)
    }

    @Test func aRowAddedKeepsTheCellsAndDeepensTheBoard() throws {
        let panel = PanelSettings(), grid = BoardGrid.standard
        let before = cell(panel, grid)
        let change = try #require(BoardSizing.setCounts(columns: 12, rows: 4, panel: panel, grid: grid, layout: layout).change)
        #expect(near(cell(change.panel, change.grid), before))
        #expect(change.panel.boardHeightFactor > panel.boardHeightFactor && change.panel.widthFactor == panel.widthFactor)
    }

    @Test func aKeptSizeMakesTheCellsAndTheGapSmaller() throws {
        var panel = PanelSettings()
        panel.keepsSize = true
        let grid = BoardGrid.standard
        let before = cell(panel, grid)
        let change = try #require(BoardSizing.setCounts(columns: 16, rows: 3, panel: panel, grid: grid, layout: layout).change)
        #expect(change.panel == panel)
        let after = cell(change.panel, change.grid)
        #expect(after.width < before.width && change.grid.gap < grid.gap)
        // Still the whole board, cells and gaps.
        #expect(abs(BoardSizing.board(change.grid, cell: after).width - BoardSizing.board(layout, panel: panel).width) < 0.01)
        // The gap about as much smaller as the cells.
        #expect(abs(change.grid.gap / after.width - grid.gap / before.width) < 0.03)
    }

    @Test func theScreenStopsThePanelAndSaysWhatElseToDo() {
        var panel = PanelSettings(), grid = BoardGrid.standard
        var refusal: String?
        for _ in 0..<12 {
            switch BoardSizing.setCounts(columns: grid.columns + 2, rows: grid.rows, panel: panel, grid: grid, layout: layout) {
            case .changed(let change):
                (panel, grid) = (change.panel, change.grid)
            case .refused(let reason):
                refusal = reason
            }
            if refusal != nil { break }
        }
        let reason = try? #require(refusal)
        #expect(reason?.contains("Keep Panel Size") == true || reason?.contains("most") == true)
        #expect(layout.replacing(panel: panel.layout).size(for: .expanded(.home)).width <= layout.maximumExpandedSize.width)
    }

    @Test func aCellSizeSetsThePanel() throws {
        let panel = PanelSettings(), grid = BoardGrid.standard
        let change = try #require(BoardSizing.setCell(CGSize(width: 50, height: 40), panel: panel, grid: grid, layout: layout).change)
        #expect(near(cell(change.panel, change.grid), CGSize(width: 50, height: 40)))
    }

    @Test func aGapKeepsTheCellsUnlessTheSizeIsKept() throws {
        var panel = PanelSettings()
        let grid = BoardGrid.standard
        let before = cell(panel, grid)
        let wider = try #require(BoardSizing.setGap(12, panel: panel, grid: grid, layout: layout).change)
        #expect(near(cell(wider.panel, wider.grid), before) && wider.grid.gap == 12)
        panel.keepsSize = true
        let kept = try #require(BoardSizing.setGap(12, panel: panel, grid: grid, layout: layout).change)
        #expect(kept.panel == panel && cell(kept.panel, kept.grid).width < before.width)
    }

    @Test func widgetsKeepTheirCellsAndTheirPlaceAboutTheNotch() {
        var board = WidgetBoard.standard
        let before = board.widgets
        board.setGridKeepingCells(BoardGrid(columns: 14, rows: 4, gap: 8))
        #expect(board.parked.isEmpty)
        for widget in before {
            let now = board.widget(widget.id)?.frame
            // One column more at the leading side: everything moves over by one, keeps its size.
            #expect(now == GridRect(column: widget.frame.column + 1, row: widget.frame.row, width: widget.frame.width, height: widget.frame.height))
            if widget.frame.isHorizontallyCentred(in: .standard), let now { #expect(now.isHorizontallyCentred(in: board.grid)) }
        }
        board.setGridKeepingCells(.standard)
        #expect(board == WidgetBoard.standard)
    }

    @Test func fewerCellsMoveInWhatTheyCutAndParkTheRest() {
        // A one-cell control in every cell of 12 × 3: 10 × 3 keeps 30 of the 36, the outer columns
        // set aside.
        var widgets: [IslandWidget] = []
        for row in 0..<3 {
            for column in 0..<12 {
                widgets.append(IslandWidget(kind: .wifi, frame: GridRect(column: column, row: row, width: 1, height: 1), options: [], id: WidgetID()))
            }
        }
        var board = WidgetBoard(widgets: widgets)
        board.setGridKeepingCells(BoardGrid(columns: 10, rows: 3, gap: 8))
        #expect(board.widgets.count == 30 && board.parked.count == 6)
        for widget in board.widgets {
            #expect(board.isFree(widget.frame, for: widget.kind, excluding: widget.id))
        }
        // The inner ones did not move about the notch.
        let inner = widgets.filter { (1...10).contains($0.frame.column) }
        for widget in inner { #expect(board.widget(widget.id)?.frame.column == widget.frame.column - 1) }
    }
}
