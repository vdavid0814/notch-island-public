import AppKit
import QuartzCore
import SwiftUI

/// Five bars beside the notch while music plays, as tall and as wide as the cover opposite: bass on the left, treble on the right, the mids
/// between — driven by what is actually playing (`AudioSpectrumTap`), in the cover's colours.
///
/// Without sound to follow (the system-audio permission not granted, a quiet intro) the bars
/// breathe as before. Core Animation rather than SwiftUI: a SwiftUI `repeatForever` animation
/// re-evaluates the view graph on the main thread every frame (measured at ~5% of a core in the
/// legacy app), while a `CABasicAnimation` on a plain layer is interpolated by the render server.
/// Following the music costs one display-link tick at 20 fps (12 on battery): five floats read and
/// five transforms set, each eased to the next by the render server.
struct EqualizerView: NSViewRepresentable {
    var isAnimating: Bool
    /// On battery the bars breathe at a lower frame rate (`EqualizerBarsView.batteryFrameRate`).
    var onBattery = false
    /// The compact pill's bars by default; Settings' illustrations draw a miniature.
    var size = Metrics.Compact.equalizerSize
    var barWidth = EqualizerBarsView.barWidth
    /// The cover's colour: the bars take it (nil: plain white).
    var tint: ArtworkColor?
    /// The cover's leading colours, run across the bars left to right (wins over `tint`).
    var palette: [ArtworkColor] = []
    /// Follow the system's audio output (the compact pill); off, the bars only breathe.
    var listensToAudio = false

    func makeNSView(context: Context) -> EqualizerBarsView {
        let view = EqualizerBarsView(frame: CGRect(origin: .zero, size: size))
        view.barWidth = barWidth
        return view
    }

    func updateNSView(_ view: EqualizerBarsView, context: Context) {
        view.frameRate = onBattery ? EqualizerBarsView.batteryFrameRate : EqualizerBarsView.frameRate
        view.barWidth = barWidth
        view.tint = tint
        view.palette = palette
        view.listensToAudio = listensToAudio
        view.isAnimating = isAnimating
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: EqualizerBarsView, context: Context) -> CGSize? {
        size
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
        Bar(low: 0.36, high: 0.88, period: 0.56, phase: 0.6),
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
            displayLink?.preferredFrameRateRange = frameRate
        }
    }
    static let barWidth: CGFloat = 2.5
    var barWidth = EqualizerBarsView.barWidth {
        didSet { if barWidth != oldValue { needsLayout = true } }
    }

    private let barLayers: [CALayer]

    /// How much of the cover's colour the playing bars take: nearly all of it — the colour is
    /// already lifted to read on the dark island (`ArtworkColor.accent`), a touch of white keeps
    /// the bars luminous.
    nonisolated static let tintFraction: CGFloat = 0.9

    var tint: ArtworkColor? {
        didSet { if tint != oldValue { applyColors(animated: true) } }
    }

    var palette: [ArtworkColor] = [] {
        didSet { if palette != oldValue { applyColors(animated: true) } }
    }

    var listensToAudio = false {
        didSet { if listensToAudio != oldValue { updateListening() } }
    }

    /// Installs the animations when playback starts and removes them when it stops. Nothing else
    /// touches them — in particular not layout, so an island resize never restarts the phase.
    var isAnimating = false {
        didSet {
            guard isAnimating != oldValue else { return }
            isFollowing = false
            applyAnimationState()
            applyColors()
            updateListening()
        }
    }

    /// The lowest a bar sinks while following the music (a fraction of the height): silence in a
    /// band still leaves a dot, as the breathing bars' lows do.
    nonisolated static let restingScale: CGFloat = 0.1
    /// How many ticks a new height takes to arrive.
    nonisolated static let glide: CFTimeInterval = 1

    /// Holding the tap and ticking: animating, listening and on screen.
    private var displayLink: CADisplayLink?
    /// The bars show the music (breathing removed) rather than breathing.
    private var isFollowing = false

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
        let spacing = max(0, (bounds.width - count * barWidth) / max(count - 1, 1))
        // Without disabling actions the bars would implicitly animate ("swim") whenever the island
        // resizes around them.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, bar) in barLayers.enumerated() {
            bar.bounds = CGRect(x: 0, y: 0, width: barWidth, height: bounds.height)
            bar.position = CGPoint(
                x: CGFloat(index) * (barWidth + spacing) + barWidth / 2,
                y: bounds.midY
            )
            bar.cornerRadius = barWidth / 2
        }
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateListening()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    /// Semantic label colours, resolved for this view's appearance: CGColor has no notion of
    /// dark/light, so it is re-resolved whenever the effective appearance changes.
    private func applyColors(animated: Bool = false) {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let base = isAnimating ? NSColor.labelColor : NSColor.secondaryLabelColor
            let covers = isAnimating ? (palette.isEmpty ? tint.map { [$0] } ?? [] : palette) : []
            let colors = Self.barColors(count: barLayers.count, palette: covers).map { cover -> NSColor in
                guard let cover else { return base }
                let color = NSColor(srgbRed: cover.red, green: cover.green, blue: cover.blue, alpha: 1)
                return base.usingColorSpace(.sRGB)?.blended(withFraction: Self.tintFraction, of: color) ?? base
            }
            CATransaction.begin()
            // A new cover eases its colour in (one short render-server animation, no app work).
            if animated {
                CATransaction.setAnimationDuration(0.45)
            } else {
                CATransaction.setDisableActions(true)
            }
            for (bar, color) in zip(barLayers, colors) { bar.backgroundColor = color.cgColor }
            CATransaction.commit()
        }
    }

    /// Each bar's cover colour: the palette spread evenly across the bars, blended between its
    /// neighbours (one colour: every bar; none: nil, plain white).
    nonisolated static func barColors(count: Int, palette: [ArtworkColor]) -> [ArtworkColor?] {
        guard !palette.isEmpty else { return Array(repeating: nil, count: count) }
        return (0..<count).map { index in
            guard palette.count > 1, count > 1 else { return palette[0] }
            let position = Double(index) / Double(count - 1) * Double(palette.count - 1)
            let low = Int(position.rounded(.down)), high = min(low + 1, palette.count - 1)
            let t = position - Double(low)
            let a = palette[low], b = palette[high]
            return ArtworkColor(red: a.red + (b.red - a.red) * t,
                                green: a.green + (b.green - a.green) * t,
                                blue: a.blue + (b.blue - a.blue) * t)
        }
    }

    // MARK: Following the music

    private func updateListening() {
        let wanted = isAnimating && listensToAudio && window != nil
        if wanted, displayLink == nil {
            AudioSpectrumTap.shared.acquire()
            let link = displayLink(target: self, selector: #selector(tick))
            link.preferredFrameRateRange = frameRate
            link.add(to: .main, forMode: .common)
            displayLink = link
        } else if !wanted, let link = displayLink {
            link.invalidate()
            displayLink = nil
            AudioSpectrumTap.shared.release()
            if isFollowing {
                isFollowing = false
                applyAnimationState()
            }
        }
    }

    @objc private func tick(_ link: CADisplayLink) {
        let levels = AudioSpectrumTap.shared.levels
        guard levels.hasSignal() else {
            // Silence, or no permission: back to breathing until sound comes through.
            if isFollowing {
                isFollowing = false
                applyAnimationState()
            }
            return
        }
        CATransaction.begin()
        if !isFollowing {
            isFollowing = true
            for bar in barLayers { bar.removeAnimation(forKey: Self.animationKey) }
        }
        // Each new height eases in over one tick, from wherever the bar is on screen, so the bars
        // glide at the render server's rate while the app sets them only 20 times a second. The
        // levels already move on a spring (`SpectrumLeveler`): a linear step between two of its
        // samples keeps its curve, where an ease-out would add a small stop at every tick.
        CATransaction.setAnimationDuration(max(link.targetTimestamp - link.timestamp, 1.0 / 60) * Self.glide)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .linear))
        for (bar, level) in zip(barLayers, levels.bands) {
            let scale = Self.restingScale + (1 - Self.restingScale) * CGFloat(level)
            bar.transform = CATransform3DMakeScale(1, scale, 1)
        }
        CATransaction.commit()
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
