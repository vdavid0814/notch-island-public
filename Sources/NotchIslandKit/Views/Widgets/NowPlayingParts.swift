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

    private func glass(_ button: TransportButton) -> Glass? {
        looks.map { ($0[button.rawValue] ?? ButtonLook()).glass }
    }

    @Environment(AppModel.self) private var model
    @Environment(\.controlSize) private var controlSize

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
                .transportGlass(glass(.previous))
                .help("Previous")
            }

            if showsPlay {
                Button {
                    model.media.send(.togglePlayPause)
                } label: {
                    Label(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill")
                        .contentTransition(.symbolEffect(.replace))
                }
                .transportGlass(glass(.playPause))
                .controlSize(Metrics.Control.larger(controlSize))
                .help(isPlaying ? "Pause" : "Play")
            }

            if showsSkip {
                Button {
                    model.media.send(.next)
                } label: {
                    Label("Next", systemImage: "forward.fill")
                        .imageScale(.small)
                }
                .transportGlass(glass(.next))
                .help("Next")
            }
        }
        .islandButton(.circle)
        .animation(Motion.content, value: isPlaying)
    }
}

private extension View {
    /// The system's glass button in a given glass (the nearest button style wins over the
    /// island's plain one).
    @ViewBuilder func transportGlass(_ glass: Glass?) -> some View {
        if let glass {
            buttonStyle(.glass(glass))
        } else {
            self
        }
    }
}

extension ButtonLook {
    /// The glass a button wears: its colour at its strength, or — colourless — a white veil as
    /// strong as the setting (0.5 is about the plain glass).
    var glass: Glass {
        if let color = tint.color {
            Glass.regular.tint(color.opacity(opacity)).interactive()
        } else {
            Glass.regular.tint(Color.white.opacity(0.3 * opacity)).interactive()
        }
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

    var body: some View {
        let rest: CGFloat = controlSize >= .large ? 7 : 6
        let height = isHovering || isDragging ? rest + 4 : rest
        GeometryReader { proxy in
            let fraction = duration > 0 ? min(max(position / duration, 0), 1) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.22))
                PlayedLine(fraction: fraction, rate: duration > 0 ? rate / duration : 0,
                           opacity: isDragging ? 1 : 0.9)
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

    /// In the kept, hidden panel the line waits: its animation had the window server update it
    /// twice a second for as long as the panel was kept, unseen.
    @Environment(\.isIslandPanelHidden) private var isHidden

    func makeNSView(context: Context) -> PlayedLineView { PlayedLineView() }

    func updateNSView(_ view: PlayedLineView, context: Context) {
        view.update(fraction: fraction, rate: rate, opacity: opacity, isPaused: isHidden)
    }
}

final class PlayedLineView: NSView {
    private let fill = CALayer()
    private var fraction = 0.0
    private var rate = 0.0
    /// When `fraction` was true.
    private var since = CACurrentMediaTime()
    /// Hidden: the line stands where it is, and runs on from where the time puts it when shown.
    private var isPaused = false
    /// About one point of travel per frame on a ~200-pt line for a three-minute track.
    nonisolated static let frameRate = CAFrameRateRange(minimum: 1, maximum: 4, preferred: 2)
    nonisolated static let animationKey = "played"

    override init(frame: CGRect) {
        super.init(frame: frame)
        wantsLayer = true
        fill.anchorPoint = CGPoint(x: 0, y: 0.5)
        fill.backgroundColor = NSColor.white.cgColor
        layer?.addSublayer(fill)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    /// Clicks and drags belong to the SwiftUI track around it.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(fraction: Double, rate: Double, opacity: Double, isPaused: Bool) {
        fill.opacity = Float(opacity)
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
        fill.cornerRadius = height / 2
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
