import Foundation

// Timers are anchored, never ticked: a running countdown is its end date, a running
// stopwatch its start date. Anything on screen derives the number from the anchor (and
// `TickingClock` does the ticking, only while on screen), so a running timer costs nothing
// while nobody looks at it.

nonisolated enum CountdownState: Sendable, Equatable {
    case idle
    case running(endDate: Date, total: TimeInterval)
    case paused(remaining: TimeInterval, total: TimeInterval)
    /// Reached zero at `at` and waits for the user to acknowledge it.
    case finished(at: Date)

    /// Seconds left at `date`; zero once finished, nil when idle.
    func remaining(at date: Date) -> TimeInterval? {
        switch self {
        case .idle: nil
        case .running(let endDate, _): max(0, endDate.timeIntervalSince(date))
        case .paused(let remaining, _): remaining
        case .finished: 0
        }
    }
}

nonisolated enum StopwatchState: Sendable, Equatable {
    case idle
    /// `accumulated` is the time banked by earlier runs, before `startDate`.
    case running(startDate: Date, accumulated: TimeInterval)
    case paused(accumulated: TimeInterval)

    /// Total elapsed time at `date`.
    func elapsed(at date: Date) -> TimeInterval {
        switch self {
        case .idle: 0
        case .running(let startDate, let accumulated): accumulated + max(0, date.timeIntervalSince(startDate))
        case .paused(let accumulated): accumulated
        }
    }
}
