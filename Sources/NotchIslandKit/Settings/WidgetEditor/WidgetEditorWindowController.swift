import AppKit
import SwiftUI

/// Hosts the widget editor (Customize Island) in its own window, built on demand and released when
/// it closes, like Settings.
@MainActor final class WidgetEditorWindowController: NSObject, NSWindowDelegate {
    nonisolated static let minimumSize = NSSize(width: 940, height: 660)
    nonisolated static let initialSize = NSSize(width: 1040, height: 720)
    nonisolated static let autosaveName = "NotchIsland.Customize"

    private let model: AppModel
    private var window: NSWindow?

    init(model: AppModel) {
        self.model = model
        super.init()
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let hosting = NSHostingController(rootView: WidgetEditorView().environment(model))
        hosting.sizingOptions = []
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.initialSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        window.contentViewController = hosting
        window.title = "Customize Island"
        window.titlebarAppearsTransparent = true
        // The island is always drawn on the dark appearance; so is its editor.
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentMinSize = Self.minimumSize
        window.setContentSize(Self.initialSize)
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
