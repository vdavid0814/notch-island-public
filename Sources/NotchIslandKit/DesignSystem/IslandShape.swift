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
