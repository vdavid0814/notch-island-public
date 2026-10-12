import AppKit
import Observation

/// Whether the Mac is in Light or Dark Mode (System Settings ▸ Appearance). The island's own windows
/// are pinned to the dark appearance, so this is read from the system, not from a window.
@MainActor @Observable final class SystemAppearance {
    static let shared = SystemAppearance()

    private(set) var isDark: Bool
    /// The appearance the island's glass is drawn for while Settings' pictures are taken
    /// (`DemoDirector`): each picture's own desktop's, whatever this Mac's is. Nothing else follows it.
    var glassOverride: Bool?
    /// Whether the glass is drawn for Dark Mode (`IslandGlassStyle.plainTint`).
    var glassIsDark: Bool { glassOverride ?? isDark }

    /// The appearance last seen, kept between launches: a change made while the app was not
    /// running is followed too.
    nonisolated private static let lastKey = "ni2.lastAppearanceDark"

    @ObservationIgnored private var token: (any NSObjectProtocol)?

    private init() {
        isDark = Self.read()
        if let last = UserDefaults.standard.object(forKey: Self.lastKey) as? Bool, last != isDark { appearanceChanged() }
        UserDefaults.standard.set(isDark, forKey: Self.lastKey)
        token = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
                // The preference is written a moment after the notification at times.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self?.refresh() }
            }
        }
    }

    private func refresh() {
        let dark = Self.read()
        guard dark != isDark else { return }
        isDark = dark
        UserDefaults.standard.set(dark, forKey: Self.lastKey)
        appearanceChanged()
    }

    /// Settings' pictures of the island go with the Mac: over the dark default wallpaper in Dark
    /// Mode, the light one in Light Mode (whichever of the three was picked before, asked for).
    private func appearanceChanged() {
        let backdrop: DesktopBackdropStyle = isDark ? .system : .systemLight
        UserDefaults.standard.set(backdrop.rawValue, forKey: DesktopBackdropStyle.key)
    }

    private static func read() -> Bool {
        // For measuring and pictures only: `NI_APPEARANCE=light|dark` stands in for the system's.
        switch ProcessInfo.processInfo.environment["NI_APPEARANCE"] {
        case "light": return false
        case "dark": return true
        default: return UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        }
    }
}
