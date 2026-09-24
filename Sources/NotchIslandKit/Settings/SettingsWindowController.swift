import AppKit
import SwiftUI

/// Hosts `SettingsView` in a plain `NSWindow`.
///
/// Not a SwiftUI `Settings` scene: that scene can only be opened from inside SwiftUI (the
/// `openSettings` action), and here it must open from the island's gear, the menu, a URL and a
/// Finder re-open.
///
/// The window is built on demand and released when it closes. Settings is opened rarely, and a
/// hidden hosting view would keep its view graph in memory and keep re-evaluating it on every
/// observed change (battery level, shelf contents) for nothing. The frame autosave and the stored
/// section make a rebuilt window indistinguishable from a kept one.
@MainActor final class SettingsWindowController: NSObject, NSWindowDelegate {
    nonisolated static let minimumSize = NSSize(width: 680, height: 460)
    nonisolated static let initialSize = NSSize(width: 720, height: 520)
    nonisolated static let autosaveName = "NotchIsland.Settings"

    private let model: AppModel
    private var window: NSWindow?

    init(model: AppModel) {
        self.model = model
        super.init()
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        // An accessory app is never frontmost on its own; without activating first the window
        // would open behind the current app.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let hosting = NSHostingController(rootView: SettingsView().environment(model))
        // The window, not SwiftUI's ideal size, owns the frame (autosaved, user-resizable).
        hosting.sizingOptions = []
        // Lets the split view's toolbar and each section's navigation title reach the window.
        hosting.sceneBridgingOptions = [.toolbars, .title]

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.initialSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        window.contentViewController = hosting
        window.title = "NotchIsland Settings"
        window.toolbarStyle = .unified
        window.titlebarAppearsTransparent = false
        // Ownership stays with `self.window` (ARC); AppKit's release-on-close would double-free it.
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentMinSize = Self.minimumSize
        window.setContentSize(Self.initialSize)
        // Centre only the very first time; afterwards the saved frame wins.
        if !window.setFrameUsingName(Self.autosaveName) {
            window.center()
        }
        window.setFrameAutosaveName(Self.autosaveName)
        return window
    }

    func windowWillClose(_ notification: Notification) {
        window?.delegate = nil
        window = nil
    }
}
