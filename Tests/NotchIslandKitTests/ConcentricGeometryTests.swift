import SwiftUI
import Testing
@testable import NotchIslandKit

/// Widget corners: 20, concentric with the panel in its bottom corners, round at one cell.
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

    @Test func widgetsAreTwentyAndConcentricInTheBoardsBottomCorners() {
        #expect(ConcentricGeometry.outer(for: GridRect(column: 3, row: 0, width: 3, height: 2), grid: grid, size: size, boardCorner: 22) == radii(20))
        let bottomLeading = ConcentricGeometry.outer(for: GridRect(column: 0, row: 1, width: 3, height: 2), grid: grid, size: size, boardCorner: 22)
        #expect(bottomLeading == RectangleCornerRadii(topLeading: 20, bottomLeading: 22, bottomTrailing: 20, topTrailing: 20))
        let fullWidth = ConcentricGeometry.outer(for: GridRect(column: 0, row: 2, width: 12, height: 1), grid: grid,
                                                 size: CGSize(width: 600, height: 42), boardCorner: 22)
        #expect(fullWidth == RectangleCornerRadii(topLeading: 20, bottomLeading: 21, bottomTrailing: 21, topTrailing: 20))
        // On the left edge but not the bottom row: a plain corner.
        #expect(ConcentricGeometry.outer(for: GridRect(column: 0, row: 0, width: 3, height: 2), grid: grid, size: size, boardCorner: 22) == radii(20))
    }

    @Test func oneCellIsACircle() {
        let round = ConcentricGeometry.outer(for: GridRect(column: 0, row: 2, width: 1, height: 1), grid: grid,
                                             size: CGSize(width: 42, height: 40), boardCorner: 22)
        #expect(round == radii(20))
    }
}
