import Foundation

/// One system level as the island shows it: output volume or built-in display brightness.
nonisolated struct LevelReading: Sendable, Equatable {
    /// 0...1. For volume this is the level the output returns to when unmuted.
    var value: Double
    /// Output mute. Always `false` for brightness.
    var isMuted: Bool
    /// We can change this level: the default output has a settable volume, or DisplayServices resolved
    /// and registered for the built-in display. Views disable their Slider when `false`.
    var isAvailable: Bool
    /// Which symbol family `systemImage` draws from. Defaulted (and declared last) so the contract's
    /// memberwise `LevelReading(value:isMuted:isAvailable:)` keeps meaning a volume reading.
    var kind: LevelKind = .volume

    static let unavailable = LevelReading(value: 0, isMuted: false, isAvailable: false)

    static func unavailable(_ kind: LevelKind) -> LevelReading {
        LevelReading(value: 0, isMuted: false, isAvailable: false, kind: kind)
    }

    /// Mirrors the system OSD: a slashed speaker when silent (muted, at zero, or not controllable),
    /// otherwise one, two or three waves by thirds; a small sun in the lower half of the brightness range.
    var systemImage: String {
        switch kind {
        case .volume:
            guard isAvailable, !isMuted, value > 0 else { return "speaker.slash.fill" }
            if value < 1.0 / 3.0 { return "speaker.wave.1.fill" }
            if value < 2.0 / 3.0 { return "speaker.wave.2.fill" }
            return "speaker.wave.3.fill"
        case .brightness:
            return value < 0.5 ? "sun.min.fill" : "sun.max.fill"
        }
    }
}

/// Whether our island replaces the system volume/brightness OSD (by swallowing the media keys).
nonisolated enum InterceptionState: Sendable, Equatable {
    case off
    /// Wanted, but the app is not trusted for Accessibility, so no event tap can be created.
    case needsPermission
    /// The event tap is installed on its thread and swallowing the keys the current policy allows.
    case active
    case failed(String)
}

/// Where a level change came from, so the composition root can decide on banner and haptics.
nonisolated enum LevelChangeSource: Sendable, Equatable {
    /// An intercepted media key. Reported even when the value did not move (volume up at 100 %),
    /// because the system OSD would have shown a full bar there too.
    case key
    /// `LevelsController.set(_:to:)` / `toggleMute()` — the island's own controls.
    case island
    /// Anything else: Control Center, the menu-bar slider, another app, a headset button,
    /// or the system handling the keys itself while interception is off.
    case external
}

/// How a service classifies an update it publishes to `LevelsController`.
nonisolated enum LevelUpdateReason: Sendable, Equatable {
    /// State to adopt without announcing it: first read, device switch, availability change,
    /// ambient auto-brightness drift, the echo of our own write.
    case silent
    /// A change a person made somewhere else; worth a HUD.
    case external
}
