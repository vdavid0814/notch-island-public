import AppKit
import Observation

/// The one countdown and the one stopwatch.
///
/// Nothing here ticks. A running countdown owns exactly one scheduled wake-up — a task
/// sleeping until its end date — which is re-armed whenever the end date moves (pause,
/// resume, +time) and re-checked when the Mac wakes or the clock is changed. The
/// displays render the passing seconds themselves (`TickingClock`).
@Observable final class TimerStore {

    /// Sleeps for a duration; tests inject a controllable one.
    typealias Sleeper = @Sendable (Duration) async throws -> Void

    /// The Timer page slider's range, in minutes.
    static let draftRange: ClosedRange<Double> = 1...120
    /// Longer than a day is not a timer anyone sets from a notch, and the cap keeps the
    /// date arithmetic far away from overflow for absurd URL-scheme inputs.
    static let maximumDuration: TimeInterval = 24 * 60 * 60

    private(set) var countdown: CountdownState = .idle
    private(set) var stopwatch: StopwatchState = .idle

    /// The countdown the ruler has set up, in whole seconds (see `TimerDraftUnits`).
    var draftDuration: TimeInterval {
        get { storedDraft }
        set {
            guard newValue.isFinite else { return }
            storedDraft = min(max(newValue.rounded(), 1), Self.maximumDuration - 1)
        }
    }
    private var storedDraft: TimeInterval = 5 * 60

    /// The draft in minutes, clamped to `draftRange` (the minutes-only ruler).
    var draftMinutes: Double {
        get { storedDraft / 60 }
        set {
            guard newValue.isFinite else { return }
            draftDuration = min(max(newValue, Self.draftRange.lowerBound), Self.draftRange.upperBound) * 60
        }
    }

    /// Fired exactly once per countdown, when it reaches zero.
    @ObservationIgnored var onFinished: (() -> Void)?

    /// Running, paused, or finished and not yet acknowledged.
    var isCountdownActive: Bool { countdown != .idle }

    /// Running, or paused with time on it.
    var isStopwatchActive: Bool {
        switch stopwatch {
        case .idle: false
        case .running: true
        case .paused(let accumulated): accumulated > 0
        }
    }

    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let sleep: Sleeper
    @ObservationIgnored private var completionTask: Task<Void, Never>?
    @ObservationIgnored private var timeObservers: [(center: NotificationCenter, token: any NSObjectProtocol)] = []

    /// - Parameters:
    ///   - now: the wall clock the end dates are expressed in (the displays use the same).
    ///   - sleep: how the completion wake-up waits. The default uses the continuous clock,
    ///     which keeps counting while the Mac sleeps, like the countdown itself.
    init(now: @escaping () -> Date = { Date() }, sleep: @escaping Sleeper = TimerStore.continuousSleep) {
        self.now = now
        self.sleep = sleep
    }

    isolated deinit {
        completionTask?.cancel()
        removeTimeObservers()
    }

    // MARK: Countdown

    func start(minutes: Double) {
        start(duration: minutes * 60)
    }

    /// Replaces whatever countdown exists. Non-positive or non-finite durations are ignored.
    func start(duration: TimeInterval) {
        guard duration.isFinite, duration > 0 else { return }
        let total = min(duration, Self.maximumDuration)
        countdown = .running(endDate: now().addingTimeInterval(total), total: total)
        armCompletion()
    }

    func pause() {
        guard case .running(let endDate, let total) = countdown else { return }
        let remaining = endDate.timeIntervalSince(now())
        guard remaining > 0 else {
            finish(at: endDate)
            return
        }
        countdown = .paused(remaining: remaining, total: total)
        armCompletion()
    }

    func resume() {
        guard case .paused(let remaining, let total) = countdown else { return }
        countdown = .running(endDate: now().addingTimeInterval(remaining), total: total)
        armCompletion()
    }

    /// Back to idle from any state, without firing `onFinished`.
    func cancel() {
        guard countdown != .idle else { return }
        countdown = .idle
        armCompletion()
    }

    /// Finished → idle. Does nothing in any other state.
    func acknowledge() {
        guard case .finished = countdown else { return }
        countdown = .idle
    }

    /// Extends a running or paused countdown (the total grows too, so progress does not
    /// jump). On an idle or finished countdown it starts a new one of `seconds` — that is
    /// what "+1 min" on the finished banner means.
    func add(seconds: TimeInterval) {
        guard seconds.isFinite, seconds > 0 else { return }
        switch countdown {
        case .idle, .finished:
            start(duration: seconds)
        case .running(let endDate, let total):
            let current = now()
            let remaining = endDate.timeIntervalSince(current)
            let extended = min(remaining + seconds, Self.maximumDuration)
            countdown = .running(endDate: current.addingTimeInterval(extended),
                                 total: total + (extended - remaining))
            armCompletion()
        case .paused(let remaining, let total):
            let extended = min(remaining + seconds, Self.maximumDuration)
            countdown = .paused(remaining: extended, total: total + (extended - remaining))
        }
    }

    /// Elapsed fraction of the countdown at `date`, 0...1 (1 once finished, 0 when idle).
    func progress(at date: Date) -> Double {
        switch countdown {
        case .idle:
            return 0
        case .finished:
            return 1
        case .running(_, let total), .paused(_, let total):
            guard total > 0, let remaining = countdown.remaining(at: date) else { return 0 }
            return min(1, max(0, (total - remaining) / total))
        }
    }

    /// Finishes a running countdown whose end date has passed, or re-arms its wake-up for
    /// the time that is really left. Called by the wake-up itself, after system wake and
    /// after clock changes; idempotent, so `onFinished` can only fire once.
    func reconcile() {
        guard case .running(let endDate, _) = countdown else { return }
        if now() >= endDate {
            finish(at: endDate)
        } else {
            armCompletion()
        }
    }

    // MARK: Stopwatch

    /// Starts from zero, or continues a paused stopwatch.
    func startStopwatch() {
        switch stopwatch {
        case .running:
            return
        case .idle:
            stopwatch = .running(startDate: now(), accumulated: 0)
        case .paused(let accumulated):
            stopwatch = .running(startDate: now(), accumulated: accumulated)
        }
    }

    func pauseStopwatch() {
        guard case .running = stopwatch else { return }
        stopwatch = .paused(accumulated: stopwatch.elapsed(at: now()))
    }

    func resetStopwatch() {
        guard stopwatch != .idle else { return }
        stopwatch = .idle
    }

    // MARK: Completion

    /// Recorded as finishing at its end date, not when we noticed: a countdown that ran
    /// out while the Mac slept finished then.
    private func finish(at endDate: Date) {
        countdown = .finished(at: endDate)
        armCompletion()
        Log.timers.notice("countdown finished")
        onFinished?()
    }

    /// Makes the scheduled wake-up match the current state: one task while running,
    /// none otherwise.
    private func armCompletion() {
        completionTask?.cancel()
        completionTask = nil
        guard case .running(let endDate, _) = countdown else {
            removeTimeObservers()
            return
        }
        addTimeObservers()
        let delay = max(0, endDate.timeIntervalSince(now()))
        let sleep = sleep
        completionTask = Task { [weak self] in
            do {
                try await sleep(.seconds(delay))
            } catch {
                return  // cancelled: a newer arm (or no countdown) owns completion now
            }
            // Cancellation happens on the main actor too, so this check is exact.
            guard !Task.isCancelled else { return }
            self?.reconcile()
        }
    }

    /// While a countdown runs, the wall clock and the sleeping task can disagree: across
    /// system sleep (the task may not fire until well after wake) and when the user or
    /// NTP sets the clock. Either event re-checks the countdown.
    private func addTimeObservers() {
        guard timeObservers.isEmpty else { return }
        let sources: [(NotificationCenter, Notification.Name)] = [
            (NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification),
            (NotificationCenter.default, .NSSystemClockDidChange),
        ]
        for (center, name) in sources {
            let token = center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                Task { @MainActor in self?.reconcile() }
            }
            timeObservers.append((center, token))
        }
    }

    private func removeTimeObservers() {
        for observer in timeObservers {
            observer.center.removeObserver(observer.token)
        }
        timeObservers.removeAll()
    }

    /// The default `Sleeper`. The 50 ms tolerance lets the kernel coalesce the wake-up
    /// with other work; nobody can see a timer finish 50 ms late.
    nonisolated static func continuousSleep(_ duration: Duration) async throws {
        try await Task.sleep(for: duration, tolerance: .milliseconds(50), clock: .continuous)
    }
}
