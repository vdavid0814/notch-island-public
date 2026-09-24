import SwiftUI

// The pieces of the Now Playing widget (`NowPlayingWidget`).

/// Title and subtitle, one line each. One text style up in a large widget, so the type grows with
/// the artwork instead of shrinking beside it.
struct CardTitle: View {
    let title: String
    let subtitle: String
    var isLarge = false

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.Spacing.xxSmall) {
            Text(title)
                .font(isLarge ? .title3.weight(.semibold) : .headline)
                .lineLimit(1)
            Text(subtitle)
                .font(isLarge ? .body : .subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

/// Previous, play/pause, next. Play/pause is the one prominent control, one size up.
struct TransportControls: View {
    let isPlaying: Bool
    var showsSkip = true

    @Environment(AppModel.self) private var model
    @Environment(\.controlSize) private var controlSize

    var body: some View {
        HStack(spacing: Metrics.Spacing.large) {
            if showsSkip {
                Button {
                    model.media.send(.previous)
                } label: {
                    Label("Previous", systemImage: "backward.fill")
                }
                .help("Previous")
            }

            Button {
                model.media.send(.togglePlayPause)
            } label: {
                Label(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill")
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.islandGlass(.circle, prominent: true))
            .controlSize(Metrics.Control.larger(controlSize))
            .help(isPlaying ? "Pause" : "Play")

            if showsSkip {
                Button {
                    model.media.send(.next)
                } label: {
                    Label("Next", systemImage: "forward.fill")
                }
                .help("Next")
            }
        }
        .buttonStyle(.islandGlass(.circle))
        .animation(Motion.content, value: isPlaying)
    }
}

/// Native slider over the track, with elapsed and remaining time.
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

    var body: some View {
        if let duration, duration > 0 {
            let shown = min(max(dragPosition ?? livePosition, 0), duration)
            let running = runningAnchor(duration: duration)
            HStack(spacing: Metrics.Spacing.medium) {
                Group {
                    if let running {
                        TickingClock(anchor: running.start, countsDown: false)
                    } else {
                        Text(IslandFormat.clock(shown))
                    }
                }
                .frame(minWidth: 34, alignment: .leading)
                Slider(
                    value: Binding(get: { shown }, set: { dragPosition = $0 }),
                    in: 0...duration
                ) {
                    Text("Playback Position")
                } onEditingChanged: { editing in
                    model.island.isInteracting = editing
                    guard !editing, let target = dragPosition else { return }
                    livePosition = target
                    dragPosition = nil
                    model.media.send(.seek(target))
                }
                .labelsHidden()
                Group {
                    if let running {
                        TickingClock(anchor: running.end, countsDown: true, prefix: "-")
                    } else {
                        Text("-\(IslandFormat.clock(duration - shown))")
                    }
                }
                .frame(minWidth: 38, alignment: .trailing)
            }
            // Follows the control size so the times keep their proportion to the slider.
            .font((controlSize >= .large ? Font.subheadline : .caption).monospacedDigit())
            .foregroundStyle(.secondary)
            .background {
                if isPlaying && dragPosition == nil {
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
        guard isPlaying, dragPosition == nil, let clock, abs(clock.rate - 1) < 0.001 else { return nil }
        let start = clock.at.addingTimeInterval(-clock.elapsed)
        let end = start.addingTimeInterval(duration)
        guard end > .now else { return nil }
        return (start, end)
    }

    private func position(at date: Date) -> TimeInterval {
        clock?.position(at: date) ?? 0
    }
}
