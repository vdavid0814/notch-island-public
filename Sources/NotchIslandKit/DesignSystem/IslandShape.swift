import SwiftUI

/// The island's silhouette: one continuous outline, so the glass lenses a single edge.
///
/// Top to bottom:
/// * **Overdraw strip** (`topInset` points, full width). It lies above the window's top edge and is
///   clipped there, so the glass never shows a top edge against the bezel — a rim there reads as a
///   grey seam across the top of the screen.
/// * **Concave shoulders** where the island leaves the screen edge, curving from the full width into
///   the body the way the physical notch meets the bezel. They are what make the island read as
///   hardware rather than a floating window.
/// * **Body** with continuous-curvature bottom corners, the same curve system shapes use.
///
/// Everything stays inside `rect`: the shoulders take their width from the frame rather than
/// flaring outside it, because the window server routes clicks by pixel alpha and the hosting
/// view's hit rect is exactly the island frame.
nonisolated struct IslandShape: RoundedRectangularShape {
    var bottomRadius: CGFloat
    var shoulderRadius: CGFloat
    /// Height of the full-width strip above the visible top edge (see `IslandLayout.overdraw`).
    var topInset: CGFloat = 0
    /// How far the island is drawn pulled in from each side (`width`) and up from the bottom
    /// (`height`) while it grows out of, or shrinks back into, the notch. Top-centred on purpose: the
    /// frame stays put during that animation (a view being removed keeps its last origin, so a
    /// shrinking frame would slide towards the left), and only the drawn silhouette changes.
    /// Negative during the open's overshoot. Not animatable: it is recomputed every frame from the
    /// emergence progress.
    var retraction: CGSize = .zero
    /// Accumulated `inset(by:)`, so the shape can serve as a container shape.
    private var insetAmount: CGFloat = 0

    init(bottomRadius: CGFloat, shoulderRadius: CGFloat, topInset: CGFloat = 0, retraction: CGSize = .zero) {
        self.bottomRadius = bottomRadius
        self.shoulderRadius = shoulderRadius
        self.topInset = topInset
        self.retraction = retraction
    }

    /// Radii only: the silhouette morphs continuously between presentations instead of cross-fading.
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(bottomRadius, shoulderRadius) }
        set {
            bottomRadius = newValue.first
            shoulderRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let body = CGRect(
            x: rect.minX + retraction.width,
            y: rect.minY,
            width: max(0, rect.width - 2 * retraction.width),
            height: max(0, rect.height - retraction.height)
        )
        let geometry = IslandShapeGeometry(
            rect: body.insetBy(dx: insetAmount, dy: insetAmount),
            bottomRadius: bottomRadius - insetAmount,
            shoulderRadius: shoulderRadius,
            topInset: topInset
        )
        return geometry.path()
    }

    func inset(by amount: CGFloat) -> IslandShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }

    /// Flush top, round bottom — lets `ConcentricRectangle` inside the island follow its corners.
    func corners(in size: CGSize?) -> RoundedRectangularShapeCorners? {
        let radius = max(0, bottomRadius - insetAmount)
        return RoundedRectangularShapeCorners(
            topLeading: 0,
            topTrailing: 0,
            bottomLeading: .fixed(radius),
            bottomTrailing: .fixed(radius)
        )
    }
}

/// The island's silhouette at a given size, top-centred in whatever rect it is drawn in.
///
/// The island is drawn on a canvas (its window) whose size stays put while the island morphs, so
/// only this outline changes from frame to frame, never a frame (see `IslandRootView`). The same
/// outline as `IslandShape` in a rect of `size`.
nonisolated struct IslandOutline: InsettableShape, Equatable {
    /// The visible island, below the overdraw strip.
    var size: CGSize
    var bottomRadius: CGFloat
    var shoulderRadius: CGFloat
    /// Height of the full-width strip above the visible top edge (see `IslandLayout.overdraw`).
    var topInset: CGFloat = 0
    private var insetAmount: CGFloat = 0

    init(size: CGSize, bottomRadius: CGFloat, shoulderRadius: CGFloat, topInset: CGFloat = 0) {
        self.size = size
        self.bottomRadius = bottomRadius
        self.shoulderRadius = shoulderRadius
        self.topInset = topInset
    }

    func withTopInset(_ inset: CGFloat) -> IslandOutline {
        var copy = self
        copy.topInset = inset
        return copy
    }

    /// `t` of the way from this outline to `other` (past 1 during an open's overshoot); radii never
    /// below zero.
    func mixed(with other: IslandOutline, by t: Double) -> IslandOutline {
        let t = CGFloat(t)
        func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * t }
        return IslandOutline(
            size: CGSize(width: mix(size.width, other.size.width), height: mix(size.height, other.size.height)),
            bottomRadius: max(0, mix(bottomRadius, other.bottomRadius)),
            shoulderRadius: max(0, mix(shoulderRadius, other.shoulderRadius)),
            topInset: other.topInset
        )
    }

    /// Where the island lies in `rect`: top-centred, `topInset` taller than `size`.
    func body(in rect: CGRect) -> CGRect {
        CGRect(
            x: rect.midX - max(0, size.width) / 2,
            y: rect.minY,
            width: max(0, size.width),
            height: max(0, size.height + topInset)
        )
    }

    func geometry(in rect: CGRect) -> IslandShapeGeometry {
        IslandShapeGeometry(
            rect: body(in: rect).insetBy(dx: insetAmount, dy: insetAmount),
            bottomRadius: bottomRadius - insetAmount,
            shoulderRadius: shoulderRadius,
            topInset: topInset
        )
    }

    func path(in rect: CGRect) -> Path {
        geometry(in: rect).path()
    }

    func inset(by amount: CGFloat) -> IslandOutline {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

/// What the island's Liquid Glass is drawn in: the outline's body — below the shoulders, with its
/// continuous bottom corners — as the system's own rounded rectangle.
///
/// Liquid Glass draws a system rounded rectangle analytically, but rasterises any other path, anew
/// for every size: in the island's own outline, each frame of a morph cost the window server fresh
/// textures, ~100 MB per open (measured; 0 MB in this shape). The outline clips the island anyway
/// (`IslandSurface`), so the body is all the glass has to cover; the two small concave shoulders at
/// the top are filled with the glass's smoke instead (`IslandShoulders`).
nonisolated struct IslandGlassBody: Shape {
    let outline: IslandOutline

    func path(in rect: CGRect) -> Path {
        let geometry = outline.geometry(in: rect)
        let body = CGRect(x: geometry.bodyMinX, y: geometry.rect.minY,
                          width: max(0, geometry.bodyMaxX - geometry.bodyMinX), height: geometry.rect.height)
        return Path(
            roundedRect: body,
            cornerRadii: RectangleCornerRadii(topLeading: 0, bottomLeading: geometry.radius,
                                              bottomTrailing: geometry.radius, topTrailing: 0),
            style: .continuous
        )
    }
}

/// The parts of the outline the glass body leaves out: the concave shoulders (and the full-width
/// strip above the screen edge).
nonisolated struct IslandShoulders: Shape {
    let outline: IslandOutline

    func path(in rect: CGRect) -> Path {
        var path = outline.path(in: rect)
        path.addPath(IslandGlassBody(outline: outline).path(in: rect))
        return path
    }
}

/// The resolved (clamped) numbers behind an `IslandShape`, separate so tests can check them.
nonisolated struct IslandShapeGeometry: Sendable, Equatable {
    /// How far a continuous corner's curve reaches along each edge, as a multiple of its radius.
    /// This is the ratio of the system's continuous ("squircle") corner.
    static let continuousExtent: CGFloat = 1.528_665

    /// Handle length of the shoulder fillet as a fraction of its size. A circle is 0.552; slightly
    /// fuller keeps the curve from looking like a chamfer at notch scale.
    static let shoulderHandle: CGFloat = 0.62

    let rect: CGRect
    let top: CGFloat
    let shoulder: CGFloat
    let radius: CGFloat

    init(rect: CGRect, bottomRadius: CGFloat, shoulderRadius: CGFloat, topInset: CGFloat) {
        self.rect = rect
        let top = rect.minY + min(max(topInset, 0), rect.height)
        self.top = top
        let visibleHeight = rect.maxY - top
        let shoulder = min(max(shoulderRadius, 0), rect.width / 4, visibleHeight / 2)
        self.shoulder = shoulder
        // The continuous corner needs `continuousExtent × r` along both edges it joins.
        let horizontalRoom = (rect.width - 2 * shoulder) / 2
        let verticalRoom = visibleHeight - shoulder
        let limit = max(0, min(horizontalRoom, verticalRoom)) / Self.continuousExtent
        self.radius = min(max(bottomRadius, 0), limit)
    }

    /// Left and right edges of the body (inside the shoulders).
    var bodyMinX: CGFloat { rect.minX + shoulder }
    var bodyMaxX: CGFloat { rect.maxX - shoulder }

    func path() -> Path {
        var path = Path()
        guard rect.width > 0, rect.height > 0 else { return path }
        let k = Self.shoulderHandle
        let s = shoulder

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: top))
        if s > 0 {
            // Right shoulder: leaves the screen edge heading inward, arrives heading down.
            path.addCurve(
                to: CGPoint(x: bodyMaxX, y: top + s),
                control1: CGPoint(x: rect.maxX - k * s, y: top),
                control2: CGPoint(x: bodyMaxX, y: top + s - k * s)
            )
        }
        addContinuousCorner(
            to: &path,
            corner: CGPoint(x: bodyMaxX, y: rect.maxY),
            incoming: CGVector(dx: 0, dy: -1),
            outgoing: CGVector(dx: -1, dy: 0)
        )
        addContinuousCorner(
            to: &path,
            corner: CGPoint(x: bodyMinX, y: rect.maxY),
            incoming: CGVector(dx: 1, dy: 0),
            outgoing: CGVector(dx: 0, dy: -1)
        )
        path.addLine(to: CGPoint(x: bodyMinX, y: top + s))
        if s > 0 {
            path.addCurve(
                to: CGPoint(x: rect.minX, y: top),
                control1: CGPoint(x: bodyMinX, y: top + s - k * s),
                control2: CGPoint(x: rect.minX + k * s, y: top)
            )
        }
        path.closeSubpath()
        return path
    }

    /// Appends a continuous-curvature corner. `incoming` points from the corner back along the edge
    /// the path arrives on; `outgoing` points along the edge it leaves on. Coefficients are the
    /// system continuous corner, expressed in multiples of the radius.
    private func addContinuousCorner(
        to path: inout Path,
        corner: CGPoint,
        incoming: CGVector,
        outgoing: CGVector
    ) {
        let r = radius
        func point(_ along: CGFloat, _ across: CGFloat) -> CGPoint {
            CGPoint(
                x: corner.x + (incoming.dx * along + outgoing.dx * across) * r,
                y: corner.y + (incoming.dy * along + outgoing.dy * across) * r
            )
        }
        guard r > 0 else {
            path.addLine(to: corner)
            return
        }
        path.addLine(to: point(1.528_665, 0))
        path.addCurve(to: point(0.669_934, 0.065_496), control1: point(1.088_493, 0), control2: point(0.868_407, 0))
        path.addLine(to: point(0.631_494, 0.074_911))
        path.addCurve(to: point(0.074_911, 0.631_494), control1: point(0.372_824, 0.169_059), control2: point(0.169_060, 0.372_824))
        path.addCurve(to: point(0, 1.528_665), control1: point(0, 0.868_407), control2: point(0, 1.088_493))
    }
}
