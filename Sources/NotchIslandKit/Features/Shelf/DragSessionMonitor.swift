import AppKit

/// Notices that a file drag has started anywhere on screen, so the island can come out
/// to meet it before the pointer reaches the notch.
///
/// Costs nothing while nobody drags, by construction:
/// * No timer. Mouse-event monitors (mach-port run-loop sources, silent until a button
///   goes down) drive everything; the decision window is measured with the events' own
///   timestamps.
/// * Drag events only while a gesture is undecided. Presses and releases are always
///   watched; the drag-event monitors exist from a press until the gesture is decided
///   (at most `DragLatch.decisionWindow` into the movement), so a long window move or
///   text selection does not wake the app on every event of it.
/// * No permission. Global monitors need Accessibility only for key events; mouse events
///   are delivered without a grant.
/// * No payload reads. Only the drag pasteboard's `changeCount` and its declared types are
///   inspected, and only during the first moments of a gesture.
@MainActor final class DragSessionMonitor {

    /// A file drag began in another app. Always balanced by exactly one `onDragEnded`.
    var onDragBegan: (() -> Void)?
    /// The file drag that `onDragBegan` announced has landed somewhere (or the monitor was
    /// stopped mid-drag). Never fires for clicks, text selections or window moves.
    var onDragEnded: (() -> Void)?

    /// The press/release listener on the shared hub; nil while stopped.
    private var token: GlobalMouseHub.Token?
    /// `.leftMouseDragged` monitors, installed only while `latch` is undecided.
    private var dragMonitors: [Any] = []
    private var latch = DragLatch()
    private var pasteboard: NSPasteboard?

    init() {}

    var isRunning: Bool { token != nil }

    /// Idempotent.
    func start() {
        guard token == nil else { return }
        pasteboard = NSPasteboard(name: .drag)
        latch = DragLatch()
        // Presses and releases everywhere, from the shared hub: events headed to other apps —
        // where every drag worth announcing starts — and our own, which is how a press on our
        // own shelf tiles is recognised (and ignored), and how a mouse-up routed to us is caught.
        token = GlobalMouseHub.shared.add { [weak self] event, inOwnProcess in
            self?.handle(event, inOwnProcess: inOwnProcess)
        }
        Log.shelf.notice("drag session monitor armed")
    }

    /// Idempotent. A drag that began is reported as ended, so nobody is left waiting for
    /// a mouse-up we will no longer see.
    func stop() {
        guard let token else { return }
        GlobalMouseHub.shared.remove(token)
        self.token = nil
        setDragMonitors(installed: false)
        pasteboard = nil
        if latch.mouseUp() { onDragEnded?() }
    }

    // MARK: Events

    private func handle(_ event: NSEvent, inOwnProcess: Bool) {
        guard let pasteboard else { return }
        switch event.type {
        case .leftMouseDown:
            if latch.mouseDown(changeCount: pasteboard.changeCount, inOwnProcess: inOwnProcess) {
                // The previous drag's mouse-up never reached us; close it before a new one.
                onDragEnded?()
            }
        case .leftMouseDragged:
            let began = latch.mouseDragged(
                at: event.timestamp,
                changeCount: { pasteboard.changeCount },
                carriesFileURLs: {
                    // Inspects the declared types only: nothing is copied and no privacy
                    // prompt can be triggered.
                    pasteboard.canReadObject(forClasses: [NSURL.self],
                                             options: [.urlReadingFileURLsOnly: true])
                }
            )
            if began {
                Log.shelf.debug("file drag detected")
                onDragBegan?()
            }
        case .leftMouseUp:
            if latch.mouseUp() { onDragEnded?() }
            // This handler belongs to the press/release monitors, so the drag monitors can go now.
            setDragMonitors(installed: false)
            return
        default:
            break
        }
        if latch.isUndecided {
            setDragMonitors(installed: true)
        } else if !dragMonitors.isEmpty {
            // Not from inside the monitor's own handler: on the next turn, if still decided.
            Task { [weak self] in
                guard let self, !self.latch.isUndecided else { return }
                self.setDragMonitors(installed: false)
            }
        }
    }

    private func setDragMonitors(installed: Bool) {
        if installed, dragMonitors.isEmpty {
            // Global only: a press in our own process leaves the latch decided (ignored), so drag
            // monitors are never installed for our own gestures.
            if let global = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged, handler: { [weak self] event in
                self?.handle(event, inOwnProcess: false)
            }) {
                dragMonitors.append(global)
            }
        } else if !installed, !dragMonitors.isEmpty {
            for monitor in dragMonitors { NSEvent.removeMonitor(monitor) }
            dragMonitors.removeAll()
        }
    }
}

/// The decision logic of `DragSessionMonitor`, free of AppKit so it can be tested.
///
/// A gesture is decided once: within `decisionWindow` of its first drag event, the first
/// drag event that sees the drag pasteboard change decides whether this is a file drag.
/// After that — or once the window has passed — nothing more is read until the next
/// mouse-down.
nonisolated struct DragLatch: Sendable, Equatable {

    /// A drag session starts within a few pixels of movement. Movement that has not
    /// become a drag by then is a text selection, a window move or a slider drag, and
    /// reading the pasteboard for it would be wasted IPC. Measured from the first drag
    /// event, not the press, so a press-and-hold before dragging a file still counts.
    static let decisionWindow: TimeInterval = 0.6

    nonisolated enum Phase: Sendable, Equatable {
        /// Button up.
        case idle
        /// Button down in another app, no movement yet.
        case pressed(baseline: Int)
        /// Moving since `since`, not decided yet.
        case watching(baseline: Int, since: TimeInterval)
        /// A file drag began (and was announced).
        case fileDrag
        /// Decided: not an announceable file drag. Ignored until mouse-up.
        case ignored
    }

    private(set) var phase: Phase = .idle
    /// When the drag pasteboard was last read in this gesture: at 120 Hz a text selection or a
    /// window drag would read it ~70 times in the decision window; a drag session is still caught
    /// within `probeInterval`.
    private var lastProbe: TimeInterval?
    static let probeInterval: TimeInterval = 0.04

    /// A press is down and the gesture has not been decided: drag events still matter.
    var isUndecided: Bool {
        switch phase {
        case .pressed, .watching: true
        case .idle, .fileDrag, .ignored: false
        }
    }

    init() {}

    /// Starts a new gesture. A press inside our own process is ignored outright: the only
    /// file drags we can source are shelf tiles being dragged out, and announcing those
    /// as incoming would open the drop banner over the drag that just left it.
    ///
    /// Returns true when a previously announced file drag never saw its mouse-up, so the
    /// caller can end it first.
    mutating func mouseDown(changeCount: Int, inOwnProcess: Bool) -> Bool {
        lastProbe = nil
        let unfinished = phase == .fileDrag
        phase = inOwnProcess ? .ignored : .pressed(baseline: changeCount)
        return unfinished
    }

    /// Returns true exactly once per gesture: when a file drag has just begun. The
    /// closures are only called while the gesture is undecided and inside the window.
    mutating func mouseDragged(at time: TimeInterval,
                               changeCount: () -> Int,
                               carriesFileURLs: () -> Bool) -> Bool {
        let baseline: Int
        let since: TimeInterval
        switch phase {
        case .pressed(let pressedBaseline):
            (baseline, since) = (pressedBaseline, time)
            phase = .watching(baseline: baseline, since: since)
        case .watching(let watchedBaseline, let watchedSince):
            (baseline, since) = (watchedBaseline, watchedSince)
        case .idle, .fileDrag, .ignored:
            return false
        }
        guard time - since <= Self.decisionWindow else {
            phase = .ignored
            return false
        }
        if let last = lastProbe, time - last < Self.probeInterval { return false }
        lastProbe = time
        guard changeCount() != baseline else { return false }
        guard carriesFileURLs() else {
            phase = .ignored
            return false
        }
        phase = .fileDrag
        return true
    }

    /// Ends the gesture. Returns true only if it was an announced file drag.
    mutating func mouseUp() -> Bool {
        defer { phase = .idle; lastProbe = nil }
        return phase == .fileDrag
    }
}
