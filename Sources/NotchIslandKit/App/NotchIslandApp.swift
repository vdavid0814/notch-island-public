import AppKit
import SwiftUI

/// The app: a menu bar extra and nothing else. The island is an AppKit panel owned by the window
/// controller (SwiftUI scenes cannot sit in the menu-bar strip), and Settings is an `NSWindow` so
/// it can be opened from the island, the menu, a URL or a Finder re-open alike.
public struct NotchIslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Bindable private var preferences = AppModel.shared.preferences

    public init() {}

    public var body: some Scene {
        MenuBarExtra("NotchIsland", systemImage: Self.menuBarSymbol, isInserted: $preferences.showMenuBarIcon) {
            MenuBarMenu()
                .environment(AppModel.shared)
        }
        .menuBarExtraStyle(.menu)
    }

    /// A pill hugging the top edge — the island itself. Resolved once with a fallback because SF
    /// Symbol availability follows the OS, not the SDK the app was built with.
    private static let menuBarSymbol: String = {
        let preferred = "capsule.tophalf.filled"
        let fallback = "rectangle.topthird.inset.filled"
        return NSImage(systemSymbolName: preferred, accessibilityDescription: nil) != nil ? preferred : fallback
    }()
}
