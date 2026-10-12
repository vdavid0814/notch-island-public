import AppKit
import SwiftUI

/// The widget studio's stage as layers the render server moves: its desktop and island (`body`),
/// its rounded outline, and the bar at its foot (`bar`), each in a view graph of its own.
///
/// Into Size mode the stage unfolds down to the window's foot and folds back out of it. Drawn by
/// SwiftUI at every height of the spring, the stage — its desktop, clip, outline and bar — was laid
/// out and drawn again at every frame on the main thread (30–100 ms a frame, 2–3 J a switch,
/// measured). Here its place takes the new height at once; the desktop is laid out once at the
/// taller of the two heights, and the render server moves the clip and the outline (one path, the
/// same spring) and slides the bar to the new foot (`sublayerTransform`). The app draws nothing
/// while it moves; the desktop is laid out at the new height once a fold is over.
///
/// A change of height outside a mode switch (a row added while sizing) is the frame SwiftUI
/// animates: the layers then follow the view's bounds as they are laid out.
struct StageSurface<Body: View, Bar: View>: NSViewRepresentable {
    /// The mode the stage edits: a change of height within `unfoldWindow` of a change of mode
    /// unfolds or folds on the render server.
    let mode: WidgetStudio.Mode
    let topRadius: CGFloat
    let bottomRadius: CGFloat
    let spring: Spring
    /// What the nested graphs take from around them. Never the whole environment (`\.self`): it
    /// carries the page's focus system, and a nested graph walking it went round for ever (a new
    /// page's Edit button in the bar hung the app, Oct 12 2026).
    let model: AppModel
    @ViewBuilder let body: Body
    @ViewBuilder let bar: Bar

    /// How long after a change of mode a change of height is the mode's: the room Size mode gives
    /// the stage is measured a moment later.
    static var unfoldWindow: TimeInterval { 0.8 }

    func makeNSView(context: Context) -> StageSurfaceView {
        let view = StageSurfaceView(body: rooted(body), bar: rooted(bar))
        view.mode = mode
        return view
    }

    func updateNSView(_ view: StageSurfaceView, context: Context) {
        view.bodyHost.rootView = rooted(body)
        view.barHost.rootView = rooted(bar)
        view.spring = spring
        view.radii = (topRadius, bottomRadius)
        if view.mode != mode {
            view.mode = mode
            view.unfoldsUntil = ProcessInfo.processInfo.systemUptime + Self.unfoldWindow
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: StageSurfaceView, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions()
    }

    private func rooted(_ content: some View) -> AnyView {
        AnyView(content
            .environment(model)
            .environment(\.colorScheme, .dark)
            .environment(\.appearsActive, true))
    }
}

final class StageSurfaceView: NSView {
    let bodyHost: NSHostingView<AnyView>
    let barHost: NSHostingView<AnyView>
    var mode: WidgetStudio.Mode?
    var unfoldsUntil: TimeInterval = 0
    var spring = Spring(duration: 0.55, bounce: 0.12)
    var radii: (top: CGFloat, bottom: CGFloat) = (18, 26) {
        didSet { if radii != oldValue { needsLayout = true } }
    }

    private let clip = CAShapeLayer()
    private let outline = CAShapeLayer()
    /// The height last laid out, and the one the desktop keeps until a fold is over.
    private var shownHeight: CGFloat?
    private var heldHeight: CGFloat?
    private var settling: DispatchWorkItem?
    private static let key = "stageUnfold"

    init(body: AnyView, bar: AnyView) {
        bodyHost = NSHostingView(rootView: body)
        barHost = NSHostingView(rootView: bar)
        bodyHost.sizingOptions = []
        // The bar's height is its content's own (laid out at the stage's foot).
        barHost.sizingOptions = [.intrinsicContentSize]
        for host in [bodyHost, barHost] { host.safeAreaRegions = [] }
        super.init(frame: .zero)
        wantsLayer = true
        addSubview(bodyHost)
        addSubview(barHost)
        bodyHost.wantsLayer = true
        bodyHost.layer?.mask = clip
        clip.fillColor = NSColor.black.cgColor
        outline.fillColor = nil
        outline.strokeColor = NSColor.white.withAlphaComponent(0.1).cgColor
        outline.lineWidth = 1
        outline.zPosition = 10
        layer?.addSublayer(outline)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let width = bounds.width, height = bounds.height
        guard width > 0, height > 0 else { return }
        let old = shownHeight
        shownHeight = height
        let unfolds = old.map { $0 != height } == true
            && ProcessInfo.processInfo.systemUptime < unfoldsUntil
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            && window != nil && !isHiddenOrHasHiddenAncestor
        let barHeight = barHost.intrinsicContentSize.height.rounded(.up)
        // The desktop as tall as the taller height while a fold runs (drawn over the shorter place,
        // clipped by the path), as tall as the stage otherwise.
        let drawnFrom = unfolds ? (presentedHeight ?? old ?? height) : height
        if unfolds, drawnFrom > height { heldHeight = max(heldHeight ?? 0, drawnFrom) }
        if !unfolds, settling == nil { heldHeight = nil }
        let bodyHeight = max(height, heldHeight ?? 0)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bodyHost.frame = CGRect(x: 0, y: 0, width: width, height: bodyHeight)
        barHost.frame = CGRect(x: 0, y: height - barHeight, width: width, height: barHeight)
        clip.frame = bodyHost.layer?.bounds ?? bodyHost.bounds
        outline.frame = layer?.bounds ?? bounds
        let to = path(height: height, in: clip)
        let outlineTo = path(height: height, in: outline, inset: 0.5)
        if unfolds {
            animate(clip, from: path(height: drawnFrom, in: clip), to: to)
            animate(outline, from: path(height: drawnFrom, in: outline, inset: 0.5), to: outlineTo)
            slideBar(by: drawnFrom - height)
            scheduleSettle()
        } else if settling == nil {
            clip.removeAnimation(forKey: Self.key)
            outline.removeAnimation(forKey: Self.key)
        }
        clip.path = to
        outline.path = outlineTo
        CATransaction.commit()
    }

    /// The stage's height as the render server now draws it, mid-fold.
    private var presentedHeight: CGFloat? {
        guard let presented = clip.presentation()?.path, clip.animation(forKey: Self.key) != nil else { return nil }
        return presented.boundingBoxOfPath.height
    }

    /// The stage's outline `height` tall, hanging from the top of `layer`.
    private func path(height: CGFloat, in layer: CALayer, inset: CGFloat = 0) -> CGPath {
        let width = bounds.width
        let rect = CGRect(x: inset, y: inset, width: width - 2 * inset, height: max(0, height - 2 * inset))
        let shape = UnevenRoundedRectangle(topLeadingRadius: radii.top, bottomLeadingRadius: radii.bottom,
                                           bottomTrailingRadius: radii.bottom, topTrailingRadius: radii.top, style: .continuous)
        let path = shape.path(in: rect).cgPath
        // Down the screen is down the layer when its geometry is flipped, up otherwise.
        guard !(layer.isGeometryFlipped || layer.contentsAreFlipped()) else { return path }
        var flip = CGAffineTransform(translationX: 0, y: layer.bounds.height).scaledBy(x: 1, y: -1)
        return path.copy(using: &flip) ?? path
    }

    private func animate(_ layer: CAShapeLayer, from: CGPath, to: CGPath) {
        let animation = springAnimation(keyPath: "path")
        animation.fromValue = layer.presentation()?.path.flatMap { layer.animation(forKey: Self.key) != nil ? $0 : nil } ?? from
        animation.toValue = to
        layer.add(animation, forKey: Self.key)
    }

    /// The bar drawn `distance` lower than its place, then gliding up into it (higher, if negative).
    private func slideBar(by distance: CGFloat) {
        guard let layer = barHost.layer else { return }
        let flipped = layer.superlayer.map { $0.isGeometryFlipped || $0.contentsAreFlipped() } ?? true
        let from = layer.presentation()?.transform ?? CATransform3DIdentity
        let start = layer.animation(forKey: Self.key) != nil ? from : CATransform3DMakeTranslation(0, flipped ? distance : -distance, 0)
        let animation = springAnimation(keyPath: "transform")
        animation.fromValue = NSValue(caTransform3D: start)
        animation.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        layer.transform = CATransform3DIdentity
        layer.add(animation, forKey: Self.key)
    }

    private func springAnimation(keyPath: String) -> CASpringAnimation {
        let animation = CASpringAnimation(keyPath: keyPath)
        animation.mass = spring.mass
        animation.stiffness = spring.stiffness
        animation.damping = spring.damping
        animation.duration = animation.settlingDuration
        return animation
    }

    /// Once the fold is over, the desktop as tall as the stage again (one layout, unseen).
    private func scheduleSettle() {
        settling?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.settling = nil
            self.heldHeight = nil
            self.needsLayout = true
        }
        settling = work
        DispatchQueue.main.asyncAfter(deadline: .now() + spring.settlingDuration, execute: work)
    }
}
