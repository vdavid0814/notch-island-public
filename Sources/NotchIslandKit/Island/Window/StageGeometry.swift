import CoreGraphics

/// Window ("stage") frames in global AppKit coordinates.
///
/// The window is resized only at animation boundaries: grown to hold both ends
/// of a transition before it starts, shrunk to the resting frame after it has
/// settled. Animating the frame per frame would cost a window-server round trip
/// and a relayout at up to 120 Hz and leave no room for overshoot; keeping it
/// permanently large would leave a transparent sheet over the menu bar.
nonisolated enum StageGeometry {
    /// The island's visible rect on screen: centred on the notch, flush with the screen top.
    static func islandFrame(for p: IslandPresentation, layout: IslandLayout, metrics: NotchMetrics) -> CGRect {
        let size = layout.size(for: p)
        return CGRect(
            x: metrics.notchRect.midX - size.width / 2,
            y: metrics.screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    /// Frame while animating: everything the island may cover, plus `stageMargin`
    /// left, right and below. The top is always the screen edge.
    static func transitionFrame(covering islands: CGRect, metrics: NotchMetrics) -> CGRect {
        frame(around: islands, margin: IslandLayout.stageMargin, top: metrics.screenFrame.maxY)
    }

    /// Frame at rest. Idle is exactly the notch, so nothing of ours sits over a
    /// menu-bar item and no click there depends on the per-pixel alpha test.
    static func restingFrame(for p: IslandPresentation, layout: IslandLayout, metrics: NotchMetrics) -> CGRect {
        if p.isIdle { return metrics.notchRect }
        return frame(
            around: islandFrame(for: p, layout: layout, metrics: metrics),
            margin: restingMargin(for: p),
            top: metrics.screenFrame.maxY
        )
    }

    /// The panel and Settings rest on their transition frame: each is the largest island of its
    /// moves, so every move to and from it happens inside that frame, and neither the close's grow
    /// nor the open's settle resizes the window (each cost a window-server round trip and a layout
    /// of the whole island: ~5–13 ms for the panel, far more for Settings' AppKit form, measured).
    /// The extra margin is transparent and lies below the menu bar's centre, which they cover
    /// anyway. Everything smaller keeps the small margin (menu-bar items beside it).
    static func restingMargin(for p: IslandPresentation) -> CGFloat {
        p.isExpanded || p.isSettings ? IslandLayout.stageMargin : IslandLayout.restingMargin
    }

    /// Converts a global rect into the window-local coordinates of `frame`.
    static func local(_ rect: CGRect, in frame: CGRect) -> CGRect {
        rect.offsetBy(dx: -frame.minX, dy: -frame.minY)
    }

    private static func frame(around rect: CGRect, margin: CGFloat, top: CGFloat) -> CGRect {
        let bottom = rect.minY - margin
        return CGRect(x: rect.minX - margin, y: bottom, width: rect.width + 2 * margin, height: top - bottom)
    }
}
