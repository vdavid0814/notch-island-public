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

    static let open: Animation = .spring(openSpring())
    static let close: Animation = .spring(closeSpring())
    static let morph: Animation = .spring(morphSpring())
    /// Content swaps that keep the island's size (switching expanded pages).
    static let content: Animation = .smooth(duration: 0.24)
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
        case (false, true): return .spring(openSpring(duration: duration))
        case (true, false): return .spring(closeSpring(duration: duration))
        case (true, true):
            // The assistant grows out of the open panel, and shrinks back to it.
            if to.isAssistant, !from.isAssistant { return .spring(openSpring(duration: duration)) }
            if from.isAssistant, !to.isAssistant { return .spring(closeSpring(duration: duration)) }
            // Settings grows out of the open panel too, and shrinks back to it.
            if to.isSettings, !from.isSettings { return .spring(openSpring(duration: duration)) }
            if from.isSettings, !to.isSettings { return .spring(closeSpring(duration: duration)) }
            // The assistant's field growing into its list and back: the open and close springs,
            // shortened like a morph, since only the bottom edge moves.
            if case .assistant(let a) = from, case .assistant(let b) = to, a != b {
                let spring = b > a ? openSpring(duration: duration * 0.7) : closeSpring(duration: duration * 0.7)
                return .spring(spring)
            }
            return content
        case (false, false): return .spring(morphSpring(duration: duration))
        }
    }
}
