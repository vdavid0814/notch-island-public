import SwiftUI

/// A countdown or stopwatch in the pill: state glyph in the leading ear, time in the trailing ear.
struct TimerCompact: View {
    nonisolated enum Mode: Sendable { case countdown, stopwatch }

    let mode: Mode
    let split: NotchSplit
    let height: CGFloat
    let glyphSide: CGFloat

    @Environment(AppModel.self) private var model

    var body: some View {
        let timers = model.timers
        NotchSplitBand(split: split, height: height) {
            Image(systemName: symbol(timers))
                .font(.system(size: glyphSide * 0.62, weight: .semibold))
                .foregroundStyle(isAttention(timers) ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                .contentTransition(.symbolEffect(.replace))
                .animation(Motion.content, value: symbol(timers))
                .frame(width: glyphSide, height: glyphSide)
        } trailing: {
            readout(timers)
                .font(.callout.weight(.semibold).monospacedDigit())
                .foregroundStyle(isDimmed(timers) ? .secondary : .primary)
                .lineLimit(1)
                .minimumScaleFactor(Metrics.Compact.timeMinimumScale)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func readout(_ timers: TimerStore) -> some View {
        switch mode {
        case .countdown: CountdownReadout(state: timers.countdown)
        case .stopwatch: StopwatchReadout(state: timers.stopwatch)
        }
    }

    /// Static glyphs only: a paused timer shows `pause.fill` rather than pulsing, because an
    /// indefinite effect on a pill that can sit there for hours is energy spent on nothing.
    private func symbol(_ timers: TimerStore) -> String {
        switch mode {
        case .countdown:
            switch timers.countdown {
            case .finished: "bell.fill"
            case .paused: "pause.fill"
            case .idle, .running: "timer"
            }
        case .stopwatch:
            timers.stopwatch.isRunning ? "stopwatch" : "pause.fill"
        }
    }

    private func isAttention(_ timers: TimerStore) -> Bool {
        mode == .countdown && timers.countdown.isFinished
    }

    private func isDimmed(_ timers: TimerStore) -> Bool {
        switch mode {
        case .countdown: timers.countdown.isPaused
        case .stopwatch: !timers.stopwatch.isRunning
        }
    }
}
