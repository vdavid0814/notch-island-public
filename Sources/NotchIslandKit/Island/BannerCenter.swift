import Foundation

/// Banner lifetime rules as a pure value, driven by explicit instants so they
/// are testable without waiting.
nonisolated struct BannerSchedule: Sendable, Equatable {
    typealias Instant = ContinuousClock.Instant

    /// Minimum time a banner lingers after the pointer lets go of it, so it
    /// does not vanish the instant the pointer moves off.
    static let releaseGrace: Duration = .seconds(1)

    private(set) var current: BannerKind?
    /// When the current banner expires; nil while held or when nothing shows.
    private(set) var deadline: Instant?
    private(set) var isHeld = false
    /// Time left on the clock at the moment the banner was held.
    private var remaining: Duration = .zero

    /// A different kind replaces the current banner, unless `preempting` is false: then it shows
    /// only if nothing else is showing (an unrequested notice must not bury the one on screen).
    /// The same kind only extends its deadline (never shortens it), so holding a volume key keeps
    /// one banner alive instead of restarting its animation on every step.
    mutating func post(_ kind: BannerKind, duration: Duration, now: Instant, preempting: Bool = true) {
        if !preempting, let current, current != kind { return }
        if current == kind {
            if isHeld {
                remaining = max(remaining, duration)
            } else {
                deadline = max(deadline ?? now, now + duration)
            }
            return
        }
        current = kind
        if isHeld {
            remaining = duration
            deadline = nil
        } else {
            deadline = now + duration
        }
    }

    /// `nil` dismisses whatever is showing; a kind dismisses only that kind.
    mutating func dismiss(_ kind: BannerKind?) {
        guard current != nil, kind == nil || kind == current else { return }
        current = nil
        deadline = nil
        remaining = .zero
    }

    mutating func setHeld(_ held: Bool, now: Instant) {
        guard held != isHeld else { return }
        isHeld = held
        guard current != nil else { return }
        if held {
            remaining = max(.zero, now.duration(to: deadline ?? now))
            deadline = nil
        } else {
            deadline = now + max(remaining, Self.releaseGrace)
            remaining = .zero
        }
    }

    /// Clears the banner if its deadline has passed and returns what expired.
    mutating func expire(now: Instant) -> BannerKind? {
        guard let current, let deadline, deadline <= now else { return nil }
        self.current = nil
        self.deadline = nil
        return current
    }
}

/// The transient banner currently asking to be shown, with its auto-dismiss.
@Observable final class BannerCenter {
    private(set) var current: BannerKind?

    /// True while the pointer is over the banner (or a control in it is being
    /// dragged): auto-dismiss pauses and resumes with at least
    /// `BannerSchedule.releaseGrace` left.
    var isHeld: Bool = false {
        didSet {
            guard isHeld != oldValue else { return }
            schedule.setHeld(isHeld, now: .now)
            sync(reason: "hold")
        }
    }

    /// Called after a banner timed out on its own (not when dismissed or
    /// replaced), so owners can settle state the banner stood for.
    @ObservationIgnored var onExpire: ((BannerKind) -> Void)?

    @ObservationIgnored private var schedule = BannerSchedule()
    @ObservationIgnored private let expiry = DelayedAction()

    init() {}

    /// `preempting: false` for notices nobody asked for (a volume change made in Control Center):
    /// they show only when no other banner is up. See `BannerSchedule.post`.
    func post(_ kind: BannerKind, duration: TimeInterval, preempting: Bool = true) {
        schedule.post(kind, duration: .seconds(max(0, duration)), now: .now, preempting: preempting)
        if schedule.current != kind {
            Log.island.notice("banner \(String(describing: kind), privacy: .public) dropped: \(String(describing: self.current), privacy: .public) is showing")
        }
        sync(reason: "post")
    }

    func dismiss(_ kind: BannerKind? = nil) {
        schedule.dismiss(kind)
        sync(reason: "dismiss")
    }

    private func sync(reason: String) {
        // Writing an equal value would still notify observers and re-run the island policy.
        if current != schedule.current {
            DiagnosticsFlow.record("banner \(schedule.current.map { String(describing: $0) } ?? "none") (\(reason))")
            Log.island.info("banner \(String(describing: self.current), privacy: .public) → \(String(describing: self.schedule.current), privacy: .public) (\(reason, privacy: .public))")
            current = schedule.current
        }
        if let deadline = schedule.deadline {
            expiry.schedule(at: deadline) { [weak self] in self?.expire() }
        } else {
            expiry.cancel()
        }
    }

    private func expire() {
        let expired = schedule.expire(now: .now)
        sync(reason: "expired")
        if let expired { onExpire?(expired) }
    }
}
