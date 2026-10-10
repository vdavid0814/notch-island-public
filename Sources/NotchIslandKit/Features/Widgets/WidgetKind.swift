import Foundation

/// What a widget shows. The six base widgets: one of each kind of element (a button, a slider, a
/// label, a live number with buttons, a composite, a chart); and the widgets built on them as they
/// are — every control as Wi-Fi is (`ControlWidget`), every level as Volume is (`LevelWidget`).
/// Everything else about a kind — its name, sizes, elements, looks — is its `WidgetKindSpec`
/// (`WidgetSpecs`). The names are the ones boards have been saved with, so a widget of a kind that
/// comes back returns from `WidgetBoard.foreign` where it was.
nonisolated enum IslandWidgetKind: String, Sendable, Codable, CaseIterable, Identifiable {
    /// A button: Control Center's Wi-Fi switch.
    case wifi
    /// A slider: the output volume.
    case volume
    /// A label: the time and the date.
    case dateTime
    /// A live number with buttons that change with its state.
    case stopwatch
    /// The composite: artwork, titles, progress and playback buttons.
    case nowPlaying
    /// A chart: processor and memory load.
    case systemStats
    // Built on the base widgets, after them (the gallery lists each group in this order).
    // Control Center's other controls, each a widget as Wi-Fi is.
    case bluetooth, airDrop, darkMode, nightShift, keepAwake, microphone
    case calculator, voiceMemos, screenshot, notes, lockScreen, focus, clock, home
    case soundOutput, outputMute, trueTone, stageManager, lowPowerMode, screenMirroring, missionControl
    case showDesktop, appsLauncher, characterViewer, displaySleep
    /// Siri in the notch: a control that opens it.
    case assistant
    /// The display's and the keyboard's brightness, each a slider as Volume is.
    case brightness, keyboardBrightness
    // The next bases, each with its first widget: a readout (a value and its caption), a list, a
    // ring with the battery, and a chart.
    /// A readout: the time in another city.
    case worldClock
    /// A list: the last things copied.
    case clipboard
    /// A ring and the battery: the charge and the time left.
    case battery
    /// A chart: today's charge.
    case batteryChart
    // Built on the readout as World Clock is: one figure each, its caption and its symbol.
    /// The battery's figures: the time left, the health, the cycles, the power flowing, the
    /// temperature, the charger and the last charge.
    case batteryTime, batteryHealth, batteryCycles, batteryPower, batteryTemperature, charger, batteryLastCharge
    /// The Mac's: how long it has been up (and how warm it runs), and the free disk space.
    case uptime, diskSpace
    // The next bases, each with its first widget: a ruler, a row of files, a dial, a grid of days
    // and bars a day.
    /// A ruler to set by scrolling: the timer.
    case timer
    /// A row of files to drag out: the shelf.
    case shelf
    /// A dial with hands: the clock face.
    case analogClock
    /// A grid of days: this month.
    case monthCalendar
    /// Bars a day, one picked: the battery's daily use.
    case batteryUsage
    // Built on the bases as they are.
    /// A readout: the memory in use.
    case memory
    /// A control: records the screen; the notch shows it meanwhile.
    case screenRecording
    /// A readout: how warm the chip runs.
    case chipTemperature
    /// A dial round a fan (MacBook Pro only): the fans' speed, set by turning it; the fan in its
    /// middle gives them back to macOS.
    case fanControl

    var id: String { rawValue }

    /// Drawn as a readout (`ReadingWidget`): a value, its caption and its symbol.
    var isReadout: Bool {
        switch self {
        case .worldClock, .batteryTime, .batteryHealth, .batteryCycles, .batteryPower, .batteryTemperature, .charger,
             .batteryLastCharge, .uptime, .diskSpace, .memory, .chipTemperature: true
        default: false
        }
    }

    var spec: WidgetKindSpec { WidgetSpecs.table[self]! }

    /// The Control Center control this widget is, if it is one (they share their names).
    var systemControl: SystemControl? { SystemControl(rawValue: rawValue) }

    /// What the widget switches or opens, drawn as Wi-Fi is (`ControlWidget`).
    var control: WidgetControl? {
        switch self {
        case .assistant: .assistant
        case .screenRecording: .screenRecording
        default: systemControl.map { .system($0) }
        }
    }

    /// The level the widget shows and sets, drawn as Volume is (`LevelWidget`).
    var level: WidgetLevel? {
        switch self {
        case .volume: .volume
        case .brightness: .brightness
        case .keyboardBrightness: .keyboard
        default: nil
        }
    }

    /// Working on this Mac: the gallery offers it.
    var isOffered: Bool { spec.isAvailable() }

    var title: String { spec.title }
    var summary: String { spec.summary }
    var systemImage: String { spec.symbol }
    var category: WidgetCategory { spec.category }
    /// The sizes in reference cells (the 12 × 3 board); `BoardGrid` converts them to its own.
    var minimumSize: GridSize { spec.minimumSize }
    var maximumSize: GridSize { spec.maximumSize }
    var defaultSize: GridSize { spec.defaultSize }
    /// The elements the user may switch on or off, in the order they are drawn. The ones always
    /// drawn (`ElementSpec.isRequired`) are not among them.
    var options: [ElementID] { spec.elements.filter { !$0.isRequired }.map(\.id) }
    var defaultOptions: Set<ElementID> { Set(spec.elements.filter { $0.defaultVisible && !$0.isRequired }.map(\.id)) }

    /// Sizes offered as one-click presets in the editor: every common footprint the kind allows,
    /// smallest first (reference cells).
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

/// The gallery's groups, in order.
nonisolated enum WidgetCategory: String, Sendable, CaseIterable, Identifiable {
    case media, time, controls, battery, system, tools

    var id: String { rawValue }

    var title: String {
        switch self {
        case .media: "Media"
        case .time: "Time"
        case .controls: "Controls"
        case .battery: "Battery"
        case .system: "System"
        case .tools: "Tools"
        }
    }

    var kinds: [IslandWidgetKind] { IslandWidgetKind.allCases.filter { $0.category == self } }
}
