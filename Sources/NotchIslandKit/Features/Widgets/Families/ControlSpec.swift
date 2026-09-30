import Foundation

/// Control Center's controls, each its own widget (`ControlWidget`; the switches are
/// `SystemControls`, the ones added in 0.6 `ExtendedControls`).
nonisolated enum ControlSpecs {
    static let all: [IslandWidgetKind: WidgetKindSpec] = [
        .wifi: control(.wifi, "Turn Wi-Fi on or off.", blue),
        .bluetooth: control(.bluetooth, "Turn Bluetooth on or off. macOS asks for access the first time.", blue,
                            permission: .bluetooth),
        .airDrop: control(.airDrop, "Open AirDrop.", blue),
        .darkMode: control(.darkMode, "Switch between Dark and Light Mode.", [.rgb(0.45, 0.45, 0.55), .rgb(0.2, 0.2, 0.28)]),
        .nightShift: control(.nightShift, "Warmer colours for the evening.", [.rgb(1.0, 0.72, 0.3), .rgb(0.98, 0.5, 0.1)]),
        .keepAwake: control(.keepAwake, "Keep the Mac and its display awake until you turn it off.",
                            [.rgb(0.7, 0.55, 0.4), .rgb(0.5, 0.35, 0.22)]),
        .microphone: control(.microphone, "Mute or unmute the microphone.", [.rgb(1.0, 0.45, 0.4), .rgb(0.9, 0.2, 0.2)]),
        .calculator: control(.calculator, "Open Calculator.", [.rgb(1.0, 0.62, 0.2), .rgb(0.95, 0.42, 0.05)]),
        .voiceMemos: control(.voiceMemos, "Open Voice Memos to record.", [.rgb(1.0, 0.38, 0.38), .rgb(0.85, 0.12, 0.2)]),
        .screenshot: control(.screenshot, "Take a screenshot or a screen recording.", [.rgb(0.62, 0.64, 0.7), .rgb(0.38, 0.4, 0.47)]),
        .notes: control(.notes, "Open Notes.", [.rgb(1.0, 0.86, 0.3), .rgb(0.98, 0.7, 0.08)]),
        .lockScreen: control(.lockScreen, "Lock the Mac at once.", slate),
        .focus: control(.focus, "Choose a Focus or turn Do Not Disturb on.", [.rgb(0.55, 0.45, 1.0), .rgb(0.35, 0.22, 0.85)]),
        .clock: control(.clock, "Open Clock for alarms and world time.", graphite),
        .home: control(.home, "Open Home for your accessories.", [.rgb(1.0, 0.66, 0.2), .rgb(1.0, 0.48, 0.1)]),
        // Added in 0.6.
        .soundOutput: control(.soundOutput, "Choose where the sound plays.", blue, isImplemented: false),
        .outputMute: control(.outputMute, "Mute or unmute the sound.", [.rgb(0.6, 0.5, 1.0), .rgb(0.4, 0.28, 0.92)],
                             isImplemented: false),
        .trueTone: control(.trueTone, "Turn True Tone on or off.", [.rgb(1.0, 0.88, 0.35), .rgb(0.98, 0.7, 0.1)],
                           isImplemented: false),
        .stageManager: control(.stageManager, "Turn Stage Manager on or off.", slate, isImplemented: false),
        .lowPowerMode: control(.lowPowerMode, "Whether Low Power Mode is on; opens Battery settings.",
                               [.rgb(1.0, 0.82, 0.25), .rgb(1.0, 0.6, 0.1)], isImplemented: false),
        .screenMirroring: control(.screenMirroring, "Mirror or extend to another display.", blue, isImplemented: false),
        .missionControl: control(.missionControl, "Show every open window at once.", slate, isImplemented: false),
        .showDesktop: control(.showDesktop, "Move the windows aside to show the desktop.", slate, isImplemented: false),
        .appsLauncher: control(.appsLauncher, "Open the Apps launcher.", [.rgb(0.36, 0.62, 1.0), .rgb(0.86, 0.3, 0.95)],
                               isImplemented: false),
        .characterViewer: control(.characterViewer, "Emoji and symbols, ready to type.",
                                  [.rgb(1.0, 0.86, 0.3), .rgb(0.98, 0.7, 0.08)], isImplemented: false),
        .displaySleep: control(.displaySleep, "Put the display to sleep.", graphite, isImplemented: false),
    ]

    private static let blue: [IslandTheme.RGB] = [.rgb(0.3, 0.62, 1.0), .rgb(0.05, 0.4, 0.95)]
    private static let slate: [IslandTheme.RGB] = [.rgb(0.5, 0.52, 0.6), .rgb(0.26, 0.28, 0.36)]
    private static let graphite: [IslandTheme.RGB] = [.rgb(0.4, 0.42, 0.48), .rgb(0.14, 0.15, 0.2)]

    /// Controls start as a tile with their name, the way Control Center shows them.
    private static func control(_ control: SystemControl, _ summary: String, _ colors: [IslandTheme.RGB],
                                permission: WidgetPermission? = nil, isImplemented: Bool = true) -> WidgetKindSpec {
        WidgetKindSpec(
            title: control.title, summary: summary, symbol: control.symbol(on: true), iconColors: colors,
            category: .controls, family: .controls,
            minimumSize: GridSize(width: 1, height: 1), defaultSize: GridSize(width: 2, height: 1),
            maximumSize: GridSize(width: 4, height: 2),
            elements: [
                ElementSpec(.controlName, "Name", symbol: "textformat", role: .text, samples: [control.title], priority: 60),
                ElementSpec(.controlStatus, "On or Off", symbol: "power", role: .text,
                            samples: [control.status(on: true), control.status(on: false)], priority: 40),
            ],
            layouts: [.automatic, .button, .tile],
            permission: permission,
            isImplemented: isImplemented
        )
    }
}
