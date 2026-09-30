import Foundation

/// What a widget shows. Everything else about a kind — its name, sizes, elements, looks — is its
/// `WidgetKindSpec`, kept in its family's spec file (`Families/`).
nonisolated enum IslandWidgetKind: String, Sendable, Codable, CaseIterable, Identifiable {
    case nowPlaying
    case timer
    case stopwatch
    case shelf
    case battery
    case volume
    case brightness
    case keyboardBrightness
    case assistant
    // Control Center's controls, each its own widget, added one by one like in Control Center.
    case wifi
    case bluetooth
    case airDrop
    case darkMode
    case nightShift
    case keepAwake
    case microphone
    case calculator
    case voiceMemos
    case screenshot
    case notes
    case lockScreen
    case focus
    case clock
    case home
    // More widgets.
    /// The time and the date.
    case dateTime
    /// Processor and memory load.
    case systemStats

    // Reserved for 0.6 (`WidgetKindSpec.isImplemented` is false until each is built): hidden from
    // the gallery and never placed on a board by the app.
    // Battery.
    case batteryTime, batteryHealth, batteryCycles, batteryChart, batteryPower, batteryTemperature, charger
    // Controls.
    case soundOutput, outputMute, trueTone, stageManager, lowPowerMode, screenMirroring, missionControl
    case showDesktop, appsLauncher, characterViewer, displaySleep
    // Time.
    case worldClock, analogClock, monthCalendar, upNext, countdown
    // System.
    case network, diskSpace, uptime, airPodsBattery
    // Tools.
    case shortcut, appLauncher, clipboard, photoFrame

    var id: String { rawValue }

    var spec: WidgetKindSpec { WidgetKindSpec.table[self]! }

    /// The Control Center control this widget is, if it is one.
    var systemControl: SystemControl? {
        switch self {
        case .wifi: .wifi
        case .bluetooth: .bluetooth
        case .airDrop: .airDrop
        case .darkMode: .darkMode
        case .nightShift: .nightShift
        case .keepAwake: .keepAwake
        case .microphone: .microphone
        case .calculator: .calculator
        case .voiceMemos: .voiceMemos
        case .screenshot: .screenshot
        case .notes: .notes
        case .lockScreen: .lockScreen
        case .focus: .focus
        case .clock: .clock
        case .home: .home
        case .soundOutput: .soundOutput
        case .outputMute: .outputMute
        case .trueTone: .trueTone
        case .stageManager: .stageManager
        case .lowPowerMode: .lowPowerMode
        case .screenMirroring: .screenMirroring
        case .missionControl: .missionControl
        case .showDesktop: .showDesktop
        case .appsLauncher: .appsLauncher
        case .characterViewer: .characterViewer
        case .displaySleep: .displaySleep
        default: nil
        }
    }

    /// Built, and working on this Mac: the gallery offers it.
    var isOffered: Bool { spec.isImplemented && spec.isAvailable() }

    var title: String { spec.title }
    var summary: String { spec.summary }
    var systemImage: String { spec.symbol }
    var category: WidgetCategory { spec.category }
    /// The sizes in reference cells (the 12 × 3 board); `BoardGrid` converts them to its own.
    var minimumSize: GridSize { spec.minimumSize }
    var maximumSize: GridSize { spec.maximumSize }
    var defaultSize: GridSize { spec.defaultSize }
    /// The widget's elements the user may switch on or off, in the order they are drawn. The ones
    /// always drawn (`ElementSpec.isRequired`) are not among them.
    var options: [ElementID] { spec.elements.filter { !$0.isRequired }.map(\.id) }
    var defaultOptions: Set<ElementID> { Set(spec.elements.filter { $0.defaultVisible && !$0.isRequired }.map(\.id)) }
    /// The arrangements the widget can be drawn in; empty when it has only one.
    var layouts: [WidgetLayout] { spec.layouts }
    /// The backgrounds it offers (the artwork only where there is one).
    var backgrounds: [WidgetBackground] { spec.backgrounds }
    /// Which widgets can swap their two sides.
    var canMirror: Bool { spec.canMirror }

    /// Sizes offered as one-click presets in the editor, like a widget gallery's families: every
    /// common footprint the kind allows, smallest first (reference cells).
    var sizePresets: [GridSize] {
        let candidates: [GridSize] = [
            .init(width: 1, height: 1), .init(width: 2, height: 1), .init(width: 3, height: 1),
            .init(width: 4, height: 1), .init(width: 5, height: 1), .init(width: 6, height: 1),
            .init(width: 2, height: 2), .init(width: 3, height: 2), .init(width: 4, height: 2),
            .init(width: 5, height: 2), .init(width: 6, height: 2),
            .init(width: 4, height: 3), .init(width: 5, height: 3), .init(width: 6, height: 3),
            .init(width: 7, height: 3), .init(width: 12, height: 1),
        ]
        let lower = minimumSize, upper = maximumSize
        return candidates.filter {
            (lower.width...upper.width).contains($0.width) && (lower.height...upper.height).contains($0.height)
        }
    }
}

/// The widget store's groups, in order.
nonisolated enum WidgetCategory: String, Sendable, CaseIterable, Identifiable {
    case media, time, controls, battery, system, tools

    var id: String { rawValue }

    var title: String {
        switch self {
        case .media: "Media"
        case .time: "Timers"
        case .controls: "Controls"
        case .battery: "Battery"
        case .system: "System"
        case .tools: "Tools"
        }
    }

    var kinds: [IslandWidgetKind] { IslandWidgetKind.allCases.filter { $0.category == self } }
}
