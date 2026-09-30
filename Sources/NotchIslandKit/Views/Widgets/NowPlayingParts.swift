import SwiftUI

// The pieces of the Now Playing widget (`NowPlayingWidget`).

/// Previous, play/pause, next, all in the same plain glass (play/pause one size up) unless the
/// widget gives each button its own colour and strength.
struct TransportControls: View {
    let isPlaying: Bool
    var showsPlay = true
    var showsSkip = true
    /// Each button's look (`IslandWidget.buttonLooks`); nil: all three in the plain glass. Values,
    /// not a closure: a closure never compares equal, so every re-render of the card rebuilt the
    /// buttons and set their interactive glass springing (see `PlayedLine`).
    var looks: [String: ButtonLook]?

    private func look(_ button: TransportButton) -> ButtonLook? {
        looks.map { $0[button.rawValue] ?? ButtonLook() }
    }

    /// The style shows the button's title with its symbol (the first element that says, of `ids`).
    private func titled(_ ids: ElementID...) -> Bool {
        ids.lazy.compactMap { style.element($0)?.button.iconOnly }.first == false
    }

    @Environment(\.widgetFrameProbe) private var probe
    @Environment(AppModel.self) private var model
    @Environment(\.controlSize) private var controlSize
    @Environment(\.widgetStyle) private var style

    var body: some View {
        HStack(spacing: Metrics.Spacing.large) {
            if showsSkip {
                Button {
                    model.media.send(.previous)
                } label: {
                    Label("Previous", systemImage: "backward.fill")
                        // A little more room around the skip glyphs inside their circles.
                        .imageScale(.small)
                }
                .widgetButton(.skipButtons.part("previous"), in: style)
                .widgetButton(.skipButtons, in: style)
                .transportGlass(look(.previous), titled: titled(.skipButtons.part("previous"), .skipButtons))
                .help("Previous")
                .buttonElement(.skipButtons.part("previous"), in: probe)
            }

            if showsPlay {
                Button {
                    model.media.send(.togglePlayPause)
                } label: {
                    Label(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill")
                        .contentTransition(.symbolEffect(.replace))
                }
                .widgetButton(.playbackButtons, in: style)
                .transportGlass(look(.playPause), titled: titled(.playbackButtons))
                .help(isPlaying ? "Pause" : "Play")
                // Tagged inside the size it is drawn at (a size up from its row): unlocked, it
                // keeps that size.
                .buttonElement(.playbackButtons, in: probe)
                .controlSize(Metrics.Control.larger(controlSize))
            }

            if showsSkip {
                Button {
                    model.media.send(.next)
                } label: {
                    Label("Next", systemImage: "forward.fill")
                        .imageScale(.small)
                }
                .widgetButton(.skipButtons.part("next"), in: style)
                .widgetButton(.skipButtons, in: style)
                .transportGlass(look(.next), titled: titled(.skipButtons.part("next"), .skipButtons))
                .help("Next")
                .buttonElement(.skipButtons.part("next"), in: probe)
            }
        }
        .islandButton(.circle)
        .animation(Motion.content, value: isPlaying)
    }
}

/// Previous or next alone (a custom layout places each on its own).
struct TransportSkip: View {
    let forward: Bool
    var looks: [String: ButtonLook]?

    @Environment(AppModel.self) private var model
    @Environment(\.widgetStyle) private var style

    var body: some View {
        let button: TransportButton = forward ? .next : .previous
        Button {
            model.media.send(forward ? .next : .previous)
        } label: {
            Label(forward ? "Next" : "Previous", systemImage: forward ? "forward.fill" : "backward.fill")
                .imageScale(.small)
        }
        .widgetButton(.skipButtons.part(forward ? "next" : "previous"), in: style)
        .widgetButton(.skipButtons, in: style)
        .transportGlass(looks.map { $0[button.rawValue] ?? ButtonLook() })
        .help(forward ? "Next" : "Previous")
        .islandButton(.circle)
    }
}

extension View {
    /// The system's glass button in a button's own look (the nearest button style wins over the
    /// island's plain one); on the editor's canvas, a drawing of that glass.
    /// `titled`: the button shows its title too, in a capsule (a circle holds a symbol alone).
    func transportGlass(_ look: ButtonLook?, titled: Bool = false) -> some View {
        modifier(TransportGlass(look: look, titled: titled))
    }
}

/// The button's colour said for `WidgetButtonStyle` (under the element's style, over the island's
/// plain glass), and a capsule where it shows its title.
private struct TransportGlass: ViewModifier {
    let look: ButtonLook?
    let titled: Bool

    func body(content: Content) -> some View {
        content
            .buttonStyle(WidgetButtonStyle())
            .buttonAppearance(shape: titled ? .capsule : nil, tint: look?.pictureFill)
    }
}

extension ButtonLook {
    /// The colour a button wears: its tint at its strength, or — colourless — a white veil as strong
    /// as the setting (0.5 is about the plain glass). The glass's tint, and the canvas's fill.
    var pictureFill: Color {
        if let color = tint.color { color.opacity(opacity) } else { Color.white.opacity(0.3 * opacity) }
    }
}

/// The playback line over the track, with elapsed and remaining time under it.
///
/// Progress is derived from `PlaybackClock` (an anchor, no ticker). While playing, the times are
/// `TickingClock`s (once a second, while on screen) and the line is moved by Core Animation
/// (`PlayedLine`), so nothing in SwiftUI changes between two seconds. While dragging, the slider
/// follows a local value and the seek is sent once, on release.
struct PlaybackScrubber: View {
    let clock: PlaybackClock?
    let duration: TimeInterval?
    let isPlaying: Bool

    @Environment(AppModel.self) private var model
    @Environment(\.controlSize) private var controlSize
    @State private var livePosition: TimeInterval = 0
    @State private var dragPosition: TimeInterval?
    /// Previews (Settings' widget gallery) show the position without ticking.
    @Environment(\.isWidgetPreview) private var isPreview

    var body: some View {
        if let duration, duration > 0 {
            let shown = min(max(dragPosition ?? livePosition, 0), duration)
            let running = runningAnchor(duration: duration)
            // The line across the whole width (thick, thicker under the pointer, like Music's),
            // the times under its two ends.
            VStack(spacing: Metrics.Spacing.xSmall) {
                ScrubTrack(position: shown, duration: duration,
                           rate: running == nil ? 0 : (clock?.rate ?? 0)) { target in
                    if dragPosition == nil { model.island.isInteracting = true }
                    dragPosition = target
                } commit: {
                    model.island.isInteracting = false
                    guard let target = dragPosition else { return }
                    livePosition = target
                    dragPosition = nil
                    model.media.send(.seek(target))
                }
                HStack {
                    Group {
                        if let running {
                            TickingClock(anchor: running.start, countsDown: false)
                        } else {
                            Text(IslandFormat.clock(shown))
                        }
                    }
                    Spacer(minLength: Metrics.Spacing.small)
                    Group {
                        if let running {
                            TickingClock(anchor: running.end, countsDown: true, prefix: "-")
                        } else {
                            Text("-\(IslandFormat.clock(duration - shown))")
                        }
                    }
                }
                // Never wrapped: an hour-long track's "-1:10:10" broke onto two lines.
                .lineLimit(1)
            }
            // Follows the control size so the times keep their proportion to the line.
            .font((controlSize >= .large ? Font.callout : .footnote).weight(.medium).monospacedDigit())
            .foregroundStyle(.secondary)
            .onChange(of: clock, initial: true) { livePosition = position(at: .now) }
        } else {
            Label("Live", systemImage: "dot.radiowaves.left.and.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Start and end of the track on the wall clock while it plays at normal speed and is not being
    /// dragged: what the running times count from and to. nil otherwise (static text).
    private func runningAnchor(duration: TimeInterval) -> (start: Date, end: Date)? {
        guard isPlaying, dragPosition == nil, !isPreview, let clock, abs(clock.rate - 1) < 0.001 else { return nil }
        let start = clock.at.addingTimeInterval(-clock.elapsed)
        let end = start.addingTimeInterval(duration)
        guard end > .now else { return nil }
        return (start, end)
    }

    private func position(at date: Date) -> TimeInterval {
        clock?.position(at: date) ?? 0
    }
}

/// The playback line: a thick capsule filled to the position, thicker while the pointer is on it
/// or dragging; a click or drag anywhere on it seeks (sent once, on release).
struct ScrubTrack: View {
    let position: TimeInterval
    let duration: TimeInterval
    /// Seconds of track per second while it plays on its own (0: the line stands still).
    var rate: Double = 0
    let scrub: (TimeInterval) -> Void
    let commit: () -> Void

    @State private var isHovering = false
    @State private var isDragging = false
    @Environment(\.controlSize) private var controlSize
    /// The widget's Progress element (`ResolvedLine`); on the Now Playing page, empty.
    @Environment(\.widgetStyle) private var style
    @Environment(\.widgetArtworkColor) private var artwork
    @Environment(\.widgetRenderMode) private var renderMode

    var body: some View {
        let line = ResolvedLine(style.element(.progress))
        let rest: CGFloat = line.thickness ?? (controlSize >= .large ? 7 : 6)
        let height = isHovering || isDragging ? rest + 4 : rest
        GeometryReader { proxy in
            let fraction = duration > 0 ? min(max(position / duration, 0), 1) : 0
            ZStack(alignment: .leading) {
                line.barShape(height: height).fill(line.trackStyle(.white.opacity(0.22), artwork: artwork))
                if renderMode == .canvas {
                    // A picture of the line where it stands, as its layer draws it: drawn off
                    // screen too (the Customize transition's snapshot), which a layer is not.
                    line.barShape(height: height)
                        .fill(line.fillColor(value: fraction, artwork: artwork) ?? .white)
                        .opacity(0.9)
                        .frame(width: PlayedLineView.width(fraction, in: proxy.size.width, height: height))
                } else {
                    PlayedLine(fraction: fraction, rate: duration > 0 ? rate / duration : 0,
                               opacity: isDragging ? 1 : 0.9, rounding: line.endRounding,
                               color: line.fillColor(value: fraction, artwork: artwork).map { NSColor($0).cgColor } ?? PlayedLineView.white)
                }
            }
            .frame(height: height)
            .frame(maxHeight: .infinity)
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        let x = min(max(value.location.x / max(proxy.size.width, 1), 0), 1)
                        scrub(duration * x)
                    }
                    .onEnded { _ in
                        isDragging = false
                        commit()
                    }
            )
        }
        .frame(height: rest + 8)
        .onHover { isHovering = $0 }
        .animation(.spring(duration: 0.25, bounce: 0.2), value: isHovering || isDragging)
        .accessibilityElement()
        .accessibilityLabel("Playback Position")
        .accessibilityValue(Text(IslandFormat.clock(position)))
        .accessibilityAdjustableAction { direction in
            let step = max(5, duration / 50)
            switch direction {
            case .increment: scrub(min(position + step, duration)); commit()
            case .decrement: scrub(max(position - step, 0)); commit()
            @unknown default: break
            }
        }
    }
}

/// The played part of the line, as a Core Animation layer: while the track plays, one linear
/// animation carries it to the end at 2 fps, drawn by the window server. A SwiftUI position ticking
/// once a second re-rendered the card, and every re-render set the island's interactive glass
/// springing for a third of a second (measured: ~40 frames a second while the panel was open).
struct PlayedLine: NSViewRepresentable {
    /// 0…1 now.
    let fraction: Double
    /// Fraction per second (0: still).
    let rate: Double
    let opacity: Double
    /// Its ends' rounding, a part of its thickness (`ResolvedLine.endRounding`).
    var rounding: CGFloat = 0.5
    /// Set on the layer when it changes, not per frame.
    let color: CGColor

    /// In the kept, hidden panel the line waits: its animation had the window server update it
    /// twice a second for as long as the panel was kept, unseen.
    @Environment(\.isIslandPanelHidden) private var isHidden

    func makeNSView(context: Context) -> PlayedLineView { PlayedLineView() }

    func updateNSView(_ view: PlayedLineView, context: Context) {
        view.rounding = rounding
        view.update(fraction: fraction, rate: rate, opacity: opacity, color: color, isPaused: isHidden)
    }
}

final class PlayedLineView: NSView {
    private let fill = CALayer()
    private var color: CGColor?
    /// Its ends' rounding, a part of its height.
    var rounding: CGFloat = 0.5 {
        didSet { if rounding != oldValue { needsLayout = true } }
    }
    private var fraction = 0.0
    private var rate = 0.0
    /// When `fraction` was true.
    private var since = CACurrentMediaTime()
    /// Hidden: the line stands where it is, and runs on from where the time puts it when shown.
    private var isPaused = false
    /// About one point of travel per frame on a ~200-pt line for a three-minute track.
    nonisolated static let frameRate = CAFrameRateRange(minimum: 1, maximum: 4, preferred: 2)
    nonisolated static let animationKey = "played"
    static let white = NSColor.white.cgColor

    override init(frame: CGRect) {
        super.init(frame: frame)
        wantsLayer = true
        fill.anchorPoint = CGPoint(x: 0, y: 0.5)
        layer?.addSublayer(fill)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    /// Clicks and drags belong to the SwiftUI track around it.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(fraction: Double, rate: Double, opacity: Double, color: CGColor, isPaused: Bool) {
        fill.opacity = Float(opacity)
        if color != self.color {
            self.color = color
            // At once, as it was set before the view was shown: not a fade from no colour.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            fill.backgroundColor = color
            CATransaction.commit()
        }
        let moved = fraction != self.fraction || rate != self.rate
        guard moved || isPaused != self.isPaused else { return }
        if moved {
            self.fraction = fraction
            self.rate = rate
            since = CACurrentMediaTime()
        }
        self.isPaused = isPaused
        restart()
    }

    override func layout() {
        super.layout()
        restart()
    }

    /// Where the line is now, and — while playing — one animation from there to the end.
    private func restart() {
        let width = bounds.width
        let height = bounds.height
        let now = min(max(fraction + rate * (CACurrentMediaTime() - since), 0), 1)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fill.removeAnimation(forKey: Self.animationKey)
        fill.cornerRadius = height * rounding
        fill.position = CGPoint(x: 0, y: height / 2)
        fill.bounds = CGRect(x: 0, y: 0, width: Self.width(now, in: width, height: height), height: height)
        if rate > 0, now < 1, width > 0, !isPaused {
            let animation = CABasicAnimation(keyPath: "bounds.size.width")
            animation.fromValue = Self.width(now, in: width, height: height)
            animation.toValue = Self.width(1, in: width, height: height)
            animation.duration = (1 - now) / rate
            animation.timingFunction = CAMediaTimingFunction(name: .linear)
            animation.fillMode = .forwards
            animation.isRemovedOnCompletion = false
            animation.preferredFrameRateRange = Self.frameRate
            fill.add(animation, forKey: Self.animationKey)
        }
        CATransaction.commit()
    }

    /// A capsule never narrower than it is tall.
    nonisolated static func width(_ fraction: Double, in width: CGFloat, height: CGFloat) -> CGFloat {
        max(height, width * CGFloat(fraction))
    }
}
