import Foundation

/// One pending delayed action.
///
/// Scheduling replaces whatever was pending, so each concern (hover dwell,
/// close grace, banner expiry, stage settle, …) owns exactly one of these and
/// never juggles overlapping timers — the race-prone `DispatchWorkItem` web the
/// legacy app had. It is a single cancellable `Task` sleeping once: nothing
/// repeats and nothing is scheduled while no action is pending.
final class DelayedAction {
    private var task: Task<Void, Never>?

    var isPending: Bool { task != nil }

    func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) {
        schedule(at: .now + .seconds(max(0, delay)), action)
    }

    func schedule(at deadline: ContinuousClock.Instant, _ action: @escaping @MainActor () -> Void) {
        task?.cancel()
        // 10 % leeway (10–100 ms) lets the kernel coalesce the wake-up with others.
        let leeway = Duration.milliseconds(min(100, max(10, Int(ContinuousClock.Instant.now.duration(to: deadline) / .milliseconds(10)))))
        task = Task { [weak self] in
            do {
                try await Task.sleep(until: deadline, tolerance: leeway, clock: .continuous)
            } catch {
                return
            }
            // A cancel that raced the wake-up must still win.
            guard !Task.isCancelled, let self else { return }
            self.task = nil
            action()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    deinit {
        task?.cancel()
    }
}
