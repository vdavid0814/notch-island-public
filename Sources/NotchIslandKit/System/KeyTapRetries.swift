import Foundation

/// When a key tap macOS refused is tried again (the media keys, ⌘Space).
///
/// macOS refuses a tap for a moment after the screen is unlocked (seen in reports: every start
/// within a second of `screenUnlocked` failed): tried again after 1, 3 and 8 s. After a Reset of
/// Accessibility or Input Monitoring it is refused until the user allows the app again, and the
/// process's own trust flag may never have moved meanwhile (0.8.2 on macOS 27: "trusted" 30 s
/// after the reset, the tap refused until the switch was back on): then every `patientGap`, for
/// `patientFor` from the reset.
///
/// A refusal that is tried again is expected, not an error: the last one is.
nonisolated struct KeyTapRetries: Sendable {
    static let delays: [Duration] = [.seconds(1), .seconds(3), .seconds(8)]
    static let patientGap: Duration = .seconds(15)
    static let patientFor: Duration = .seconds(600)

    private(set) var failures = 0
    private var patientUntil: ContinuousClock.Instant?

    /// A refusal: how long until the next attempt, or nil when the tap is left failed (a later
    /// start, an unlock or a permission allowed tries again).
    mutating func next(now: ContinuousClock.Instant = .now) -> Duration? {
        if failures < Self.delays.count {
            failures += 1
            return Self.delays[failures - 1]
        }
        guard let patientUntil, now < patientUntil else { return nil }
        return Self.patientGap
    }

    /// The tap is in, or its owner starts over: the next refusal is the first again.
    mutating func reset() {
        failures = 0
    }

    /// A permission Reset is under way: refusals are to be expected for a while.
    mutating func expectRefusals(now: ContinuousClock.Instant = .now) {
        patientUntil = now + Self.patientFor
    }
}
