import SwiftUI

// The pieces of the Now Playing widget (`NowPlayingWidget`).

/// Previous, play/pause, next, all in the same plain glass (play/pause one size up) unless the
/// widget gives each button its own colour and strength.
struct TransportControls: View {
    let isPlaying: Bool
    var showsPlay = true
    var showsSkip = true
    /// Each button's glass; nil is the plain glass.
    var glass: (TransportButton) -> Glass? = { _ in nil }

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
/// `TickingClock`s (once a second, while on screen), and a
/// `TimelineView` in the background moves the slider about once per point of travel — every few
/// seconds for a long track — only while this card is on screen, playing, and not being dragged. The slider itself lives outside the timeline, so the timeline
/// coming and going never tears down a slider mid-drag. While dragging, the slider follows a local
/// value and the seek is sent once, on release.
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
                ScrubTrack(position: shown, duration: duration) { target in
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
            .background {
                if isPlaying && dragPosition == nil && !isPreview {
                    // A fixed anchor: `.now` made a new schedule on every render, whose first entry
                    // (now) moved the slider, which rendered again — every frame while the card was
                    // open (measured: 100 renders per open and close, most of the panel's CPU).
                    TimelineView(.periodic(from: Self.tickAnchor, by: Self.sliderTick(duration: duration))) { context in
                        Color.clear.onChange(of: context.date, initial: true) { _, date in
                            livePosition = position(at: date)
                        }
                    }
                }
            }
            .onChange(of: clock, initial: true) { livePosition = position(at: .now) }
        } else {
            Label("Live", systemImage: "dot.radiowaves.left.and.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    nonisolated static let tickAnchor = Date(timeIntervalSinceReferenceDate: 0)

    /// About one step per point of a ~200-pt slider, never faster than 1 Hz nor slower than 0.2 Hz.
    nonisolated static func sliderTick(duration: TimeInterval) -> TimeInterval {
        min(max(duration / 200, 1), 5)
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
                Capsule().fill(.white.opacity(isDragging ? 1 : 0.9))
                    .frame(width: max(height, proxy.size.width * fraction))
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
