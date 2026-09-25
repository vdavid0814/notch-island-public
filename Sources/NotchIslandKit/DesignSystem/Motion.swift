import SwiftUI

/// Every island animation in one place, so open, close and morph read as one
/// physical system and Reduce Motion is honoured by construction rather than
/// per call site (legacy let a third of its animations bypass it).
nonisolated enum Motion {
    /// Length of the open and close animations the user may pick (Settings ▸ General), in seconds.
    static let durationRange: ClosedRange<Double> = 0.2...1.5
    /// The default length: the open spring's own duration.
    static let defaultDuration: Double = 0.4

    /// Opening overshoots slightly (about 2 %), so the panel lands the way the
    /// hardware island does.
    static func openSpring(duration: Double = defaultDuration) -> Spring {
        Spring(duration: duration, bounce: 0.22)
    }

    /// No bounce on exit: a bounce while leaving reads as indecision. Same length as the open, so
    /// closing is the opening played backwards into the notch.
    static func closeSpring(duration: Double = defaultDuration) -> Spring {
        Spring(duration: duration, bounce: 0.0)
    }

    /// Compact ↔ banner ↔ idle: small shape changes around the notch, a little quicker than an open.
    static func morphSpring(duration: Double = defaultDuration) -> Spring {
        Spring(duration: duration * 0.38 / defaultDuration, bounce: 0.14)
    }

    static let open: Animation = .lean(openSpring())
    static let close: Animation = .lean(closeSpring())
    static let morph: Animation = .lean(morphSpring())
    /// Content swaps that keep the island's size (switching expanded pages). `.smooth` is a spring
    /// without bounce.
    static let content: Animation = .lean(Spring(duration: 0.24, bounce: 0))
    /// Reduce Motion: a short flat fade replaces every spring.
    static let reduced: Animation = .easeInOut(duration: 0.18)

    /// How long after a transition starts the window may shrink to its resting
    /// frame. A plain delay rather than a transaction-completion callback: a
    /// spring keeps moving after its transaction reports completion, and
    /// shrinking early clips the island mid-settle. At 0.75 s (for the default
    /// length) every spring is within 0.05 % of its target (a fraction of a
    /// point on the widest open), which `IslandLayout.restingMargin` absorbs;
    /// SwiftUI's own `settlingDuration` uses a far stricter threshold and would
    /// keep the large stage over the menu bar noticeably longer. Settling time
    /// scales with the spring's duration; shorter lengths keep the 0.75 s floor.
    static func settleDuration(for duration: Double = defaultDuration) -> TimeInterval {
        max(0.75, 0.75 * duration / defaultDuration)
    }

    static func animation(
        from: IslandPresentation,
        to: IslandPresentation,
        reduceMotion: Bool,
        duration: Double = defaultDuration
    ) -> Animation {
        if reduceMotion { return reduced }
        switch (from.isOpen, to.isOpen) {
        case (false, true): return .lean(openSpring(duration: duration))
        case (true, false): return .lean(closeSpring(duration: duration))
        case (true, true):
            // The assistant grows out of the open panel, and shrinks back to it.
            if to.isAssistant, !from.isAssistant { return .lean(openSpring(duration: duration)) }
            if from.isAssistant, !to.isAssistant { return .lean(closeSpring(duration: duration)) }
            // Settings grows out of the open panel too, and shrinks back to it.
            if to.isSettings, !from.isSettings { return .lean(openSpring(duration: duration)) }
            if from.isSettings, !to.isSettings { return .lean(closeSpring(duration: duration)) }
            // The assistant's field growing into its list and back: the open and close springs,
            // shortened like a morph, since only the bottom edge moves.
            if case .assistant(let a) = from, case .assistant(let b) = to, a != b {
                let spring = b > a ? openSpring(duration: duration * 0.7) : closeSpring(duration: duration * 0.7)
                return .lean(spring)
            }
            return content
        case (false, false): return .lean(morphSpring(duration: duration))
        }
    }
}

/// Runs `body` in a transaction that animates nothing. For state set as a view appears inside the
/// island's open: set in the open's transaction, it rode the open's spring (a system widget's bars
/// grew from zero with it), and every frame re-laid the content out (measured).
@MainActor func withoutAnimation(_ body: () -> Void) {
    var transaction = Transaction(animation: nil)
    transaction.disablesAnimations = true
    withTransaction(transaction, body)
}

nonisolated extension Animation {
    /// A spring that costs only the frames it is seen in (`LeanSpring`).
    static func lean(_ spring: Spring) -> Animation {
        Animation(LeanSpring(spring: spring))
    }
}

/// A spring animation that stops once it is visually settled.
///
/// SwiftUI's own spring keeps animating until it is within a tiny fraction of a point of its target:
/// a 0.3 s close ran for 1.4 s (measured, 120 Hz: ~170 frames of SwiftUI layout and display-list
/// work, most of the island's CPU per open and close). This one ends when it is within
/// `settledFraction` of the distance it travels. (Holding the value between 60 Hz steps was tried:
/// SwiftUI still runs its update on every display frame, so it saved nothing.)
nonisolated struct LeanSpring: CustomAnimation {
    let spring: Spring
    /// Remaining distance, as a share of the whole move, at which the spring counts as settled.
    static let settledFraction = 0.003

    func animate<V: VectorArithmetic>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? {
        let end: TimeInterval
        if let cached = context.state[EndTime.self] {
            end = cached
        } else {
            end = endTime(for: value)
            context.state[EndTime.self] = end
        }
        if time >= end { return nil }
        return spring.value(target: value, time: time)
    }

    func velocity<V: VectorArithmetic>(value: V, time: TimeInterval, context: AnimationContext<V>) -> V? {
        spring.velocity(target: value, time: time)
    }

    /// Settling depends only on the spring and on the move's size, so it is worked out once per
    /// animation (kept in the context's state).
    private struct EndTime: AnimationStateKey {
        static var defaultValue: TimeInterval? { nil }
    }

    private func endTime<V: VectorArithmetic>(for value: V) -> TimeInterval {
        let distance = value.magnitudeSquared.squareRoot()
        guard distance > 0 else { return 0 }
        return min(spring.settlingDuration(target: value, epsilon: distance * Self.settledFraction),
                   spring.duration * 4)
    }
}
