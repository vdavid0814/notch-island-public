import AppKit

/// Application lifecycle for the agent app.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // `LSUIElement` already makes the bundle an agent; setting the policy as well keeps the
        // raw binary (run from `.build` during development) out of the Dock and the app switcher.
        NSApp.setActivationPolicy(.accessory)
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
