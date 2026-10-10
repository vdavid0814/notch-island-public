import Foundation

/// The widgets' specs: the six base widgets', and the controls and levels built on Wi-Fi and Volume.
nonisolated enum WidgetSpecs {
    static let table: [IslandWidgetKind: WidgetKindSpec] = controls.merging(levels) { $1 }.merging(base) { $1 }
        .merging(nextBases) { $1 }.merging(readouts) { $1 }
        .merging(newBases) { $1 }

    /// Control Center's controls and Siri, each as Wi-Fi is: a round button, its name and its state.
    private static let controls: [IslandWidgetKind: WidgetKindSpec] = [
        .wifi: control(.wifi, "Turn Wi-Fi on or off.", blue),
        .bluetooth: control(.bluetooth, "Turn Bluetooth on or off. macOS asks for access the first time.", blue),
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
        .focus: control(.focus, "Open Focus to choose one or turn Do Not Disturb on.", [.rgb(0.55, 0.45, 1.0), .rgb(0.35, 0.22, 0.85)]),
        .clock: control(.clock, "Open Clock for alarms and world time.", graphite),
        .home: control(.home, "Open Home for your accessories.", [.rgb(1.0, 0.66, 0.2), .rgb(1.0, 0.48, 0.1)]),
        .soundOutput: control(.soundOutput, "Choose where the sound plays.", blue),
        .outputMute: control(.outputMute, "Mute or unmute the sound.", [.rgb(0.6, 0.5, 1.0), .rgb(0.4, 0.28, 0.92)]),
        .trueTone: control(.trueTone, "Turn True Tone on or off.", [.rgb(1.0, 0.88, 0.35), .rgb(0.98, 0.7, 0.1)]),
        .stageManager: control(.stageManager, "Turn Stage Manager on or off.", slate),
        .lowPowerMode: control(.lowPowerMode, "Whether Low Power Mode is on; opens Battery settings.",
                               [.rgb(1.0, 0.82, 0.25), .rgb(1.0, 0.6, 0.1)]),
        .screenMirroring: control(.screenMirroring, "Mirror or extend to another display.", blue),
        .missionControl: control(.missionControl, "Show every open window at once.", slate),
        .showDesktop: control(.showDesktop, "Move the windows aside to show the desktop.", slate),
        .appsLauncher: control(.appsLauncher, "Open the Apps launcher.", [.rgb(0.36, 0.62, 1.0), .rgb(0.86, 0.3, 0.95)]),
        .characterViewer: control(.characterViewer, "Emoji and symbols, ready to type.",
                                  [.rgb(1.0, 0.86, 0.3), .rgb(0.98, 0.7, 0.08)]),
        .displaySleep: control(.displaySleep, "Put the display to sleep.", graphite),
        // On while it records; the notch shows the recording meanwhile.
        .screenRecording: WidgetKindSpec(
            title: "Screen Recording", summary: "Record the screen. The notch shows how long, and Stop under the pointer.",
            symbol: "record.circle", iconColors: [.rgb(1.0, 0.38, 0.38), .rgb(0.85, 0.12, 0.2)], category: .controls,
            minimumSize: GridSize(width: 1, height: 1), defaultSize: GridSize(width: 2, height: 1),
            maximumSize: GridSize(width: 4, height: 2),
            elements: [
                ElementSpec(.controlButton, "Button", symbol: "record.circle", isRequired: true),
                ElementSpec(.controlName, "Name", symbol: "textformat"),
                ElementSpec(.controlStatus, "Recording or not", symbol: "power"),
            ],
            movable: [.controlButton, .controlName, .controlStatus],
            texts: [.controlName, .controlStatus],
            buttons: [.controlButton]
        ),
        // Siri opens; it has no state to show.
        .assistant: WidgetKindSpec(
            title: "Siri", summary: "Search apps and files, or ask Apple Intelligence, right in the notch.", symbol: "siri",
            iconColors: siri, category: .tools,
            minimumSize: GridSize(width: 1, height: 1), defaultSize: GridSize(width: 2, height: 1),
            maximumSize: GridSize(width: 6, height: 3),
            elements: [
                ElementSpec(.controlButton, "Button", symbol: "siri", isRequired: true),
                ElementSpec(.controlName, "Name", symbol: "textformat"),
            ],
            movable: [.controlButton, .controlName],
            texts: [.controlName],
            buttons: [.controlButton]
        ),
    ]

    /// The levels, each as Volume is: a slider with its symbol and value, a ring when about square.
    private static let levels: [IslandWidgetKind: WidgetKindSpec] = [
        .volume: level("Volume", "The output volume as a slider.", symbol: "speaker.wave.2.fill",
                       colors: [.rgb(0.6, 0.5, 1.0), .rgb(0.4, 0.28, 0.92)], category: .media),
        .brightness: level("Display Brightness", "The display brightness as a slider.", symbol: "sun.max.fill",
                           colors: [.rgb(1.0, 0.88, 0.35), .rgb(0.98, 0.7, 0.1)], category: .system),
        .keyboardBrightness: level("Keyboard Brightness", "The keyboard backlight as a slider.", symbol: "light.max",
                                   colors: [.rgb(0.5, 0.85, 0.95), .rgb(0.2, 0.6, 0.8)], category: .system),
    ]

    private static let blue: [IslandTheme.RGB] = [.rgb(0.3, 0.62, 1.0), .rgb(0.05, 0.4, 0.95)]
    private static let slate: [IslandTheme.RGB] = [.rgb(0.5, 0.52, 0.6), .rgb(0.26, 0.28, 0.36)]
    private static let graphite: [IslandTheme.RGB] = [.rgb(0.4, 0.42, 0.48), .rgb(0.14, 0.15, 0.2)]
    /// Siri's own gradient (its glyph is drawn in it, `ControlWidget`).
    static let siri: [IslandTheme.RGB] = [.rgb(0.36, 0.62, 1.0), .rgb(0.86, 0.3, 0.95)]

    /// A control as Wi-Fi is: the button always drawn, its name and its state switchable, all three
    /// moved and styled in Customize. Offered where it works on this Mac.
    private static func control(_ control: SystemControl, _ summary: String, _ colors: [IslandTheme.RGB]) -> WidgetKindSpec {
        WidgetKindSpec(
            title: control.title, summary: summary, symbol: control.symbol(on: true), iconColors: colors, category: .controls,
            minimumSize: GridSize(width: 1, height: 1), defaultSize: GridSize(width: 2, height: 1),
            maximumSize: GridSize(width: 4, height: 2),
            elements: [
                ElementSpec(.controlButton, "Button", symbol: control.symbol(on: true), isRequired: true),
                ElementSpec(.controlName, "Name", symbol: "textformat"),
                ElementSpec(.controlStatus, control.isAction ? "What it does" : "On or Off", symbol: "power"),
            ],
            movable: [.controlButton, .controlName, .controlStatus],
            texts: [.controlName, .controlStatus],
            buttons: [.controlButton],
            isAvailable: { ExtendedControls.isAvailable(control) }
        )
    }

    /// A level as Volume is: the slider always drawn, its symbol and value switchable; the symbol a
    /// button, the value a text and the slider a line in Customize.
    private static func level(_ title: String, _ summary: String, symbol: String, colors: [IslandTheme.RGB],
                              category: WidgetCategory) -> WidgetKindSpec {
        WidgetKindSpec(
            title: title, summary: summary, symbol: symbol, iconColors: colors, category: category,
            minimumSize: GridSize(width: 2, height: 1), defaultSize: GridSize(width: 5, height: 1),
            maximumSize: GridSize(width: 12, height: 2),
            elements: [
                ElementSpec(.levelIcon, "Symbol", symbol: "speaker.wave.2"),
                ElementSpec(.levelValue, "Value", symbol: "number"),
                ElementSpec(.levelSlider, "Slider", symbol: "slider.horizontal.3", isRequired: true),
            ],
            movable: [.levelIcon, .levelSlider, .levelValue],
            texts: [.levelValue],
            buttons: [.levelIcon],
            progressBars: [.levelSlider]
        )
    }

    private static let green: [IslandTheme.RGB] = [.rgb(0.4, 0.9, 0.45), .rgb(0.16, 0.7, 0.3)]

    /// The next bases, each with its first widget.
    private static let nextBases: [IslandWidgetKind: WidgetKindSpec] = [
        // A readout: its value, its caption and its symbol, each moved and styled in Customize.
        .worldClock: WidgetKindSpec(
            title: "World Clock", summary: "The time in another city.", symbol: "globe",
            iconColors: [.rgb(1.0, 0.4, 0.36), .rgb(0.95, 0.2, 0.22)], category: .time,
            minimumSize: GridSize(width: 2, height: 1), defaultSize: GridSize(width: 3, height: 1),
            maximumSize: GridSize(width: 6, height: 3),
            elements: readout,
            movable: [.symbol, .value, .label],
            texts: [.value, .label],
            buttons: [.symbol],
            settings: [.timeZone, .label]
        ),
        // Its copies, each a text and a symbol of its own: the texts set as Now Playing's are, the
        // symbols as its buttons are.
        .clipboard: WidgetKindSpec(
            title: "Clipboard", summary: "The last things you copied; a click copies one again.", symbol: "doc.on.clipboard.fill",
            iconColors: [.rgb(0.62, 0.64, 0.7), .rgb(0.38, 0.4, 0.47)], category: .tools,
            minimumSize: GridSize(width: 3, height: 1), defaultSize: GridSize(width: 4, height: 2),
            maximumSize: GridSize(width: 12, height: 3),
            elements: [ElementSpec(.clipSymbols, "Symbols", symbol: "doc.on.doc")]
                + WidgetConfig.countRange.map { ElementSpec(.clipText($0), "Copy \($0)", symbol: "doc.plaintext", isRequired: true) },
            movable: WidgetConfig.countRange.flatMap { [ElementID.clipSymbol($0), .clipText($0)] },
            texts: WidgetConfig.countRange.map { .clipText($0) },
            buttons: WidgetConfig.countRange.map { .clipSymbol($0) },
            settings: [.count, .symbols]
        ),
        // A ring (about square) or the battery (wide), the percentage and the time left.
        .battery: WidgetKindSpec(
            title: "Battery", summary: "Charge level and time remaining.", symbol: "battery.75percent",
            iconColors: green, category: .battery,
            minimumSize: GridSize(width: 1, height: 1), defaultSize: GridSize(width: 3, height: 1),
            maximumSize: GridSize(width: 6, height: 3),
            elements: [
                ElementSpec(.batteryGlyph, "Battery", symbol: "battery.75percent"),
                ElementSpec(.percentage, "Percentage", symbol: "percent"),
                ElementSpec(.timeRemaining, "Time remaining", symbol: "hourglass"),
            ],
            // The ring (about square) is a button of its own: set as every button is.
            movable: [.batteryGlyph, .batteryRing, .percentage, .timeRemaining],
            texts: [.percentage, .timeRemaining],
            buttons: [.batteryRing],
            rings: [.batteryRing],
            isAvailable: { BatteryAvailability.hasBattery }
        ),
        // A chart: the day's charge, the level and the day over it.
        .batteryChart: WidgetKindSpec(
            title: "Battery Chart", summary: "Today's charge level, like the iPhone's battery chart.", symbol: "chart.bar.fill",
            iconColors: green, category: .battery,
            minimumSize: GridSize(width: 3, height: 1), defaultSize: GridSize(width: 4, height: 2),
            maximumSize: GridSize(width: 12, height: 3),
            elements: [
                ElementSpec(.chart, "Chart", symbol: "chart.bar", isRequired: true),
                ElementSpec(.value, "Level", symbol: "number"),
                ElementSpec(.label, "Caption", symbol: "textformat"),
            ],
            movable: [.value, .label, .chart],
            texts: [.value, .label],
            charts: [.chart],
            isAvailable: { BatteryAvailability.hasBattery }
        ),
    ]

    /// The battery's and the Mac's figures, each a readout as World Clock is.
    private static let readouts: [IslandWidgetKind: WidgetKindSpec] = [
        .batteryTime: figure("Battery Time", "Time left on the battery, or until it is charged.", symbol: "hourglass"),
        .batteryHealth: figure("Battery Health", "The battery's maximum capacity and condition.", symbol: "heart.fill"),
        .batteryCycles: figure("Charge Cycles", "How many charge cycles the battery has been through.",
                               symbol: "arrow.triangle.2.circlepath"),
        .batteryPower: figure("Power", "What the Mac draws, or what the charger gives it.", symbol: "bolt.fill"),
        .batteryTemperature: figure("Temperature", "How warm the battery is.", symbol: "thermometer.medium",
                                    isAvailable: { BatteryAvailability.hasTemperature }),
        .charger: figure("Charger", "The charger's power and whether it is charging.", symbol: "powerplug.fill"),
        .batteryLastCharge: figure("Last Charge", "The level the battery was last charged to, and when.",
                                   symbol: "battery.100percent.bolt"),
        .uptime: systemReading("Uptime", "How long since the Mac started, and how warm it runs.", symbol: "clock.arrow.circlepath"),
        .diskSpace: systemReading("Disk Space", "Free space on the startup disk.", symbol: "internaldrive.fill"),
        .memory: systemReading("Memory", "How much memory is in use, as Activity Monitor counts it.", symbol: "memorychip"),
        .chipTemperature: systemReading("Chip Temperature", "How warm the chip runs: its cores on average, and the hottest.",
                                        symbol: "thermometer.medium", isAvailable: { ChipSensors.isAvailable }),
    ]

    private static let mint: [IslandTheme.RGB] = [.rgb(0.36, 0.85, 0.62), .rgb(0.1, 0.62, 0.45)]

    /// A readout's parts: the value and the caption texts, the symbol a button, each moved and
    /// styled in Customize.
    private static func reading(_ title: String, _ summary: String, symbol: String, colors: [IslandTheme.RGB],
                                category: WidgetCategory, sizes: (minimum: GridSize, standard: GridSize, maximum: GridSize),
                                isAvailable: @escaping @Sendable () -> Bool = { true }) -> WidgetKindSpec {
        WidgetKindSpec(
            title: title, summary: summary, symbol: symbol, iconColors: colors, category: category,
            minimumSize: sizes.minimum, defaultSize: sizes.standard, maximumSize: sizes.maximum,
            elements: readout,
            movable: [.symbol, .value, .label],
            texts: [.value, .label],
            buttons: [.symbol],
            isAvailable: isAvailable
        )
    }

    private static func figure(_ title: String, _ summary: String, symbol: String,
                               isAvailable: @escaping @Sendable () -> Bool = { BatteryAvailability.hasBattery }) -> WidgetKindSpec {
        reading(title, summary, symbol: symbol, colors: green, category: .battery,
                sizes: (GridSize(width: 2, height: 1), GridSize(width: 2, height: 1), GridSize(width: 4, height: 2)),
                isAvailable: isAvailable)
    }

    private static func systemReading(_ title: String, _ summary: String, symbol: String,
                                      isAvailable: @escaping @Sendable () -> Bool = { true }) -> WidgetKindSpec {
        reading(title, summary, symbol: symbol, colors: mint, category: .system,
                sizes: (GridSize(width: 2, height: 1), GridSize(width: 3, height: 1), GridSize(width: 6, height: 3)),
                isAvailable: isAvailable)
    }

    /// The next bases, each with its first widget: a ruler, a row of files, a dial, a grid of days
    /// and bars a day. Each new kind of part moves and sizes in Customize; its own look comes later.
    private static let newBases: [IslandWidgetKind: WidgetKindSpec] = [
        // A ruler: scrolled to the length, the time beside the buttons under it.
        .timer: WidgetKindSpec(
            title: "Timer", summary: "Scroll the ruler to a length and start it.", symbol: "timer",
            iconColors: [.rgb(1.0, 0.66, 0.2), .rgb(1.0, 0.45, 0.08)], category: .time,
            minimumSize: GridSize(width: 3, height: 1), defaultSize: GridSize(width: 5, height: 2),
            maximumSize: GridSize(width: 12, height: 3),
            elements: [
                ElementSpec(.ruler, "Ruler", symbol: "ruler"),
                ElementSpec(.rulerUnit, "Unit name", symbol: "textformat"),
                ElementSpec(.readout, "Time", symbol: "clock"),
                ElementSpec(.timerActions, "Start / Pause", symbol: "playpause.circle", isRequired: true),
                ElementSpec(.addMinute, "+1 Minute", symbol: "plus.circle", defaultVisible: false),
                ElementSpec(.timerHours, "Set hours", symbol: "h.circle", defaultVisible: false),
                ElementSpec(.timerSeconds, "Set seconds", symbol: "s.circle", defaultVisible: false),
            ],
            movable: [.ruler, .readout, .timerActions, .addMinute, .timerCancel],
            texts: [.readout],
            buttons: [.timerActions, .addMinute, .timerCancel],
            trailingTexts: [.readout],
            innerTexts: [.rulerUnit],
            rulers: [.ruler]
        ),
        // A row of files: their previews over the tray, the count and AirDrop and Clear.
        .shelf: WidgetKindSpec(
            title: "Shelf", summary: "Files dropped on the notch, ready to drag out.", symbol: "tray.full.fill",
            iconColors: [.rgb(0.35, 0.78, 1.0), .rgb(0.12, 0.48, 1.0)], category: .tools,
            minimumSize: GridSize(width: 2, height: 1), defaultSize: GridSize(width: 5, height: 1),
            maximumSize: GridSize(width: 12, height: 3),
            elements: [
                ElementSpec(.previews, "Files", symbol: "photo.on.rectangle"),
                ElementSpec(.shelfCount, "Tray and count", symbol: "number"),
                ElementSpec(.shelfActions, "AirDrop and Clear", symbol: "square.and.arrow.up"),
            ],
            movable: [.previews, .shelfTray, .shelfCount, .shelfAirDrop, .shelfClear],
            texts: [.shelfCount],
            buttons: [.shelfTray, .shelfAirDrop, .shelfClear],
            settings: [.files]
        ),
        // A dial: the hour and minute hands, the seconds hand switched on, a caption under it.
        .analogClock: WidgetKindSpec(
            title: "Clock Face", summary: "An analog clock, here or in another city.", symbol: "clock",
            iconColors: [.rgb(1.0, 0.4, 0.36), .rgb(0.95, 0.2, 0.22)], category: .time,
            minimumSize: GridSize(width: 1, height: 1), defaultSize: GridSize(width: 2, height: 2),
            maximumSize: GridSize(width: 4, height: 3),
            elements: [
                ElementSpec(.face, "Clock face", symbol: "clock", isRequired: true),
                ElementSpec(.secondsHand, "Seconds hand", symbol: "s.circle", defaultVisible: false),
                ElementSpec(.label, "Caption", symbol: "textformat", defaultVisible: false),
            ],
            movable: [.face, .label],
            texts: [.label],
            buttons: [.face],
            settings: [.timeZone, .label]
        ),
        // A grid of days: the month's name over them, today on a disc.
        .monthCalendar: WidgetKindSpec(
            title: "Calendar", summary: "This month at a glance.", symbol: "calendar",
            iconColors: [.rgb(1.0, 0.4, 0.36), .rgb(0.95, 0.2, 0.22)], category: .time,
            minimumSize: GridSize(width: 3, height: 2), defaultSize: GridSize(width: 4, height: 3),
            maximumSize: GridSize(width: 6, height: 3),
            elements: [
                ElementSpec(.label, "Month", symbol: "textformat"),
                ElementSpec(.monthGrid, "Days", symbol: "calendar"),
                ElementSpec(.monthWeekdays, "Weekdays", symbol: "textformat.abc"),
            ],
            movable: [.label, .monthGrid],
            texts: [.label],
            innerTexts: [.monthDays],
            dayGrids: [.monthGrid]
        ),
        // Bars a day: the title, the picked day's use and its name over the last eight days.
        .batteryUsage: WidgetKindSpec(
            title: "Daily Usage", summary: "How much battery each of the last days used, like the iPhone's Battery Usage.",
            symbol: "chart.bar.xaxis", iconColors: green, category: .battery,
            minimumSize: GridSize(width: 3, height: 2), defaultSize: GridSize(width: 4, height: 3),
            maximumSize: GridSize(width: 8, height: 3),
            elements: [
                ElementSpec(.label, "Title", symbol: "textformat"),
                ElementSpec(.value, "Percentage", symbol: "percent"),
                ElementSpec(.usageDay, "Day", symbol: "calendar"),
                ElementSpec(.chart, "Bars", symbol: "chart.bar", isRequired: true),
            ],
            movable: [.label, .value, .usageDay, .chart],
            texts: [.label, .value, .usageDay],
            charts: [.chart],
            isAvailable: { BatteryAvailability.hasBattery }
        ),
        // A dial round a fan, a dial of the chip's temperature and a graph of it over the last ten
        // minutes, in a row: the fan dial turned to set the speed, the fan in it a button that gives
        // the fans back to macOS; the speed's graph beside the temperature's where the widget is wide
        // (as wide as the panel). Each part moved and resized in Customize — a graph made lower.
        // Only where there is a fan: MacBook Pro.
        .fanControl: WidgetKindSpec(
            title: "Fan Control", summary: "The fans' speed and the chip's temperature. Turn the fan's dial to set it; click the fan for automatic.",
            symbol: "fan.fill", iconColors: [.rgb(0.4, 0.78, 1.0), .rgb(0.12, 0.45, 0.95)], category: .system,
            minimumSize: GridSize(width: 2, height: 1), defaultSize: GridSize(width: 7, height: 2),
            maximumSize: GridSize(width: 12, height: 3),
            elements: [
                ElementSpec(.fanDial, "Fan", symbol: "fan", isRequired: true),
                ElementSpec(.value, "Speed", symbol: "number"),
                ElementSpec(.label, "Automatic or Manual", symbol: "textformat"),
                ElementSpec(.tempDial, "Temperature", symbol: "thermometer.medium"),
                ElementSpec(.tempGraph, "Temperature graph", symbol: "chart.xyaxis.line"),
                ElementSpec(.rpmGraph, "Speed graph", symbol: "waveform.path.ecg", defaultVisible: false),
            ],
            movable: [.fanDial, .value, .label, .tempDial, .tempGraph, .rpmGraph],
            texts: [.value, .label],
            // The dials set as lines are, the graphs as charts are.
            progressBars: [.fanDial, .tempDial],
            innerTexts: [.fanName, .fanUnit, .tempName, .tempValue, .tempGraphText, .rpmGraphText],
            charts: [.tempGraph, .rpmGraph],
            isAvailable: { FanSensors.hasFans }
        ),
    ]

    /// A readout's elements: the value always, its caption and symbol switchable.
    private static let readout = [
        ElementSpec(.value, "Value", symbol: "number", isRequired: true),
        ElementSpec(.label, "Caption", symbol: "textformat"),
        ElementSpec(.symbol, "Symbol", symbol: "star"),
    ]

    /// The six base widgets but Wi-Fi and Volume (built above with their kin).
    private static let base: [IslandWidgetKind: WidgetKindSpec] = [
        .dateTime: WidgetKindSpec(
            title: "Date & Time", summary: "The time and today's date.", symbol: "calendar.badge.clock",
            iconColors: [.rgb(1.0, 0.4, 0.36), .rgb(0.95, 0.2, 0.22)], category: .time,
            minimumSize: GridSize(width: 2, height: 1), defaultSize: GridSize(width: 3, height: 1),
            maximumSize: GridSize(width: 6, height: 3),
            elements: [
                ElementSpec(.readout, "Time", symbol: "clock"),
                ElementSpec(.dateLine, "Date", symbol: "calendar"),
            ],
            movable: [.dateLine, .readout],
            texts: [.readout, .dateLine]
        ),
        .stopwatch: WidgetKindSpec(
            title: "Stopwatch", summary: "Start, pause and reset a stopwatch.", symbol: "stopwatch.fill",
            iconColors: [.rgb(1.0, 0.82, 0.25), .rgb(1.0, 0.6, 0.1)], category: .time,
            minimumSize: GridSize(width: 3, height: 1), defaultSize: GridSize(width: 4, height: 1),
            maximumSize: GridSize(width: 12, height: 2),
            elements: [
                ElementSpec(.readout, "Time", symbol: "clock"),
                ElementSpec(.resetButton, "Reset", symbol: "arrow.counterclockwise"),
                ElementSpec(.stopwatchButton, "Start / Pause", symbol: "playpause.circle", isRequired: true),
            ],
            movable: [.readout, .resetButton, .stopwatchButton],
            texts: [.readout],
            buttons: [.resetButton, .stopwatchButton]
        ),
        .nowPlaying: WidgetKindSpec(
            title: "Now Playing", summary: "Artwork, track and playback controls for any player.", symbol: "play.circle.fill",
            iconColors: [.rgb(1.0, 0.36, 0.47), .rgb(0.93, 0.16, 0.33)], category: .media,
            minimumSize: GridSize(width: 3, height: 1), defaultSize: GridSize(width: 7, height: 3),
            maximumSize: GridSize(width: 12, height: 3),
            elements: [
                ElementSpec(.artwork, "Artwork", symbol: "photo"),
                ElementSpec(.trackInfo, "Title", symbol: "textformat"),
                ElementSpec(.artist, "Artist", symbol: "person"),
                ElementSpec(.progress, "Progress", symbol: "minus"),
                ElementSpec(.playbackButtons, "Play / Pause", symbol: "playpause.fill"),
                ElementSpec(.skipButtons, "Previous / Next", symbol: "forward.fill"),
                ElementSpec(.seekButtons, "Back / Forward", symbol: "goforward", defaultVisible: false),
            ],
            movable: [.artwork, .trackInfo, .artist, .progress, .seekBackButton, .previousButton, .playbackButtons, .nextButton,
                      .seekForwardButton],
            texts: [.trackInfo, .artist],
            buttons: [.seekBackButton, .previousButton, .playbackButtons, .nextButton, .seekForwardButton],
            progressBars: [.progress],
            innerTexts: [.elapsedTime, .remainingTime],
            images: [.artwork]
        ),
        .systemStats: WidgetKindSpec(
            title: "System", summary: "Processor and memory load, read only while shown.", symbol: "cpu.fill",
            iconColors: [.rgb(0.36, 0.85, 0.62), .rgb(0.1, 0.62, 0.45)], category: .system,
            minimumSize: GridSize(width: 2, height: 1), defaultSize: GridSize(width: 3, height: 1),
            maximumSize: GridSize(width: 6, height: 3),
            elements: [
                ElementSpec(.cpuLoad, "Processor", symbol: "cpu"),
                ElementSpec(.memoryLoad, "Memory", symbol: "memorychip"),
            ],
            movable: [.cpuLoad, .memoryLoad],
            progressBars: [.cpuLoad, .memoryLoad],
            innerTexts: [.cpuTitle, .cpuValue, .memoryTitle, .memoryValue]
        ),
    ]
}
