import AppKit

/// The one pair of press/release monitors the app keeps on the mouse everywhere (the shelf's
/// file-drag watch and the Window Anchor both need every press and release; two pairs would wake
/// the app twice for each). Installed with the first listener, removed with the last: nothing is
/// monitored while no feature asks.
///
/// Mouse-event monitors are mach-port run-loop sources, silent until a button moves, and need no
/// permission. AppKit calls them on the main thread.
@MainActor final class GlobalMouseHub {
    static let shared = GlobalMouseHub()

    /// A press or a release, and whether it happened in one of our own windows (global monitors
    /// skip those; a local one sees them).
    typealias Handler = (NSEvent, _ inOwnProcess: Bool) -> Void

    final class Token {}

    private var handlers: [(token: Token, handler: Handler)] = []
    private var monitors: [Any] = []

    var isRunning: Bool { !monitors.isEmpty }

    func add(_ handler: @escaping Handler) -> Token {
        let token = Token()
        handlers.append((token, handler))
        if monitors.isEmpty { install() }
        return token
    }

    func remove(_ token: Token) {
        handlers.removeAll { $0.token === token }
        guard handlers.isEmpty else { return }
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors.removeAll()
    }

    private func install() {
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseUp]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.deliver(event, inOwnProcess: false)
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.deliver(event, inOwnProcess: true)
            return event
        }) {
            monitors.append(local)
        }
    }

    private func deliver(_ event: NSEvent, inOwnProcess: Bool) {
        // A handler may remove itself (or another) while being called.
        for entry in handlers { entry.handler(event, inOwnProcess) }
    }
}
