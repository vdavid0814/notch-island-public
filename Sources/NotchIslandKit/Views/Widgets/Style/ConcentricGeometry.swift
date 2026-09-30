import SwiftUI

/// Native corners: each widget's own, and those of what sits in its corners, concentric with it.
nonisolated enum ConcentricGeometry {
    /// An inner corner is never squarer than this.
    static let minimumInnerRadius: CGFloat = 4
    /// How near an element's edge must be to the widget's edge or its padding line to count as touching.
    static let touchTolerance: CGFloat = 0.5

    /// The radius of the board's bottom corners: the panel's, less the page's inset, so a widget
    /// in a bottom corner of the panel is concentric with it.
    static func boardCornerRadius(_ layout: IslandLayout) -> CGFloat {
        layout.bottomRadius(for: .expanded(.home)) - Metrics.Expanded.pageBottomInset
    }

    /// A widget's corners at `rect` on the board: 16, the board's corner radius where it sits in a
    /// bottom corner of the board, a circle when it is one cell; all four `custom` (the style's
    /// radius) when it has one and is not a circle. Never more than half a side.
    static func outer(for rect: GridRect, grid: BoardGrid, size: CGSize, boardCorner: CGFloat,
                      custom: CGFloat? = nil) -> RectangleCornerRadii {
        let half = min(size.width, size.height) / 2
        if rect.width == 1, rect.height == 1 {
            return RectangleCornerRadii(topLeading: half, bottomLeading: half, bottomTrailing: half, topTrailing: half)
        }
        if let custom { return .uniform(min(custom, half)) }
        let standard = min(WidgetMetrics.cornerRadius, half)
        let bottom = rect.maxRow == grid.rows
        let corner = min(max(boardCorner, 0), half)
        return RectangleCornerRadii(topLeading: standard,
                                    bottomLeading: bottom && rect.column == 0 ? corner : standard,
                                    bottomTrailing: bottom && rect.maxColumn == grid.columns ? corner : standard,
                                    topTrailing: standard)
    }

    /// A corner `inset` inside one of radius `outer`.
    static func inner(_ outer: CGFloat, inset: CGFloat) -> CGFloat { max(outer - inset, minimumInnerRadius) }

    static func inner(_ outer: RectangleCornerRadii, inset: CGFloat) -> RectangleCornerRadii {
        RectangleCornerRadii(topLeading: inner(outer.topLeading, inset: inset), bottomLeading: inner(outer.bottomLeading, inset: inset),
                             bottomTrailing: inner(outer.bottomTrailing, inset: inset), topTrailing: inner(outer.topTrailing, inset: inset))
    }

    /// The corners of an element at `element` in a widget of `size`: where it reaches a widget
    /// corner — its two edges on the widget's edges, or on the padding line — concentric with that
    /// corner; elsewhere `otherwise`. Never more than half the element's shorter side.
    static func corners(element: CGRect, in size: CGSize, outer: RectangleCornerRadii, padding: CGFloat,
                        otherwise: CGFloat) -> RectangleCornerRadii {
        func radius(_ outer: CGFloat, _ horizontal: CGFloat, _ vertical: CGFloat) -> CGFloat {
            guard let x = inset(horizontal, padding), let y = inset(vertical, padding) else { return otherwise }
            let inset = max(x, y)
            return inset == 0 ? outer : inner(outer, inset: inset)
        }
        let radii = RectangleCornerRadii(
            topLeading: radius(outer.topLeading, element.minX, element.minY),
            bottomLeading: radius(outer.bottomLeading, element.minX, size.height - element.maxY),
            bottomTrailing: radius(outer.bottomTrailing, size.width - element.maxX, size.height - element.maxY),
            topTrailing: radius(outer.topTrailing, size.width - element.maxX, element.minY)
        )
        let half = max(min(element.width, element.height) / 2, 0)
        return RectangleCornerRadii(topLeading: min(radii.topLeading, half), bottomLeading: min(radii.bottomLeading, half),
                                    bottomTrailing: min(radii.bottomTrailing, half), topTrailing: min(radii.topTrailing, half))
    }

    /// An element's shape for its corners (continuous, like every corner on the island).
    static func shape(_ radii: RectangleCornerRadii) -> UnevenRoundedRectangle {
        UnevenRoundedRectangle(cornerRadii: radii, style: .continuous)
    }

    /// 0 on the widget's edge, `padding` on the padding line, nil anywhere else.
    private static func inset(_ distance: CGFloat, _ padding: CGFloat) -> CGFloat? {
        if abs(distance) <= touchTolerance { return 0 }
        if abs(distance - padding) <= touchTolerance { return padding }
        return nil
    }
}
