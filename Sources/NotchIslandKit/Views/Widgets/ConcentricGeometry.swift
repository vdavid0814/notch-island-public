import SwiftUI

/// Native corners: each widget's own, concentric with the panel in its bottom corners.
nonisolated enum ConcentricGeometry {
    /// The radius of the board's bottom corners: the panel's, less the page's inset, so a widget
    /// in a bottom corner of the panel is concentric with it.
    static func boardCornerRadius(_ layout: IslandLayout) -> CGFloat {
        layout.bottomRadius(for: .expanded(.home)) - Metrics.Expanded.pageBottomInset
    }

    /// How much further in than the widget's padding (less than none: nearer the edge) a round
    /// part in one of its corners stands, from the side and from the top or bottom alike:
    /// concentric with the corner (its middle on the corner's centre), never nearer either edge than
    /// `closest` — the same from both, so it sits in the corner's curve.
    static func cornerInset(radius: CGFloat, part height: CGFloat, padding: CGFloat, closest: CGFloat = 3) -> CGFloat {
        (max(closest, radius - height / 2) - padding).rounded()
    }

    /// A widget's corners at `rect` on the board: 20, the board's corner radius where it sits in a
    /// bottom corner of the board, a circle when it is one cell. Never more than half a side.
    static func outer(for rect: GridRect, grid: BoardGrid, size: CGSize, boardCorner: CGFloat) -> RectangleCornerRadii {
        let half = min(size.width, size.height) / 2
        if rect.width == 1, rect.height == 1 { return .uniform(half) }
        let standard = min(WidgetMetrics.cornerRadius, half)
        let bottom = rect.maxRow == grid.rows
        let corner = min(max(boardCorner, 0), half)
        return RectangleCornerRadii(topLeading: standard,
                                    bottomLeading: bottom && rect.column == 0 ? corner : standard,
                                    bottomTrailing: bottom && rect.maxColumn == grid.columns ? corner : standard,
                                    topTrailing: standard)
    }
}
