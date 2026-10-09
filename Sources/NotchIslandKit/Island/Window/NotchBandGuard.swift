import AppKit
import Synchronization

/// Keeps a full-screen app's menu bar out of sight while the pointer goes into the notch.
///
/// On a notched screen, the menu bar of a full-screen app is revealed as soon as the pointer enters
/// the menu-bar band (29 pt on a 28-pt notch: 28 and 29 pt from the top reveal it, 30 does not),
/// and nothing outside the active app can stop that: `.hideMenuBar` works only for the app in
/// front, and an agent app cannot take the front (neither `activate()` nor Accessibility gives it
/// the focus), which would steal it from the video anyway. So the band is covered instead: while
/// the pointer is near the notch in full screen, a black strip — the band's own colour there — lies
/// over the whole band, above the menu bar and below the island. The pointer is never held.
///
/// When the strip goes (`BandCoverPolicy`): only once the pointer is back out of the zone below the
/// band and the island is closed, or when the pointer has been in the band far from the notch for a moment — the
/// user going to the menu bar on purpose. Never on a timer while the pointer is still in the band.
///
/// Runs only while a full-screen window is on a physical notch screen and the menu bar hides in
/// full screen: a global pointer monitor (the panel is never key, so it receives no moves of its
/// own) that checks one precomputed rectangle per move.
@MainActor final class NotchBandGuard {
    /// The screen the island is on, and whether its notch is physical.
    var screen: () -> NSScreen? = { nil }
    /// The notch in global AppKit coordinates.
    var notchRect: () -> CGRect? = { nil }
    /// Whether the island is open (the strip stays while it is).
    var isIslandOpen: () -> Bool = { false }
    /// A click landed on the strip: our own window, so the assistant's outside-click monitor (a
    /// global one) never sees it.
    var coverClicked: () -> Void = {}

    private var monitors: [Any] = []
    /// The moves from other apps, off the main thread (nil: a global event monitor has them).
    private var pointerWatch: BandPointerWatch?
    private var cover: BandCoverPanel?
    private var geometry: BandCoverPolicy.Geometry?
    private var state = BandCoverPolicy.State()
    private let tick = DelayedAction()

    var isActive: Bool { !monitors.isEmpty }

    func setActive(_ active: Bool) {
        if active, monitors.isEmpty {
            let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
            // The moves everywhere else come through a listen-only tap on a thread of its own, which
            // wakes the main thread only near the notch or in the band (`BandPointerWatch`). A global
            // monitor ran a whole main run-loop turn (a Core Animation commit included) for every
            // move anywhere on the screen while a full-screen app was up: Energy Impact ~6.5 for as
            // long as the mouse moved (measured).
            let watch = BandPointerWatch { [weak self] in self?.update() }
            if watch.start() {
                pointerWatch = watch
                monitors.append(watch)
            } else if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
                self?.update()
            }) {
                monitors.append(global)
            }
            if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
                self?.update()
                return event
            }) {
                monitors.append(local)
            }
            invalidateGeometry()
            // The pointer may already be at the notch (a swipe into a full-screen space).
            update()
            Log.window.notice("menu-bar guard on\(self.pointerWatch == nil ? " (event monitor)" : "", privacy: .public)")
        } else if !active, !monitors.isEmpty {
            for monitor in monitors where !(monitor is BandPointerWatch) { NSEvent.removeMonitor(monitor) }
            monitors.removeAll()
            pointerWatch?.stop()
            pointerWatch = nil
            tick.cancel()
            state = BandCoverPolicy.State()
            setCovered(false, at: NSEvent.mouseLocation, reason: "guard off")
            Log.window.notice("menu-bar guard off")
        }
    }

    /// The island, the notch or the screen changed: recompute the zone and judge again. A strip
    /// already up follows the new band (it only moves when it is shown), and goes with the screen.
    func islandChanged() {
        guard isActive else { return }
        invalidateGeometry()
        guard let geometry else {
            tick.cancel()
            state = BandCoverPolicy.State()
            setCovered(false, at: NSEvent.mouseLocation, reason: "no screen")
            return
        }
        if let cover, cover.isVisible, cover.frame != geometry.bandRect {
            cover.setFrame(geometry.bandRect, display: true)
        }
        update()
    }

    isolated deinit {
        for monitor in monitors where !(monitor is BandPointerWatch) { NSEvent.removeMonitor(monitor) }
        pointerWatch?.stop()
    }

    private func invalidateGeometry() {
        guard let screen = screen(), let notch = notchRect() else {
            geometry = nil
            pointerWatch?.watch(nil, everywhere: true)
            return
        }
        let geometry = BandCoverPolicy.Geometry(
            screen: screen.frame,
            band: FullscreenMonitor.menuBarBand(of: screen) + 1,
            notch: notch
        )
        self.geometry = geometry
        watchPointer()
    }

    /// What the pointer watch must report: moves where the policy can change its mind (the zone, the
    /// band, a display above the band's x range), and every move while the strip is up or the menu
    /// bar is yielded (leaving those is decided anywhere).
    private func watchPointer() {
        guard let pointerWatch else { return }
        guard let geometry else {
            pointerWatch.watch(nil, everywhere: true)
            return
        }
        let zone = geometry.zone
        let band = geometry.bandRect
        // Up to the top of everything above the band: a display arranged over the notch screen.
        let interest = zone.union(band).union(CGRect(x: zone.minX, y: zone.maxY, width: zone.width, height: 100_000))
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? geometry.screen.maxY
        // CoreGraphics' global coordinates: the primary display's top-left origin, y down.
        let flipped = CGRect(x: interest.minX, y: primaryHeight - interest.maxY, width: interest.width, height: interest.height)
        pointerWatch.watch(flipped.insetBy(dx: -2, dy: -2), everywhere: state.covered || state.yielded)
    }

    /// Judges the pointer now, and again after the policy's hold time if it asked for one.
    private func update() {
        guard let geometry else { return }
        let pointer = NSEvent.mouseLocation
        let decision = BandCoverPolicy.decide(pointer: pointer, geometry: geometry, islandOpen: isIslandOpen(),
                                              state: &state, now: .now)
        setCovered(decision.covered, at: pointer, reason: decision.reason)
        watchPointer()
        if let recheck = decision.recheckAfter {
            tick.schedule(after: recheck) { [weak self] in self?.update() }
        } else {
            tick.cancel()
        }
    }

    private func setCovered(_ covered: Bool, at pointer: CGPoint, reason: String) {
        guard covered != (cover?.isVisible ?? false) else { return }
        if covered, let geometry {
            let panel = cover ?? BandCoverPanel()
            panel.onMouseDown = { [weak self] in self?.coverClicked() }
            cover = panel
            panel.setFrame(geometry.bandRect, display: true)
            panel.orderFrontRegardless()
        } else {
            cover?.orderOut(nil)
        }
        Log.window.notice("menu-bar band \(covered ? "covered" : "uncovered", privacy: .public) at \(Int(pointer.x), privacy: .public),\(Int(pointer.y), privacy: .public) (\(reason, privacy: .public))")
    }
}

/// The pointer's moves for `NotchBandGuard`, from a listen-only event tap on a thread of its own: the
/// main thread hears of a move only inside `region` (CoreGraphics global coordinates), when the
/// pointer has just left it, or with `everywhere`, and then once per turn however many moves came.
/// A listen-only tap delays no event; it needs no permission for mouse moves.
nonisolated final class BandPointerWatch: @unchecked Sendable {
    private struct Shared {
        var region: CGRect?
        var everywhere = true
        var wasInside = false
        var pending = false
    }

    private let shared = Mutex(Shared())
    private let onMove: @MainActor () -> Void
    private var port: CFMachPort?
    private var runLoop: CFRunLoop?
    private var thread: Thread?

    init(onMove: @escaping @MainActor () -> Void) {
        self.onMove = onMove
    }

    /// Starts the tap and its thread; false if the system refused the tap.
    func start() -> Bool {
        let ready = DispatchSemaphore(value: 0)
        var started = false
        let thread = Thread { [self] in
            let mask = (1 << CGEventType.mouseMoved.rawValue) | (1 << CGEventType.leftMouseDragged.rawValue)
                | (1 << CGEventType.rightMouseDragged.rawValue) | (1 << CGEventType.otherMouseDragged.rawValue)
            guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
                                               eventsOfInterest: CGEventMask(mask), callback: bandPointerTapCallback,
                                               userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
                ready.signal()
                return
            }
            let source = CFMachPortCreateRunLoopSource(nil, port, 0)
            let loop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(loop, source, .commonModes)
            self.port = port
            self.runLoop = loop
            started = true
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "com.davidvarga.notchisland.band-pointer"
        thread.qualityOfService = .utility
        self.thread = thread
        thread.start()
        ready.wait()
        return started
    }

    func stop() {
        if let port { CGEvent.tapEnable(tap: port, enable: false); CFMachPortInvalidate(port) }
        if let runLoop { CFRunLoopStop(runLoop) }
        port = nil
        runLoop = nil
        thread = nil
    }

    func watch(_ region: CGRect?, everywhere: Bool) {
        shared.withLock {
            $0.region = region
            $0.everywhere = everywhere || region == nil
        }
    }

    fileprivate func received(_ type: CGEventType, _ event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            return
        }
        let location = event.location
        let forward = shared.withLock { state -> Bool in
            let inside = state.region?.contains(location) ?? true
            let wanted = state.everywhere || inside || state.wasInside
            state.wasInside = inside
            guard wanted, !state.pending else { return false }
            state.pending = true
            return true
        }
        guard forward else { return }
        DispatchQueue.main.async { [self] in
            shared.withLock { $0.pending = false }
            MainActor.assumeIsolated { onMove() }
        }
    }
}

nonisolated private func bandPointerTapCallback(_ proxy: CGEventTapProxy, _ type: CGEventType, _ event: CGEvent,
                                                 _ userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if let userInfo {
        Unmanaged<BandPointerWatch>.fromOpaque(userInfo).takeUnretainedValue().received(type, event)
    }
    return Unmanaged.passUnretained(event)
}

/// When the band is covered. Pure, so the rules are testable without a screen.
nonisolated enum BandCoverPolicy {
    /// Beside the notch, the zone reaches this far on each side: just past the compact pill, so
    /// the menu bar stays reachable everywhere else (the user marked this width).
    static let sideMargin: CGFloat = 48
    /// How far below the band the zone begins, so the strip is up before the pointer gets there.
    static let approachDepth: CGFloat = 120
    /// The pointer must be this far below the band before the strip may go.
    static let releaseDepth: CGFloat = 12
    /// …and stay there this long (no flicker while it skims the edge).
    static let releaseHold: TimeInterval = 0.15
    /// In the band this far outside the zone for `menuHold`, the user is going to the menu bar.
    static let menuDistance: CGFloat = 120
    static let menuHold: TimeInterval = 0.5

    struct Geometry: Equatable {
        /// Global AppKit coordinates.
        let screen: CGRect
        /// Height of the covered band (the menu bar plus a point).
        let band: CGFloat
        let notch: CGRect

        var bandRect: CGRect {
            CGRect(x: screen.minX, y: screen.maxY - band, width: screen.width, height: band)
        }

        /// Around the notch, from `approachDepth` below the band up to the top of the screen.
        var zone: CGRect {
            let half = notch.width / 2 + BandCoverPolicy.sideMargin
            let bottom = bandRect.minY - BandCoverPolicy.approachDepth
            return CGRect(x: notch.midX - half, y: bottom, width: 2 * half, height: screen.maxY - bottom)
        }
    }

    struct State: Equatable {
        var covered = false
        /// Since when the pointer has been where the strip may go.
        var releasableSince: Date?
        /// Since when the pointer has been in the band far from the notch.
        var menuSince: Date?
        /// The user took the menu bar: stay uncovered until the pointer leaves the band.
        var yielded = false
    }

    struct Decision: Equatable {
        var covered: Bool
        var reason: String
        /// Judge again after this long even without a move (a hold is running).
        var recheckAfter: TimeInterval?
    }

    static func decide(pointer p: CGPoint, geometry g: Geometry, islandOpen: Bool, state: inout State, now: Date) -> Decision {
        let band = g.bandRect
        // On the notch screen only: a display arranged above shares its x range (and its y is above
        // this screen's top), and a pointer there is not in this menu bar.
        let inBand = p.y <= g.screen.maxY && p.y >= band.minY && p.x >= band.minX && p.x <= band.maxX
        let zone = g.zone
        let inZone = zone.contains(p) || (p.y >= zone.maxY && p.x >= zone.minX && p.x <= zone.maxX)

        // A menu bar the user went to on purpose stays usable until the pointer leaves the band, or
        // the zone just under it (the top of a menu opened from a title).
        if state.yielded {
            if inBand || inZone { return Decision(covered: false, reason: "menu bar in use") }
            state.yielded = false
        }

        if !state.covered {
            // Nothing to hide yet: cover as soon as the pointer is near the notch or the island is
            // open with the pointer anywhere around it.
            if inZone || (islandOpen && inBand) {
                state = State(covered: true)
                return Decision(covered: true, reason: islandOpen ? "island open" : "near the notch")
            }
            if inBand {
                // Reached the band away from the notch: the menu bar is out and the user is using it;
                // blacking it out when they slide along it would take it from under them.
                state.yielded = true
                return Decision(covered: false, reason: "menu bar in use")
            }
            return Decision(covered: false, reason: "away")
        }

        // Covered: in the band far from the notch for a moment → the user wants the menu bar.
        let farFromNotch = p.x < zone.minX - menuDistance || p.x > zone.maxX + menuDistance
        if inBand, farFromNotch, !islandOpen {
            let since = state.menuSince ?? now
            state.menuSince = since
            state.releasableSince = nil
            let held = now.timeIntervalSince(since)
            if held >= menuHold {
                state = State(covered: false, yielded: true)
                return Decision(covered: false, reason: "menu bar wanted")
            }
            return Decision(covered: true, reason: "far along the band", recheckAfter: menuHold - held)
        }
        state.menuSince = nil

        // Covered: the strip goes only with the island closed and the pointer out of the zone that
        // covered it (and well below the band), so a pointer lingering near the notch cannot drop and
        // re-cover it on every move. Off the notch screen (a display above) it may go too.
        let offScreen = p.y > g.screen.maxY && !inZone
        let releasable = offScreen || (!inZone && p.y < band.minY - releaseDepth)
        guard releasable, !islandOpen else {
            state.releasableSince = nil
            return Decision(covered: true, reason: islandOpen ? "island open" : (inBand ? "in the band" : "near the notch"))
        }
        let since = state.releasableSince ?? now
        state.releasableSince = since
        let held = now.timeIntervalSince(since)
        if held >= releaseHold {
            state = State()
            return Decision(covered: false, reason: "pointer left")
        }
        return Decision(covered: true, reason: "leaving", recheckAfter: releaseHold - held)
    }
}

/// Opaque black, above the menu bar (`.statusBar`) and below the island (`IslandPanel`'s level), on
/// every space including full-screen ones, never key, and never pushed below the menu bar.
private final class BandCoverPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        backgroundColor = .black
        isOpaque = true
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
    }

    var onMouseDown: (() -> Void)?

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        // Only a press on the strip itself: while the app is not active, a press in one of its
        // popovers over Settings can be handed to this window too (measured, Oct 2026).
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            if NSRect(origin: .zero, size: frame.size).contains(event.locationInWindow),
               frame.contains(NSEvent.mouseLocation) {
                onMouseDown?()
            }
        default: break
        }
        super.sendEvent(event)
    }

    /// AppKit would move a window in the menu-bar strip down below the menu bar.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}
