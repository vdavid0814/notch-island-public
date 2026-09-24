import SwiftUI

// Countdown and stopwatch readouts. A running readout is a `TickingClock`; a paused one is plain
// text — nothing changes, so nothing needs to tick.

/// A running clock as plain text, redrawn once a second (a `TimelineView` aligned to the anchor,
/// so the digits turn on the second, and only while it is on screen).
///
/// Not SwiftUI's timer text (`Text(_:style: .timer)`, `Text(timerInterval:)`): that is formatted
/// again — a sentence tokenizer and all — on every frame of any animation on screen. Measured: most
/// of the main-thread time of opening and closing the panel while music played.
struct TickingClock: View {
    /// Counting up: the moment the clock read 0. Counting down: the moment it reaches 0.
    let anchor: Date
    let countsDown: Bool
    var prefix = ""

    var body: some View {
        TimelineView(.periodic(from: phase, by: 1)) { context in
            Text(prefix + IslandFormat.clock(Self.value(at: context.date, anchor: anchor, countsDown: countsDown)))
        }
    }

    /// A tick boundary in the past: the shown second changes exactly a whole number of seconds
    /// from the anchor.
    private var phase: Date {
        let offset = anchor.timeIntervalSinceNow
        return offset <= 0 ? anchor : anchor.addingTimeInterval(-(offset.rounded(.up) + 1))
    }

    /// Whole seconds shown at `date`: elapsed rounded down, remaining rounded up (0:01 until it
    /// actually reaches zero), as the system's timer text shows them. The nudge absorbs a tick
    /// that lands a hair before its boundary.
    nonisolated static func value(at date: Date, anchor: Date, countsDown: Bool) -> TimeInterval {
        if countsDown {
            return max(0, (anchor.timeIntervalSince(date) - 0.01).rounded(.up))
        }
        return max(0, (date.timeIntervalSince(anchor) + 0.01).rounded(.down))
    }
}

struct CountdownReadout: View {
    let state: CountdownState

    var body: some View {
        switch state {
        case .running(let endDate, _):
            TickingClock(anchor: endDate, countsDown: true)
        case .paused(let remaining, _):
            // Rounded up, as a running countdown shows it: 0:01 until it actually reaches zero.
            Text(IslandFormat.clock(remaining.rounded(.up)))
        case .idle, .finished:
            Text(IslandFormat.clock(0))
        }
    }
}

struct StopwatchReadout: View {
    let state: StopwatchState

    var body: some View {
        switch state {
        case .running(let startDate, let accumulated):
            TickingClock(anchor: startDate.addingTimeInterval(-accumulated), countsDown: false)
        case .paused(let accumulated):
            Text(IslandFormat.clock(accumulated))
        case .idle:
            Text(IslandFormat.clock(0))
        }
    }
}

extension CountdownState {
    var isRunning: Bool { if case .running = self { true } else { false } }
    var isPaused: Bool { if case .paused = self { true } else { false } }
    var isFinished: Bool { if case .finished = self { true } else { false } }
}

extension StopwatchState {
    var isRunning: Bool { if case .running = self { true } else { false } }
}

extension StatusTint {
    /// The foreground for a status symbol. `.primary` unless the colour means something.
    var style: AnyShapeStyle {
        switch self {
        case .none: AnyShapeStyle(.primary)
        case .charging: AnyShapeStyle(.green)
        case .low: AnyShapeStyle(.red)
        case .lowPower: AnyShapeStyle(.orange)
        }
    }
}

extension PowerState {
    /// Header / widget battery glyph tint: red when low on battery, orange in Low Power Mode, green
    /// while charging, otherwise primary.
    var tint: StatusTint {
        if isCharging { return .charging }
        if level <= 10 { return .low }
        if isLowPowerMode { return .lowPower }
        return .none
    }
}
