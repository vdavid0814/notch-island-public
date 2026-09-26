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
/// Following the music, each bar breathes through its own band's range at the music's pace, taken
/// afresh from the last three seconds of the tap's analyses (`Follower`): Core Animation hears from
/// the app only when that changes, every few seconds, and interpolates the rest itself.
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
            follower.onBattery = frameRate == Self.batteryFrameRate
            guard frameRate != oldValue, isAnimating else { return }
            applyAnimationState()
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
            applyAnimationState()
            applyColors()
            updateListening()
        }
    }

    /// The lowest a bar sinks while following the music (a fraction of the height): silence in a
    /// band still leaves a dot, as the breathing bars' lows do.
    nonisolated static let restingScale: CGFloat = 0.1

    /// Holding the tap and following: animating, listening and on screen.
    private var isListening = false
    /// Turns the tap's analyses into breathings.
    private let follower = Follower()
    /// The breathing each bar has now: the resting one, or one taken from the music.
    private var specs: [Bar] = EqualizerBarsView.bars
    /// When each bar's breathing had phase 0 (media time): where it is in its cycle now.
    private var starts: [CFTimeInterval] = []

    override init(frame: CGRect) {
        barLayers = Self.bars.map { _ in CALayer() }
        super.init(frame: frame)
        follower.view = self
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
        if wanted, !isListening {
            isListening = true
            AudioSpectrumTap.shared.acquire()
            follower.start()
            AudioSpectrumTap.addSink(follower)
        } else if !wanted, isListening {
            isListening = false
            // Stopped before it is removed: an analysis already under way sets nothing more.
            follower.stop()
            AudioSpectrumTap.removeSink(follower)
            AudioSpectrumTap.shared.release()
            specs = Self.bars
            applyAnimationState()
        }
    }

    /// The follower lost the sound for a second: the default breathing comes back.
    fileprivate func followingChanged(_ following: Bool) {
        guard isListening, !following else { return }
        specs = Self.bars
        applyAnimationState()
    }

    /// The music's character over the last seconds: each bar breathes through its band's range
    /// at a pace that follows how lively it is. Each bar carries on from where it is, in the
    /// direction it is going: the new breathing starts at the phase that has it there (restarting
    /// every bar from its low each time read as a stutter every couple of seconds).
    fileprivate func adapt(to new: [Bar]) {
        guard isListening, isAnimating, new.count == barLayers.count, starts.count == barLayers.count else { return }
        let now = CACurrentMediaTime()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, bar) in barLayers.enumerated() {
            let old = specs[index], spec = new[index]
            let current = (bar.presentation()?.value(forKeyPath: "transform.scale.y") as? CGFloat) ?? old.low
            // Rising or falling now, in the running breathing.
            let cycle = ((now - starts[index]) / old.period).truncatingRemainder(dividingBy: 2)
            let rising = cycle >= 0 && cycle < 1
            // Where `current` lies in the new range, through the inverse of the ease-in-ease-out
            // curve (a smoothstep: u = ½ − sin(asin(1 − 2f) / 3)).
            let fraction = Double(min(max((current - spec.low) / max(spec.high - spec.low, 0.01), 0), 1))
            let u = 0.5 - sin(asin(1 - 2 * fraction) / 3)
            let offset = (rising ? u : 2 - u) * spec.period
            let breathing = Self.breathing(spec, frameRate: frameRate)
            breathing.timeOffset = offset
            bar.transform = CATransform3DMakeScale(1, spec.low, 1)
            bar.add(breathing, forKey: Self.animationKey)
            starts[index] = now - offset
        }
        specs = new
        CATransaction.commit()
    }


    /// Listens to the tap's analyses on its I/O thread and turns them into a breathing for each
    /// bar, handed to the main thread only when the music's character has changed.
    ///
    /// Setting the bars from every analysis (23 a second, or one keyframe animation per I/O cycle)
    /// kept the app at Energy Impact 0.6–1.0 while music played: most of it Core Animation's
    /// commits, the analysis itself ~0.05 % CPU (measured). The breathing is interpolated by the
    /// render server, so the app sends Core Animation something only every few seconds.
    fileprivate final class Follower: SpectrumSink, @unchecked Sendable {
        /// Main thread only.
        weak var view: EqualizerBarsView?
        private let lock = NSLock()
        private var isActive = false
        private var following = false
        private var battery = false
        /// This window's sums per band: level and level squared, and how many.
        private var sum: [Double] = []
        private var squares: [Double] = []
        private var count = 0
        private var windowTime: CFTimeInterval = 0
        /// The breathing last handed over.
        private var applied: [EqualizerBarsView.Bar] = EqualizerBarsView.bars

        /// Seconds of music each breathing is taken from.
        static let window: CFTimeInterval = 3

        var isFollowing: Bool { lock.withLock { isActive && following } }

        var onBattery: Bool {
            get { lock.withLock { battery } }
            set { lock.withLock { battery = newValue } }
        }

        func start() {
            lock.withLock {
                isActive = true
                following = false
                reset()
                applied = EqualizerBarsView.bars
            }
        }

        func stop() {
            lock.withLock { isActive = false }
        }

        private func reset() {
            sum = Array(repeating: 0, count: EqualizerBarsView.bars.count)
            squares = sum
            count = 0
            windowTime = 0
        }

        func spectrumDidUpdate(_ batch: [SpectrumLevels], interval: CFTimeInterval) {
            guard let newest = batch.last else { return }
            let signal = newest.hasSignal()
            var handOver: (following: Bool, specs: [EqualizerBarsView.Bar]?)?
            lock.lock()
            defer {
                lock.unlock()
                if let handOver {
                    DispatchQueue.main.async { [weak self] in
                        guard let view = self?.view else { return }
                        if let specs = handOver.specs { view.adapt(to: specs) } else { view.followingChanged(handOver.following) }
                    }
                }
            }
            guard isActive else { return }
            if signal != following {
                following = signal
                reset()
                if !signal {
                    applied = EqualizerBarsView.bars
                    handOver = (false, nil)
                }
            }
            guard signal else { return }
            for levels in batch {
                for band in 0..<min(sum.count, levels.bands.count) {
                    let value = Double(levels.bands[band])
                    sum[band] += value
                    squares[band] += value * value
                }
                count += 1
            }
            windowTime += interval * Double(batch.count)
            guard windowTime >= Self.window, count > 0 else { return }
            let specs = Self.breathing(sum: sum, squares: squares, count: count, battery: battery)
            reset()
            if Self.differs(specs, applied) {
                applied = specs
                handOver = (true, specs)
            }
        }

        /// Each bar through its band's range over the window (its mean, give or take its spread),
        /// faster the more the music moves. The default breathing's phases keep the bars apart.
        static func breathing(sum: [Double], squares: [Double], count: Int, battery: Bool) -> [EqualizerBarsView.Bar] {
            let n = Double(count)
            let means = sum.map { $0 / n }
            let spreads = zip(squares, means).map { sqrt(max($0 / n - $1 * $1, 0)) }
            let liveliness = spreads.reduce(0, +) / Double(max(spreads.count, 1))
            return EqualizerBarsView.bars.enumerated().map { index, base in
                let rest = Double(EqualizerBarsView.restingScale)
                let mean = index < means.count ? rest + (1 - rest) * means[index] : Double(base.low)
                let spread = index < spreads.count ? (1 - rest) * spreads[index] : 0
                var low = mean - 1.3 * spread - 0.06
                var high = mean + 1.3 * spread + 0.12
                if high - low < 0.25 {
                    let middle = (high + low) / 2
                    low = middle - 0.125
                    high = middle + 0.125
                }
                low = min(max(low, rest), 0.85)
                high = min(max(high, low + 0.15), 1)
                // 0 (a held note) … ~0.3 (drums): a third slower … two fifths faster than resting.
                let pace = min(max(1.3 - 2.3 * liveliness, 0.6), 1.3)
                return EqualizerBarsView.Bar(low: CGFloat(low), high: CGFloat(high),
                                             period: base.period * pace * (battery ? 1.2 : 1), phase: base.phase)
            }
        }

        /// Worth an update: a bar's range moved by more than a few percent of its height, or its
        /// pace by more than a fifth.
        static func differs(_ a: [EqualizerBarsView.Bar], _ b: [EqualizerBarsView.Bar]) -> Bool {
            guard a.count == b.count else { return true }
            return zip(a, b).contains { x, y in
                abs(x.low - y.low) > 0.09 || abs(x.high - y.high) > 0.09 || abs(x.period - y.period) / y.period > 0.2
            }
        }
    }

    private func applyAnimationState() {
        let now = CACurrentMediaTime()
        starts = specs.map { now - $0.period * $0.phase }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (bar, spec) in zip(barLayers, specs) {
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
