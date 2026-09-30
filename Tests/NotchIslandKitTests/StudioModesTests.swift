import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import NotchIslandKit

/// Settings ▸ Widgets ▸ Top Bar and Size: where a dragged item lands, what the grid may be, and the
/// panel's proportions from its dragged size.
@Suite struct HeaderDropTests {
    private let split = NotchSplit(islandWidth: 540, notchWidth: 156, shoulder: 12, outerInset: 12, clearance: 6)

    private func fit(_ items: [HeaderItem], _ side: HeaderSide, room: CGFloat? = nil) -> HeaderFit {
        HeaderFit(items: items, side: side, room: room ?? split.earWidth, size: .mini, pages: ExpandedPage.allCases) {
            HeaderFit.pickerEstimate(pages: $0, size: .mini)
        }
    }

    private func frames(_ fit: HeaderFit, _ side: HeaderSide) -> (items: [ClosedRange<CGFloat>], menu: ClosedRange<CGFloat>?) {
        HeaderDrop.frames(fit, side: side, split: split, size: .mini) { HeaderFit.pickerEstimate(pages: $0, size: .mini) }
    }

    @Test func theLeadingSideStartsAtItsEarAndTheTrailingSideEndsAtIts() {
        let leading = frames(fit([.pages, .clock], .leading), .leading)
        #expect(leading.items.first?.lowerBound == split.leadingEar.lowerBound)
        #expect(leading.items[1].lowerBound == leading.items[0].upperBound + HeaderFit.spacing)
        #expect(leading.menu == nil)
        let trailing = frames(fit([.battery, .siri, .pin, .settings], .trailing), .trailing)
        #expect(abs(trailing.items.last!.upperBound - split.trailingEar.upperBound) < 1e-9)
        for (left, right) in zip(trailing.items, trailing.items.dropFirst()) {
            #expect(abs(right.lowerBound - left.upperBound - HeaderFit.spacing) < 1e-9)
        }
    }

    /// "⋯" stands at the notch's end of its side.
    @Test func theMenuIsAtTheNotchsEnd() {
        let items: [HeaderItem] = [.clock, .toggle(.wifi), .siri, .pin, .lock, .screenshot, .settings]
        let leading = fit(items, .leading, room: 70)
        #expect(leading.hasOverflow)
        let left = frames(leading, .leading)
        #expect(left.menu!.lowerBound == left.items.last!.upperBound + HeaderFit.spacing)
        let trailing = fit(items, .trailing, room: 70)
        let right = frames(trailing, .trailing)
        #expect(right.menu!.upperBound + HeaderFit.spacing == right.items.first!.lowerBound)
        #expect(abs(right.items.last!.upperBound - split.trailingEar.upperBound) < 1e-9)
    }

    @Test func aDragLandsOnThePointersSideBeforeTheFirstItemPastIt() {
        let leading = frames(fit([.pages, .clock], .leading), .leading).items
        let trailing = frames(fit([.battery, .siri, .settings], .trailing), .trailing).items
        let all: [HeaderSide: [ClosedRange<CGFloat>]] = [.leading: leading, .trailing: trailing]
        func target(_ x: CGFloat) -> (HeaderSide, Int) {
            let result = HeaderDrop.target(x: x, split: split, frames: all)
            return (result.side, result.index)
        }
        #expect(target(0) == (.leading, 0))
        #expect(target(leading[0].upperBound + 1) == (.leading, 1))
        #expect(target(leading[1].upperBound + 1) == (.leading, 2))
        // Under the notch: the nearer side, at its notch end.
        #expect(target(split.islandWidth / 2 - 1) == (.leading, 2))
        #expect(target(split.islandWidth / 2 + 1) == (.trailing, 0))
        #expect(target(trailing[0].upperBound + 1) == (.trailing, 1))
        #expect(target(split.islandWidth) == (.trailing, 3))
        // An empty side takes it first.
        let empty = HeaderDrop.target(x: 10, split: split, frames: [.trailing: trailing])
        #expect(empty.side == .leading && empty.index == 0)
    }
}

@Suite struct StudioGridTests {
    /// This Mac's board at the standard size: 12 × 3 cells of about 34 × 37 pt.
    private let board = CGSize(width: 492, height: 127)

    @Test func cellsStayLargeEnoughForAControl() {
        let columns = StudioGrid.columns(board: board, gap: 8)
        #expect(columns.contains(12))
        #expect(columns.allSatisfy { $0 % 2 == 0 })
        #expect(columns == columns.sorted())
        for count in stride(from: 8, through: 24, by: 2) {
            let width = StudioGrid.cell(BoardGrid(columns: count, rows: 3, gap: 8), board: board).width
            #expect(columns.contains(count) == (width >= StudioGrid.minimumCell))
        }
        let rows = StudioGrid.rows(board: board, gap: 8)
        #expect(rows.contains(3) && !rows.contains(6))
        // A larger board offers more.
        let roomy = CGSize(width: 900, height: 330)
        #expect(StudioGrid.columns(board: roomy, gap: 8).count > columns.count)
        #expect(StudioGrid.rows(board: roomy, gap: 8) == Array(BoardGrid.rowRange))
    }

    @Test func aBlockedStepSaysWhy() {
        let grid = BoardGrid.standard
        #expect(StudioGrid.blocked(columns: 12, grid: grid, board: board) == nil)
        #expect(StudioGrid.blocked(columns: 14, grid: grid, board: board) == nil || StudioGrid.cell(BoardGrid(columns: 14, rows: 3, gap: 8), board: board).width < 26)
        let tooMany = StudioGrid.blocked(columns: 24, grid: grid, board: board)
        #expect(tooMany?.contains("24 columns") == true && tooMany?.contains("wider") == true)
        let tooTall = StudioGrid.blocked(rows: 6, grid: grid, board: board)
        #expect(tooTall?.contains("6 rows") == true && tooTall?.contains("taller") == true)
        // Past the range's ends.
        #expect(StudioGrid.blocked(columns: 6, grid: grid, board: board)?.contains("fewest") == true)
        #expect(StudioGrid.blocked(columns: 26, grid: grid, board: board)?.contains("most") == true)
        #expect(StudioGrid.blocked(rows: 1, grid: grid, board: board)?.contains("fewest") == true)
        #expect(StudioGrid.blocked(rows: 7, grid: grid, board: board)?.contains("most") == true)
    }

    @Test func aGridThatLeavesNoRoomNamesWhatItSetsAside() {
        let board = WidgetBoard.standard
        #expect(StudioGrid.setAside(by: board.grid, on: board).isEmpty)
        // Two rows instead of three: whatever stood in the third and finds no room is named, and
        // the board itself is not touched by asking.
        let smaller = BoardGrid(columns: 8, rows: 2, gap: 8)
        let aside = StudioGrid.setAside(by: smaller, on: board)
        var changed = board
        changed.setGrid(smaller)
        #expect(aside == changed.parked.map(\.kind.title))
        #expect(board.parked.isEmpty)
    }

    @Test func aParkedWidgetGoesBackWhereThereIsRoom() {
        var board = WidgetBoard.standard
        let before = board.widgets
        board.setGrid(BoardGrid(columns: 8, rows: 2, gap: 8))
        let parked = board.parked
        // No room while the grid is small and full.
        for widget in parked {
            let restored = board.restore(widget.id)
            #expect(restored == board.contains(widget.id))
        }
        // The grid back: every widget finds room again, its look kept.
        board.setGrid(.standard)
        for widget in board.parked { board.restore(widget.id) }
        #expect(board.parked.isEmpty)
        #expect(Set(board.widgets.map(\.id)) == Set(before.map(\.id)))
        for widget in board.widgets {
            #expect(board.isInBounds(widget.frame))
            #expect(!board.widgets.contains { $0.id != widget.id && $0.frame.intersects(widget.frame) })
        }
        // Restoring what is not parked does nothing.
        let again = board.restore(before[0].id)
        #expect(!again)
    }
}

@Suite struct PanelSizingTests {
    /// This Mac: a 156-pt notch on 1280 × 832.
    private func layout(_ scale: IslandScale, panel: PanelLayout = PanelLayout()) -> IslandLayout {
        IslandLayout(notch: CGSize(width: 156, height: 29), scale: scale, screen: CGSize(width: 1280, height: 832), panel: panel)
    }

    /// A size the panel takes gives back the proportions that made it.
    @Test func thePanelsSizeGivesBackItsProportions() {
        for scale in IslandScale.allCases {
            let base = layout(scale)
            let limit = base.maximumExpandedSize
            // Whole steps, as a drag makes them.
            let widths = (17...32).map { Double($0) * PanelSettings.step }
            let heights = stride(from: 16, through: 44, by: 4).map { Double($0) * PanelSettings.step }
            for width in widths {
                for height in heights {
                    let panel = PanelSettings(widthFactor: width, boardHeightFactor: height)
                    let size = base.replacing(panel: panel.layout).size(for: .expanded(.home))
                    let back = base.panel(forExpandedSize: size)
                    // Below the screen's limit exactly; at the limit, the smallest factor that reaches it.
                    if size.width < limit.width {
                        #expect(abs(back.widthFactor - panel.widthFactor) < 1e-9, "\(scale) width \(width)")
                    } else {
                        #expect(back.widthFactor <= panel.widthFactor + 1e-9)
                    }
                    if size.height < limit.height {
                        #expect(abs(back.boardHeightFactor - panel.boardHeightFactor) < 1e-9, "\(scale) height \(height)")
                    } else {
                        #expect(back.boardHeightFactor <= panel.boardHeightFactor + 1e-9)
                    }
                    // And it makes the same panel.
                    #expect(base.replacing(panel: back.layout).size(for: .expanded(.home)) == size)
                }
            }
        }
    }

    @Test func aDraggedSizeSnapsToStepsWithinTheRanges() {
        let base = layout(.compact)
        let tiny = base.panel(forExpandedSize: CGSize(width: 10, height: 10))
        #expect(tiny.widthFactor == PanelSettings.widthRange.lowerBound && tiny.boardHeightFactor == PanelSettings.boardHeightRange.lowerBound)
        let huge = base.panel(forExpandedSize: CGSize(width: 9000, height: 9000))
        #expect(huge.widthFactor <= PanelSettings.widthRange.upperBound && huge.boardHeightFactor <= PanelSettings.boardHeightRange.upperBound)
        let own = base.size(for: .expanded(.home))
        let nudged = base.panel(forExpandedSize: CGSize(width: own.width + 3, height: own.height + 2))
        #expect(nudged == PanelSettings())
        let wider = base.panel(forExpandedSize: CGSize(width: own.width * 1.2, height: own.height))
        #expect(abs(wider.widthFactor - 1.2) < 1e-9 && wider.boardHeightFactor == 1)
        // Whole steps.
        let steps = wider.widthFactor / PanelSettings.step
        #expect(abs(steps - steps.rounded()) < 1e-9)
    }

    /// On this Mac the standard panel is 600 pt wide before scaling and never taller than 62 % of
    /// the screen.
    @Test func thisMacsPanel() {
        let standard = layout(.standard)
        #expect(standard.size(for: .expanded(.home)).width == (600 * IslandScale.standard.factor).rounded())
        #expect(standard.maximumExpandedSize == CGSize(width: 1180, height: 515))
        let tallest = layout(.large, panel: PanelLayout(widthFactor: 1.6, boardHeightFactor: 2.2)).size(for: .expanded(.home))
        #expect(tallest.width <= 1180 && tallest.height <= 515)
    }
}
