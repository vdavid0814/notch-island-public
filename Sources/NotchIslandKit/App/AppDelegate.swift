import AppKit

/// Application lifecycle for the agent app.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// SIGTERM (`kill`, `pkill`, a relaunch): quit as from the menu, so what waits to be written
    /// is written (the battery's last readings, a board change) and the run ends as a quit, not a
    /// crash. Killed outright, the battery history lost its readings since the last write and
    /// the next launch began with a gap.
    private var termination: (any DispatchSourceSignal)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // `LSUIElement` already makes the bundle an agent; setting the policy as well keeps the
        // raw binary (run from `.build` during development) out of the Dock and the app switcher.
        NSApp.setActivationPolicy(.accessory)
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { NSApp.terminate(nil) }
        source.resume()
        termination = source
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
        AppModel.shared.showSettings()
        return false
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
