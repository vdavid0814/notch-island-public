import AppKit

/// Reports whether the pointer is over the expanded island.
///
/// Tracking-area exits alone are not enough: they are not delivered when the
/// pointer is warped, leaves across a screen edge, or when the tracking rect is
/// swapped underneath it, and an island stuck open is the worst failure mode.
/// Legacy polled the pointer at 20 Hz; NSEvent monitors carry the same
/// information but only fire when the pointer actually moves, so a still
/// pointer costs nothing. They are installed only while the island is expanded.
/// Mouse-move monitors need no permission (only key-event monitors do).
final class PointerMonitor {
    /// Slack around the island, so a pointer resting on the very edge does not
    /// flicker in and out. Small: the island closes as the pointer visibly
    /// leaves it (8 pt kept it open under a pointer clearly below it, and with
    /// a close delay of 0 there is nothing else to wait for). A pointer that
    /// grazes out and back within the close delay keeps it open anyway.
    nonisolated static let slack: CGFloat = 2

    var onChange: ((_ isInside: Bool) -> Void)?

    /// nil until the first evaluation after `start`.
    private(set) var isInside: Bool?
    private var region: CGRect = .null
    private var monitors: [Any] = []

    var isRunning: Bool { !monitors.isEmpty }

    /// Installs the monitors if needed, adopts `region` (global AppKit
    /// coordinates) and evaluates the current pointer position immediately, so
    /// an island opened from the menu knows at once that the pointer is away.
    func start(region: CGRect) {
        self.region = region
        if monitors.isEmpty { install() }
        evaluate()
    }

    func stop() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors.removeAll()
        isInside = nil
        region = .null
    }

    nonisolated static func contains(_ point: CGPoint, in region: CGRect) -> Bool {
        !region.isNull && region.insetBy(dx: -slack, dy: -slack).contains(point)
    }

    private func install() {
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        // Global: moves delivered to other apps (the pointer is away from our panel).
        if let global = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] _ in
            self?.evaluate()
        }) {
            monitors.append(global)
        }
        // Local: drags that started inside the island (a slider) and left it.
        if let local = NSEvent.addLocalMonitorForEvents(matching: events, handler: { [weak self] event in
            self?.evaluate()
            return event
        }) {
            monitors.append(local)
        }
    }

    private func evaluate() {
        let inside = Self.contains(NSEvent.mouseLocation, in: region)
        guard inside != isInside else { return }
        isInside = inside
        onChange?(inside)
    }

    /// Isolated so it can reach the monitor tokens; a monitor left installed
    /// would keep delivering events for the rest of the process.
    isolated deinit {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
    }
}
