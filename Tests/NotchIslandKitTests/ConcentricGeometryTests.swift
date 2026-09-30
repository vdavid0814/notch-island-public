import SwiftUI
import Testing
@testable import NotchIslandKit

/// Widget corners: 16, concentric with the panel in its bottom corners, round at one cell; and
/// what sits in a widget's corner concentric with it.
@Suite struct ConcentricGeometryTests {
    private let grid = BoardGrid.standard
    private let size = CGSize(width: 138, height: 92)

    private func radii(_ all: CGFloat) -> RectangleCornerRadii {
        RectangleCornerRadii(topLeading: all, bottomLeading: all, bottomTrailing: all, topTrailing: all)
    }

    @Test func theBoardCornerIsThePanelsLessTheInset() {
        let layout = IslandLayout(notch: CGSize(width: 185, height: 32), scale: .standard)
        #expect(ConcentricGeometry.boardCornerRadius(layout) == layout.bottomRadius(for: .expanded(.home)) - 8)
    }

    @Test func widgetsAreSixteenAndConcentricInTheBoardsBottomCorners() {
        #expect(ConcentricGeometry.outer(for: GridRect(column: 3, row: 0, width: 3, height: 2), grid: grid, size: size, boardCorner: 22) == radii(16))
        let bottomLeading = ConcentricGeometry.outer(for: GridRect(column: 0, row: 1, width: 3, height: 2), grid: grid, size: size, boardCorner: 22)
        #expect(bottomLeading == RectangleCornerRadii(topLeading: 16, bottomLeading: 22, bottomTrailing: 16, topTrailing: 16))
        let fullWidth = ConcentricGeometry.outer(for: GridRect(column: 0, row: 2, width: 12, height: 1), grid: grid,
                                                 size: CGSize(width: 600, height: 42), boardCorner: 22)
        #expect(fullWidth == RectangleCornerRadii(topLeading: 16, bottomLeading: 21, bottomTrailing: 21, topTrailing: 16))
        // On the left edge but not the bottom row: a plain corner.
        #expect(ConcentricGeometry.outer(for: GridRect(column: 0, row: 0, width: 3, height: 2), grid: grid, size: size, boardCorner: 22) == radii(16))
    }

    @Test func oneCellIsACircle() {
        let round = ConcentricGeometry.outer(for: GridRect(column: 0, row: 2, width: 1, height: 1), grid: grid,
                                             size: CGSize(width: 42, height: 40), boardCorner: 22)
        #expect(round == radii(20))
    }

    @Test func innerCornersAreTheOuterLessTheInsetAtLeastFour() {
        #expect(ConcentricGeometry.inner(16, inset: 6) == 10)
        #expect(ConcentricGeometry.inner(16, inset: 14) == 4)
        #expect(ConcentricGeometry.inner(RectangleCornerRadii(topLeading: 16, bottomLeading: 22, bottomTrailing: 16, topTrailing: 16), inset: 6)
            == RectangleCornerRadii(topLeading: 10, bottomLeading: 16, bottomTrailing: 10, topTrailing: 10))
    }

    @Test func elementsInACornerFollowIt() {
        let widget = CGSize(width: 200, height: 100)
        let outer = RectangleCornerRadii(topLeading: 16, bottomLeading: 22, bottomTrailing: 16, topTrailing: 16)
        // A cover bleeding down the leading edge: the widget's own corners there.
        let bleeding = ConcentricGeometry.corners(element: CGRect(x: 0, y: 0, width: 90, height: 100), in: widget, outer: outer,
                                                  padding: 6, otherwise: 3)
        #expect(bleeding == RectangleCornerRadii(topLeading: 16, bottomLeading: 22, bottomTrailing: 3, topTrailing: 3))
        // On the padding line (within half a point): concentric, the padding less.
        let padded = ConcentricGeometry.corners(element: CGRect(x: 6.4, y: 6, width: 80, height: 88), in: widget, outer: outer,
                                                padding: 6, otherwise: 3)
        #expect(padded == RectangleCornerRadii(topLeading: 10, bottomLeading: 16, bottomTrailing: 3, topTrailing: 3))
        // On the edge one way and the padding line the other: the larger inset.
        let mixed = ConcentricGeometry.corners(element: CGRect(x: 150, y: 6, width: 50, height: 94), in: widget, outer: outer,
                                               padding: 6, otherwise: 3)
        #expect(mixed == RectangleCornerRadii(topLeading: 3, bottomLeading: 3, bottomTrailing: 16, topTrailing: 10))
        // Never more than half its shorter side.
        let small = ConcentricGeometry.corners(element: CGRect(x: 0, y: 0, width: 12, height: 12), in: widget, outer: outer,
                                               padding: 6, otherwise: 3)
        #expect(small.topLeading == 6)
    }
}
