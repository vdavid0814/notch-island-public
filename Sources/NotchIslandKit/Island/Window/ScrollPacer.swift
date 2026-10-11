import AppKit

/// A trackpad scroll over the island, handed on once a display frame, from a timer's turn.
///
/// A trackpad sends up to 120 scroll events a second, and each one was a main-thread turn of its
/// own with a SwiftUI update and a commit (the Timer's ruler: ~4 ms each) — twice what a 60 Hz
/// display shows, and, as the turn of an input event, on a performance core whatever the thread's
/// quality of service is: a swipe along the ruler read ~300 for its second in Activity Monitor
/// (measured by `ws/moused`'s scroll). Here the moving events of a gesture (and of its momentum)
/// are summed and delivered with the next frame's timer; the first and the last event of each
/// phase, and every other kind of event, go through at once, in order.
@MainActor final class ScrollPacer {
    static let isEnabled = ProcessInfo.processInfo.environment["NI_NO_SCROLL_PACE"] != "1"

    private var pending: CGEvent?
    private var pendingPhases: (NSEvent.Phase, NSEvent.Phase)?
    private var timer: Timer?
    private let deliver: (NSEvent) -> Void

    init(deliver: @escaping (NSEvent) -> Void) {
        self.deliver = deliver
    }

    /// True when the event was taken: it is delivered, summed with what else arrives meanwhile,
    /// with the next frame.
    func take(_ event: NSEvent) -> Bool {
        let moving = event.phase == .changed || event.momentumPhase == .changed
        guard moving, event.hasPreciseScrollingDeltas, let copy = event.cgEvent?.copy() else {
            flush()
            return false
        }
        if let pending, let phases = pendingPhases, phases == (event.phase, event.momentumPhase) {
            Self.add(pending, to: copy)
        } else {
            flush()
        }
        pending = copy
        pendingPhases = (event.phase, event.momentumPhase)
        if timer == nil {
            let timer = Timer(timeInterval: 1.0 / 60, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.timer = nil
                    self?.flush()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
        return true
    }

    /// What waits is delivered now (before an event that must not overtake it).
    func flush() {
        timer?.invalidate()
        timer = nil
        guard let waiting = pending else { return }
        pending = nil
        pendingPhases = nil
        if let event = NSEvent(cgEvent: waiting) { deliver(event) }
    }

    /// The scroll of `earlier` added to `event`'s. Lines first, then the fixed-point and the point
    /// deltas: setting the line delta resets the other two.
    private static func add(_ earlier: CGEvent, to event: CGEvent) {
        let lines: [CGEventField] = [.scrollWheelEventDeltaAxis1, .scrollWheelEventDeltaAxis2]
        let fixed: [CGEventField] = [.scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis2]
        let points: [CGEventField] = [.scrollWheelEventPointDeltaAxis1, .scrollWheelEventPointDeltaAxis2]
        let fixedSums = fixed.map { event.getDoubleValueField($0) + earlier.getDoubleValueField($0) }
        let pointSums = points.map { event.getIntegerValueField($0) + earlier.getIntegerValueField($0) }
        for field in lines {
            event.setIntegerValueField(field, value: event.getIntegerValueField(field) + earlier.getIntegerValueField(field))
        }
        for (field, sum) in zip(fixed, fixedSums) { event.setDoubleValueField(field, value: sum) }
        for (field, sum) in zip(points, pointSums) { event.setIntegerValueField(field, value: sum) }
    }
}
