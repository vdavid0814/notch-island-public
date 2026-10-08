import Foundation

/// What a control widget (`ControlWidget`) switches or opens: one of Control Center's controls,
/// Siri, or the screen recording. Its name, its symbol, its state as words, and whether it only
/// opens something.
nonisolated enum WidgetControl: Hashable, Sendable {
    case system(SystemControl)
    case assistant
    /// Starts and stops recording the screen (`ScreenRecorder`): on while it records.
    case screenRecording

    var title: String {
        switch self {
        case .system(let control): control.title
        case .assistant: "Siri"
        case .screenRecording: String(localized: "Screen Recording")
        }
    }

    /// The symbol the widget draws: the control's own, but Bluetooth's and AirDrop's logos, which
    /// the system has no symbol for, drawn by hand (`DrawnSymbol`).
    func symbol(on: Bool) -> String {
        switch self {
        case .system(.bluetooth): DrawnSymbol.bluetoothName
        case .system(.airDrop): DrawnSymbol.airDropName
        case .system(let control): control.symbol(on: on)
        case .assistant: "siri"
        case .screenRecording: on ? "record.circle.fill" : "record.circle"
        }
    }

    /// "On", "Off", or what it does.
    func status(on: Bool) -> String {
        switch self {
        case .system(let control): control.status(on: on)
        case .assistant: String(localized: "Open")
        case .screenRecording: on ? String(localized: "Recording") : String(localized: "Record")
        }
    }

    /// The longer of its two states: a label sized for it does not change size when it flips.
    var longestStatus: String {
        let on = status(on: true), off = status(on: false)
        return on.count >= off.count ? on : off
    }

    /// Opens or does something rather than switching: no state to show.
    var isAction: Bool {
        switch self {
        case .system(let control): control.isAction
        case .assistant: true
        case .screenRecording: false
        }
    }

    var systemControl: SystemControl? {
        if case .system(let control) = self { control } else { nil }
    }
}

/// The level a level widget (`LevelWidget`) shows and sets.
nonisolated enum WidgetLevel: Hashable, Sendable {
    case volume, brightness, keyboard

    /// What the slider is called (for VoiceOver).
    var title: String {
        switch self {
        case .volume: String(localized: "Volume")
        case .brightness: String(localized: "Display Brightness")
        case .keyboard: String(localized: "Keyboard Brightness")
        }
    }

    /// The island's own level, where it is one (the keyboard's is `SystemControls`').
    var levelKind: LevelKind? {
        switch self {
        case .volume: .volume
        case .brightness: .brightness
        case .keyboard: nil
        }
    }

    /// The symbol for `reading`: the volume's speaker and the display's sun as the island draws
    /// them, the keyboard's light dimmed at zero.
    func symbol(_ reading: LevelReading) -> String {
        switch self {
        case .volume: IslandFormat.levelSymbol(.volume, reading: reading)
        case .brightness: IslandFormat.levelSymbol(.brightness, reading: reading)
        case .keyboard: reading.value < 0.01 ? "light.min" : "light.max"
        }
    }
}
