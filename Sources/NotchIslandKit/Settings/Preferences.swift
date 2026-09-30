import Foundation

/// User preferences, persisted in `UserDefaults` under `ni2.<name>`.
///
/// The `ni2.` prefix keeps the rewrite from inheriting the legacy app's keys (same bundle id, but
/// different names, ranges and meanings). Each property writes itself back in `didSet`; loading
/// happens once in `init`, where property observers do not run.
///
/// Consumers observe the properties they care about (Observation tracks each one separately), so a
/// hover-delay slider drag touches nothing but the hover policy.
@Observable final class Preferences {
    /// Allowed hover-delay range in seconds; the Settings slider uses the same bounds.
    nonisolated static let hoverDelayRange: ClosedRange<Double> = 0...0.8
    /// Allowed close-delay range in seconds (pointer left the open island → it closes).
    nonisolated static let closeDelayRange: ClosedRange<Double> = 0...1
    nonisolated static let defaultCloseDelay: Double = 0.1
    nonisolated static let defaultHoverDelay: Double = 0.1

    nonisolated enum Key {
        static let prefix = "ni2."
        static let openOnHover = prefix + "openOnHover"
        static let hoverDelay = prefix + "hoverDelay"
        static let scale = prefix + "scale"
        static let hapticsEnabled = prefix + "hapticsEnabled"
        static let showNowPlaying = prefix + "showNowPlaying"
        static let showWebMedia = prefix + "showWebMedia"
        static let showPowerAlerts = prefix + "showPowerAlerts"
        static let showLevelHUD = prefix + "showLevelHUD"
        static let replaceSystemHUD = prefix + "replaceSystemHUD"
        static let shelfEnabled = prefix + "shelfEnabled"
        static let timerSound = prefix + "timerSound"
        static let showMenuBarIcon = prefix + "showMenuBarIcon"
        static let glassStyle = prefix + "glassStyle"
        static let theme = prefix + "theme"
        static let animationDuration = prefix + "animationDuration"
        static let hideInFullscreen = prefix + "hideInFullscreen"
        static let commandSpaceOpensSiri = prefix + "commandSpaceOpensSiri"
        static let closeDelay = prefix + "closeDelay"
        static let levelStyle = prefix + "levelStyle"
        static let showAirPods = prefix + "showAirPods"
        static let siri = prefix + "siri"
        static let panel = prefix + "panel"
        static let battery = prefix + "battery"
        static let levelDuration = prefix + "levelDuration"
        static let airPodsDuration = prefix + "airPodsDuration"
        static let powerDuration = prefix + "powerDuration"
        static let airPodsSystemCard = prefix + "airPodsSystemCard"
        static let musicBars = prefix + "musicBars"
        static let musicBarsOnPower = prefix + "musicBarsOnPower"
        static let musicBarsContinuousOnPower = prefix + "musicBarsContinuousOnPower"
        static let liquidVolume = prefix + "liquidVolume"
        static let liquidAirPods = prefix + "liquidAirPods"
    }

    @ObservationIgnored private let defaults: UserDefaults

    /// Open the island when the pointer rests on the notch.
    var openOnHover: Bool { didSet { defaults.set(openOnHover, forKey: Key.openOnHover) } }
    /// Seconds the pointer must rest on the notch before it opens.
    var hoverDelay: Double { didSet { defaults.set(hoverDelay, forKey: Key.hoverDelay) } }
    /// Seconds after the pointer leaves the open island before it closes.
    var closeDelay: Double { didSet { defaults.set(closeDelay, forKey: Key.closeDelay) } }
    /// How volume and brightness changes show: the banner under the notch, or the small pill.
    var levelStyle: LevelHUDStyle { didSet { defaults.set(levelStyle.rawValue, forKey: Key.levelStyle) } }
    /// Size of the expanded island (compact and banner always hug the notch).
    var scale: IslandScale { didSet { defaults.set(scale.rawValue, forKey: Key.scale) } }
    var hapticsEnabled: Bool { didSet { defaults.set(hapticsEnabled, forKey: Key.hapticsEnabled) } }
    var showNowPlaying: Bool { didSet { defaults.set(showNowPlaying, forKey: Key.showNowPlaying) } }
    /// Also show YouTube and other playback in browsers and video apps (read only while one is open).
    var showWebMedia: Bool { didSet { defaults.set(showWebMedia, forKey: Key.showWebMedia) } }
    var showPowerAlerts: Bool { didSet { defaults.set(showPowerAlerts, forKey: Key.showPowerAlerts) } }
    var showLevelHUD: Bool { didSet { defaults.set(showLevelHUD, forKey: Key.showLevelHUD) } }
    /// Show AirPods (and other headphones) connecting, with their batteries.
    var showAirPods: Bool { didSet { defaults.set(showAirPods, forKey: Key.showAirPods) } }
    /// What the island's AirPods card does about macOS's own.
    var airPodsSystemCard: AirPodsSystemCard {
        didSet {
            defaults.set(airPodsSystemCard.rawValue, forKey: Key.airPodsSystemCard)
            AirPodsSystemCard.current = airPodsSystemCard
        }
    }
    /// Seconds each notice stays up (Live Activities).
    var levelDuration: Double { didSet { defaults.set(levelDuration, forKey: Key.levelDuration) } }
    var airPodsDuration: Double { didSet { defaults.set(airPodsDuration, forKey: Key.airPodsDuration) } }
    var powerDuration: Double { didSet { defaults.set(powerDuration, forKey: Key.powerDuration) } }

    nonisolated static let noticeDurationRange: ClosedRange<Double> = 0.5...10
    /// Take over the volume/brightness keys so the system HUD does not appear (needs Accessibility).
    var replaceSystemHUD: Bool { didSet { defaults.set(replaceSystemHUD, forKey: Key.replaceSystemHUD) } }
    var shelfEnabled: Bool { didSet { defaults.set(shelfEnabled, forKey: Key.shelfEnabled) } }
    var timerSound: Bool { didSet { defaults.set(timerSound, forKey: Key.timerSound) } }
    var showMenuBarIcon: Bool { didSet { defaults.set(showMenuBarIcon, forKey: Key.showMenuBarIcon) } }
    /// The island's surface: Liquid Glass, black, or black fading into the glass.
    var glassStyle: IslandGlassStyle { didSet { defaults.set(glassStyle.rawValue, forKey: Key.glassStyle) } }
    /// The island's colour (`IslandTheme`), shared with every view through `IslandThemeStore`.
    var theme: IslandTheme {
        didSet {
            guard theme != oldValue else { return }
            defaults.set(try? JSONEncoder().encode(theme), forKey: Key.theme)
            IslandThemeStore.shared.theme = theme
        }
    }
    /// Seconds the island takes to grow out of the notch (and to shrink back into it).
    var animationDuration: Double { didSet { defaults.set(animationDuration, forKey: Key.animationDuration) } }
    /// Step aside while the playing video (a film, a YouTube video) is in full screen.
    var hideInFullscreen: Bool { didSet { defaults.set(hideInFullscreen, forKey: Key.hideInFullscreen) } }
    /// Siri in the notch: opening, search, lists, answers, window size.
    var siri: SiriSettings {
        didSet {
            guard siri != oldValue, let data = try? JSONEncoder().encode(siri) else { return }
            defaults.set(data, forKey: Key.siri)
        }
    }
    /// The open panel's width and board height (Settings ▸ Widgets ▸ Size).
    var panel: PanelSettings {
        didSet {
            guard panel != oldValue, let data = try? JSONEncoder().encode(panel) else { return }
            defaults.set(data, forKey: Key.panel)
        }
    }
    /// The battery page's chart: its style, range, colours and what it marks.
    var battery: BatteryDisplaySettings {
        didSet {
            guard battery != oldValue, let data = try? JSONEncoder().encode(battery) else { return }
            defaults.set(data, forKey: Key.battery)
        }
    }
    /// How the bars beside the notch move while music plays, on battery.
    var musicBars: MusicBarsStyle { didSet { defaults.set(musicBars.rawValue, forKey: Key.musicBars) } }
    /// … and on the charger (or a Mac without a battery).
    var musicBarsOnPower: MusicBarsStyle { didSet { defaults.set(musicBarsOnPower.rawValue, forKey: Key.musicBarsOnPower) } }
    /// Following the music: on the charger, listen 0.8 s in every 1.8 instead of 2 s in every 8.
    /// The island's liquid runs out to macOS's own volume / AirPods card when that one comes up away
    /// from the notch, and lies on it (`LiquidCard`).
    var liquidVolume: Bool { didSet { defaults.set(liquidVolume, forKey: Key.liquidVolume) } }
    var liquidAirPods: Bool { didSet { defaults.set(liquidAirPods, forKey: Key.liquidAirPods) } }
    var musicBarsContinuousOnPower: Bool {
        didSet { defaults.set(musicBarsContinuousOnPower, forKey: Key.musicBarsContinuousOnPower) }
    }
    /// ⌘Space opens Siri in the notch instead of the system's Search window (needs Accessibility).
    var commandSpaceOpensSiri: Bool { didSet { defaults.set(commandSpaceOpensSiri, forKey: Key.commandSpaceOpensSiri) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        openOnHover = defaults.object(forKey: Key.openOnHover) as? Bool ?? true
        // Clamped because the stored value may come from a hand-edited plist or an older build.
        let delay = defaults.object(forKey: Key.hoverDelay) as? Double ?? Self.defaultHoverDelay
        hoverDelay = min(max(delay.isFinite ? delay : Self.defaultHoverDelay, Self.hoverDelayRange.lowerBound), Self.hoverDelayRange.upperBound)
        let close = defaults.object(forKey: Key.closeDelay) as? Double ?? Self.defaultCloseDelay
        closeDelay = min(max(close.isFinite ? close : Self.defaultCloseDelay, Self.closeDelayRange.lowerBound),
                         Self.closeDelayRange.upperBound)
        levelStyle = defaults.string(forKey: Key.levelStyle).flatMap(LevelHUDStyle.init(rawValue:)) ?? .pill
        scale = defaults.string(forKey: Key.scale).flatMap(IslandScale.init(rawValue:)) ?? .compact
        hapticsEnabled = defaults.object(forKey: Key.hapticsEnabled) as? Bool ?? true
        showNowPlaying = defaults.object(forKey: Key.showNowPlaying) as? Bool ?? true
        showWebMedia = defaults.object(forKey: Key.showWebMedia) as? Bool ?? true
        showPowerAlerts = defaults.object(forKey: Key.showPowerAlerts) as? Bool ?? true
        showLevelHUD = defaults.object(forKey: Key.showLevelHUD) as? Bool ?? true
        showAirPods = defaults.object(forKey: Key.showAirPods) as? Bool ?? true
        let systemCard = defaults.string(forKey: Key.airPodsSystemCard).flatMap(AirPodsSystemCard.init(rawValue:)) ?? .cover
        airPodsSystemCard = systemCard
        AirPodsSystemCard.current = systemCard
        func duration(_ key: String, _ fallback: Double) -> Double {
            let value = defaults.object(forKey: key) as? Double ?? fallback
            return min(max(value.isFinite ? value : fallback, Self.noticeDurationRange.lowerBound), Self.noticeDurationRange.upperBound)
        }
        levelDuration = duration(Key.levelDuration, 1.5)
        airPodsDuration = duration(Key.airPodsDuration, 5)
        powerDuration = duration(Key.powerDuration, 3)
        replaceSystemHUD = defaults.object(forKey: Key.replaceSystemHUD) as? Bool ?? true
        shelfEnabled = defaults.object(forKey: Key.shelfEnabled) as? Bool ?? true
        timerSound = defaults.object(forKey: Key.timerSound) as? Bool ?? true
        showMenuBarIcon = defaults.object(forKey: Key.showMenuBarIcon) as? Bool ?? true
        glassStyle = IslandGlassStyle(storedValue: defaults.string(forKey: Key.glassStyle))
        theme = defaults.data(forKey: Key.theme).flatMap { try? JSONDecoder().decode(IslandTheme.self, from: $0) } ?? .default
        hideInFullscreen = defaults.object(forKey: Key.hideInFullscreen) as? Bool ?? true
        commandSpaceOpensSiri = defaults.object(forKey: Key.commandSpaceOpensSiri) as? Bool ?? true
        let barsOnBattery = defaults.string(forKey: Key.musicBars).flatMap(MusicBarsStyle.init(rawValue:)) ?? .followMusic
        musicBars = barsOnBattery
        // Until chosen on its own, the charger follows the battery's choice.
        musicBarsOnPower = defaults.string(forKey: Key.musicBarsOnPower).flatMap(MusicBarsStyle.init(rawValue:)) ?? barsOnBattery
        musicBarsContinuousOnPower = defaults.object(forKey: Key.musicBarsContinuousOnPower) as? Bool ?? true
        liquidVolume = defaults.object(forKey: Key.liquidVolume) as? Bool ?? true
        liquidAirPods = defaults.object(forKey: Key.liquidAirPods) as? Bool ?? true
        siri = defaults.data(forKey: Key.siri).flatMap { try? JSONDecoder().decode(SiriSettings.self, from: $0) } ?? SiriSettings()
        panel = defaults.data(forKey: Key.panel).flatMap { try? JSONDecoder().decode(PanelSettings.self, from: $0) } ?? PanelSettings()
        battery = defaults.data(forKey: Key.battery).flatMap { try? JSONDecoder().decode(BatteryDisplaySettings.self, from: $0) }
            ?? BatteryDisplaySettings()
        let duration = defaults.object(forKey: Key.animationDuration) as? Double ?? Motion.defaultDuration
        animationDuration = min(
            max(duration.isFinite ? duration : Motion.defaultDuration, Motion.durationRange.lowerBound),
            Motion.durationRange.upperBound
        )
    }
}

/// How the bars beside the notch move while music plays.
nonisolated enum MusicBarsStyle: String, Sendable, CaseIterable, Identifiable {
    /// They follow what is playing (the system-audio permission; macOS shows its purple dot).
    case followMusic
    /// A set animation, the same for every song: nothing is listened to.
    case animation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .followMusic: "Follow the Music"
        case .animation: "Animation"
        }
    }
}

/// How a volume or brightness change shows in the notch.
nonisolated enum LevelHUDStyle: String, Sendable, CaseIterable, Identifiable {
    /// Under the notch: the symbol, a full slider and the percentage.
    case banner
    /// Beside the notch only, like Now Playing's pill: the symbol on the left, a small slider on
    /// the right.
    case pill

    var id: String { rawValue }

    var title: String {
        switch self {
        case .banner: "Banner"
        case .pill: "Minimal"
        }
    }
}

/// macOS shows its own card when AirPods connect, and an app cannot turn it off.
nonisolated enum AirPodsSystemCard: String, Sendable, CaseIterable, Identifiable {
    /// The island's card comes at once, above macOS's, and hides it.
    case cover
    /// The island's card waits until macOS's has gone.
    case after
    /// Only macOS's card shows.
    case skip

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cover: "Cover It"
        case .after: "After It"
        case .skip: "Don't Show"
        }
    }

    /// The user's choice, for the window layer (set by `Preferences`).
    nonisolated(unsafe) static var current: AirPodsSystemCard = .cover
}
