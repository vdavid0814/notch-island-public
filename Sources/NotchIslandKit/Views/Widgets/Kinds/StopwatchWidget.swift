import SwiftUI

/// The stopwatch: its time, bright while it runs, and its buttons — Start or Pause always, Reset
/// once it has counted (and in Customize's editor, to be styled). Each can be moved and restyled
/// in Customize: the time as a text (`WidgetLabel`), the buttons as Now Playing's are
/// (`ButtonLook`; as the widget draws them until then).
struct StopwatchWidget: View {
    let widget: IslandWidget
    let size: CGSize

    @Environment(AppModel.self) private var model
    @Environment(\.isElementEditing) private var isEditing

    /// The time's size: never wider than about two thirds of the row ("0:00" is about 2.4 of its size wide).
    static func readoutPoints(inner: CGSize) -> CGFloat {
        min(WidgetMetrics.points(inner.height, ratio: 0.55, min: 15, max: 40), inner.width * 0.65 / 2.4)
    }

    /// A restyled button's symbol size.
    static func buttonPoints(inner: CGSize) -> CGFloat {
        WidgetMetrics.points(inner.height, ratio: 0.42, min: 12, max: 20)
    }

    var body: some View {
        let timers = model.timers
        let running = timers.stopwatch.isRunning
        HStack(spacing: Metrics.Spacing.medium) {
            if widget.shows(.readout) {
                readout(timers.stopwatch, running: running)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Spacer(minLength: 0)
            }
            if widget.shows(.resetButton), timers.isStopwatchActive || isEditing {
                button(.resetButton, title: "Reset", symbol: "arrow.counterclockwise", prominent: false) { timers.resetStopwatch() }
            }
            button(.stopwatchButton, title: running ? "Pause" : "Start", symbol: running ? "pause.fill" : "play.fill",
                   prominent: true) {
                running ? timers.pauseStopwatch() : timers.startStopwatch()
            }
            if !widget.shows(.readout) { Spacer(minLength: 0) }
        }
        .controlSize(WidgetMetrics.buttonSize(rowHeight: size.height))
        .frame(width: size.width, height: size.height)
        .animation(Motion.content, value: timers.stopwatch)
    }

    /// The time: as the widget sets it, or restyled (ticking each second while it runs).
    @ViewBuilder private func readout(_ state: StopwatchState, running: Bool) -> some View {
        let points = Self.readoutPoints(inner: size)
        let plain = StopwatchReadout(state: state)
            .font(.system(size: points, design: .rounded).monospacedDigit())
            .foregroundStyle(running ? .primary : .secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
        let shown = widget.withOwnDesign(.rounded, for: .readout)
        Group {
            if widget.textStyle(of: .readout) == .plain, !isEditing {
                plain
            } else if running {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    WidgetLabel(id: .readout, text: IslandFormat.clock(state.elapsed(at: context.date)), widget: shown, size: points,
                                weight: .regular, isSecondary: false) { plain }
                }
            } else {
                WidgetLabel(id: .readout, text: IslandFormat.clock(state.elapsed(at: .now)), widget: shown, size: points,
                            weight: .regular, isSecondary: !running) { plain }
            }
        }
        .movableElement(.readout, of: widget)
    }

    /// A button as the widget draws it (on glass), or as Customize styled it.
    @ViewBuilder private func button(_ id: ElementID, title: String, symbol: String, prominent: Bool,
                                     action: @escaping () -> Void) -> some View {
        let look = widget.buttonLook(of: id)
        Group {
            if look == .plain {
                Button(action: action) {
                    Label(title, systemImage: symbol).contentTransition(.symbolEffect(.replace))
                }
                .islandButton(.circle, prominent: prominent)
                .help(title)
            } else {
                NowPlayingButton(title: title, symbol: symbol, points: Self.buttonPoints(inner: size), look: look, action: action)
            }
        }
        .movableElement(id, of: widget)
    }
}
