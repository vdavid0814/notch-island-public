import AppKit

/// Apps whose playback only the system's Now Playing reports: browsers (YouTube and every other
/// web video or audio) and video players. Music and Spotify are not here: they broadcast their own
/// changes and are read by the scriptable source.
nonisolated enum SystemPlayers {
    static let bundleIDs: Set<String> = [
        // Browsers
        "com.apple.Safari",
        "com.apple.SafariTechnologyPreview",
        "com.google.Chrome",
        "com.google.Chrome.beta",
        "com.google.Chrome.dev",
        "com.google.Chrome.canary",
        "org.chromium.Chromium",
        "company.thebrowser.Browser",
        "company.thebrowser.dia",
        "org.mozilla.firefox",
        "org.mozilla.firefoxdeveloperedition",
        "com.microsoft.edgemac",
        "com.brave.Browser",
        "com.operasoftware.Opera",
        "com.vivaldi.Vivaldi",
        "com.kagi.kagimacOS",
        "app.zen-browser.zen",
        // Video and audio players that report to the system
        "com.apple.QuickTimePlayerX",
        "com.apple.TV",
        "com.apple.podcasts",
        "org.videolan.vlc",
        "com.colliderli.iina",
    ]

    /// Web apps saved from a browser ("Add to Dock") run under their own bundle IDs.
    static let bundlePrefixes = [
        "com.apple.Safari.WebApp.",
        "com.google.Chrome.app.",
        "com.microsoft.edgemac.app.",
        "com.brave.Browser.app.",
    ]

    /// Browsers (and web apps saved from them): a page in a background tab that has been paused for
    /// a few minutes is suspended by the browser and answers no Now Playing command until its window
    /// is brought forward (measured with YouTube in Safari: play, toggle, seek and the keyboard's
    /// play key all went unanswered after eight minutes).
    static let browserIDs: Set<String> = [
        "com.apple.Safari", "com.apple.SafariTechnologyPreview", "com.google.Chrome", "com.google.Chrome.beta",
        "com.google.Chrome.dev", "com.google.Chrome.canary", "org.chromium.Chromium", "company.thebrowser.Browser",
        "company.thebrowser.dia", "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition", "com.microsoft.edgemac",
        "com.brave.Browser", "com.operasoftware.Opera", "com.vivaldi.Vivaldi", "com.kagi.kagimacOS", "app.zen-browser.zen",
    ]

    static func isBrowser(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return browserIDs.contains(bundleID) || bundlePrefixes.contains { bundleID.hasPrefix($0) }
    }

    static func contains(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return bundleIDs.contains(bundleID) || bundlePrefixes.contains { bundleID.hasPrefix($0) }
    }
}

/// Tells whether any `SystemPlayers` app is running, from workspace launch and quit notifications:
/// no polling, nothing to do while no app launches or quits.
final class SystemPlayerWatcher {
    /// Called with the new answer whenever it changes.
    var onChange: ((Bool) -> Void)?

    private let relay = NotificationRelay()
    private var running: Set<pid_t> = []
    private var isStarted = false

    var isAnyRunning: Bool { !running.isEmpty }

    /// Idempotent. Returns the current answer.
    @discardableResult
    func start() -> Bool {
        guard !isStarted else { return isAnyRunning }
        isStarted = true
        let workspace = NSWorkspace.shared
        running = Set(workspace.runningApplications
            .filter { SystemPlayers.contains($0.bundleIdentifier) }
            .map(\.processIdentifier))
        relay.observe(NSWorkspace.didLaunchApplicationNotification, in: workspace.notificationCenter) { [weak self] in
            self?.update($0, launched: true)
        }
        relay.observe(NSWorkspace.didTerminateApplicationNotification, in: workspace.notificationCenter) { [weak self] in
            self?.update($0, launched: false)
        }
        return isAnyRunning
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        relay.removeAll()
        running.removeAll()
    }

    private func update(_ notification: Notification, launched: Bool) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              SystemPlayers.contains(app.bundleIdentifier) else { return }
        let before = isAnyRunning
        if launched {
            running.insert(app.processIdentifier)
        } else {
            running.remove(app.processIdentifier)
        }
        Log.media.info("\(app.bundleIdentifier ?? "?", privacy: .public) \(launched ? "opened" : "quit", privacy: .public)")
        if isAnyRunning != before { onChange?(isAnyRunning) }
    }
}
