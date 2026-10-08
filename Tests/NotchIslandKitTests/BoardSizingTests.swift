import CoreGraphics
import Foundation
import Testing
@testable import NotchIslandKit

/// Settings ▸ Widgets ▸ Size: the panel by its square cells (`PanelSettings`, `BoardSizing`).
@Suite struct BoardSizingTests {
    /// This Mac: a 156-pt notch on 1280 × 832.
    private func layout(_ panel: PanelSettings = PanelSettings(), scale: IslandScale = .standard) -> IslandLayout {
        IslandLayout(notch: CGSize(width: 156, height: 29), scale: scale, screen: CGSize(width: 1280, height: 832), panel: panel.layout)
    }

    private func cell(_ layout: IslandLayout, _ panel: PanelSettings) -> CGSize {
        let geometry = WidgetBoardGeometry(size: BoardSizing.board(layout), grid: panel.grid)
        return CGSize(width: geometry.cellWidth, height: geometry.cellHeight)
    }

    /// Whatever the counts, the gap and the scale, a cell is square and of the panel's size: the
    /// panel is exactly as large as its cells make it.
    @Test(arguments: IslandScale.allCases)
    func cellsAreSquareAndThePanelIsTheirs(scale: IslandScale) {
        for (columns, rows, gap) in [(12, 3, 8.0), (13, 4, 4), (9, 2, 14), (16, 5, 10)] {
            let panel = PanelSettings(cell: 40, gap: gap, columns: columns, rows: rows)
            let layout = layout(panel, scale: scale)
            let side = cell(layout, panel)
            // The island's size is whole points: a cell is a fraction of a point off at most.
            #expect(abs(side.width - side.height) < 0.2, "\(scale) \(columns)×\(rows)")
            #expect(abs(side.width - layout.cell) < 0.2, "\(scale) \(columns)×\(rows)")
            #expect(layout.pitch == ((40 + gap) * scale.factor).rounded() && layout.cell == layout.pitch - gap)
        }
    }

    /// One more column is one more cell of the same size: the panel one step wider, nothing else.
    @Test func aColumnMoreIsACellMore() {
        var panel = PanelSettings()
        let before = layout(panel)
        panel.columns += 1
        let after = layout(panel)
        let grown = after.size(for: .expanded(.home)).width - before.size(for: .expanded(.home)).width
        #expect(abs(grown - CGFloat(panel.cell + panel.gap)) <= 1)
        #expect(abs(cell(after, panel).width - cell(before, PanelSettings()).width) < 0.2)
        #expect(after.size(for: .expanded(.home)).height == before.size(for: .expanded(.home)).height)
    }

    /// Smaller cells divide the same room into more of them; larger ones into fewer.
    @Test func smallerCellsFitMoreInTheSameRoom() {
        let base = layout()
        let room = BoardSizing.board(base)
        let small = BoardSizing.dividing(room, into: 30, from: PanelSettings(), layout: base)
        let large = BoardSizing.dividing(room, into: 56, from: PanelSettings(), layout: base)
        #expect(small.cell == 30 && small.columns > 12 && small.rows > 3)
        #expect(large.cell == 56 && large.columns < 12 && large.rows < 3)
        // About the room it was: within a cell each way.
        let smallBoard = BoardSizing.board(layout(small))
        #expect(abs(smallBoard.width - room.width) <= CGFloat(small.cell + small.gap))
        #expect(abs(smallBoard.height - room.height) <= CGFloat(small.cell + small.gap))
    }

    /// A dragged edge lands on whole cells.
    @Test func aDragLandsOnWholeCells() {
        let panel = PanelSettings()
        let base = layout(panel)
        let island = base.size(for: .expanded(.home))
        let step = CGFloat(panel.cell + panel.gap)
        #expect(BoardSizing.counts(forIsland: island, panel: panel, layout: base) == (12, 3))
        #expect(BoardSizing.counts(forIsland: CGSize(width: island.width + step * 0.4, height: island.height), panel: panel, layout: base) == (12, 3))
        #expect(BoardSizing.counts(forIsland: CGSize(width: island.width + step * 0.6, height: island.height), panel: panel, layout: base).columns == 13)
        #expect(BoardSizing.counts(forIsland: CGSize(width: island.width, height: island.height + step), panel: panel, layout: base).rows == 4)
    }

    /// No fewer columns than leave the header room beside the notch, no more than the screen takes.
    @Test func theCountsStayWithinTheScreenAndTheHeader() {
        let base = layout()
        let tiny = BoardSizing.fitted(PanelSettings(cell: 40, gap: 8, columns: 4, rows: 1), layout: base)
        let narrow = layout(tiny).size(for: .expanded(.home)).width
        #expect(narrow >= 156 + 2 * IslandLayout.headerEar - 1)
        let huge = BoardSizing.fitted(PanelSettings(cell: 40, gap: 8, columns: 40, rows: 10), layout: base)
        let size = layout(huge).size(for: .expanded(.home))
        #expect(size.width <= base.maximumExpandedSize.width && size.height <= base.maximumExpandedSize.height)
        #expect(huge.columns < 40 && huge.rows < 10)
    }

    /// A panel stored before (its width and height as factors) comes back as its board's grid.
    @Test func aPanelFromBeforeIsMarked() throws {
        let old = try JSONDecoder().decode(PanelSettings.self, from: Data(#"{"widthFactor":1.2,"boardHeightFactor":1.5}"#.utf8))
        #expect(old.isFromBefore)
        let new = try JSONDecoder().decode(PanelSettings.self, from: JSONEncoder().encode(PanelSettings(cell: 32, gap: 6, columns: 15, rows: 4)))
        #expect(!new.isFromBefore && new == PanelSettings(cell: 32, gap: 6, columns: 15, rows: 4))
    }

    /// A column added at the side whose edge was dragged: the widgets stay on their cells, counted
    /// from the other side.
    @Test func aColumnGoesWhereTheEdgeWasDragged() throws {
        var board = WidgetBoard(widgets: [])
        let added = board.add(.wifi, near: GridRect(column: 0, row: 0, width: 2, height: 1))
        let id = try #require(added)
        var leading = board, trailing = board
        let wider = BoardGrid(columns: 13, rows: 3, gap: 8)
        leading.setGridKeepingCells(wider, leadingColumns: 1)
        trailing.setGridKeepingCells(wider, leadingColumns: 0)
        #expect(leading.widget(id)?.frame.column == 1)
        #expect(trailing.widget(id)?.frame.column == 0)
        #expect(leading.widget(id)?.frame.size == board.widget(id)?.frame.size)
    }
}

/// The gap and the zoom: the gap never changes the panel, and a widget smaller than its design is
/// that design zoomed out.
@Suite struct GapAndZoomTests {
    private func layout(_ panel: PanelSettings) -> IslandLayout {
        IslandLayout(notch: CGSize(width: 156, height: 29), scale: .standard, screen: CGSize(width: 1280, height: 832), panel: panel.layout)
    }

    @Test func theGapLeavesThePanelAsItIs() {
        let panel = PanelSettings()
        let island = layout(panel).size(for: .expanded(.home))
        for gap in [2.0, 6, 12, 16, 24] {
            let next = BoardSizing.withGap(gap, panel)
            #expect(next.cell + next.gap == panel.cell + panel.gap && next.columns == 12 && next.rows == 3)
            #expect(layout(next).size(for: .expanded(.home)) == island, "gap \(gap)")
            // The board drawn inside is the cells and gaps exactly, its cells square.
            let board = BoardSizing.board(layout(next))
            let geometry = WidgetBoardGeometry(size: board, grid: next.grid)
            #expect(abs(geometry.cellWidth - geometry.cellHeight) < 0.01 && abs(geometry.cellWidth - CGFloat(next.cell)) < 0.01)
        }
        // No gap so wide the cells go under the smallest.
        #expect(BoardSizing.gapRange(PanelSettings(cell: 24, gap: 8, columns: 12, rows: 3)).upperBound == 8)
    }

    @Test func aWidgetIsZoomedOnlyBelowItsDesign() {
        let span = GridSize(width: 4, height: 2)
        let design = WidgetZoom.designSize(span: span)
        #expect(design == CGSize(width: 4 * 48 - 8, height: 2 * 48 - 8))
        #expect(WidgetZoom.scale(span: span, size: design) == 1)
        #expect(WidgetZoom.scale(span: span, size: CGSize(width: design.width * 1.5, height: design.height * 1.5)) == 1)
        let small = WidgetZoom.scale(span: span, size: CGSize(width: design.width * 0.75, height: design.height * 0.8))
        #expect(abs(small - 0.75) < 1e-9)
    }

    /// Reset Size: every board exactly as Size mode found it, though a smaller grid moved and
    /// parked its widgets in between.
    @MainActor @Test func theBoardsComeBackAsTheyWere() {
        let defaults = UserDefaults(suiteName: "BoardSizingTests.\(UUID().uuidString)")!
        let pages = WidgetPages(home: WidgetStore(defaults: defaults), defaults: defaults)
        let entry = pages.snapshot()
        pages.follow(BoardGrid(columns: 6, rows: 1, gap: 8))
        #expect(!pages.home.board.parked.isEmpty)
        pages.follow(.standard)
        #expect(pages.snapshot() != entry)
        pages.restore(entry, grid: .standard)
        #expect(pages.snapshot() == entry && pages.home.board == .standard)
        #expect(pages.home.undoStack.isEmpty)
    }
}
