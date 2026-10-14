import AppKit

/// Two fingers sideways on the trackpad over Siri: to the right goes back (a suggestion to the
/// search), to the left forward (the search into the suggestion last left), as in Safari.
///
/// Read from the scroll events the panel gets (a local monitor, only while Siri shows): a
/// trackpad's precise deltas, not a mouse wheel's, and not the momentum after the fingers lift.
@MainActor final class AssistantSwipe {
    private var monitor: Any?
    private var tracker = SwipeTracker()

    /// `back`: the fingers went to the right.
    func start(_ onSwipe: @escaping (_ back: Bool) -> Void) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, event.window is IslandPanel, event.hasPreciseScrollingDeltas, event.momentumPhase.isEmpty else { return event }
            // The deltas follow the content; with natural scrolling that is the fingers' way.
            let flip: CGFloat = event.isDirectionInvertedFromDevice ? 1 : -1
            if let swipe = self.tracker.feed(phase: event.phase, dx: event.scrollingDeltaX * flip, dy: event.scrollingDeltaY * flip) {
                onSwipe(swipe == .right)
            }
            return event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        tracker = SwipeTracker()
    }
}

/// One two-finger gesture's travel: a swipe once it has gone far enough sideways and mostly
/// sideways (a list scrolled up and down is not one), once per gesture.
nonisolated struct SwipeTracker: Sendable {
    enum Direction: Sendable { case left, right }

    /// Points the fingers travel sideways before it counts.
    static let distance: CGFloat = 40

    private var x: CGFloat = 0
    private var y: CGFloat = 0
    private var done = false

    /// `dx`, `dy`: the fingers' movement (right and down positive).
    mutating func feed(phase: NSEvent.Phase, dx: CGFloat, dy: CGFloat) -> Direction? {
        if phase.contains(.began) || phase.contains(.mayBegin) {
            x = 0; y = 0; done = false
        }
        if phase.contains(.ended) || phase.contains(.cancelled) {
            x = 0; y = 0; done = false
            return nil
        }
        guard !done else { return nil }
        x += dx
        y += dy
        guard abs(x) >= Self.distance, abs(x) > 2 * abs(y) else { return nil }
        done = true
        return x > 0 ? .right : .left
    }
}
