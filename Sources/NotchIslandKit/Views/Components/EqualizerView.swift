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
    /// Following the music, listen without rests (on the charger).
    var continuous = false

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
        view.continuous = continuous
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
    /// The crossfade from one breathing into the next (`adapt`).
    nonisolated static let blendKey = "blend"
    /// On the charger (or a Mac without a battery): smooth, the display's 60 frames a second.
    nonisolated static let frameRate = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
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
    /// Each bar's holder: a beat's pulse scales it (the bar inside breathes), so the two motions
    /// multiply instead of fighting over one property.
    private let pulseLayers: [CALayer]

    /// How much of the cover's colour the playing bars take: nearly all of it — the colour is
    /// already lifted to read on the dark island (`ArtworkColor.accent`), a touch of white keeps
    /// the bars luminous.
    nonisolated static let tintFraction: CGFloat = 0.9

    var tint: ArtworkColor? {
        didSet { if tint != oldValue { coverChanged() } }
    }

    var palette: [ArtworkColor] = [] {
        didSet { if palette != oldValue { coverChanged() } }
    }

    /// A new cover is a new track: its colours ease in, and a rest under way ends, so the bars take
    /// the new song's character within a window instead of after the rest.
    private func coverChanged() {
        applyColors(animated: true)
        if isListening { AudioSpectrumTap.shared.wake() }
    }

    var listensToAudio = false {
        didSet { if listensToAudio != oldValue { updateListening() } }
    }

    /// On the charger: shorter windows and rests (`Follower.chargingWindow`, `chargingRest`); a
    /// longer rest under way ends at once.
    var continuous = false {
        didSet {
            follower.charging = continuous
            if continuous, !oldValue, isListening { AudioSpectrumTap.shared.wake() }
        }
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
        pulseLayers = Self.bars.map { _ in CALayer() }
        super.init(frame: frame)
        follower.view = self
        wantsLayer = true
        layer?.masksToBounds = false
        for (bar, holder) in zip(barLayers, pulseLayers) {
            bar.cornerCurve = .continuous
            holder.addSublayer(bar)
            layer?.addSublayer(holder)
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
            let holder = pulseLayers[index]
            holder.bounds = CGRect(x: 0, y: 0, width: barWidth, height: bounds.height)
            holder.position = CGPoint(
                x: CGFloat(index) * (barWidth + spacing) + barWidth / 2,
                y: bounds.midY
            )
            bar.bounds = holder.bounds
            bar.position = CGPoint(x: holder.bounds.midX, y: holder.bounds.midY)
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

    /// The follower lost the sound for a few seconds: the default breathing comes back.
    fileprivate func followingChanged(_ following: Bool) {
        guard isListening, !following else { return }
        // Back to the resting breathing from where each bar is, and the beats eased out: no snap.
        if isAnimating, starts.count == barLayers.count {
            adapt(to: Self.bars)
            applyPulses([])
        } else {
            specs = Self.bars
            applyAnimationState()
        }
    }

    /// What the follower found in the last window of music.
    fileprivate struct Reading {
        var specs: [Bar]?
        var pulses: [Pulse?]
    }

    /// A beat for one bar: every `period` seconds from `beat` (media time), the bar's holder jumps
    /// to `peak` times its height and falls back.
    nonisolated struct Pulse: Sendable, Equatable {
        var period: CFTimeInterval
        var beat: CFTimeInterval
        var peak: CGFloat
    }

    fileprivate func apply(_ reading: Reading) {
        guard isListening, isAnimating else { return }
        if let specs = reading.specs { adapt(to: specs) }
        applyPulses(reading.pulses)
    }

    /// Schedules each bar's beat on the render server: a repeating pulse, started on the next
    /// predicted beat. Nothing runs in the app between one window of music and the next.
    private func applyPulses(_ pulses: [Pulse?]) {
        let now = CACurrentMediaTime()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, holder) in pulseLayers.enumerated() {
            // Mid-swell, the old beat is not cut off (a visible snap back to 1): it eases down first.
            let swell = (holder.presentation()?.value(forKeyPath: "transform.scale.y") as? CGFloat) ?? 1
            let settling = abs(swell - 1) > 0.01
            guard index < pulses.count, let pulse = pulses[index], pulse.period > 0.15 else {
                if settling {
                    holder.removeAnimation(forKey: Self.pulseKey)
                    holder.add(Self.settle(from: swell, rate: pulseFrameRate), forKey: Self.settleKey)
                } else {
                    holder.removeAnimation(forKey: Self.pulseKey)
                }
                continue
            }
            // The next beat far enough ahead to start on it.
            let ahead = max(0, ((now + 0.03 - pulse.beat) / pulse.period).rounded(.up))
            let first = pulse.beat + ahead * pulse.period
            let rise = min(Self.pulseRise, pulse.period * 0.25)
            let fall = min(Self.pulseFall, pulse.period * 0.65)
            let animation = CAKeyframeAnimation(keyPath: "transform.scale.y")
            animation.values = [1, pulse.peak, 1, 1]
            animation.keyTimes = [0, NSNumber(value: rise / pulse.period), NSNumber(value: (rise + fall) / pulse.period), 1]
            // A soft swell: eased up, eased back down (no edge anywhere).
            animation.timingFunctions = [CAMediaTimingFunction(name: .easeInEaseOut),
                                         CAMediaTimingFunction(name: .easeInEaseOut),
                                         CAMediaTimingFunction(name: .linear)]
            animation.duration = pulse.period
            animation.repeatCount = .infinity
            // The swell tops out just after the beat.
            animation.preferredFrameRateRange = pulseFrameRate
            let start = first - rise + 0.02
            if settling {
                // The ease down first; the new beat starts once it is over.
                let settle = Self.settle(from: swell, rate: pulseFrameRate)
                settle.beginTime = holder.convertTime(now, from: nil)
                animation.beginTime = holder.convertTime(max(start, now + settle.duration), from: nil)
                holder.add(animation, forKey: Self.pulseKey)
                holder.add(settle, forKey: Self.settleKey)
            } else {
                animation.beginTime = holder.convertTime(start, from: nil)
                holder.add(animation, forKey: Self.pulseKey)
            }
        }
        CATransaction.commit()
    }

    private var pulseFrameRate: CAFrameRateRange {
        frameRate == Self.batteryFrameRate ? Self.batteryPulseRate : Self.pulseRate
    }

    /// A cut-off swell easing back from `value` to rest.
    private static func settle(from value: CGFloat, rate: CAFrameRateRange) -> CABasicAnimation {
        let settle = CABasicAnimation(keyPath: "transform.scale.y")
        settle.fromValue = value
        settle.toValue = 1
        settle.duration = pulseFall
        settle.timingFunction = CAMediaTimingFunction(name: .easeOut)
        settle.preferredFrameRateRange = rate
        return settle
    }

    nonisolated static let pulseKey = "pulse"
    nonisolated static let settleKey = "settle"
    /// A beat's swell up and back down.
    nonisolated static let pulseRise: CFTimeInterval = 0.1
    nonisolated static let pulseFall: CFTimeInterval = 0.32
    /// The swell is quicker than the breathing: a few more frames keep it smooth.
    nonisolated static let pulseRate = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
    nonisolated static let batteryPulseRate = CAFrameRateRange(minimum: 20, maximum: 30, preferred: 30)

    /// The music's character over the last seconds: each bar breathes through its band's range
    /// at a pace that follows how lively it is. Each bar carries on from where it is, in the
    /// direction it is going: the new breathing starts at the phase that has it there (restarting
    /// every bar from its low each time read as a stutter every couple of seconds).
    fileprivate func adapt(to new: [Bar]) {
        guard isListening, isAnimating, new.count == barLayers.count, starts.count == barLayers.count else { return }
        let now = CACurrentMediaTime()
        var adapted = new
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, bar) in barLayers.enumerated() {
            let old = specs[index]
            let current = (bar.presentation()?.value(forKeyPath: "transform.scale.y") as? CGFloat) ?? old.low
            // Rising or falling now, in the running breathing.
            let cycle = ((now - starts[index]) / old.period).truncatingRemainder(dividingBy: 2)
            let rising = cycle >= 0 && cycle < 1
            // The new range always holds where the bar is, so nothing jumps: the range stretches
            // to it until the next update.
            var spec = new[index]
            if current > spec.high { spec = Bar(low: spec.low, high: current, period: spec.period, phase: spec.phase) }
            if current < spec.low { spec = Bar(low: current, high: spec.high, period: spec.period, phase: spec.phase) }
            let fraction = Double((current - spec.low) / max(spec.high - spec.low, 0.001))
            let offset = (rising ? Self.easeTime(at: fraction) : 2 - Self.easeTime(at: fraction)) * spec.period
            adapted[index] = spec
            let breathing = Self.breathing(spec, frameRate: frameRate)
            let newStart = now - offset
            bar.transform = CATransform3DMakeScale(1, spec.low, 1)
            // The old breathing crossfades into the new one over `blend`: sampled once here, both
            // curves mixed with a smooth step, so the bar's speed changes gradually as well as
            // its place (restarting on the new curve kept the place but the speed jumped).
            let oldStart = starts[index]
            let drift = Double(current) - Self.breathingValue(old, start: oldStart, at: now)
            let steps = max(Int((Self.blend * Double(frameRate.preferred ?? 20)).rounded()), 2)
            let values: [Double] = (0...steps).map { step in
                let t = Double(step) / Double(steps)
                let time = now + t * Self.blend
                let weight = t * t * (3 - 2 * t)
                let from = Self.breathingValue(old, start: oldStart, at: time) + drift * (1 - weight)
                let to = Self.breathingValue(spec, start: newStart, at: time)
                return from + (to - from) * weight
            }
            let transition = CAKeyframeAnimation(keyPath: "transform.scale.y")
            transition.values = values
            transition.duration = Self.blend
            transition.calculationMode = .linear
            transition.beginTime = bar.convertTime(now, from: nil)
            transition.preferredFrameRateRange = frameRate
            // Two animations, not a group (a group of infinite duration stood still): the new
            // breathing starts as the crossfade ends, and the crossfade, added last, wins until then.
            breathing.beginTime = bar.convertTime(now + Self.blend, from: nil)
            breathing.timeOffset = offset + Self.blend
            bar.add(breathing, forKey: Self.animationKey)
            bar.add(transition, forKey: Self.blendKey)
            starts[index] = newStart
        }
        specs = adapted
        CATransaction.commit()
    }

    /// Listens to the tap's analyses on its I/O thread, for three seconds at a time, and turns
    /// them into a breathing for each bar and a beat for the bass and treble bars, handed to the
    /// main thread once per window. The tap then sleeps (`rest`).
    ///
    /// Setting the bars from every analysis (23 a second, or one keyframe animation per I/O cycle)
    /// kept the app at Energy Impact 0.6–1.0 while music played, nearly all of it Core Animation's
    /// commits (measured). Breathing and beats are interpolated by the render server.
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
        private var onsets: [OnsetSample] = []
        /// The breathing last handed over (smoothed).
        private var applied: [EqualizerBarsView.Bar] = EqualizerBarsView.bars
        private var hasApplied = false
        /// The beat periods found in earlier windows (bass, treble), to steady the tempo.
        private var periods: [CFTimeInterval?] = [nil, nil]
        /// The last beats handed over (bass, treble), and how many windows in a row missed them.
        private var pulses: [Pulse?] = [nil, nil]
        private var misses = [0, 0]

        /// Seconds of music each reading is taken from.
        static let window: CFTimeInterval = 2
        /// On the charger: a reading from every 0.8 s of music, then 1 s of rest.
        static let chargingWindow: CFTimeInterval = 0.8
        static let chargingRest: Duration = .seconds(1)
        /// How long the tap rests after each window: the music is analysed 2 s in every 8.
        static let rest: Duration = .seconds(6)
        /// Silence this long (a track's end, a pause) brings the resting breathing back; a
        /// shorter gap between two songs keeps the music's.
        static let silence: CFTimeInterval = 1

        var isFollowing: Bool { lock.withLock { isActive && following } }

        private var onCharger = false
        var charging: Bool {
            get { lock.withLock { onCharger } }
            set { lock.withLock { onCharger = newValue } }
        }

        var onBattery: Bool {
            get { lock.withLock { battery } }
            set { lock.withLock { battery = newValue } }
        }

        func start() {
            lock.withLock {
                isActive = true
                following = false
                hasApplied = false
                periods = [nil, nil]
                pulses = [nil, nil]
                misses = [0, 0]
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
            onsets.removeAll(keepingCapacity: true)
        }

        func spectrumDidUpdate(_ batch: [SpectrumLevels], onsets slices: [OnsetSample], interval: CFTimeInterval) {
            guard let newest = batch.last ?? nil as SpectrumLevels? else {
                lock.withLock { if isActive { onsets.append(contentsOf: slices) } }
                return
            }
            let loud = newest.hasSignal()
            let silent = newest.lastSignal > 0 ? CACurrentMediaTime() - newest.lastSignal > Self.silence : !loud
            var handOver: Reading?
            var backToRest = false
            lock.lock()
            defer {
                lock.unlock()
                if backToRest {
                    DispatchQueue.main.async { [weak self] in self?.view?.followingChanged(false) }
                } else if let handOver {
                    DispatchQueue.main.async { [weak self] in
                        guard let view = self?.view else { return }
                        view.apply(handOver)
                        AudioSpectrumTap.shared.rest(for: view.continuous ? Self.chargingRest : Self.rest)
                    }
                }
            }
            guard isActive else { return }
            if loud { following = true }
            if following, silent {
                following = false
                hasApplied = false
                periods = [nil, nil]
                pulses = [nil, nil]
                misses = [0, 0]
                applied = EqualizerBarsView.bars
                reset()
                backToRest = true
                return
            }
            guard loud else { return }
            onsets.append(contentsOf: slices)
            for levels in batch {
                for band in 0..<min(sum.count, levels.bands.count) {
                    let value = Double(levels.bands[band])
                    sum[band] += value
                    squares[band] += value * value
                }
                count += 1
            }
            windowTime += interval * Double(batch.count)
            guard windowTime >= (onCharger ? Self.chargingWindow : Self.window), count > 0 else { return }

            // The breathing, eased from the last one: a new song or a volume change moves it over
            // a couple of windows instead of all at once.
            let raw = Self.breathing(sum: sum, squares: squares, count: count, battery: battery)
            let smoothed = hasApplied ? zip(applied, raw).map { Self.mix($0, $1, 0.5) } : raw
            var reading = Reading(specs: nil, pulses: [nil, nil, nil, nil, nil])
            if !hasApplied || Self.differs(smoothed, applied) {
                applied = smoothed
                hasApplied = true
                reading.specs = smoothed
            }
            // The beats: a strong kick drum lifts the bass bar a little higher on each beat, strong
            // cymbals the treble bar; their neighbours get 15 % of it. Faint ones lift nothing.
            // A window without a clear beat keeps the last one, fainter, for one more window, so
            // the pulses do not come and go with every reading.
            let bands: [(slices: [(CFTimeInterval, Float)], range: ClosedRange<Double>, bar: Int, neighbour: Int)] = [
                (onsets.map { ($0.time, $0.bass) }, 0.33...0.9, 0, 1),
                (onsets.map { ($0.time, $0.treble) }, 0.25...0.9, 4, 3),
            ]
            for (slot, band) in bands.enumerated() {
                if let found = BeatFinder.beat(band.slices, range: band.range, previous: periods[slot]),
                   let lift = Self.lift(strength: found.strength) {
                    periods[slot] = found.period
                    pulses[slot] = Pulse(period: found.period, beat: found.beat, peak: 1 + lift)
                    misses[slot] = 0
                } else if let last = pulses[slot], misses[slot] == 0 {
                    misses[slot] = 1
                    pulses[slot] = Pulse(period: last.period, beat: last.beat, peak: 1 + (last.peak - 1) * 0.6)
                } else {
                    periods[slot] = nil
                    pulses[slot] = nil
                }
                if let pulse = pulses[slot] {
                    let peak = min(pulse.peak, max(1.02, 1.04 / max(applied[band.bar].high, 0.1)))
                    reading.pulses[band.bar] = Pulse(period: pulse.period, beat: pulse.beat, peak: peak)
                    reading.pulses[band.neighbour] = Pulse(period: pulse.period, beat: pulse.beat,
                                                           peak: 1 + (peak - 1) * Self.neighbourShare)
                }
            }
            reset()
            handOver = reading
            let bass = reading.pulses[0].map { String(format: "%.0f bpm ×%.2f", 60 / $0.period, $0.peak) } ?? "-"
            let treble = reading.pulses[4].map { String(format: "%.0f bpm ×%.2f", 60 / $0.period, $0.peak) } ?? "-"
            Log.media.debug("beat: bass \(bass, privacy: .public) treble \(treble, privacy: .public) specs \(reading.specs != nil, privacy: .public)")
        }

        /// How much higher a beat lifts its bar (a share of its height), from how much the beats
        /// stand out: nothing below a clear beat, up to a third for a very prominent one.
        static func lift(strength: Double) -> CGFloat? {
            let lift = min(max((strength - 2.5) * 0.06, 0), 0.32)
            return lift >= 0.06 ? CGFloat(lift) : nil
        }

        /// The neighbour of a beat's bar moves with it by this share.
        static let neighbourShare: CGFloat = 0.15

        /// How much faster the bars move while following the music than the pace alone gives (10 %).
        static let speed = 1.1

        /// Each bar through its band's range over the window (its mean, give or take its spread),
        /// faster the more the music moves. The faintest wavers barely move a bar: the spread
        /// counts only past a small floor.
        static func breathing(sum: [Double], squares: [Double], count: Int, battery: Bool) -> [EqualizerBarsView.Bar] {
            let n = Double(count)
            let means = sum.map { $0 / n }
            let spreads = zip(squares, means).map { sqrt(max($0 / n - $1 * $1, 0)) }
            let liveliness = spreads.reduce(0, +) / Double(max(spreads.count, 1))
            return EqualizerBarsView.bars.enumerated().map { index, base in
                let rest = Double(EqualizerBarsView.restingScale)
                let mean = index < means.count ? rest + (1 - rest) * means[index] : Double(base.low)
                let spread = index < spreads.count ? (1 - rest) * max(spreads[index] - 0.035, 0) : 0
                var low = mean - 1.5 * spread - 0.03
                var high = mean + 1.5 * spread + 0.06
                if high - low < 0.14 {
                    let middle = (high + low) / 2
                    low = middle - 0.07
                    high = middle + 0.07
                }
                low = min(max(low, rest), 0.85)
                high = min(max(high, low + 0.1), 1)
                // 0 (a held note) … ~0.3 (drums): a third slower … two fifths faster than resting.
                let pace = min(max(1.3 - 2.3 * liveliness, 0.6), 1.3)
                return EqualizerBarsView.Bar(low: CGFloat(low), high: CGFloat(high),
                                             period: base.period * pace * (battery ? 1.2 : 1) / speed, phase: base.phase)
            }
        }

        static func mix(_ a: EqualizerBarsView.Bar, _ b: EqualizerBarsView.Bar, _ t: CGFloat) -> EqualizerBarsView.Bar {
            EqualizerBarsView.Bar(low: a.low + (b.low - a.low) * t, high: a.high + (b.high - a.high) * t,
                                  period: a.period + (b.period - a.period) * Double(t), phase: a.phase)
        }

        /// Worth an update: a bar's range moved by more than a few percent of its height, or its
        /// pace by more than a fifth.
        static func differs(_ a: [EqualizerBarsView.Bar], _ b: [EqualizerBarsView.Bar]) -> Bool {
            guard a.count == b.count else { return true }
            return zip(a, b).contains { x, y in
                abs(x.low - y.low) > 0.06 || abs(x.high - y.high) > 0.06 || abs(x.period - y.period) / y.period > 0.15
            }
        }
    }

    /// How long the old breathing takes to turn into the new one.
    nonisolated static let blend: CFTimeInterval = 0.6

    /// A breathing's value at `time`, for a breathing whose phase 0 fell at `start`: up from its
    /// low on the ease-in-ease-out curve, then back down (autoreversed).
    nonisolated static func breathingValue(_ bar: Bar, start: CFTimeInterval, at time: CFTimeInterval) -> Double {
        var cycle = ((time - start) / bar.period).truncatingRemainder(dividingBy: 2)
        if cycle < 0 { cycle += 2 }
        let progress = cycle < 1 ? cycle : 2 - cycle
        return Double(bar.low) + Double(bar.high - bar.low) * easeValue(at: progress)
    }

    /// The breathing's ease-in-ease-out curve's value (0…1) at `time` (0…1), from the same table.
    nonisolated static func easeValue(at time: Double) -> Double {
        let x = min(max(time, 0), 1)
        let table = easeTable
        var lo = 0, hi = table.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if table[mid].x < x { lo = mid } else { hi = mid }
        }
        let a = table[lo], b = table[hi]
        let t = b.x > a.x ? (x - a.x) / (b.x - a.x) : 0
        return a.y + (b.y - a.y) * t
    }

    /// The time (0…1) at which the breathing's ease-in-ease-out curve — CAMediaTimingFunction's
    /// Bézier (0.42, 0) (0.58, 1) — reaches `value` (0…1): the exact inverse, from a table.
    nonisolated static func easeTime(at value: Double) -> Double {
        let v = min(max(value, 0), 1)
        let table = easeTable
        var lo = 0, hi = table.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if table[mid].y < v { lo = mid } else { hi = mid }
        }
        let a = table[lo], b = table[hi]
        let t = b.y > a.y ? (v - a.y) / (b.y - a.y) : 0
        return a.x + (b.x - a.x) * t
    }

    /// (time, value) along the curve, in steps of its parameter.
    nonisolated private static let easeTable: [(x: Double, y: Double)] = (0...512).map { step in
        let s = Double(step) / 512, r = 1 - s
        return (x: 3 * r * r * s * 0.42 + 3 * r * s * s * 0.58 + s * s * s,
                y: 3 * r * s * s + s * s * s)
    }


    private func applyAnimationState() {
        let now = CACurrentMediaTime()
        starts = specs.map { now - $0.period * $0.phase }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for holder in pulseLayers {
            holder.removeAnimation(forKey: Self.pulseKey)
            holder.removeAnimation(forKey: Self.settleKey)
        }
        for (bar, spec) in zip(barLayers, specs) {
            bar.removeAnimation(forKey: Self.blendKey)
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
