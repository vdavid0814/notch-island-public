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
    /// Whether the glass is drawn for Dark Mode (`IslandGlassStyle.plainGlass`).
    var glassIsDark: Bool { glassOverride ?? isDark }

    /// The appearance last seen, kept between launches: a change made while the app was not
    /// running is followed too.
    nonisolated private static let lastKey = "ni2.lastAppearanceDark"

    /// Where the system's Liquid Glass slider stands: 0 (clear) … 1 (tinted), followed as it moves
    /// (System Settings ▸ Appearance ▸ Liquid Glass).
    private(set) var glassTint: Double

    @ObservationIgnored private var token: (any NSObjectProtocol)?
    @ObservationIgnored private var tintObserver: DefaultsObserver?

    private init() {
        isDark = Self.read()
        glassTint = Self.readTint()
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
        // The slider is kept in the global domain; defaults tell an observer of a change made
        // by another process too.
        tintObserver = DefaultsObserver(key: Self.tintKey) { [weak self] in
            guard let self else { return }
            let tint = Self.readTint()
            if tint != glassTint { glassTint = tint }
        }
    }

    nonisolated static let tintKey = "NSGlassTintAmount"

    private static func readTint() -> Double {
        // For measuring and pictures only: `NI_GLASS_TINT=0…1` stands in for the system's slider.
        let tint = ProcessInfo.processInfo.environment["NI_GLASS_TINT"].flatMap(Double.init)
            ?? UserDefaults.standard.double(forKey: tintKey)
        return min(max(tint, 0), 1)
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

/// Calls `onChange` on the main thread when a default changes, in this process or another.
private final class DefaultsObserver: NSObject {
    private let key: String
    private let onChange: @MainActor () -> Void

    init(key: String, onChange: @escaping @MainActor () -> Void) {
        self.key = key
        self.onChange = onChange
        super.init()
        UserDefaults.standard.addObserver(self, forKeyPath: key, options: [], context: nil)
    }

    deinit { UserDefaults.standard.removeObserver(self, forKeyPath: key) }

    nonisolated override func observeValue(forKeyPath keyPath: String?, of object: Any?,
                                           change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        DispatchQueue.main.async { [onChange] in MainActor.assumeIsolated { onChange() } }
    }
}
