import QuartzCore
import SwiftUI

/// Siri's colours: a band of flowing Apple Intelligence colour over a soft, still glow of the same
/// colours, shown while the assistant is answering.
///
/// SwiftUI draws the band as a Core Animation gradient layer, which the render server draws; the
/// flow only turns that layer's end point. So the flow is played there: a copy of SwiftUI's own
/// layer, its end point stepped through one turn in `frameCount` keyframes (the 30 fps the band was
/// drawn at as a timeline, and the same angles), and the app does nothing per frame. If the layer
/// cannot be copied, SwiftUI's own band flows as a timeline instead. The still glow under it is drawn
/// once. Under Reduce Motion or in Low Power Mode it stands still.
struct AssistantGlow: View {
    var isFlowing: Bool

    static let colors: [Color] = [
        Color(red: 0.25, green: 0.55, blue: 1.0),
        Color(red: 0.65, green: 0.35, blue: 1.0),
        Color(red: 1.0, green: 0.35, blue: 0.65),
        Color(red: 1.0, green: 0.62, blue: 0.25),
        Color(red: 0.25, green: 0.55, blue: 1.0),
    ]

    static var gradient: LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// One turn of the band (220° a second).
    static let period: TimeInterval = 360 / 220
    /// The flow's steps per turn: one per 30th of a second.
    static let frameCount = 49

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if isFlowing, !reduceMotion, !model.activity.prefersReducedWork {
            GlowFlow()
                .frame(height: 4)
                .background { Self.halo }
                .accessibilityHidden(true)
        } else {
            Self.band(phase: 0)
                .frame(height: 4)
                .background { Self.halo }
                .accessibilityHidden(true)
        }
    }

    /// The band `phase` seconds into its flow.
    static func band(phase: TimeInterval) -> some View {
        Capsule()
            .fill(AngularGradient(colors: colors, center: .center, angle: angle(phase: phase)))
    }

    private static func angle(phase: TimeInterval) -> Angle {
        .degrees((phase * 220).truncatingRemainder(dividingBy: 360))
    }

    private static var halo: some View {
        Capsule()
            .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
            .blur(radius: 8)
            .opacity(0.7)
    }

    /// Where step `index` of the flow is.
    static func phase(ofFrame index: Int) -> TimeInterval {
        period * Double(index) / Double(frameCount)
    }

    /// A copy of the layer SwiftUI draws the band `size` points large at `phase` with: every
    /// property of it, as a plain gradient layer (SwiftUI's own class and delegate stay behind).
    @MainActor static func bandLayer(size: CGSize, phase: TimeInterval = 0) -> CAGradientLayer? {
        let host = NSHostingView(rootView: band(phase: phase).frame(width: size.width, height: size.height))
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        func gradient(in layer: CALayer) -> CAGradientLayer? {
            layer as? CAGradientLayer ?? layer.sublayers?.lazy.compactMap(gradient).first
        }
        guard let drawn = host.layer.flatMap(gradient) else { return nil }
        let archiver = NSKeyedArchiver(requiringSecureCoding: false)
        archiver.setClassName(NSStringFromClass(CAGradientLayer.self), for: type(of: drawn))
        archiver.encode(drawn, forKey: NSKeyedArchiveRootObjectKey)
        archiver.finishEncoding()
        guard let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: archiver.encodedData) else { return nil }
        unarchiver.requiresSecureCoding = false
        guard let copy = unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey) as? CAGradientLayer else { return nil }
        // The archive keeps numbers at single precision (these at SwiftUI's own) and leaves out the
        // colour space the colours are mixed in.
        copy.colors = drawn.colors
        copy.locations = drawn.locations
        copy.startPoint = drawn.startPoint
        copy.endPoint = drawn.endPoint
        copy.cornerRadius = drawn.cornerRadius
        copy.setValue(drawn.value(forKey: "colorSpace"), forKey: "colorSpace")
        return copy
    }

    /// The band's end point `phase` seconds into the flow, as SwiftUI places it for the angle.
    static func endPoint(phase: TimeInterval) -> CGPoint {
        let radians = angle(phase: phase).radians
        return CGPoint(x: 0.5 + cos(radians), y: 0.5 + sin(radians))
    }

    /// One turn of the flow, a step per `frameCount`th: held at `frozen` seconds into it when
    /// given (`demo/freeze`), else in step with the clock, as the band drawn from the time of day was.
    static func flow(frozenAt frozen: TimeInterval?) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: "endPoint")
        animation.values = (0..<frameCount).map { NSValue(point: endPoint(phase: phase(ofFrame: $0))) }
        animation.keyTimes = (0...frameCount).map { NSNumber(value: Double($0) / Double(frameCount)) }
        animation.calculationMode = .discrete
        animation.duration = period
        // The render server steps it at the band's 30 fps, not the display's rate.
        animation.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 30, preferred: 30)
        animation.repeatCount = .infinity
        if let frozen {
            animation.speed = 0
            animation.timeOffset = frozen.truncatingRemainder(dividingBy: period)
        } else {
            animation.timeOffset = Date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period)
        }
        return animation
    }
}

/// The flowing band: SwiftUI's band layer, copied for the band's size when it shows and gone with
/// it, its flow played by the render server.
private struct GlowFlow: NSViewRepresentable {
    func makeNSView(context: Context) -> GlowFlowView { GlowFlowView() }
    func updateNSView(_ view: GlowFlowView, context: Context) {}
}

final class GlowFlowView: NSView {
    private let makeBand: (CGSize) -> CAGradientLayer?
    private var band: CAGradientLayer?
    /// SwiftUI's own band flowing as a timeline, as it did before: shown if its layer cannot be
    /// copied at the band's size, so there is always a band.
    private var fallback: NSView?

    init(makeBand: @escaping (CGSize) -> CAGradientLayer? = { AssistantGlow.bandLayer(size: $0) }) {
        self.makeBand = makeBand
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Top-down, as SwiftUI's own layers lie: the band turns the same way round.
    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        needsLayout = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            needsLayout = true
        } else {
            band?.removeFromSuperlayer()
            band = nil
            fallback?.removeFromSuperview()
            fallback = nil
        }
    }

    override func layout() {
        super.layout()
        guard let window, bounds.width > 0, bounds.height > 0 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if fallback == nil, band?.bounds.size != bounds.size {
            band?.removeFromSuperlayer()
            band = makeBand(bounds.size)
            if let band {
                band.add(AssistantGlow.flow(frozenAt: LeanSpring.frozenTime), forKey: "flow")
                layer?.addSublayer(band)
            } else {
                let fallback = NSHostingView(rootView: TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                    AssistantGlow.band(phase: context.date.timeIntervalSinceReferenceDate)
                })
                addSubview(fallback)
                self.fallback = fallback
            }
        }
        band?.frame = bounds
        // As SwiftUI's own layer has in a window.
        band?.contentsScale = window.backingScaleFactor
        fallback?.frame = bounds
        shapeShadow()
        CATransaction.commit()
    }

    /// SwiftUI gives this view the island's legibility shadow (`GlassLegibility`), as it gives every
    /// leaf, on a layer around it, which draws it from the pixels inside and fades them one by one.
    /// Its own band's layer draws the shadow of the band's shape (its bounds, rounded as the capsule)
    /// and fades as one: set up so, the band and its shadow are SwiftUI's to the pixel, still or
    /// fading.
    private func shapeShadow() {
        var view = superview
        while let around = view, around.bounds.size == bounds.size {
            // Only the layer with the shadow: rounded, one that clips (SwiftUI's frame of this view,
            // once shown) would round the band's ends a second time.
            if let layer = around.layer, layer.shadowOpacity > 0, !layer.masksToBounds {
                layer.cornerRadius = min(bounds.width, bounds.height) / 2
                layer.cornerCurve = .continuous
                layer.setValue(true, forKey: "shadowPathIsBounds")
                layer.allowsGroupOpacity = true
            }
            view = around.superview
        }
    }
}
