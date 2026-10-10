import SwiftUI

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
    /// As Customize set it: the line's colours, ends and knob.
    var look: ProgressLook = .plain
    /// Each time in its own style (nil: as the line sets it).
    var elapsedStyle: TextStyle?
    var remainingStyle: TextStyle?

    @Environment(AppModel.self) private var model
    @Environment(\.controlSize) private var controlSize
    @State private var livePosition: TimeInterval = 0
    @State private var dragPosition: TimeInterval?
    /// Previews (Settings' widget gallery) show the position without ticking.
    @Environment(\.isWidgetPreview) private var isPreview
    /// In Customize's panel for the line: where its parts are drawn (`ProgressPartFramesKey`).
    @Environment(\.reportsProgressParts) private var reportsParts

    var body: some View {
        if let duration, duration > 0 {
            let shown = min(max(dragPosition ?? livePosition, 0), duration)
            let running = runningAnchor(duration: duration)
            // The line across the whole width (thick, thicker under the pointer, like Music's),
            // the times under its two ends.
            VStack(spacing: Metrics.Spacing.xSmall) {
                ScrubTrack(position: shown, duration: duration,
                           rate: running == nil ? 0 : (clock?.rate ?? 0), look: look, reportsFrame: reportsParts) { target in
                    if dragPosition == nil { model.island.isInteracting = true }
                    dragPosition = target
                } commit: {
                    model.island.isInteracting = false
                    guard let target = dragPosition else { return }
                    livePosition = target
                    dragPosition = nil
                    model.media.send(.seek(target))
                }
                let elapsed = Group {
                    if let running {
                        TickingClock(anchor: running.start, countsDown: false)
                    } else {
                        Text(IslandFormat.clock(shown))
                    }
                }
                let remaining = Group {
                    if let running {
                        TickingClock(anchor: running.end, countsDown: true, prefix: "-")
                    } else {
                        Text("-\(IslandFormat.clock(duration - shown))")
                    }
                }
                Group {
                    if elapsedStyle == nil, remainingStyle == nil, look.elapsedOffset == .zero, look.remainingOffset == .zero,
                       !reportsParts {
                        HStack {
                            elapsed
                            Spacer(minLength: Metrics.Spacing.small)
                            remaining
                        }
                    } else {
                        // Each at its end of the line, in its style, where it was moved to.
                        HStack(spacing: Metrics.Spacing.small) {
                            styled(elapsed, elapsedStyle, part: .elapsed)
                            styled(remaining, remainingStyle, part: .remaining)
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

    /// A time in `style` (its size, weight, typeface, lines and colour), or as the line sets it
    /// where nil — at its end of the line, moved as the look says (over the room it takes there).
    @ViewBuilder private func styled(_ time: some View, _ style: TextStyle?, part: ProgressLook.Part) -> some View {
        let offset = look.offset(of: part)
        Group {
            if let style {
                let points: CGFloat = controlSize >= .large ? 12 : 10
                time
                    .font(Font(style.font(size: points, weight: .medium)).monospacedDigit())
                    .underline(style.isUnderlined)
                    .strikethrough(style.isStruckThrough)
                    .foregroundStyle(color(style.color))
            } else {
                time
            }
        }
        .fixedSize()
        .reportsProgressPart(part, if: reportsParts)
        .offset(x: offset.x, y: offset.y)
        .frame(maxWidth: .infinity, alignment: part == .elapsed ? .leading : .trailing)
    }

    private func color(_ color: TextStyle.TextColor) -> AnyShapeStyle {
        switch color {
        case .automatic: AnyShapeStyle(.secondary)
        case .custom(let rgb): AnyShapeStyle(rgb.color)
        case .artwork: AnyShapeStyle(model.media.artworkColor.map { Color($0) } ?? .islandAccent)
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
    var look: ProgressLook = .plain
    /// Reports where the line is drawn (Customize's panel for it).
    var reportsFrame = false
    /// What it is to VoiceOver, its value read out, and one step of it (a level's: the volume).
    var accessibilityName: LocalizedStringKey = "Playback Position"
    var spokenValue: (TimeInterval) -> String = { IslandFormat.clock($0) }
    var step: TimeInterval?
    /// The part played on a layer of its own, stepped by the render server while it plays; a line
    /// that only moves when it is set (the volume) is drawn as shapes.
    var drawsOnLayer = true
    /// The part played where its look leaves it automatic (white; a load's own colour).
    var automaticFill: Color = .white
    /// Set by dragging (a reading, the system's load, is not).
    var isAdjustable = true
    let scrub: (TimeInterval) -> Void
    let commit: () -> Void
    /// A drag begins (true) or ends (false).
    var onDrag: (Bool) -> Void = { _ in }

    @State private var isHovering = false
    @State private var isDragging = false
    @Environment(\.controlSize) private var controlSize
    @Environment(\.widgetRenderMode) private var renderMode
    @Environment(AppModel.self) private var model

    var body: some View {
        // Its room as the widget lays it out; drawn thicker or thinner, shorter, moved, over it.
        let room: CGFloat = controlSize >= .large ? 7 : 6
        let rest = (room * look.barThickness).rounded()
        let height = isAdjustable && (isHovering || isDragging) ? rest + 4 : rest
        let radius = look.ends.radius(height: height)
        let fill = color(look.fillColor, automatic: automaticFill)
        GeometryReader { full in
            let lineWidth = (full.size.width * look.barLength).rounded()
            GeometryReader { proxy in
            let fraction = duration > 0 ? min(max(position / duration, 0), 1) : 0
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(color(look.trackColor, automatic: .white.opacity(0.22)))
                if renderMode == .canvas || !drawsOnLayer {
                    // A picture of the line where it stands, as its layer draws it.
                    let width = PlayedLineView.width(fraction, in: proxy.size.width, height: height)
                    RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill)
                        .opacity(isDragging ? 1 : 0.9)
                        .frame(width: width)
                    if let knob = look.knob.size(height: rest) {
                        RoundedRectangle(cornerRadius: look.knob.radius(size: knob), style: .continuous)
                            .fill(.white)
                            .frame(width: knob.width, height: knob.height)
                            .shadow(color: .black.opacity(0.3), radius: 1.5, y: 0.5)
                            .position(x: PlayedLineView.knobCentre(width, height: height, knob: knob.width), y: height / 2)
                    }
                } else {
                    PlayedLine(fraction: fraction, rate: duration > 0 ? rate / duration : 0, opacity: isDragging ? 1 : 0.9,
                               radius: radius, color: NSColor(fill).cgColor,
                               knob: look.knob.size(height: rest).map { ($0, look.knob.radius(size: $0)) })
                }
            }
            .frame(height: height)
            .reportsProgressPart(.bar, if: reportsFrame)
            .frame(maxHeight: .infinity)
            .contentShape(.rect)
            .allowsHitTesting(isAdjustable)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isDragging { onDrag(true) }
                        isDragging = true
                        let x = min(max(value.location.x / max(proxy.size.width, 1), 0), 1)
                        scrub(duration * x)
                    }
                    .onEnded { _ in
                        isDragging = false
                        onDrag(false)
                        commit()
                    }
            )
            }
            .frame(width: lineWidth, height: max(rest + 8, room + 8))
            .offset(x: look.barOffset.x, y: look.barOffset.y)
            .frame(width: full.size.width, height: full.size.height, alignment: .leading)
        }
        .frame(height: room + 8)
        .onHover { isHovering = $0 }
        .animation(.spring(duration: 0.25, bounce: 0.2), value: isHovering || isDragging)
        .accessibilityElement()
        .accessibilityLabel(Text(accessibilityName))
        .accessibilityValue(Text(spokenValue(position)))
        .accessibilityAdjustableAction { direction in
            let step = self.step ?? max(5, duration / 50)
            switch direction {
            case .increment: scrub(min(position + step, duration)); commit()
            case .decrement: scrub(max(position - step, 0)); commit()
            @unknown default: break
            }
        }
    }

    /// A colour the look picked, or `automatic` where it picked none.
    private func color(_ color: TextStyle.TextColor, automatic: Color) -> Color {
        switch color {
        case .automatic: automatic
        case .custom(let rgb): rgb.color
        case .artwork: model.media.artworkColor.map { Color($0) } ?? .islandAccent
        }
    }
}

/// The played part of the line, as a Core Animation layer: while the track plays, one animation
/// steps it to the end twice a second, drawn by the window server. A SwiftUI position ticking
/// once a second re-rendered the card, and every re-render set the island's interactive glass
/// springing for a third of a second (measured: ~40 frames a second while the panel was open).
struct PlayedLine: NSViewRepresentable {
    /// 0…1 now.
    let fraction: Double
    /// Fraction per second (0: still).
    let rate: Double
    let opacity: Double

    var radius: CGFloat?
    var color: CGColor = NSColor.white.cgColor
    /// The knob on the position: its size and corner radius (nil: none).
    var knob: (size: CGSize, radius: CGFloat)?

    /// In the kept, hidden panel the line waits: its animation had the window server update it
    /// twice a second for as long as the panel was kept, unseen.
    @Environment(\.isIslandPanelHidden) private var isHidden

    func makeNSView(context: Context) -> PlayedLineView { PlayedLineView() }

    func updateNSView(_ view: PlayedLineView, context: Context) {
        view.style(radius: radius, color: color, knob: knob)
        view.update(fraction: fraction, rate: rate, opacity: opacity, isPaused: isHidden)
    }
}

final class PlayedLineView: NSView {
    private let fill = CALayer()
    /// On the position, over the line's end (none: hidden).
    private let knob = CALayer()
    private var radius: CGFloat?
    private var knobSize: CGSize?
    private var fraction = 0.0
    private var rate = 0.0
    /// When `fraction` was true.
    private var since = CACurrentMediaTime()
    /// Hidden: the line stands where it is, and runs on from where the time puts it when shown.
    private var isPaused = false
    /// About one point of travel per step on a ~200-pt line for a three-minute track.
    nonisolated static let step: CFTimeInterval = 0.5
    /// Steps per animation at most (keyframes the render server holds).
    nonisolated static let maximumSteps = 2400
    nonisolated static let animationKey = "played"

    override init(frame: CGRect) {
        super.init(frame: frame)
        wantsLayer = true
        fill.anchorPoint = CGPoint(x: 0, y: 0.5)
        fill.backgroundColor = NSColor.white.cgColor
        layer?.addSublayer(fill)
        knob.backgroundColor = NSColor.white.cgColor
        knob.shadowColor = NSColor.black.cgColor
        knob.shadowOpacity = 0.3
        knob.shadowRadius = 1.5
        knob.shadowOffset = CGSize(width: 0, height: -0.5)
        knob.isHidden = true
        layer?.addSublayer(knob)
    }

    /// The line's ends, colour and knob (`ProgressLook`).
    func style(radius: CGFloat?, color: CGColor, knob: (size: CGSize, radius: CGFloat)?) {
        let changed = radius != self.radius || knob?.size != knobSize
        fill.backgroundColor = color
        self.radius = radius
        knobSize = knob?.size
        self.knob.isHidden = knob == nil
        self.knob.cornerRadius = knob?.radius ?? 0
        if changed { restart() }
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
        knob.removeAnimation(forKey: Self.animationKey)
        fill.cornerRadius = radius ?? height / 2
        fill.position = CGPoint(x: 0, y: height / 2)
        fill.bounds = CGRect(x: 0, y: 0, width: Self.width(now, in: width, height: height), height: height)
        if let knobSize {
            knob.bounds = CGRect(origin: .zero, size: knobSize)
            knob.position = CGPoint(x: Self.knobCentre(fill.bounds.width, height: height, knob: knobSize.width), y: height / 2)
        }
        if rate > 0, now < 1, width > 0, !isPaused {
            // A step every half second (a longer one only on tracks over twenty minutes, where a
            // step is still a fraction of a point), as discrete keyframes: the render server draws a
            // frame only when the line steps. A linear animation with a 2 fps frame-rate hint was
            // drawn far more often (~200 window-server wake-ups a second, ~25–70 mW while the
            // panel was open on a playing track, measured), the hint notwithstanding.
            let duration = (1 - now) / rate
            let step = max(Self.step, duration / Double(Self.maximumSteps))
            let steps = max(1, Int((duration / step).rounded(.up)))
            let animation = CAKeyframeAnimation(keyPath: "bounds.size.width")
            animation.values = (0..<steps).map {
                NSNumber(value: Double(Self.width(min(now + rate * step * Double($0), 1), in: width, height: height)))
            }
            animation.keyTimes = (0...steps).map { NSNumber(value: min(step * Double($0) / duration, 1)) }
            animation.calculationMode = .discrete
            animation.duration = duration
            animation.fillMode = .forwards
            animation.isRemovedOnCompletion = false
            fill.bounds.size.width = Self.width(1, in: width, height: height)
            fill.add(animation, forKey: Self.animationKey)
            if let knobSize {
                // The knob steps with the line's end.
                let moves = CAKeyframeAnimation(keyPath: "position.x")
                moves.values = (animation.values ?? []).map {
                    NSNumber(value: Double(Self.knobCentre(CGFloat(($0 as? NSNumber)?.doubleValue ?? 0), height: height, knob: knobSize.width)))
                }
                moves.keyTimes = animation.keyTimes
                moves.calculationMode = .discrete
                moves.duration = duration
                moves.fillMode = .forwards
                moves.isRemovedOnCompletion = false
                knob.position.x = Self.knobCentre(fill.bounds.width, height: height, knob: knobSize.width)
                knob.add(moves, forKey: Self.animationKey)
            }
        }
        CATransaction.commit()
    }

    /// A capsule never narrower than it is tall.
    nonisolated static func width(_ fraction: Double, in width: CGFloat, height: CGFloat) -> CGFloat {
        max(height, width * CGFloat(fraction))
    }

    /// The knob's centre over a line `width` played: at its end, never past its start.
    nonisolated static func knobCentre(_ width: CGFloat, height: CGFloat, knob: CGFloat) -> CGFloat {
        max(width - height / 2, knob / 2)
    }
}

/// Where each part of a playback line is drawn, in `ProgressPartFramesKey.space` (Customize's panel
/// for the line).
struct ProgressPartFramesKey: PreferenceKey {
    static let space = "progressParts"

    static var defaultValue: [ProgressLook.Part: CGRect] { [:] }

    static func reduce(value: inout [ProgressLook.Part: CGRect], nextValue: () -> [ProgressLook.Part: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

extension EnvironmentValues {
    /// In Customize's panel for a playback line: its parts report where they are drawn.
    @Entry var reportsProgressParts = false
}

extension View {
    /// Reports where `part` is drawn when `reports` (nothing at all otherwise) — and, in a picture
    /// of the line without a part or of one part alone (`ProgressPartFilter`), is seen or not.
    @ViewBuilder func reportsProgressPart(_ part: ProgressLook.Part, if reports: Bool) -> some View {
        if reports {
            modifier(ProgressPartReport(part: part))
        } else {
            self
        }
    }
}

private struct ProgressPartReport: ViewModifier {
    let part: ProgressLook.Part
    @Environment(\.progressPartFilter) private var filter

    func body(content: Content) -> some View {
        content
            .background {
                // One part alone is a second picture of it: the whole one says where it is.
                if case .only = filter {
                    EmptyView()
                } else {
                    GeometryReader { proxy in
                        Color.clear.preference(key: ProgressPartFramesKey.self,
                                               value: [part: proxy.frame(in: .named(ProgressPartFramesKey.space))])
                    }
                }
            }
            .opacity(filter.shows(part) ? 1 : 0)
    }
}
