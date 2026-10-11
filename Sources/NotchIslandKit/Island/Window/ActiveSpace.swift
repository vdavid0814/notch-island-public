import AppKit

// A window that is on every Space (`.canJoinAllSpaces`) and kept for as long as the app runs can be
// held on one Space by the window server all the same: ordered in anywhere else it is "visible"
// and not on the screen. Seen with Settings' kept window (October 7 2026: Settings grew empty) and
// with the menu-bar guard's strip (October 11: the strip "covered" the band on a full-screen Space
// while it was on another, and the menu bar came down at the notch). Its behaviour set again, or
// `.moveToActiveSpace`, does not free it (tried on the live window); moved to the active Space by
// the window server, it is on every Space again.

extension NSWindow {
    /// Orders the window in, and onto the active Space if it came in off it. True if it had to be
    /// moved.
    @discardableResult
    func orderFrontOnActiveSpace() -> Bool {
        if !isVisible { rejoinAllSpaces() }
        orderFrontRegardless()
        guard !isOnActiveSpace else { return false }
        ActiveSpace.move(self)
        rejoinAllSpaces()
        orderFrontRegardless()
        return true
    }

    private func rejoinAllSpaces() {
        guard collectionBehavior.contains(.canJoinAllSpaces) else { return }
        collectionBehavior.remove(.canJoinAllSpaces)
        collectionBehavior.insert(.canJoinAllSpaces)
    }
}

enum ActiveSpace {
    private typealias ConnectionID = @convention(c) () -> Int32
    private typealias Current = @convention(c) (Int32) -> UInt64
    private typealias MoveToSpace = @convention(c) (Int32, CFArray, UInt64) -> Void

    /// SkyLight's own, not in the headers: looked up once, nothing done on a system without them.
    private static let skyLight: (ConnectionID, Current, MoveToSpace)? = {
        let all = UnsafeMutableRawPointer(bitPattern: -2)
        guard let connection = dlsym(all, "SLSMainConnectionID"), let active = dlsym(all, "SLSGetActiveSpace"),
              let move = dlsym(all, "SLSMoveWindowsToManagedSpace") else { return nil }
        return (unsafeBitCast(connection, to: ConnectionID.self), unsafeBitCast(active, to: Current.self),
                unsafeBitCast(move, to: MoveToSpace.self))
    }()

    static func move(_ window: NSWindow) {
        guard let (connection, active, move) = skyLight, window.windowNumber > 0 else { return }
        let id = connection()
        move(id, [window.windowNumber] as CFArray, active(id))
    }
}
