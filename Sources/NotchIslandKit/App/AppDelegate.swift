import AppKit

/// Application lifecycle for the agent app.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// SIGTERM (`kill`, `pkill`, a relaunch): quit as from the menu, so what waits to be written
    /// is written (the battery's last readings, a board change) and the run ends as a quit, not a
    /// crash. Killed outright, the battery history lost its readings since the last write and
    /// the next launch began with a gap.
    private var termination: (any DispatchSourceSignal)?
    private var activations: (any NSObjectProtocol)?
    /// The last app in front other than NotchIsland.
    private var lastOtherFront: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // `LSUIElement` already makes the bundle an agent; setting the policy as well keeps the
        // raw binary (run from `.build` during development) out of the Dock and the app switcher.
        NSApp.setActivationPolicy(.accessory)
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { NSApp.terminate(nil) }
        source.resume()
        termination = source
        // The app in front before NotchIsland (`applicationShouldHandleReopen`).
        activations = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier,
                  app != Bundle.main.bundleIdentifier else { return }
            MainActor.assumeIsolated { self?.lastOtherFront = app }
        }
        AppModel.shared.start()
    }

    /// `notchisland://…`. URLs that launch the app arrive before `applicationDidFinishLaunching`;
    /// `AppModel` queues them until it has started.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            PerfTrace.mark(url.absoluteString)
            guard let command = AppCommand.parse(url) else {
                Log.app.error("unrecognised URL: \(url.absoluteString, privacy: .public)")
                continue
            }
            PerfTrace.measure("perform") { AppModel.shared.perform(command) }
        }
    }

    /// Opening the app again from Finder, Spotlight or Launchpad shows Settings. With the menu bar
    /// icon hidden this is the way back in.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        let sender = Self.appleEventSender
        // A reopen that activates has already brought NotchIsland forward: the app it came over.
        let running = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let front = running == Bundle.main.bundleIdentifier ? lastOtherFront : running
        Log.app.notice("reopen from \(sender ?? "unknown", privacy: .public), in front \(front ?? "nothing", privacy: .public)")
        guard Self.reopenIsTheUsers(sender: sender, frontmost: front), !SiriHandoff.isSettling else { return false }
        AppModel.shared.showSettings()
        return false
    }

    /// Siri AI sends NotchIsland reopens of its own (opening a chat, closing its window), through
    /// helpers as well: not the user coming back to NotchIsland. With Siri AI in front only a
    /// launcher's reopen counts, whichever process the rest came from.
    nonisolated static func reopenIsTheUsers(sender: String?, frontmost: String?) -> Bool {
        if let sender, sender == "com.apple.campo" || sender.contains("Siri") { return false }
        guard frontmost == "com.apple.campo" else { return true }
        return ["com.apple.finder", "com.apple.dock", "com.apple.Spotlight"].contains(sender)
    }

    /// The process that sent the Apple event being handled: an app's bundle identifier, or the
    /// path of anything else (a helper is no app `NSRunningApplication` knows); nil once it is gone.
    private static var appleEventSender: String? {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              let pid = event.attributeDescriptor(forKeyword: keySenderPIDAttr)?.int32Value else { return nil }
        if let app = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier { return app }
        var path = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { return nil }
        return String(cString: path)
    }

    /// The app lives in the notch; closing Settings must not quit it.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        // A board change still waiting for its write (`WidgetStore.persistDelay`).
        AppModel.shared.boards.flush()
        AppModel.shared.stop()
    }
}
