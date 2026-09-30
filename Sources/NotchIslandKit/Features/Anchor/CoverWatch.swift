import AppKit
import ApplicationServices

/// Whether other windows lie over the anchored one. Never polled: the window list is read (off the
/// main thread) only when an app comes to the front, the space changes (and twice more while the
/// switch settles), or the app in front moves, opens or closes a window — one `AXObserver` on that
/// app, replaced when another comes forward. Nothing of it exists while no window is anchored.
@MainActor final class CoverWatch {
    /// The answer changed: covered or not, and whether the window is on this space at all.
    var onChange: ((_ covered: Bool, _ onScreen: Bool) -> Void)?

    private(set) var isCovered = false
    private(set) var isOnScreen = true

    /// When the list is read again after a space switch (it animates for about half a second).
    static let settleReads: [TimeInterval] = [0.3, 0.7]
    /// A burst of notices (a window dragged across) is read once per this long.
    static let coalesce: TimeInterval = 0.1

    private var windowID: CGWindowID?
    private var window: AnchorWindow?
    private var state = CoverState()
    private var tokens: [any NSObjectProtocol] = []
    private var observer: AXObserverRef?
    private var observedPID: pid_t?
    private var generation = 0
    private let pending = DelayedAction()
    private var settles: [DelayedAction] = []
    private var isReading = false
    private var needsRead = false

    /// Follows this window (nil: stops, and forgets).
    func follow(_ window: AnchorWindow?) {
        guard window?.windowID != self.windowID else {
            self.window = window
            if window != nil { check() }
            return
        }
        stop()
        self.windowID = window?.windowID
        self.window = window
        guard windowID != nil else { return }
        let center = NSWorkspace.shared.notificationCenter
        tokens.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.observeFrontApp()
                self?.check()
            }
        })
        tokens.append(center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.spaceChanged() }
        })
        observeFrontApp()
        check()
    }

    private func stop() {
        generation += 1
        let center = NSWorkspace.shared.notificationCenter
        for token in tokens { center.removeObserver(token) }
        tokens.removeAll()
        pending.cancel()
        settles.forEach { $0.cancel() }
        settles.removeAll()
        if let observer { Task { await AXWorker.shared.stop(observer) } }
        observer = nil
        observedPID = nil
        windowID = nil
        window = nil
        state.reset()
        isCovered = false
        isOnScreen = true
        needsRead = false
    }

    private func spaceChanged() {
        check()
        settles.forEach { $0.cancel() }
        settles = Self.settleReads.map { delay in
            let action = DelayedAction()
            action.schedule(after: delay) { [weak self] in self?.check() }
            return action
        }
    }

    /// One observer on the app in front: its windows are the ones that come to lie over ours.
    private func observeFrontApp() {
        guard windowID != nil, let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != getpid(),
              front.processIdentifier != observedPID else { return }
        if let observer { Task { await AXWorker.shared.stop(observer) } }
        observer = nil
        observedPID = front.processIdentifier
        let generation = generation
        let pid = front.processIdentifier
        let bits = UInt(bitPattern: Unmanaged.passUnretained(self).toOpaque())
        Task { [weak self] in
            let observer = await AXWorker.shared.observeWindows(pid: pid, callback: coverObserverCallback, context: UnsafeMutableRawPointer(bitPattern: bits)!)
            guard let self, self.generation == generation, self.observedPID == pid else {
                if let observer { await AXWorker.shared.stop(observer) }
                return
            }
            self.observer = observer
        }
    }

    /// A window of the app in front moved, came or went.
    fileprivate func noticed() {
        guard windowID != nil, !pending.isPending else { return }
        pending.schedule(after: Self.coalesce) { [weak self] in self?.check() }
    }

    /// Reads what lies over the window now.
    func check() {
        guard let windowID, let window else { return }
        guard !isReading else {
            needsRead = true
            return
        }
        isReading = true
        let generation = generation
        Task { [weak self] in
            let cover = await AXWorker.shared.cover(of: windowID, window: window.ref, pid: window.pid, own: getpid())
            guard let self else { return }
            self.isReading = false
            guard self.generation == generation else { return }
            let changed = self.state.update(share: cover.share)
            if changed || cover.onScreen != self.isOnScreen {
                self.isCovered = self.state.isCovered
                self.isOnScreen = cover.onScreen
                Log.anchor.info("cover: \(self.isCovered ? "covered" : "clear", privacy: .public) (\(Int(cover.share * 100), privacy: .public) %), on screen \(cover.onScreen, privacy: .public)")
                self.onChange?(self.isCovered, self.isOnScreen)
            }
            if self.needsRead {
                self.needsRead = false
                self.check()
            }
        }
    }
}

nonisolated private func coverObserverCallback(_ observer: AXObserver, _ element: AXUIElement, _ notification: CFString,
                                               _ context: UnsafeMutableRawPointer?) {
    let bits = UInt(bitPattern: context)
    MainActor.assumeIsolated {
        guard let pointer = UnsafeMutableRawPointer(bitPattern: bits) else { return }
        Unmanaged<CoverWatch>.fromOpaque(pointer).takeUnretainedValue().noticed()
    }
}
