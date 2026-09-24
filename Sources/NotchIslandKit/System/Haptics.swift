import AppKit

/// Force Touch trackpad feedback, named by what happened rather than by pattern.
///
/// `NSHapticFeedbackManager.defaultPerformer` already honours the input device, the accessibility
/// settings and the user's system preferences, and does nothing on hardware without a Force Touch
/// trackpad, so none of that is checked here. Each pulse is a real actuation with a small energy
/// cost, and pulses closer than ~80 ms are felt as one, hence the rate limit.
final class Haptics {
    nonisolated enum Event: Sendable {
        case open, close, tick, snap, drop, alert
    }

    private let preferences: Preferences
    private var throttle = HapticThrottle()

    init(preferences: Preferences) {
        self.preferences = preferences
    }

    func play(_ event: Event) {
        guard preferences.hapticsEnabled else { return }
        guard throttle.admit(event, at: ProcessInfo.processInfo.systemUptime) else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(Self.pattern(for: event), performanceTime: .now)
    }

    nonisolated static func pattern(for event: Event) -> NSHapticFeedbackManager.FeedbackPattern {
        switch event {
        // Geometry landing somewhere: the island opening/closing or a tile snapping into place.
        case .open, .close, .snap: .alignment
        // Discrete value steps and an accepted drop read as "one notch further".
        case .tick, .drop: .levelChange
        // Something that wants attention (timer done, charger, low battery).
        case .alert: .generic
        }
    }
}

/// Per-event rate limit.
///
/// Limiting per event rather than globally matters: a stream of volume ticks must never swallow the
/// open/close pulse that happens to land within the same 80 ms (a legacy bug). Ticks allow 40 ms
/// because a held key repeats at ~30 ms and every second step should still be felt; everything else
/// allows one pulse per 120 ms.
nonisolated struct HapticThrottle: Sendable {
    private var lastFired: [Haptics.Event: TimeInterval] = [:]

    static func minimumInterval(for event: Haptics.Event) -> TimeInterval {
        event == .tick ? 0.040 : 0.120
    }

    /// Returns true (and records the time) if `event` may fire at monotonic time `now`.
    mutating func admit(_ event: Haptics.Event, at now: TimeInterval) -> Bool {
        if let last = lastFired[event], now - last < Self.minimumInterval(for: event) {
            return false
        }
        lastFired[event] = now
        return true
    }
}
