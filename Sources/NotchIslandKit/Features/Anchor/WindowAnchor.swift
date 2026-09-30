import AppKit
import ApplicationServices
import Observation

/// Window Anchor: holds another app's window centred under the notch. The window is put there
/// through Accessibility, watched by one `AXObserver` on its app, and put back when something
/// moves it; dragged well away (or zoomed, or closed) it is the user's again.
///
/// Off, it has no monitors, observers or timers. On, it listens to presses and releases on the
/// shared mouse hub (for dragging a window to the notch, and for knowing when a drag of the held
/// window ends); drag events are monitored only from a press until the gesture is decided, and
/// through a window drag. Every Accessibility call runs on `AXWorker`, never on the main thread.
@Observable final class WindowAnchor {
    /// The window held under the notch.
    nonisolated struct Held: Sendable, Equatable {
        var window: AnchorWindow
        /// Where it rests (what the app accepted, centred).
        var rest: CGRect
        /// How far its top is raised from the usual rest.
        var tuck: CGFloat
        var tuckLimit: CGFloat?
        /// Minimised, or its app hidden: left alone until it is back.
        var isDormant = false
    }

    /// A moved or resized window is looked at this long after the last notice of it.
    static let settleDelay: TimeInterval = 0.15

    private(set) var held: Held?
    /// A window is being dragged and the pointer is where letting go anchors it.
    private(set) var isTargeted = false

    var isAnchored: Bool { held != nil }

    /// The notch screen now; nil while there is none (the anchor is dormant then).
    @ObservationIgnored var screen: () -> AnchorScreen? = { nil }
    /// The size an anchored window is given on a screen (Settings ▸ Window Anchor).
    @ObservationIgnored var size: (AnchorScreen) -> CGSize = AnchorGeometry.defaultSize
    /// The held window's app opened, closed or focused a window (a sheet, a dialog).
    @ObservationIgnored var onAppWindowsChanged: (() -> Void)?
    /// The drop zone was entered or left (the island's banner).
    @ObservationIgnored var onTargeted: ((Bool) -> Void)?
    /// A window was taken or let go (the cover watch and the live copy follow it).
    @ObservationIgnored var onHeldChanged: ((Held?) -> Void)?
    /// For tests and the log: why nothing was anchored.
    @ObservationIgnored private(set) var lastRefusal: AnchorRefusal?

    @ObservationIgnored private var isEnabled = false
    @ObservationIgnored private var isDragEnabled = false
    @ObservationIgnored private var isPaused = false
    @ObservationIgnored private var memory = AnchorMemory.load()

    @ObservationIgnored private var token: GlobalMouseHub.Token?
    @ObservationIgnored private var dragMonitor: Any?
    @ObservationIgnored private var latch = WindowDragLatch()
    /// The window under the current press, as the window server had it then.
    @ObservationIgnored private var pressed: ServerWindow?
    /// The pressed window as Accessibility names it, once it turned out to be dragged and anchorable.
    @ObservationIgnored private var candidate: AnchorWindow?
    @ObservationIgnored private var pressGeneration = 0

    @ObservationIgnored private var observer: AXObserverRef?
    @ObservationIgnored private let settle = DelayedAction()
    /// The held window moved with the button down: decided when the button comes up.
    @ObservationIgnored private var awaitsMouseUp = false
    /// Bumped whenever the held window changes, so a read that was under way is dropped.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private let outline = AnchorOutline()

    init() {}

    // MARK: On and off

    /// The feature as a whole: off lets go of the window and removes every monitor and observer.
    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        if enabled {
            token = GlobalMouseHub.shared.add { [weak self] event, inOwnProcess in self?.handle(event, inOwnProcess: inOwnProcess) }
        } else {
            release(reason: "turned off")
            if let token { GlobalMouseHub.shared.remove(token) }
            token = nil
            endGesture()
        }
        Log.anchor.notice("anchor \(enabled ? "on" : "off", privacy: .public)")
    }

    /// Dragging a window to the notch anchors it.
    func setDragEnabled(_ enabled: Bool) {
        isDragEnabled = enabled
        if !enabled { endGesture() }
    }

    /// Asleep, locked, in a full-screen space or without the notch screen: the window is left
    /// alone, and looked at again afterwards.
    func setPaused(_ paused: Bool) {
        guard paused != isPaused else { return }
        isPaused = paused
        if paused {
            settle.cancel()
            endGesture()
        } else if held != nil {
            settle.schedule(after: Self.settleDelay) { [weak self] in self?.evaluate(byUser: false) }
        }
    }

    // MARK: Anchoring

    /// The window in front (menu, link, Spotlight).
    func anchorFront() {
        guard isEnabled else { return refused(.notTrusted) }
        guard !StageManager.isEnabled else { return refused(.stageManager) }
        let own = getpid()
        let front = NSWorkspace.shared.frontmostApplication
        Task { [weak self] in
            let result: Result<AnchorWindow, AnchorRefusal>
            if let front, front.processIdentifier != own {
                result = await AXWorker.shared.frontWindow(pid: front.processIdentifier, bundleID: front.bundleIdentifier)
            } else if let server = await AXWorker.shared.topWindow(excluding: own) {
                // The island has the keyboard (Spotlight): the window in front of everyone else's.
                result = await AXWorker.shared.window(matching: server, bundleID: Self.bundleID(of: server.pid))
            } else {
                result = .failure(.noWindow)
            }
            self?.anchor(result)
        }
    }

    /// One window of an app, by its window-server id (Spotlight's "Anchor this window").
    func anchor(_ server: ServerWindow) {
        guard isEnabled else { return refused(.notTrusted) }
        guard !StageManager.isEnabled else { return refused(.stageManager) }
        Task { [weak self] in
            self?.anchor(await AXWorker.shared.window(matching: server, bundleID: Self.bundleID(of: server.pid)))
        }
    }

    private func anchor(_ result: Result<AnchorWindow, AnchorRefusal>) {
        switch result {
        case .failure(let refusal):
            refused(refusal)
        case .success(let window):
            guard window.pid != getpid() else { return refused(.ownWindow) }
            guard let screen = screen(), !isPaused else { return refused(.noScreen) }
            hold(window, on: screen)
        }
    }

    private func hold(_ window: AnchorWindow, on screen: AnchorScreen) {
        if held != nil { release(reason: "another window") }
        let entry = window.bundleID.flatMap { memory[$0] }
        // The size set in Settings, for every app; right under the menu bar.
        let asked = AnchorGeometry.restFrame(screen, size: size(screen))
        generation += 1
        let generation = generation
        Task { [weak self] in
            guard let got = await AXWorker.shared.place(window.ref, at: asked) else {
                self?.refused(.noWindow)
                return
            }
            let adopted = AnchorGeometry.adopted(screen, asked: asked, got: got)
            var rest = got
            if abs(adopted.frame.minX - got.minX) > 0.5 {
                rest = await AXWorker.shared.move(window.ref, to: adopted.frame.origin) ?? adopted.frame
            }
            guard let self, self.generation == generation, self.isEnabled else { return }
            var window = window
            window.frame = rest
            let held = Held(window: window, rest: rest, tuck: adopted.tuck, tuckLimit: adopted.tuckLimit ?? entry?.tuckLimit.map { CGFloat($0) })
            self.held = held
            self.lastRefusal = nil
            self.remember(held)
            self.observe(held)
            Log.anchor.notice("anchored \(window.bundleID ?? "?", privacy: .public) at \(String(describing: rest), privacy: .public), tuck \(adopted.tuck, privacy: .public)")
            DiagnosticsFlow.record("anchor: held \(window.bundleID ?? "?")")
            self.onHeldChanged?(held)
        }
    }

    /// Lets go of the window; it stays where it is.
    func release(reason: String = "asked") {
        guard let held else { return }
        generation += 1
        settle.cancel()
        awaitsMouseUp = false
        stopObserving()
        self.held = nil
        Log.anchor.notice("released \(held.window.bundleID ?? "?", privacy: .public): \(reason, privacy: .public)")
        DiagnosticsFlow.record("anchor: released (\(reason))")
        onHeldChanged?(nil)
    }

    /// The held window and its app come to the front (the live copy was clicked).
    func bringForward() {
        guard let held else { return }
        NSRunningApplication(processIdentifier: held.window.pid)?.activate()
        Task { await AXWorker.shared.raise(held.window.ref) }
    }

    private func refused(_ refusal: AnchorRefusal) {
        lastRefusal = refusal
        Log.anchor.notice("not anchored: \(refusal.rawValue, privacy: .public)")
    }

    private func remember(_ held: Held) {
        guard let bundleID = held.window.bundleID else { return }
        memory.remember(.init(width: held.rest.width, height: held.rest.height, tuck: held.tuck, tuckLimit: held.tuckLimit.map(Double.init)),
                        for: bundleID)
        memory.save()
    }

    private static func bundleID(of pid: pid_t) -> String? {
        NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    }

    // MARK: Holding

    private func observe(_ held: Held) {
        stopObserving()
        let generation = generation
        let context = Unmanaged.passUnretained(self).toOpaque()
        let bits = UInt(bitPattern: context)
        Task { [weak self] in
            let observer = await AXWorker.shared.observe(held.window.ref, pid: held.window.pid, callback: anchorObserverCallback,
                                                         context: UnsafeMutableRawPointer(bitPattern: bits)!)
            guard let self, self.generation == generation else {
                if let observer { await AXWorker.shared.stop(observer) }
                return
            }
            self.observer = observer
        }
    }

    private func stopObserving() {
        guard let observer else { return }
        self.observer = nil
        Task { await AXWorker.shared.stop(observer) }
    }

    /// A notification about the held window or its app, on the main thread.
    fileprivate func received(_ name: String) {
        guard var held else { return }
        switch name {
        case kAXUIElementDestroyedNotification as String:
            release(reason: "window closed")
        case kAXWindowMiniaturizedNotification as String, kAXApplicationHiddenNotification as String:
            held.isDormant = true
            self.held = held
            settle.cancel()
            onHeldChanged?(held)
        case kAXWindowDeminiaturizedNotification as String, kAXApplicationShownNotification as String:
            held.isDormant = false
            self.held = held
            onHeldChanged?(held)
            settle.schedule(after: Self.settleDelay) { [weak self] in self?.evaluate(byUser: false) }
        case kAXMovedNotification as String, kAXResizedNotification as String:
            guard !held.isDormant, !isPaused else { return }
            if NSEvent.pressedMouseButtons & 1 != 0 {
                // The user has it: decided when the button comes up.
                awaitsMouseUp = true
                settle.cancel()
            } else if !awaitsMouseUp {
                settle.schedule(after: Self.settleDelay) { [weak self] in self?.evaluate(byUser: false) }
            }
        case kAXWindowCreatedNotification as String, kAXFocusedWindowChangedNotification as String:
            onAppWindowsChanged?()
        default:
            break
        }
    }

    /// The held window's app quit.
    func applicationTerminated(_ pid: pid_t) {
        if held?.window.pid == pid { release(reason: "app quit") }
    }

    /// Looks at where the held window is now and decides: put back, adopted at its new size, or let
    /// go. `byUser`: the user moved it with the mouse. `keeps`: it was dropped on the notch again.
    /// `dragged`: by its title bar (a drag that ends resized is a tile, not a resize).
    private func evaluate(byUser: Bool, keeps: Bool = false, dragged: Bool = false) {
        guard let held, !held.isDormant, !isPaused, let screen = screen() else { return }
        let generation = generation
        Task { [weak self] in
            let frame = await AXWorker.shared.frame(of: held.window.ref)
            let condition = await AXWorker.shared.condition(of: held.window.ref)
            guard let self, self.generation == generation, self.held == held else { return }
            guard let frame else { return self.release(reason: "window gone") }
            if condition.fullScreen { return self.release(reason: "full screen") }
            if condition.minimized {
                self.held?.isDormant = true
                return
            }
            let resized = abs(frame.width - held.rest.width) > 1 || abs(frame.height - held.rest.height) > 1
            let moved = abs(frame.minX - held.rest.minX) > 1 || abs(frame.minY - held.rest.minY) > 1
            if resized {
                if AnchorGeometry.fillsScreen(frame.size, screen: screen) { return self.release(reason: "zoomed") }
                if dragged, !keeps, AnchorGeometry.isReleased(frame, rest: held.rest) {
                    // Dragged away and resized on the way (a tile at the screen's edge): the user's again.
                    return self.release(reason: "dragged away")
                }
                let tuck = byUser ? AnchorGeometry.tuck(afterResizeTo: frame, screen: screen, limit: held.tuckLimit) : held.tuck
                let asked = AnchorGeometry.restFrame(screen, size: frame.size, tuck: tuck, tuckLimit: held.tuckLimit)
                guard let got = await AXWorker.shared.place(held.window.ref, at: asked) else { return }
                let adopted = AnchorGeometry.adopted(screen, asked: asked, got: got)
                var rest = got
                if abs(adopted.frame.minX - got.minX) > 0.5 {
                    rest = await AXWorker.shared.move(held.window.ref, to: adopted.frame.origin) ?? adopted.frame
                }
                guard self.generation == generation, var now = self.held else { return }
                now.rest = rest
                now.window.frame = rest
                now.tuck = adopted.tuck
                now.tuckLimit = adopted.tuckLimit ?? held.tuckLimit
                self.held = now
                self.remember(now)
                self.onHeldChanged?(now)
            } else if moved {
                if byUser, !keeps, AnchorGeometry.isReleased(frame, rest: held.rest) { return self.release(reason: "dragged away") }
                _ = await AXWorker.shared.move(held.window.ref, to: held.rest.origin)
            }
        }
    }

    // MARK: Dragging a window to the notch

    /// The pointer in the coordinates the window server uses (y down from the primary display's top).
    private static func pointer() -> CGPoint {
        let location = NSEvent.mouseLocation
        return CGPoint(x: location.x, y: (NSScreen.screens.first?.frame.maxY ?? 0) - location.y)
    }

    private func handle(_ event: NSEvent, inOwnProcess: Bool) {
        switch event.type {
        case .leftMouseDown:
            endGesture()
            guard isDragEnabled, !inOwnProcess, !isPaused, screen() != nil else { return }
            let point = Self.pointer()
            pressGeneration += 1
            let generation = pressGeneration
            latch.mouseDown(overWindow: true)
            setDragMonitor(installed: true)
            Task { [weak self] in
                let window = await AXWorker.shared.windowUnder(point, excluding: getpid())
                guard let self, self.pressGeneration == generation else { return }
                if let window {
                    self.pressed = window
                } else {
                    self.latch.mouseDown(overWindow: false)
                    self.setDragMonitor(installed: false)
                }
            }
        case .leftMouseUp:
            let wasDragging = latch.mouseUp()
            let targeted = isTargeted
            let pressed = pressed, candidate = candidate
            let awaited = awaitsMouseUp
            awaitsMouseUp = false
            endGesture()
            if wasDragging, let pressed, let held, held.window.windowID == pressed.id {
                // The held window itself: dropped on the notch it stays, however far its corner went.
                evaluate(byUser: true, keeps: targeted, dragged: true)
            } else if wasDragging, targeted, let candidate, let screen = screen() {
                hold(candidate, on: screen)
            } else if awaited {
                evaluate(byUser: true)
            }
        case .leftMouseDragged:
            dragged(event)
        default:
            break
        }
    }

    private func dragged(_ event: NSEvent) {
        if latch.isDragging {
            // One rectangle test per event.
            if let screen = screen(), candidate != nil {
                setTargeted(AnchorGeometry.dropZone(screen).contains(Self.pointer()))
            }
            return
        }
        guard latch.mouseDragged(at: event.timestamp) else { return }
        guard let pressed else {
            latch.lookFailed()
            return setDragMonitor(installed: false)
        }
        let generation = pressGeneration
        Task { [weak self] in
            let now = await AXWorker.shared.frame(ofServerWindow: pressed.id)
            guard let self, self.pressGeneration == generation else { return }
            if let now { self.latch.looked(atPress: pressed.frame, now: now) } else { self.latch.lookFailed() }
            if self.latch.isDragging {
                self.resolveCandidate(pressed, generation: generation)
            } else if !self.latch.isUndecided {
                self.setDragMonitor(installed: false)
            }
        }
    }

    /// The dragged window as Accessibility names it: only a window that can be anchored lights the
    /// notch (no sheet, no panel; nothing while Stage Manager arranges the windows).
    private func resolveCandidate(_ pressed: ServerWindow, generation: Int) {
        guard !StageManager.isEnabled else { return setDragMonitor(installed: false) }
        let bundleID = Self.bundleID(of: pressed.pid)
        Task { [weak self] in
            let result = await AXWorker.shared.window(matching: ServerWindow(id: pressed.id, pid: pressed.pid, frame: pressed.frame), bundleID: bundleID)
            guard let self, self.pressGeneration == generation, self.latch.isDragging else { return }
            switch result {
            case .success(let window):
                self.candidate = window
                if let screen = self.screen() { self.setTargeted(AnchorGeometry.dropZone(screen).contains(Self.pointer())) }
            case .failure:
                self.setDragMonitor(installed: false)
            }
        }
    }

    private func setTargeted(_ targeted: Bool) {
        guard targeted != isTargeted else { return }
        isTargeted = targeted
        if targeted, let screen = screen(), let candidate {
            let rest: CGRect = if let held, held.window.windowID == candidate.windowID { held.rest } else {
                AnchorGeometry.restFrame(screen, size: size(screen))
            }
            outline.show(rest)
        } else {
            outline.hide()
        }
        onTargeted?(targeted)
    }

    /// `demo/anchortarget`: the banner and the landing outline, as while a window is dragged there.
    func demoTarget(_ on: Bool) {
        guard let screen = screen() else { return }
        isTargeted = on
        if on { outline.show(AnchorGeometry.restFrame(screen, size: size(screen))) } else { outline.hide() }
        onTargeted?(on)
    }

    private func endGesture() {
        pressGeneration += 1
        latch = WindowDragLatch()
        pressed = nil
        candidate = nil
        setDragMonitor(installed: false)
        setTargeted(false)
    }

    /// Drag events from a press until the gesture is decided, and through a window drag; never
    /// otherwise (a text selection or a slider does not wake the app on every event of it).
    private func setDragMonitor(installed: Bool) {
        if installed, dragMonitor == nil {
            dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] event in
                self?.handle(event, inOwnProcess: false)
            }
        } else if !installed, let monitor = dragMonitor {
            NSEvent.removeMonitor(monitor)
            dragMonitor = nil
        }
    }

    /// For diagnostics.
    var diagnosticsSnapshot: String {
        "enabled \(isEnabled), drag \(isDragEnabled), paused \(isPaused), held \(held.map { "\($0.window.bundleID ?? "?") \($0.rest)" } ?? "none"), monitors \(dragMonitor != nil)"
    }
}

/// `AXObserver` delivers here, on the main run loop; the context is the anchor.
nonisolated private func anchorObserverCallback(_ observer: AXObserver, _ element: AXUIElement, _ notification: CFString,
                                                _ context: UnsafeMutableRawPointer?) {
    let name = notification as String
    let bits = UInt(bitPattern: context)
    MainActor.assumeIsolated {
        guard let pointer = UnsafeMutableRawPointer(bitPattern: bits) else { return }
        Unmanaged<WindowAnchor>.fromOpaque(pointer).takeUnretainedValue().received(name)
    }
}

/// Where a dragged window will land: a rounded outline, drawn once by the render server in a
/// panel that takes no clicks. Nothing of it exists while no window is dragged to the notch.
@MainActor final class AnchorOutline {
    static let radius: CGFloat = 14

    private var panel: NSPanel?
    private let hiding = DelayedAction()

    func show(_ rest: CGRect) {
        hiding.cancel()
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let frame = CGRect(x: rest.minX, y: top - rest.maxY, width: rest.width, height: rest.height).insetBy(dx: -4, dy: -4)
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.setFrame(frame, display: false)
        guard let layer = panel.contentView?.layer?.sublayers?.first as? CAShapeLayer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.frame = CGRect(origin: .zero, size: frame.size)
        layer.path = CGPath(roundedRect: layer.bounds.insetBy(dx: 4, dy: 4), cornerWidth: Self.radius, cornerHeight: Self.radius, transform: nil)
        CATransaction.commit()
        panel.orderFrontRegardless()
        fade(layer, to: 1)
    }

    func hide() {
        guard let panel, panel.isVisible, let layer = panel.contentView?.layer?.sublayers?.first as? CAShapeLayer else { return }
        fade(layer, to: 0)
        hiding.schedule(after: 0.22) { [weak self] in
            self?.panel?.orderOut(nil)
            self?.panel = nil
        }
    }

    private func fade(_ layer: CALayer, to opacity: Float) {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = layer.presentation()?.opacity ?? layer.opacity
        animation.toValue = opacity
        animation.duration = 0.18
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.opacity = opacity
        layer.add(animation, forKey: "opacity")
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        let view = NSView()
        view.wantsLayer = true
        let shape = CAShapeLayer()
        shape.fillColor = NSColor.white.withAlphaComponent(0.10).cgColor
        shape.strokeColor = NSColor.white.withAlphaComponent(0.85).cgColor
        shape.lineWidth = 2
        shape.opacity = 0
        view.layer?.addSublayer(shape)
        panel.contentView = view
        return panel
    }
}
