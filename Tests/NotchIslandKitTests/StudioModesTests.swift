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
    @Test func aParkedWidgetGoesBackWhereThereIsRoom() {
        // A board with some room left: a full one may not fit back together the way it was.
        var board = WidgetBoard.standard
        board.remove(.legacy(.volume))
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
