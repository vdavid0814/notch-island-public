import Foundation

/// The Control Center items added in 0.6 (`SystemControl.soundOutput` … `.displaySleep`): their
/// names, symbols, and what reading and switching them does. `SystemControl` and `SystemControls`
/// hand every question about them to this file, so they are built here without touching those.
///
/// Until one is built its widget is not offered (`WidgetKindSpec.isImplemented`): it reads as off
/// and switching it does nothing.
nonisolated enum ExtendedControls {
    static func title(of control: SystemControl) -> String {
        switch control {
        case .soundOutput: "Sound Output"
        case .outputMute: "Mute"
        case .trueTone: "True Tone"
        case .stageManager: "Stage Manager"
        case .lowPowerMode: "Low Power Mode"
        case .screenMirroring: "Screen Mirroring"
        case .missionControl: "Mission Control"
        case .showDesktop: "Show Desktop"
        case .appsLauncher: "Apps"
        case .characterViewer: "Emoji & Symbols"
        case .displaySleep: "Display Sleep"
        default: control.rawValue
        }
    }

    static func symbol(of control: SystemControl, on: Bool) -> String {
        switch control {
        case .soundOutput: "hifispeaker.fill"
        case .outputMute: on ? "speaker.slash.fill" : "speaker.wave.2.fill"
        case .trueTone: "sun.max.fill"
        case .stageManager: "rectangle.stack.fill"
        case .lowPowerMode: "battery.25percent"
        case .screenMirroring: "rectangle.on.rectangle"
        case .missionControl: "rectangle.3.group.fill"
        case .showDesktop: "menubar.dock.rectangle"
        case .appsLauncher: "square.grid.3x3.fill"
        case .characterViewer: "face.smiling"
        case .displaySleep: "display"
        default: "questionmark"
        }
    }

    /// Opens or does one thing, with no state to show.
    static func isAction(_ control: SystemControl) -> Bool {
        switch control {
        case .outputMute, .trueTone, .stageManager, .lowPowerMode: false
        default: true
        }
    }

    static func actionURL(of control: SystemControl) -> URL? { nil }

    static func isOn(_ control: SystemControl) -> Bool { false }

    /// Whether the switch was made.
    static func toggle(_ control: SystemControl, to on: Bool) -> Bool {
        Log.app.notice("control \(control.rawValue, privacy: .public) is not built yet")
        return false
    }
}
