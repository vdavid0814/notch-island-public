import AppKit
import SwiftUI

/// SwiftUI content in a view graph of its own that slides in and out on the render server.
///
/// Slid by SwiftUI (`offset`, also as a `visualEffect`), the Liquid Glass controls in Customize's
/// panels — switches, sliders, segmented controls, glass buttons — were drawn again on the CPU in
/// every frame of the slide (SwiftUI's renderer draws them on the CPU here, `RB_DISABLE_GPU`):
/// ~0.65 J of a Customize opening and closing (measured). Here the content stays where it is in its
/// own window coordinates and the container's layer shifts it (`sublayerTransform`) along the same
/// spring (`Spring`'s mass, stiffness and damping as a `CASpringAnimation`) or ease-in: the app draws
/// nothing while it moves. Clicks land where the content is at rest.
///
/// The nested graph gets the environment around it (`environment`), so the content looks and
/// behaves as it would inline.
struct RenderServerSlide<Content: View>: NSViewRepresentable {
    /// In place; otherwise moved by `away`.
    let isIn: Bool
    /// Where the content is while out, in points (y down, as SwiftUI's `offset`).
    let away: CGSize
    /// The way in (the way out is an ease-in of `outDuration`).
    let spring: Spring
    let outDuration: TimeInterval
    let environment: EnvironmentValues
    let content: Content

    init(isIn: Bool, away: CGSize, spring: Spring, outDuration: TimeInterval, environment: EnvironmentValues,
         @ViewBuilder content: () -> Content) {
        self.isIn = isIn
        self.away = away
        self.spring = spring
        self.outDuration = outDuration
        self.environment = environment
        self.content = content()
    }

    func makeNSView(context: Context) -> RenderServerSlideView<Content> {
        RenderServerSlideView(rootView: rooted)
    }

    func updateNSView(_ view: RenderServerSlideView<Content>, context: Context) {
        view.host.rootView = rooted
        view.slide(isIn: isIn, away: away, animated: context.transaction.animation != nil && !context.transaction.disablesAnimations,
                   spring: spring, outDuration: outDuration)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: RenderServerSlideView<Content>, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions()
    }

    private var rooted: AnyView {
        AnyView(content.environment(\.self, environment))
    }
}

final class RenderServerSlideView<Content: View>: NSView {
    let host: NSHostingView<AnyView>
    private var shownIn: Bool?
    private static var slideKey: String { "renderServerSlide" }

    init(rootView: AnyView) {
        host = NSHostingView(rootView: rootView)
        host.sizingOptions = []
        host.safeAreaRegions = []
        super.init(frame: .zero)
        wantsLayer = true
        host.frame = bounds
        host.autoresizingMask = [.width, .height]
        addSubview(host)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    func slide(isIn: Bool, away: CGSize, animated: Bool, spring: Spring, outDuration: TimeInterval) {
        guard let layer, isIn != shownIn else { return }
        let first = shownIn == nil
        shownIn = isIn
        // Points down the screen are down the layer when its geometry is flipped, up otherwise.
        let flipped = layer.isGeometryFlipped || layer.contentsAreFlipped()
        let target = isIn ? CATransform3DIdentity
            : CATransform3DMakeTranslation(away.width, flipped ? away.height : -away.height, 0)
        let from = layer.presentation()?.sublayerTransform ?? layer.sublayerTransform
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.removeAnimation(forKey: Self.slideKey)
        layer.sublayerTransform = target
        if animated, !first {
            let animation: CABasicAnimation
            if isIn {
                let springy = CASpringAnimation(keyPath: "sublayerTransform")
                springy.mass = spring.mass
                springy.stiffness = spring.stiffness
                springy.damping = spring.damping
                springy.duration = springy.settlingDuration
                animation = springy
            } else {
                animation = CABasicAnimation(keyPath: "sublayerTransform")
                animation.duration = outDuration
                animation.timingFunction = CAMediaTimingFunction(name: .easeIn)
            }
            animation.fromValue = NSValue(caTransform3D: from)
            animation.toValue = NSValue(caTransform3D: target)
            layer.add(animation, forKey: Self.slideKey)
        }
        CATransaction.commit()
    }
}
