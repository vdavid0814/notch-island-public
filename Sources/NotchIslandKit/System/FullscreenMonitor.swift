import AppKit
import CoreGraphics

/// Which apps have a full-screen window (a native full-screen space, or a borderless window that
/// covers the screen) on the notch screen. The island steps aside only when one of them is the app
/// playing the current media — a video gone full screen — never for full-screen apps as such.
///
/// Event-driven: the window list is read only when the active space changes, an app activates or
/// quits, or the displays change, plus a few re-reads while a space switch settles. The read
/// (`CGWindowListCopyWindowInfo`: owners, layers and bounds only, no screen-recording permission)
/// runs off the main thread.
///
/// A read taken during a space-switch animation can miss a window that is there, so reads only
/// ever add apps at once; an app is removed only when two settled reads, a moment apart, agree it
/// is gone. (Publishing every read made the island flash its pill and restart the media-key tap on
/// each switch, and switched the menu-bar guard off for 0.7 s at a time.)
@Observable final class FullscreenMonitor {
    /// Bundle identifiers (or "pid:<n>" for apps without one) of the apps with a full-screen window
    /// on the notch screen.
    private(set) var fullscreenApps: Set<String> = []

    /// The screen to judge; set by the owner whenever the notch screen changes.
    @ObservationIgnored var screen: (() -> NSScreen?)?

    @ObservationIgnored private var observers: [(center: NotificationCenter, token: any NSObjectProtocol)] = []
    @ObservationIgnored private var recheck: Task<Void, Never>?
    @ObservationIgnored private var confirm: Task<Void, Never>?
    /// While a borderless full screen (a player covering a normal space) is up: nothing observable
    /// fires when it ends, so it is re-read now and then.
    @ObservationIgnored private var poll: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    /// A smaller set a settled read reported, waiting for a second read to agree.
    @ObservationIgnored private var pendingRemoval: Set<String>?

    /// When the window list is re-read after a space switch (cumulative, from the switch). A switch
    /// animates for about half a second; the later reads catch slow full-screen transitions.
    static let settleReads: [Duration] = [.milliseconds(300), .milliseconds(700), .milliseconds(1500), .seconds(3)]
    /// Gap before the read that confirms a removal.
    static let confirmDelay: Duration = .milliseconds(350)
    /// Re-read interval while only a borderless full screen is up.
    static let borderlessPoll: Duration = .seconds(2)

    var isRunning: Bool { !observers.isEmpty }

    /// Idempotent.
    func start() {
        guard observers.isEmpty else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        observe(NSWorkspace.activeSpaceDidChangeNotification, in: workspace, settles: true)
        observe(NSWorkspace.didActivateApplicationNotification, in: workspace, settles: false)
        observe(NSWorkspace.didTerminateApplicationNotification, in: workspace, settles: false)
        observe(NSApplication.didChangeScreenParametersNotification, in: .default, settles: true)
        evaluate(settled: true)
    }

    /// Idempotent. Reports "not full screen" once stopped.
    func stop() {
        for observer in observers { observer.center.removeObserver(observer.token) }
        observers.removeAll()
        recheck?.cancel()
        recheck = nil
        confirm?.cancel()
        confirm = nil
        poll?.cancel()
        poll = nil
        pendingRemoval = nil
        generation &+= 1
        if !fullscreenApps.isEmpty { fullscreenApps = [] }
    }

    private func observe(_ name: Notification.Name, in center: NotificationCenter, settles: Bool) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.changed(settles: settles) }
        }
        observers.append((center, token))
    }

    /// Re-reads now (and while things settle): the notch screen changed or became known.
    func refresh() {
        guard isRunning else { return }
        changed(settles: true)
    }

    /// `settles`: a space or screen change, which animates; an app activating or quitting does not,
    /// and gets one settled read only.
    private func changed(settles: Bool) {
        // A removal needs two settled reads after the latest change, not one from before it.
        confirm?.cancel()
        confirm = nil
        pendingRemoval = nil
        evaluate(settled: false)
        recheck?.cancel()
        let reads = settles ? Self.settleReads : [Self.settleReads[1]]
        recheck = Task { [weak self] in
            var elapsed: Duration = .zero
            for read in reads {
                try? await Task.sleep(for: read - elapsed, tolerance: .milliseconds(50))
                guard !Task.isCancelled else { return }
                elapsed = read
                self?.evaluate(settled: true)
            }
        }
    }

    private func evaluate(settled: Bool) {
        guard let screen = screen?() else {
            pendingRemoval = nil
            if !fullscreenApps.isEmpty { fullscreenApps = [] }
            return
        }
        generation &+= 1
        let generation = generation
        let region = Self.cgFrame(of: screen)
        let band = Self.menuBarBand(of: screen)
        let ownPID = ProcessInfo.processInfo.processIdentifier
        Task.detached(priority: .utility) { [weak self] in
            let windows = Self.onScreenWindows()
            let owners = Self.fullscreenOwners(windows, screen: region, band: band, excluding: ownPID)
            let borderless = !owners.isEmpty && !Self.isFullscreenSpace(windows, screen: region)
            await self?.apply(owners, generation: generation, settled: settled, borderless: borderless)
        }
    }

    private func apply(_ owners: Set<pid_t>, generation: Int, settled: Bool, borderless: Bool) {
        guard generation == self.generation, isRunning else { return }
        poll?.cancel()
        poll = nil
        if borderless {
            poll = Task { [weak self] in
                try? await Task.sleep(for: Self.borderlessPoll, tolerance: .milliseconds(500))
                guard !Task.isCancelled else { return }
                self?.evaluate(settled: true)
            }
        }
        // Processes without a bundle identifier still count (for the menu-bar guard); ones with no
        // running application at all (the window server) do not.
        let apps = Set(owners.compactMap { pid in
            NSRunningApplication(processIdentifier: pid).map { $0.bundleIdentifier ?? "pid:\(pid)" }
        })
        if apps.isSuperset(of: fullscreenApps) {
            pendingRemoval = nil
            publish(apps)
            return
        }
        // Something is gone. An unsettled read only contributes what it adds.
        guard settled else {
            publish(fullscreenApps.union(apps))
            return
        }
        if pendingRemoval == apps {
            pendingRemoval = nil
            publish(apps)
            return
        }
        // Additions count at once; only the removal waits for a second read to agree.
        publish(fullscreenApps.union(apps))
        pendingRemoval = apps
        confirm?.cancel()
        confirm = Task { [weak self] in
            try? await Task.sleep(for: Self.confirmDelay, tolerance: .milliseconds(50))
            guard !Task.isCancelled else { return }
            self?.evaluate(settled: true)
        }
    }

    private func publish(_ apps: Set<String>) {
        guard apps != fullscreenApps else { return }
        Log.window.notice("full-screen apps: \(apps.sorted().joined(separator: ", "), privacy: .public)")
        fullscreenApps = apps
    }

    // MARK: Pure parts

    nonisolated struct WindowInfo: Sendable, Equatable {
        var pid: pid_t
        var owner: String
        var layer: Int
        var alpha: Double
        /// CoreGraphics global coordinates (top-left origin).
        var bounds: CGRect
    }

    /// The owner of the window server's full-screen backdrop and wallpaper windows.
    nonisolated static let windowManager = "WindowManager"

    /// Owners of normal-layer, visible windows of other apps that cover the whole screen.
    ///
    /// A native full-screen window on a notched screen starts below the menu-bar band, and so does
    /// a zoomed window when the Dock hides: the two have the same bounds. What tells them apart is
    /// the window manager's full-screen backdrop, a second screen-sized window of its own behind
    /// the wallpaper-level ones, present only in a full-screen space. A window that covers the band
    /// too (a borderless full-screen player) counts without it.
    nonisolated static func fullscreenOwners(_ windows: [WindowInfo], screen: CGRect, band: CGFloat,
                                             excluding ownPID: pid_t) -> Set<pid_t> {
        let isFullscreenSpace = isFullscreenSpace(windows, screen: screen)
        return Set(windows.filter { window in
            guard window.pid != ownPID, window.layer == 0, window.alpha > 0.01 else { return false }
            if covers(window.bounds, screen, top: 0) { return true }
            return isFullscreenSpace && covers(window.bounds, screen, top: band)
        }.map(\.pid))
    }

    /// The window manager's full-screen backdrop is there: a second screen-sized window of its own
    /// behind the wallpaper-level ones, present only in a full-screen space.
    nonisolated static func isFullscreenSpace(_ windows: [WindowInfo], screen: CGRect) -> Bool {
        windows.filter { $0.owner == windowManager && $0.layer < 0 && covers($0.bounds, screen, top: 0) }.count >= 2
    }

    /// `bounds` spans the screen's width and height, allowing its top to start up to `top` lower.
    nonisolated static func covers(_ bounds: CGRect, _ screen: CGRect, top: CGFloat) -> Bool {
        bounds.minX <= screen.minX + 1 && bounds.maxX >= screen.maxX - 1
            && bounds.minY <= screen.minY + top + 1 && bounds.maxY >= screen.maxY - 1
    }

    nonisolated static func onScreenWindows() -> [WindowInfo] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
            as? [[String: Any]] else { return [] }
        return list.compactMap { info in
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict) else { return nil }
            let alpha = info[kCGWindowAlpha as String] as? Double ?? 1
            let owner = info[kCGWindowOwnerName as String] as? String ?? ""
            return WindowInfo(pid: pid, owner: owner, layer: layer, alpha: alpha, bounds: bounds)
        }
    }

    /// Height of the menu-bar band at the top of `screen`: the menu bar itself (29 pt on a 28-pt
    /// notch, measured), never less than the notch plus one point.
    static func menuBarBand(of screen: NSScreen) -> CGFloat {
        let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
        return max(menuBar, screen.safeAreaInsets.top + 1, NSStatusBar.system.thickness)
    }

    /// An `NSScreen` frame (bottom-left origin) in CoreGraphics global coordinates (top-left origin
    /// of the primary display).
    static func cgFrame(of screen: NSScreen) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
        let frame = screen.frame
        return CGRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height)
    }
}
