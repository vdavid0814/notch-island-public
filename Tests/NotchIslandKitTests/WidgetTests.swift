import CoreGraphics
import Foundation
import Testing
@testable import NotchIslandKit

@Suite struct WidgetBoardTests {
    @Test func standardBoardIsValidAndFull() {
        let board = WidgetBoard.standard
        #expect(board.widgets.map(\.kind) == [.nowPlaying, .timer, .shelf])
        for widget in board.widgets {
            #expect(board.isFree(widget.frame, for: widget.kind))
        }
        let cells = board.widgets.reduce(0) { $0 + $1.frame.width * $1.frame.height }
        #expect(cells == WidgetBoard.columns * WidgetBoard.rows)
        #expect(board.freeSlot(for: .battery) == nil)
    }

    @Test func overlappingAndOutOfBoundsFramesAreRefused() {
        var board = WidgetBoard.standard
        let result1 = board.setFrame(GridRect(column: 6, row: 0, width: 5, height: 2), for: .timer)
        #expect(!result1)
        let result2 = board.setFrame(GridRect(column: 8, row: 0, width: 5, height: 2), for: .timer)
        #expect(!result2)
        // Below the minimum size.
        let result3 = board.setFrame(GridRect(column: 7, row: 0, width: 2, height: 1), for: .timer)
        #expect(!result3)
        #expect(board.widget(.timer)?.frame == GridRect(column: 7, row: 0, width: 5, height: 2))
    }

    @Test func addFindsRoomAndShrinksToFit() {
        var board = WidgetBoard.standard
        board.remove(.shelf)
        // The default 3 × 1 fits where the shelf was.
        let result4 = board.add(.battery)
        #expect(result4)
        #expect(board.widget(.battery)?.frame == GridRect(column: 7, row: 2, width: 3, height: 1))
        // Two cells left: too small for the shelf's 3 × 1 minimum.
        let result5 = board.add(.shelf)
        #expect(!result5)
        let result6 = board.add(.battery)
        #expect(!result6)  // one of each kind
    }

    @Test func optionsAreLimitedToTheKind() {
        var board = WidgetBoard.standard
        board.setOption(.percentage, true, for: .timer)
        #expect(board.widget(.timer)?.shows(.percentage) == false)
        board.setOption(.addMinute, true, for: .timer)
        #expect(board.widget(.timer)?.shows(.addMinute) == true)
        board.setOption(.ruler, false, for: .timer)
        #expect(board.widget(.timer)?.shows(.ruler) == false)
    }

    @Test func roundTripsAndDropsInvalidEntries() throws {
        var board = WidgetBoard.standard
        board.setOption(.skipButtons, false, for: .nowPlaying)
        let data = try JSONEncoder().encode(board)
        #expect(try JSONDecoder().decode(WidgetBoard.self, from: data) == board)

        let broken = """
        {"widgets":[
          {"kind":"timer","frame":{"column":0,"row":0,"width":5,"height":2},"options":["ruler","percentage"]},
          {"kind":"shelf","frame":{"column":2,"row":1,"width":5,"height":1},"options":[]},
          {"kind":"battery","frame":{"column":11,"row":0,"width":3,"height":1},"options":[]},
          {"kind":"timer","frame":{"column":6,"row":0,"width":5,"height":2},"options":[]}
        ]}
        """
        let decoded = try JSONDecoder().decode(WidgetBoard.self, from: Data(broken.utf8))
        // The shelf overlaps the timer, the battery leaves the board, the second timer is a duplicate.
        #expect(decoded.widgets.map(\.kind) == [.timer])
        #expect(decoded.widget(.timer)?.options == [.ruler])
    }

    @Test func centring() {
        #expect(GridRect(column: 4, row: 0, width: 4, height: 1).isHorizontallyCentred)
        #expect(!GridRect(column: 4, row: 0, width: 5, height: 1).isHorizontallyCentred)
        #expect(GridRect(column: 0, row: 1, width: 12, height: 1).isVerticallyCentred)
    }
}

@Suite struct WidgetBoardGeometryTests {
    // 12 columns of 40 with 8 between; 3 rows of 40 with 8 between.
    let geometry = WidgetBoardGeometry(size: CGSize(width: 12 * 40 + 11 * 8, height: 3 * 40 + 2 * 8), gap: 8)

    @Test func framesSitOnTheGrid() {
        #expect(geometry.cellWidth == 40 && geometry.cellHeight == 40)
        #expect(geometry.frame(for: GridRect(column: 1, row: 1, width: 2, height: 1))
                == CGRect(x: 48, y: 48, width: 88, height: 40))
    }

    @Test func moveSnapsToTheNearestCellAndStaysInside() {
        let size = GridSize(width: 5, height: 2)
        #expect(geometry.snappedMove(origin: CGPoint(x: 70, y: 20), size: size)
                == GridRect(column: 1, row: 0, width: 5, height: 2))
        #expect(geometry.snappedMove(origin: CGPoint(x: 1000, y: 1000), size: size)
                == GridRect(column: 7, row: 1, width: 5, height: 2))
        #expect(geometry.snappedMove(origin: CGPoint(x: -300, y: -40), size: size)
                == GridRect(column: 0, row: 0, width: 5, height: 2))
    }

    @Test func resizeSnapsEdgesAndRespectsLimits() {
        let start = GridRect(column: 4, row: 0, width: 4, height: 1)
        // Trailing edge dragged about two cells right.
        let wider = geometry.snappedResize(
            frame: CGRect(x: 192, y: 0, width: 4 * 48 - 8 + 100, height: 40),
            from: start, kind: .timer, movesLeading: false, movesTop: false)
        #expect(wider == GridRect(column: 4, row: 0, width: 6, height: 1))
        // Leading edge dragged far right: held at the timer's 4-column minimum.
        let narrow = geometry.snappedResize(
            frame: CGRect(x: 400, y: 0, width: 40, height: 40),
            from: start, kind: .timer, movesLeading: true, movesTop: false)
        #expect(narrow == GridRect(column: 4, row: 0, width: 4, height: 1))
        // Bottom edge dragged beyond the board.
        let tall = geometry.snappedResize(
            frame: CGRect(x: 192, y: 0, width: 184, height: 900),
            from: start, kind: .timer, movesLeading: false, movesTop: false)
        #expect(tall == GridRect(column: 4, row: 0, width: 4, height: 3))
    }
}
