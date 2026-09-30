import AppKit
import ApplicationServices

/// Another app's window as Accessibility names it. The element is only ever messaged on the
/// worker's queue.
nonisolated struct AXWindowRef: @unchecked Sendable, Equatable {
    let element: AXUIElement

    static func == (a: AXWindowRef, b: AXWindowRef) -> Bool { CFEqual(a.element, b.element) }
}

/// A window the anchor can hold.
nonisolated struct AnchorWindow: Sendable, Equatable {
    var ref: AXWindowRef
    var pid: pid_t
    var bundleID: String?
    /// The window server's id (for what lies over it, and the live copy); nil when it cannot be told.
    var windowID: CGWindowID?
    var frame: CGRect
}

/// Why a window was not anchored.
nonisolated enum AnchorRefusal: String, Error, Sendable, Equatable {
    case noWindow, fullScreen, notStandard, stageManager, ownWindow, noScreen, notTrusted
}

/// A window as the window server lists it: no permission is needed for its owner and bounds.
nonisolated struct ServerWindow: Sendable, Equatable {
    var id: CGWindowID
    var pid: pid_t
    var frame: CGRect
}

/// An `AXObserver`, created on the worker and delivering on the main run loop.
nonisolated struct AXObserverRef: @unchecked Sendable {
    let observer: AXObserver
}

/// Every Accessibility call the anchor makes, off the main thread on one utility queue, each with
/// a quarter-second timeout: an app that hangs holds up this queue for that long, never the island.
actor AXWorker {
    static let shared = AXWorker()

    static let timeout: Float = 0.25

    private let queue = DispatchSerialQueue(label: "notchisland.anchor.ax", qos: .utility)
    nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    private typealias GetWindow = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
    /// `_AXUIElementGetWindow`: the window server's id of an element. Private, so looked up by
    /// name; without it the window is matched by its owner and bounds.
    private static let getWindow: GetWindow? = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementGetWindow")
        .map { unsafeBitCast($0, to: GetWindow.self) }

    // MARK: Reading

    private func copy(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    private func frame(_ element: AXUIElement) -> CGRect? {
        guard let position = copy(element, kAXPositionAttribute), let size = copy(element, kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero, extent = CGSize.zero
        AXValueGetValue(position as! AXValue, .cgPoint, &origin)
        AXValueGetValue(size as! AXValue, .cgSize, &extent)
        return CGRect(origin: origin, size: extent)
    }

    private func application(_ pid: pid_t) -> AXUIElement {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, Self.timeout)
        return app
    }

    private func windowID(_ element: AXUIElement, pid: pid_t, frame: CGRect) -> CGWindowID? {
        var id: CGWindowID = 0
        if let getWindow = Self.getWindow, getWindow(element, &id) == .success, id != 0 { return id }
        return Self.serverWindows().first { $0.pid == pid && Self.near($0.frame, frame) }?.id
    }

    private func describe(_ element: AXUIElement, pid: pid_t, bundleID: String?) -> Result<AnchorWindow, AnchorRefusal> {
        guard let frame = frame(element) else { return .failure(.noWindow) }
        guard copy(element, kAXSubroleAttribute) as? String == kAXStandardWindowSubrole as String else { return .failure(.notStandard) }
        if copy(element, "AXFullScreen") as? Bool == true { return .failure(.fullScreen) }
        return .success(AnchorWindow(ref: AXWindowRef(element: element), pid: pid, bundleID: bundleID,
                                     windowID: windowID(element, pid: pid, frame: frame), frame: frame))
    }

    /// The app's window in front: the focused one, else the main one.
    func frontWindow(pid: pid_t, bundleID: String?) -> Result<AnchorWindow, AnchorRefusal> {
        let app = application(pid)
        let window = copy(app, kAXFocusedWindowAttribute) ?? copy(app, kAXMainWindowAttribute)
        guard let window, CFGetTypeID(window) == AXUIElementGetTypeID() else { return .failure(.noWindow) }
        return describe(window as! AXUIElement, pid: pid, bundleID: bundleID)
    }

    /// The Accessibility window behind a window-server one: by its id, else by its bounds.
    func window(matching server: ServerWindow, bundleID: String?) -> Result<AnchorWindow, AnchorRefusal> {
        let windows = copy(application(server.pid), kAXWindowsAttribute) as? [AXUIElement] ?? []
        var byFrame: AXUIElement?
        for window in windows {
            var id: CGWindowID = 0
            if let getWindow = Self.getWindow, getWindow(window, &id) == .success, id == server.id {
                return describe(window, pid: server.pid, bundleID: bundleID)
            }
            if byFrame == nil, let frame = frame(window), Self.near(frame, server.frame) { byFrame = window }
        }
        guard let byFrame else { return .failure(.noWindow) }
        return describe(byFrame, pid: server.pid, bundleID: bundleID)
    }

    func frame(of window: AXWindowRef) -> CGRect? { frame(window.element) }

    /// Full screen, minimised: what the window is doing besides being somewhere.
    func condition(of window: AXWindowRef) -> (fullScreen: Bool, minimized: Bool) {
        (copy(window.element, "AXFullScreen") as? Bool ?? false, copy(window.element, kAXMinimizedAttribute) as? Bool ?? false)
    }

    // MARK: Placing

    /// Puts the window at `frame` and returns where the app let it be. The position goes first (a
    /// size is cut to what fits from where the window is), then the size, then the position again
    /// (a window grown from the old place can have been pushed).
    func place(_ window: AXWindowRef, at frame: CGRect) -> CGRect? {
        var origin = frame.origin, size = frame.size
        guard let position = AXValueCreate(.cgPoint, &origin), let extent = AXValueCreate(.cgSize, &size) else { return nil }
        AXUIElementSetAttributeValue(window.element, kAXPositionAttribute as CFString, position)
        AXUIElementSetAttributeValue(window.element, kAXSizeAttribute as CFString, extent)
        AXUIElementSetAttributeValue(window.element, kAXPositionAttribute as CFString, position)
        return self.frame(window.element)
    }

    /// Only moves it (a snap back, the accepted size centred).
    func move(_ window: AXWindowRef, to origin: CGPoint) -> CGRect? {
        var origin = origin
        guard let position = AXValueCreate(.cgPoint, &origin) else { return nil }
        AXUIElementSetAttributeValue(window.element, kAXPositionAttribute as CFString, position)
        return frame(window.element)
    }

    /// Puts the app in front through Accessibility: works from an app that is not active itself
    /// (macOS 14's cooperative activation ignores `NSRunningApplication.activate` from one).
    func makeFrontmost(pid: pid_t) {
        AXUIElementSetAttributeValue(application(pid), kAXFrontmostAttribute as CFString, kCFBooleanTrue)
    }

    /// Brings the window to the front of its app (the app itself is activated by the caller).
    func raise(_ window: AXWindowRef) {
        AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(window.element, kAXMainAttribute as CFString, kCFBooleanTrue)
    }

    // MARK: Observing

    /// What the anchor hears about a held window, and about its app.
    static let windowNotifications = [kAXMovedNotification, kAXResizedNotification, kAXUIElementDestroyedNotification,
                                      kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification]
    static let applicationNotifications = [kAXApplicationHiddenNotification, kAXApplicationShownNotification,
                                           kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification]
    /// What the cover watch hears from the app in front: its windows coming, going and moving.
    static let coverNotifications = [kAXWindowMovedNotification, kAXWindowResizedNotification, kAXWindowCreatedNotification,
                                     kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification,
                                     kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification]

    /// One observer on the window's app: the window's own notifications, and the app's. It
    /// delivers on the main run loop to `callback`, with `context` as its refcon.
    func observe(_ window: AXWindowRef, pid: pid_t, callback: AXObserverCallback, context: UnsafeMutableRawPointer) -> AXObserverRef? {
        var observer: AXObserver?
        guard AXObserverCreate(pid, callback, &observer) == .success, let observer else { return nil }
        for name in Self.windowNotifications { AXObserverAddNotification(observer, window.element, name as CFString, context) }
        let app = application(pid)
        for name in Self.applicationNotifications { AXObserverAddNotification(observer, app, name as CFString, context) }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        return AXObserverRef(observer: observer)
    }

    /// An observer on an app's windows as a whole (the cover watch).
    func observeWindows(pid: pid_t, callback: AXObserverCallback, context: UnsafeMutableRawPointer) -> AXObserverRef? {
        var observer: AXObserver?
        guard AXObserverCreate(pid, callback, &observer) == .success, let observer else { return nil }
        let app = application(pid)
        for name in Self.coverNotifications { AXObserverAddNotification(observer, app, name as CFString, context) }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        return AXObserverRef(observer: observer)
    }

    func stop(_ observer: AXObserverRef) {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer.observer), .commonModes)
    }

    // MARK: The window server's list

    /// Two frames of one window, read a moment apart or by two services.
    static func near(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= 2 && abs(a.minY - b.minY) <= 2 && abs(a.width - b.width) <= 2 && abs(a.height - b.height) <= 2
    }

    private static func serverWindow(_ info: [String: Any]) -> ServerWindow? {
        guard info[kCGWindowLayer as String] as? Int == 0, let id = info[kCGWindowNumber as String] as? CGWindowID,
              let pid = info[kCGWindowOwnerPID as String] as? pid_t, let bounds = info[kCGWindowBounds as String] as? NSDictionary,
              let frame = CGRect(dictionaryRepresentation: bounds), (info[kCGWindowAlpha as String] as? Double ?? 1) > 0.01 else { return nil }
        return ServerWindow(id: id, pid: pid, frame: frame)
    }

    /// The ordinary windows on screen, front to back.
    static func serverWindows() -> [ServerWindow] {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return list.compactMap(serverWindow)
    }

    /// The ordinary window in front of everyone's but ours.
    func topWindow(excluding own: pid_t) -> ServerWindow? {
        Self.serverWindows().first { $0.pid != own }
    }

    /// The ordinary window under a point that is not one of ours.
    func windowUnder(_ point: CGPoint, excluding own: pid_t) -> ServerWindow? {
        Self.serverWindows().first { $0.frame.contains(point) }.flatMap { $0.pid == own ? nil : $0 }
    }

    func frame(ofServerWindow id: CGWindowID) -> CGRect? {
        let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]] ?? []
        return list.first.flatMap { $0[kCGWindowBounds as String] as? NSDictionary }.flatMap { CGRect(dictionaryRepresentation: $0) }
    }

    /// The share of the window's area under the ordinary windows in front of it (ours left out:
    /// the island and the live copy lie over it on purpose), and whether it is on this space at all.
    ///
    /// A window completely under others drops out of the window server's on-screen list, just as
    /// one on another space does; the app's own window list (current space only) tells them apart:
    /// still in it, the window is entirely covered.
    func cover(of id: CGWindowID, window: AXWindowRef, pid: pid_t, own: pid_t) -> (share: Double, onScreen: Bool) {
        let info = (CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]] ?? []).first
        guard let info, let frame = (info[kCGWindowBounds as String] as? NSDictionary).flatMap({ CGRect(dictionaryRepresentation: $0) }) else { return (0, false) }
        guard info[kCGWindowIsOnscreen as String] as? Bool == true else {
            let here = (copy(application(pid), kAXWindowsAttribute) as? [AXUIElement] ?? []).contains { CFEqual($0, window.element) }
            let minimized = copy(window.element, kAXMinimizedAttribute) as? Bool ?? false
            return here && !minimized ? (1, true) : (0, false)
        }
        let onScreen = true
        let above = (CGWindowListCopyWindowInfo([.optionOnScreenAboveWindow, .excludeDesktopElements], id) as? [[String: Any]] ?? [])
            .compactMap(Self.serverWindow).filter { $0.pid != own }
        return (CoverState.share(of: frame, under: above.map(\.frame)), onScreen)
    }
}
