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
        static let animationDuration = prefix + "animationDuration"
        static let hideInFullscreen = prefix + "hideInFullscreen"
        static let commandSpaceOpensSiri = prefix + "commandSpaceOpensSiri"
    }

    @ObservationIgnored private let defaults: UserDefaults

    /// Open the island when the pointer rests on the notch.
    var openOnHover: Bool { didSet { defaults.set(openOnHover, forKey: Key.openOnHover) } }
    /// Seconds the pointer must rest on the notch before it opens.
    var hoverDelay: Double { didSet { defaults.set(hoverDelay, forKey: Key.hoverDelay) } }
    /// Size of the expanded island (compact and banner always hug the notch).
    var scale: IslandScale { didSet { defaults.set(scale.rawValue, forKey: Key.scale) } }
    var hapticsEnabled: Bool { didSet { defaults.set(hapticsEnabled, forKey: Key.hapticsEnabled) } }
    var showNowPlaying: Bool { didSet { defaults.set(showNowPlaying, forKey: Key.showNowPlaying) } }
    /// Also show YouTube and other playback in browsers and video apps (read only while one is open).
    var showWebMedia: Bool { didSet { defaults.set(showWebMedia, forKey: Key.showWebMedia) } }
    var showPowerAlerts: Bool { didSet { defaults.set(showPowerAlerts, forKey: Key.showPowerAlerts) } }
    var showLevelHUD: Bool { didSet { defaults.set(showLevelHUD, forKey: Key.showLevelHUD) } }
    /// Take over the volume/brightness keys so the system HUD does not appear (needs Accessibility).
    var replaceSystemHUD: Bool { didSet { defaults.set(replaceSystemHUD, forKey: Key.replaceSystemHUD) } }
    var shelfEnabled: Bool { didSet { defaults.set(shelfEnabled, forKey: Key.shelfEnabled) } }
    var timerSound: Bool { didSet { defaults.set(timerSound, forKey: Key.timerSound) } }
    var showMenuBarIcon: Bool { didSet { defaults.set(showMenuBarIcon, forKey: Key.showMenuBarIcon) } }
    /// The island's surface: Liquid Glass, black, or black fading into the glass.
    var glassStyle: IslandGlassStyle { didSet { defaults.set(glassStyle.rawValue, forKey: Key.glassStyle) } }
    /// Seconds the island takes to grow out of the notch (and to shrink back into it).
    var animationDuration: Double { didSet { defaults.set(animationDuration, forKey: Key.animationDuration) } }
    /// Step aside while the playing video (a film, a YouTube video) is in full screen.
    var hideInFullscreen: Bool { didSet { defaults.set(hideInFullscreen, forKey: Key.hideInFullscreen) } }
    /// ⌘Space opens Siri in the notch instead of the system's Search window (needs Accessibility).
    var commandSpaceOpensSiri: Bool { didSet { defaults.set(commandSpaceOpensSiri, forKey: Key.commandSpaceOpensSiri) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        openOnHover = defaults.object(forKey: Key.openOnHover) as? Bool ?? true
        // Clamped because the stored value may come from a hand-edited plist or an older build.
        let delay = defaults.object(forKey: Key.hoverDelay) as? Double ?? 0.22
        hoverDelay = min(max(delay.isFinite ? delay : 0.22, Self.hoverDelayRange.lowerBound), Self.hoverDelayRange.upperBound)
        scale = defaults.string(forKey: Key.scale).flatMap(IslandScale.init(rawValue:)) ?? .standard
        hapticsEnabled = defaults.object(forKey: Key.hapticsEnabled) as? Bool ?? true
        showNowPlaying = defaults.object(forKey: Key.showNowPlaying) as? Bool ?? true
        showWebMedia = defaults.object(forKey: Key.showWebMedia) as? Bool ?? true
        showPowerAlerts = defaults.object(forKey: Key.showPowerAlerts) as? Bool ?? true
        showLevelHUD = defaults.object(forKey: Key.showLevelHUD) as? Bool ?? true
        replaceSystemHUD = defaults.object(forKey: Key.replaceSystemHUD) as? Bool ?? true
        shelfEnabled = defaults.object(forKey: Key.shelfEnabled) as? Bool ?? true
        timerSound = defaults.object(forKey: Key.timerSound) as? Bool ?? true
        showMenuBarIcon = defaults.object(forKey: Key.showMenuBarIcon) as? Bool ?? true
        glassStyle = IslandGlassStyle(storedValue: defaults.string(forKey: Key.glassStyle))
        hideInFullscreen = defaults.object(forKey: Key.hideInFullscreen) as? Bool ?? true
        commandSpaceOpensSiri = defaults.object(forKey: Key.commandSpaceOpensSiri) as? Bool ?? true
        let duration = defaults.object(forKey: Key.animationDuration) as? Double ?? Motion.defaultDuration
        animationDuration = min(
            max(duration.isFinite ? duration : Motion.defaultDuration, Motion.durationRange.lowerBound),
            Motion.durationRange.upperBound
        )
    }
}
