import AppKit
import Observation

/// How the system draws app icons (System Settings ▸ Appearance ▸ Icon & widget style): what the
/// tiles drawn beside them follow (`AssistantTile`).
nonisolated struct IconLook: Sendable, Equatable {
    nonisolated enum Kind: Sendable, Equatable { case regular, dark, clearLight, clearDark, tintedLight, tintedDark }

    var kind: Kind = .regular
    /// The tinted style's colour (red, green, blue, 0…1); nil: the Mac's accent colour.
    var tint: [Double]?

    /// `theme`: `AppleIconAppearanceTheme`, as Regular, Clear or Tinted with Light, Dark or Automatic;
    /// Automatic goes with the Mac's mode. Unset, icons are the default colourful ones.
    static func kind(theme: String?, isDark: Bool) -> Kind {
        guard let theme else { return .regular }
        let dark = theme.hasSuffix("Dark") || (theme.hasSuffix("Automatic") && isDark)
        if theme.hasPrefix("Clear") { return dark ? .clearDark : .clearLight }
        if theme.hasPrefix("Tinted") { return dark ? .tintedDark : .tintedLight }
        return dark ? .dark : .regular
    }

    /// The tint as stored: a colour's name, or "r g b a" for a colour of the user's own.
    static func tint(name: String?, custom: String?) -> [Double]? {
        let parts = custom?.split(separator: " ").compactMap { Double($0) } ?? []
        if parts.count >= 3 { return Array(parts.prefix(3)) }
        return switch name?.lowercased() {
        case "red": [1, 0.27, 0.23]
        case "orange": [1, 0.62, 0.04]
        case "yellow": [1, 0.8, 0]
        case "green": [0.2, 0.78, 0.35]
        case "blue": [0, 0.48, 1]
        case "purple": [0.69, 0.32, 0.87]
        case "pink": [1, 0.18, 0.57]
        case "graphite", "gray", "grey": [0.56, 0.56, 0.58]
        default: nil
        }
    }
}

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

    /// How the system draws app icons now.
    private(set) var iconLook = IconLook()

    @ObservationIgnored private var token: (any NSObjectProtocol)?
    @ObservationIgnored private var tintObserver: DefaultsObserver?
    @ObservationIgnored private var iconObservers: [DefaultsObserver] = []

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
        iconLook = Self.readIconLook(isDark: isDark)
        iconObservers = ["AppleIconAppearanceTheme", "AppleIconAppearanceTintColor", "AppleIconAppearanceCustomTintColor"].map { key in
            DefaultsObserver(key: key) { [weak self] in self?.refreshIconLook() }
        }
    }

    private static func readIconLook(isDark: Bool) -> IconLook {
        // For measuring and pictures only: `NI_ICON_THEME=ClearDark` … stands in for the system's.
        let environment = ProcessInfo.processInfo.environment
        let defaults = UserDefaults.standard
        return IconLook(kind: IconLook.kind(theme: environment["NI_ICON_THEME"] ?? defaults.string(forKey: "AppleIconAppearanceTheme"), isDark: isDark),
                        tint: IconLook.tint(name: environment["NI_ICON_TINT"] ?? defaults.string(forKey: "AppleIconAppearanceTintColor"),
                                            custom: defaults.string(forKey: "AppleIconAppearanceCustomTintColor")))
    }

    private func refreshIconLook() {
        let look = Self.readIconLook(isDark: isDark)
        if look != iconLook { iconLook = look }
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
        defer { refreshIconLook() }
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
