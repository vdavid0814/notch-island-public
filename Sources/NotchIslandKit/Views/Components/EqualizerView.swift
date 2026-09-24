import AppKit
import QuartzCore
import SwiftUI

/// Four breathing bars beside the notch while music plays.
///
/// Core Animation rather than SwiftUI: a SwiftUI `repeatForever` animation re-evaluates the view
/// graph on the main thread every frame (measured at ~5% of a core in the legacy app), while a
/// `CABasicAnimation` on a plain layer is interpolated by the render server — a playing track costs
/// the app no CPU at all.
struct EqualizerView: NSViewRepresentable {
    var isAnimating: Bool
    /// On battery the bars breathe at a lower frame rate (`EqualizerBarsView.batteryFrameRate`).
    var onBattery = false

    func makeNSView(context: Context) -> EqualizerBarsView {
        EqualizerBarsView(frame: CGRect(origin: .zero, size: Metrics.Compact.equalizerSize))
    }

    func updateNSView(_ view: EqualizerBarsView, context: Context) {
        view.frameRate = onBattery ? EqualizerBarsView.batteryFrameRate : EqualizerBarsView.frameRate
        view.isAnimating = isAnimating
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: EqualizerBarsView, context: Context) -> CGSize? {
        Metrics.Compact.equalizerSize
    }
}

/// The layer-backed view behind `EqualizerView`.
final class EqualizerBarsView: NSView {
    /// One bar's breathing range (fractions of the view height), half-period, and starting phase
    /// (fraction of the period).
    nonisolated struct Bar: Sendable, Equatable {
        let low: CGFloat
        let high: CGFloat
        let period: CFTimeInterval
        let phase: Double
    }

    /// Unequal periods so the bars never fall into step, staggered phases so they do not start
    /// together; the lows double as the resting shape.
    nonisolated static let bars: [Bar] = [
        Bar(low: 0.30, high: 0.95, period: 0.52, phase: 0.0),
        Bar(low: 0.55, high: 0.70, period: 0.68, phase: 0.5),
        Bar(low: 0.22, high: 1.00, period: 0.44, phase: 0.25),
        Bar(low: 0.44, high: 0.80, period: 0.60, phase: 0.75),
    ]
    nonisolated static let animationKey = "breathe"
    nonisolated static let frameRate = CAFrameRateRange(minimum: 10, maximum: 24, preferred: 20)
    /// Hours of playback on battery: the breathing still reads as motion at 12.
    nonisolated static let batteryFrameRate = CAFrameRateRange(minimum: 8, maximum: 15, preferred: 12)

    /// Applied to the running animations when it changes (the power source switched).
    var frameRate = EqualizerBarsView.frameRate {
        didSet {
            guard frameRate != oldValue, isAnimating else { return }
            applyAnimationState()
        }
    }
    static let barWidth: CGFloat = 2.5

    private let barLayers: [CALayer]

    /// Installs the animations when playback starts and removes them when it stops. Nothing else
    /// touches them — in particular not layout, so an island resize never restarts the phase.
    var isAnimating = false {
        didSet {
            guard isAnimating != oldValue else { return }
            applyAnimationState()
            applyColors()
        }
    }

    override init(frame: CGRect) {
        barLayers = Self.bars.map { _ in CALayer() }
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        for bar in barLayers {
            bar.cornerCurve = .continuous
            layer?.addSublayer(bar)
        }
        applyAnimationState()
        applyColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let count = CGFloat(barLayers.count)
        let spacing = max(0, (bounds.width - count * Self.barWidth) / max(count - 1, 1))
        // Without disabling actions the bars would implicitly animate ("swim") whenever the island
        // resizes around them.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, bar) in barLayers.enumerated() {
            bar.bounds = CGRect(x: 0, y: 0, width: Self.barWidth, height: bounds.height)
            bar.position = CGPoint(
                x: CGFloat(index) * (Self.barWidth + spacing) + Self.barWidth / 2,
                y: bounds.midY
            )
            bar.cornerRadius = Self.barWidth / 2
        }
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    /// Semantic label colours, resolved for this view's appearance: CGColor has no notion of
    /// dark/light, so it is re-resolved whenever the effective appearance changes.
    private func applyColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let color = (isAnimating ? NSColor.labelColor : NSColor.secondaryLabelColor).cgColor
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for bar in barLayers { bar.backgroundColor = color }
            CATransaction.commit()
        }
    }

    private func applyAnimationState() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (bar, spec) in zip(barLayers, Self.bars) {
            bar.transform = CATransform3DMakeScale(1, spec.low, 1)
            if isAnimating {
                bar.add(Self.breathing(spec, frameRate: frameRate), forKey: Self.animationKey)
            } else {
                bar.removeAnimation(forKey: Self.animationKey)
            }
        }
        CATransaction.commit()
    }

    /// The looping scale animation for one bar. `timeOffset` starts each bar mid-breath rather than
    /// all from their lows.
    private static func breathing(_ bar: Bar, frameRate: CAFrameRateRange) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: "transform.scale.y")
        animation.fromValue = bar.low
        animation.toValue = bar.high
        animation.duration = bar.period
        animation.timeOffset = bar.period * bar.phase
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        // The bars run for as long as music plays — hours. At the display's full rate (120 Hz on
        // ProMotion) the window server would recomposite the pill 120 times a second for motion
        // that reads the same at 20; capping it is most of the island's cost while playing.
        animation.preferredFrameRateRange = frameRate
        return animation
    }

    /// Test hook: the animation currently installed on each bar.
    var installedAnimations: [CAAnimation?] {
        barLayers.map { $0.animation(forKey: Self.animationKey) }
    }
}
