import AppKit
import ApplicationServices

/// A running app, or one of its windows (Windows, ⌘6).
nonisolated struct AssistantWindow: Hashable, Sendable, Identifiable {
    let pid: pid_t
    let appName: String
    /// The app's bundle, for its icon.
    let appPath: String
    /// The window's title; nil for the app itself (no titled window, or no Accessibility).
    var title: String?
    /// Its place in the app's Accessibility window list, to find it again when switching.
    var index = 0

    var id: String { "\(pid):\(index)" }
    var name: String { title ?? appName }
}

/// The running apps, and (for ⌘6 only) their windows' titles read through Accessibility (the
/// permission the island already has for the media keys). Read off the main thread, only while
/// Spotlight lists them, with a short timeout on every element asked so a hung app cannot hold
/// the list.
nonisolated enum RunningWindows {
    /// How long one app may take to answer.
    static let timeout: Float = 0.25

    /// Regular apps (not NotchIsland), the frontmost first as the screen stacks them; with `titles`,
    /// each as its titled windows, or as itself when it has none.
    @concurrent static func list(titles readsTitles: Bool) async -> [AssistantWindow] {
        let own = ProcessInfo.processInfo.processIdentifier
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != own && !$0.isTerminated
        }
        let order = stackingOrder()
        let sorted = apps.sorted { a, b in
            let oa = order[a.processIdentifier] ?? .max, ob = order[b.processIdentifier] ?? .max
            if oa != ob { return oa < ob }
            return (a.localizedName ?? "").localizedStandardCompare(b.localizedName ?? "") == .orderedAscending
        }
        let readsTitles = readsTitles && AXIsProcessTrusted()
        return sorted.flatMap { app -> [AssistantWindow] in
            let base = AssistantWindow(pid: app.processIdentifier, appName: app.localizedName ?? "",
                                       appPath: app.bundleURL?.path ?? "")
            let titled = readsTitles ? titles(of: app.processIdentifier) : []
            guard !titled.isEmpty else { return [base] }
            return titled.map { index, title in
                var window = base
                window.title = title
                window.index = index
                return window
            }
        }
    }

    /// The first on-screen window of each app, front to back (owners and layers need no
    /// permission, unlike titles).
    private static func stackingOrder() -> [pid_t: Int] {
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        var order: [pid_t: Int] = [:]
        for (position, window) in info.enumerated() where (window[kCGWindowLayer as String] as? Int) == 0 {
            guard let pid = window[kCGWindowOwnerPID as String] as? pid_t, order[pid] == nil else { continue }
            order[pid] = position
        }
        return order
    }

    private static func windows(of pid: pid_t) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, timeout)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        // Each element has its own timeout (the app's does not carry over to its windows).
        AXUIElementSetMessagingTimeout(element, timeout)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    /// The app's standard windows with a title (not its panels and sheets), by their place in its list.
    private static func titles(of pid: pid_t) -> [(Int, String)] {
        windows(of: pid).enumerated().compactMap { index, window in
            guard string(window, kAXSubroleAttribute) == kAXStandardWindowSubrole,
                  let title = string(window, kAXTitleAttribute), !title.isEmpty else { return nil }
            return (index, title)
        }
    }

    /// Activates the app, then raises the window (un-minimizing it) off the main thread.
    static func switchTo(_ window: AssistantWindow) {
        guard let app = NSRunningApplication(processIdentifier: window.pid) else { return }
        if app.isHidden { app.unhide() }
        // Spotlight is the active app until it closes, so it can hand the activation over.
        app.activate(from: .current)
        guard let title = window.title else { return }
        let pid = window.pid, index = window.index
        Task.detached(priority: .userInitiated) {
            let all = windows(of: pid)
            // The same place in the list, or the first window of that title if the list moved.
            let match = all.indices.contains(index) && string(all[index], kAXTitleAttribute) == title
                ? all[index] : all.first { string($0, kAXTitleAttribute) == title }
            guard let match else { return }
            AXUIElementSetAttributeValue(match, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            AXUIElementPerformAction(match, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(match, kAXMainAttribute as CFString, kCFBooleanTrue)
        }
    }
}
