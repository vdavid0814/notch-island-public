import CoreGraphics

/// The auxiliary-control keys we can replace. Raw values are the key codes from
/// IOKit/hidsystem/ev_keymap.h. Illumination (21–23) and play/next/previous are deliberately
/// absent: they are left to the system untouched.
nonisolated enum MediaKey: Int, Sendable, Equatable, CaseIterable {
    case volumeUp = 0        // NX_KEYTYPE_SOUND_UP
    case volumeDown = 1      // NX_KEYTYPE_SOUND_DOWN
    case brightnessUp = 2    // NX_KEYTYPE_BRIGHTNESS_UP
    case brightnessDown = 3  // NX_KEYTYPE_BRIGHTNESS_DOWN
    case mute = 7            // NX_KEYTYPE_MUTE

    var kind: LevelKind {
        switch self {
        case .volumeUp, .volumeDown, .mute: .volume
        case .brightnessUp, .brightnessDown: .brightness
        }
    }
}

nonisolated struct MediaKeyEvent: Sendable, Equatable {
    var key: MediaKey
    var isDown: Bool
    /// Auto-repeat of a held key.
    var isRepeat: Bool
    /// Shift+Option held: quarter step, as in macOS.
    var isFine: Bool
}

/// Decodes the payload of an `NX_SYSDEFINED` event. Pure, so it is unit-tested and cheap enough for
/// the event-tap callback.
nonisolated enum MediaKeyDecoder {
    /// `NX_SUBTYPE_AUX_CONTROL_BUTTONS`: the only subtype that carries media keys.
    static let auxControlButtonsSubtype: Int16 = 8
    /// `NX_SYSDEFINED` — not a named `CGEventType` case in Swift.
    static let systemDefinedEventType: UInt32 = 14
    static let keyDownState = 0x0A
    static let keyUpState = 0x0B

    /// `data1` layout: key code in bits 16–31; key state (0x0A down, 0x0B up) in bits 8–15;
    /// repeat flag in bit 0.
    static func decode(subtype: Int16, data1: Int, flags: CGEventFlags) -> MediaKeyEvent? {
        guard subtype == auxControlButtonsSubtype,
              let key = MediaKey(rawValue: (data1 & 0xFFFF_0000) >> 16)
        else { return nil }
        let state = (data1 & 0xFF00) >> 8
        guard state == keyDownState || state == keyUpState else { return nil }
        return MediaKeyEvent(
            key: key,
            isDown: state == keyDownState,
            isRepeat: data1 & 0x1 != 0,
            isFine: flags.contains([.maskShift, .maskAlternate])
        )
    }
}

/// What the tap does with one decoded key event.
nonisolated enum MediaKeyAction: Sendable, Equatable {
    /// Let the system have it (it will draw its own OSD).
    case passThrough
    /// Swallow without acting (key-up of a key we own, or an auto-repeat that must not re-apply).
    case swallow
    /// Swallow and apply the change ourselves.
    case handle
}

/// Which keys the tap may take. Written by the main actor whenever capabilities change, read by the
/// tap callback under a lock. We only swallow what we can act on: a swallowed key we then fail to
/// apply is a dead key, far worse than the system OSD.
nonisolated struct MediaKeyPolicy: Sendable, Equatable {
    /// The default output has a settable volume.
    var volume: Bool
    /// The default output has a settable mute.
    var mute: Bool
    /// DisplayServices resolved and registered for the built-in display.
    var brightness: Bool

    static let passThrough = MediaKeyPolicy(volume: false, mute: false, brightness: false)

    func swallows(_ key: MediaKey) -> Bool {
        switch key {
        case .volumeUp, .volumeDown: volume
        case .mute: mute
        case .brightnessUp, .brightnessDown: brightness
        }
    }

    func action(for event: MediaKeyEvent) -> MediaKeyAction {
        guard swallows(event.key) else { return .passThrough }
        // Key-up is swallowed too, so the system never sees half a key press. (A key-up whose
        // key-down went to the system is `MediaKeyPressTracker`'s business, not the policy's.)
        guard event.isDown else { return .swallow }
        // A held mute key would otherwise flip mute on every repeat. Held volume/brightness keys
        // keep stepping, as they do with the system handling them.
        if event.key == .mute, event.isRepeat { return .swallow }
        return .handle
    }
}

/// Who owns each key press, so every press ends where it began.
///
/// A tap armed while a key is held (start-up, a wake, Accessibility granted mid-press) would
/// otherwise swallow the key-up of a press whose key-down went to the system: Control Center then
/// never sees the release and keeps auto-repeating — brightness or volume runs to the end of its
/// range on its own. Confined to the tap thread.
nonisolated struct MediaKeyPressTracker: Sendable, Equatable {
    private(set) var taken: Set<MediaKey> = []

    mutating func action(for event: MediaKeyEvent, policy: MediaKeyPolicy) -> MediaKeyAction {
        guard event.isDown else {
            // The release of a press we took is ours; any other release belongs to the system.
            return taken.remove(event.key) != nil ? .swallow : .passThrough
        }
        // A repeat of a press the system owns (it began before the tap) stays the system's.
        if event.isRepeat, !taken.contains(event.key) { return .passThrough }
        let action = policy.action(for: event)
        if action == .passThrough {
            taken.remove(event.key)
        } else {
            taken.insert(event.key)
        }
        return action
    }
}
