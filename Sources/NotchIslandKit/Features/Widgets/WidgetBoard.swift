import CoreGraphics
import Foundation

// The expanded island's home page is a board of widgets the user arranges (Customize Island).
//
// Everything here is pure: a widget sits on whole cells of a fixed grid, so free dragging in the
// editor always lands on cell boundaries, and every edge lines up with some other edge or with the
// island's centre. The grid has an even number of columns, so a widget of even width can sit exactly
// on the notch's centre line.

/// What a widget shows.
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

    var id: String { rawValue }

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
        default: nil
        }
    }

    /// Where the widget store lists it.
    var category: WidgetCategory {
        if systemControl != nil { return .controls }
        switch self {
        case .nowPlaying, .volume: return .media
        case .timer, .stopwatch: return .time
        case .battery, .brightness, .keyboardBrightness, .systemStats: return .system
        case .dateTime: return .time
        default: return .tools
        }
    }

    var title: String {
        if let control = systemControl { return control.title }
        switch self {
        case .nowPlaying: return "Now Playing"
        case .timer: return "Timer"
        case .stopwatch: return "Stopwatch"
        case .shelf: return "Shelf"
        case .battery: return "Battery"
        case .volume: return "Volume"
        case .brightness: return "Display Brightness"
        case .keyboardBrightness: return "Keyboard Brightness"
        case .assistant: return "Siri"
        case .dateTime: return "Date & Time"
        case .systemStats: return "System"
        default: return rawValue
        }
    }

    /// One line for the widget store.
    var summary: String {
        switch self {
        case .nowPlaying: "Artwork, track and playback controls for any player."
        case .timer: "Scroll the ruler to a length and start it."
        case .stopwatch: "Start, pause and reset a stopwatch."
        case .shelf: "Files dropped on the notch, ready to drag out."
        case .battery: "Charge level and time remaining."
        case .volume: "The output volume as a slider."
        case .brightness: "The display brightness as a slider."
        case .keyboardBrightness: "The keyboard backlight as a slider."
        case .assistant: "Search apps and files, or ask Apple Intelligence, right in the notch."
        case .wifi: "Turn Wi-Fi on or off."
        case .bluetooth: "Turn Bluetooth on or off. macOS asks for access the first time."
        case .airDrop: "Open AirDrop."
        case .darkMode: "Switch between Dark and Light Mode."
        case .nightShift: "Warmer colours for the evening."
        case .keepAwake: "Keep the Mac and its display awake until you turn it off."
        case .microphone: "Mute or unmute the microphone."
        case .calculator: "Open Calculator."
        case .voiceMemos: "Open Voice Memos to record."
        case .screenshot: "Take a screenshot or a screen recording."
        case .notes: "Open Notes."
        case .lockScreen: "Lock the Mac at once."
        case .focus: "Choose a Focus or turn Do Not Disturb on."
        case .clock: "Open Clock for alarms and world time."
        case .home: "Open Home for your accessories."
        case .dateTime: "The time and today's date."
        case .systemStats: "Processor and memory load, read only while shown."
        }
    }

    var systemImage: String {
        if let control = systemControl { return control.symbol(on: true) }
        switch self {
        case .nowPlaying: return "play.circle.fill"
        case .timer: return "timer"
        case .stopwatch: return "stopwatch.fill"
        case .shelf: return "tray.full.fill"
        case .battery: return "battery.75percent"
        case .volume: return "speaker.wave.2.fill"
        case .brightness: return "sun.max.fill"
        case .keyboardBrightness: return "light.max"
        case .assistant: return "siri"
        case .dateTime: return "calendar.badge.clock"
        case .systemStats: return "cpu.fill"
        default: return "questionmark"
        }
    }

    /// Every widget works down to this: below its default it drops what no longer fits (the
    /// artwork, the names, the value) instead of squeezing it.
    var minimumSize: GridSize {
        if systemControl != nil { return GridSize(width: 1, height: 1) }
        switch self {
        case .nowPlaying, .timer, .stopwatch: return GridSize(width: 3, height: 1)
        case .shelf, .volume, .brightness, .keyboardBrightness, .dateTime, .systemStats: return GridSize(width: 2, height: 1)
        default: return GridSize(width: 1, height: 1)
        }
    }

    var maximumSize: GridSize {
        if systemControl != nil { return GridSize(width: 4, height: 2) }
        switch self {
        case .battery, .assistant: return GridSize(width: 6, height: 3)
        case .volume, .brightness, .keyboardBrightness, .stopwatch: return GridSize(width: 12, height: 2)
        case .dateTime, .systemStats: return GridSize(width: 6, height: 3)
        default: return GridSize(width: WidgetBoard.columns, height: WidgetBoard.rows)
        }
    }

    /// Controls start as a tile with their name, the way Control Center shows them.
    var defaultSize: GridSize {
        if systemControl != nil { return GridSize(width: 2, height: 1) }
        switch self {
        case .nowPlaying: return GridSize(width: 7, height: 3)
        case .timer: return GridSize(width: 5, height: 2)
        case .stopwatch: return GridSize(width: 4, height: 1)
        case .shelf: return GridSize(width: 5, height: 1)
        case .battery: return GridSize(width: 3, height: 1)
        case .volume, .brightness, .keyboardBrightness: return GridSize(width: 5, height: 1)
        case .dateTime, .systemStats: return GridSize(width: 3, height: 1)
        default: return GridSize(width: 2, height: 1)
        }
    }

    /// The widget's elements — the parts the user may switch on or off and size — in the order
    /// they are drawn.
    var options: [WidgetOption] {
        if systemControl != nil { return [.controlName, .controlStatus] }
        switch self {
        case .nowPlaying: return [.artwork, .trackInfo, .artist, .progress, .playbackButtons, .skipButtons]
        case .timer: return [.ruler, .readout, .addMinute, .timerSeconds, .timerHours]
        case .stopwatch: return [.readout, .resetButton]
        case .shelf: return [.previews, .shelfCount, .shelfActions]
        case .battery: return [.batteryGlyph, .percentage, .timeRemaining]
        case .volume, .brightness, .keyboardBrightness: return [.levelIcon, .levelValue]
        case .assistant: return [.assistantLabel]
        case .dateTime: return [.readout, .dateLine]
        case .systemStats: return [.cpuLoad, .memoryLoad]
        default: return []
        }
    }

    var defaultOptions: Set<WidgetOption> {
        switch self {
        case .timer: [.ruler, .readout]
        default: Set(options)
        }
    }

    /// Elements that did not exist in boards saved before elements (version 1): they are switched
    /// on there, so an old widget keeps looking the way it did.
    var elementsAddedInVersion2: Set<WidgetOption> {
        switch self {
        case .nowPlaying: [.artist, .playbackButtons]
        case .stopwatch: [.readout]
        case .shelf: [.shelfCount]
        case .battery: [.batteryGlyph]
        case .assistant: [.assistantLabel]
        default: []
        }
    }

    /// The arrangements the widget can be drawn in; empty when it has only one.
    var layouts: [WidgetLayout] {
        if systemControl != nil { return [.automatic, .button, .tile] }
        switch self {
        case .nowPlaying: return [.automatic, .beside, .cover, .minimal]
        case .battery: return [.automatic, .glyph, .ring]
        case .volume, .brightness, .keyboardBrightness: return [.automatic, .slider, .ring]
        default: return []
        }
    }

    /// The backgrounds it offers (the artwork only where there is one).
    var backgrounds: [WidgetBackground] {
        self == .nowPlaying ? WidgetBackground.allCases : WidgetBackground.allCases.filter { $0 != .artwork }
    }

    /// Sizes offered as one-click presets in the editor, like a widget gallery's families: every
    /// common footprint the kind allows, smallest first.
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

/// How large an element is drawn, relative to what fits the widget.
nonisolated enum ElementSize: String, Sendable, Codable, CaseIterable, Identifiable {
    case small, medium, large

    var id: String { rawValue }

    var title: String {
        switch self {
        case .small: "S"
        case .medium: "M"
        case .large: "L"
        }
    }

    var accessibilityTitle: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }

    var factor: CGFloat {
        switch self {
        case .small: 0.8
        case .medium: 1
        case .large: 1.25
        }
    }
}

/// A widget's arrangement. `automatic` picks one from the widget's size.
nonisolated enum WidgetLayout: String, Sendable, Codable, CaseIterable, Identifiable {
    case automatic
    /// Now Playing: artwork beside the title and the controls.
    case beside
    /// Now Playing: the artwork fills the widget, everything else on top of it.
    case cover
    /// Now Playing: one line — a small cover, the title and play.
    case minimal
    /// Battery: the battery with its charge inside.
    case glyph
    /// Battery, levels: a ring filled to the value.
    case ring
    /// Levels: a slider.
    case slider
    /// Controls: Control Center's round button.
    case button
    /// Controls: the button with its name, like Control Center's wide tiles.
    case tile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .beside: "Beside"
        case .cover: "Cover"
        case .minimal: "Minimal"
        case .glyph: "Battery"
        case .ring: "Ring"
        case .slider: "Slider"
        case .button: "Button"
        case .tile: "Tile"
        }
    }

    var systemImage: String {
        switch self {
        case .automatic: "wand.and.sparkles"
        case .beside: "rectangle.lefthalf.inset.filled"
        case .cover: "photo.fill"
        case .minimal: "rectangle.compress.vertical"
        case .glyph: "battery.75percent"
        case .ring: "circle.dashed.inset.filled"
        case .slider: "slider.horizontal.below.rectangle"
        case .button: "circle.fill"
        case .tile: "capsule.lefthalf.filled"
        }
    }
}

/// What a widget sits on.
nonisolated enum WidgetBackground: String, Sendable, Codable, CaseIterable, Identifiable {
    /// Straight on the island.
    case none
    /// A faint rounded plate.
    case plate
    /// The plate in the widget's colour.
    case tinted
    /// Now Playing: the blurred artwork.
    case artwork

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "None"
        case .plate: "Plate"
        case .tinted: "Colour"
        case .artwork: "Artwork"
        }
    }

    /// Whether it has a strength to set (None has nothing to draw).
    var hasOpacity: Bool { self != .none }

    /// The strength each background is drawn with until the user sets one (plate 40 %, as the
    /// user chose; colour and artwork as they looked before the setting existed).
    var defaultOpacity: Double {
        switch self {
        case .none: 0
        case .plate: 0.4
        case .tinted: 0.5
        case .artwork: 1
        }
    }
}

/// The widget store's groups, in order.
nonisolated enum WidgetCategory: String, Sendable, CaseIterable, Identifiable {
    case media, time, controls, system, tools

    var id: String { rawValue }

    var title: String {
        switch self {
        case .media: "Media"
        case .time: "Timers"
        case .controls: "Controls"
        case .system: "Display and Battery"
        case .tools: "Tools"
        }
    }

    var kinds: [IslandWidgetKind] { IslandWidgetKind.allCases.filter { $0.category == self } }
}

/// A control a widget can show or hide.
nonisolated enum WidgetOption: String, Sendable, Codable, CaseIterable, Identifiable {
    case artwork, trackInfo, progress, skipButtons
    case ruler, readout, addMinute
    /// The timer is set in seconds too, and in hours (`TimerDraftUnits`).
    case timerSeconds, timerHours
    case resetButton
    case previews, shelfActions
    case percentage, timeRemaining
    case levelIcon, levelValue
    /// A control widget's name and its On / Off (shown when it is wider than its button).
    case controlName, controlStatus
    // Since version 2 (elements).
    case artist, playbackButtons
    case shelfCount
    case batteryGlyph
    case assistantLabel
    // New widgets.
    case dateLine, cpuLoad, memoryLoad

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .artwork: "photo"
        case .trackInfo: "textformat"
        case .artist: "person"
        case .progress: "minus"
        case .playbackButtons: "playpause.fill"
        case .skipButtons: "forward.fill"
        case .ruler: "ruler"
        case .readout: "clock"
        case .addMinute: "plus.circle"
        case .timerSeconds: "s.circle"
        case .timerHours: "h.circle"
        case .resetButton: "arrow.counterclockwise"
        case .previews: "photo.on.rectangle"
        case .shelfCount: "number"
        case .shelfActions: "square.and.arrow.up"
        case .batteryGlyph: "battery.75percent"
        case .percentage: "percent"
        case .timeRemaining: "hourglass"
        case .levelIcon: "speaker.wave.2"
        case .levelValue: "number"
        case .controlName: "textformat"
        case .controlStatus: "power"
        case .assistantLabel: "textformat"
        case .dateLine: "calendar"
        case .cpuLoad: "cpu"
        case .memoryLoad: "memorychip"
        }
    }

    /// Whether the element has a size of its own (buttons and switches do not).
    var isSizable: Bool {
        switch self {
        case .artwork, .trackInfo, .artist, .playbackButtons, .ruler, .readout, .previews, .shelfCount,
             .batteryGlyph, .percentage, .timeRemaining, .levelIcon, .levelValue, .controlName, .controlStatus,
             .assistantLabel, .dateLine, .cpuLoad, .memoryLoad:
            true
        default:
            false
        }
    }

    var title: String {
        switch self {
        case .artwork: "Artwork"
        case .trackInfo: "Title"
        case .progress: "Progress bar"
        case .skipButtons: "Previous and next buttons"
        case .ruler: "Ruler"
        case .readout: "Time"
        case .addMinute: "+1 minute button"
        case .timerSeconds: "Set seconds"
        case .timerHours: "Set hours"
        case .resetButton: "Reset button"
        case .previews: "File previews"
        case .shelfActions: "AirDrop and Clear buttons"
        case .percentage: "Percentage"
        case .timeRemaining: "Time remaining"
        case .levelIcon: "Symbol"
        case .levelValue: "Value"
        case .controlName: "Name"
        case .controlStatus: "On or Off"
        case .artist: "Artist"
        case .playbackButtons: "Play and pause"
        case .shelfCount: "Item count"
        case .batteryGlyph: "Battery"
        case .assistantLabel: "Name"
        case .dateLine: "Date"
        case .cpuLoad: "Processor"
        case .memoryLoad: "Memory"
        }
    }
}

nonisolated struct GridSize: Sendable, Codable, Hashable {
    var width: Int
    var height: Int
}

/// Whole cells: column and row of the top-left cell, and the size in cells.
nonisolated struct GridRect: Sendable, Codable, Hashable {
    var column: Int
    var row: Int
    var width: Int
    var height: Int

    var size: GridSize { GridSize(width: width, height: height) }
    var maxColumn: Int { column + width }
    var maxRow: Int { row + height }

    func intersects(_ other: GridRect) -> Bool {
        column < other.maxColumn && other.column < maxColumn && row < other.maxRow && other.row < maxRow
    }

    /// Centred on the board's vertical centre line (the notch).
    var isHorizontallyCentred: Bool { column * 2 + width == WidgetBoard.columns }
    var isVerticallyCentred: Bool { row * 2 + height == WidgetBoard.rows }
}

nonisolated struct IslandWidget: Sendable, Codable, Hashable, Identifiable {
    /// Boards before this had no element sizes, layouts or backgrounds.
    static let version = 2

    var kind: IslandWidgetKind
    var frame: GridRect
    /// The elements switched on.
    var options: Set<WidgetOption>
    /// Element sizes other than medium.
    var sizes: [WidgetOption: ElementSize] = [:]
    /// The widget's accent colour (buttons, sliders, the timer).
    var tint: WidgetTint = .automatic
    var layout: WidgetLayout = .automatic
    var background: WidgetBackground = .plate
    /// How strongly the background is drawn, 0…1; nil is the background's own default
    /// (`WidgetBackground.defaultOpacity`). Reset whenever the background changes.
    var backgroundOpacity: Double?
    /// Now Playing's buttons all in the plain (colourless) glass. Off: each button's own look.
    var plainButtons = true
    /// Each Now Playing button's colour and strength (`TransportButton.rawValue` → look).
    var buttonLooks: [String: ButtonLook] = [:]
    /// Its two sides swapped: the artwork on the right, the time on the left…
    var mirrored = false

    init(kind: IslandWidgetKind, frame: GridRect, options: Set<WidgetOption>) {
        self.kind = kind
        self.frame = frame
        self.options = options
    }

    /// One widget per kind: the kind is the identity.
    var id: IslandWidgetKind { kind }

    func shows(_ option: WidgetOption) -> Bool { options.contains(option) }

    func size(of element: WidgetOption) -> ElementSize { sizes[element] ?? .medium }

    /// Drawn on a plate (plain, tinted or the artwork), or straight on the island.
    var showsPlate: Bool {
        get { background != .none }
        set { background = newValue ? (background == .none ? .plate : background) : .none }
    }

    private enum CodingKeys: String, CodingKey {
        case version, kind, frame, options, sizes, tint, layout, background, backgroundOpacity, showsPlate, mirrored
        case plainButtons, buttonLooks
    }

    func look(of button: TransportButton) -> ButtonLook { buttonLooks[button.rawValue] ?? ButtonLook() }

    /// The background's strength as drawn.
    var effectiveBackgroundOpacity: Double { backgroundOpacity ?? background.defaultOpacity }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.version, forKey: .version)
        try container.encode(kind, forKey: .kind)
        try container.encode(frame, forKey: .frame)
        try container.encode(options.map(\.rawValue).sorted(), forKey: .options)
        try container.encode(Dictionary(uniqueKeysWithValues: sizes.map { ($0.key.rawValue, $0.value) }), forKey: .sizes)
        try container.encode(tint, forKey: .tint)
        try container.encode(layout, forKey: .layout)
        try container.encode(background, forKey: .background)
        try container.encodeIfPresent(backgroundOpacity, forKey: .backgroundOpacity)
        try container.encode(mirrored, forKey: .mirrored)
        try container.encode(plainButtons, forKey: .plainButtons)
        if !buttonLooks.isEmpty { try container.encode(buttonLooks, forKey: .buttonLooks) }
    }

    // Boards saved before a field existed decode with its default.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(IslandWidgetKind.self, forKey: .kind)
        frame = try container.decode(GridRect.self, forKey: .frame)
        let version = (try? container.decodeIfPresent(Int.self, forKey: .version)) ?? 1
        options = Set((try? container.decode([String].self, forKey: .options))?.compactMap(WidgetOption.init) ?? [])
        if version < 2 { options.formUnion(kind.elementsAddedInVersion2) }
        let rawSizes = (try? container.decodeIfPresent([String: ElementSize].self, forKey: .sizes)) ?? [:]
        sizes = Dictionary(uniqueKeysWithValues: rawSizes.compactMap { key, value in
            WidgetOption(rawValue: key).map { ($0, value) }
        })
        tint = (try? container.decodeIfPresent(WidgetTint.self, forKey: .tint)) ?? .automatic
        layout = (try? container.decodeIfPresent(WidgetLayout.self, forKey: .layout)) ?? .automatic
        if let background = try? container.decodeIfPresent(WidgetBackground.self, forKey: .background) {
            self.background = background
        } else {
            background = ((try? container.decodeIfPresent(Bool.self, forKey: .showsPlate)) ?? true) ? .plate : .none
        }
        backgroundOpacity = (try? container.decodeIfPresent(Double.self, forKey: .backgroundOpacity))
            .flatMap { $0 }.map { min(max($0, 0), 1) }
        mirrored = (try? container.decodeIfPresent(Bool.self, forKey: .mirrored)) ?? false
        plainButtons = (try? container.decodeIfPresent(Bool.self, forKey: .plainButtons)) ?? true
        buttonLooks = (try? container.decodeIfPresent([String: ButtonLook].self, forKey: .buttonLooks)) ?? [:]
    }
}

/// Now Playing's three buttons, each with its own look.
nonisolated enum TransportButton: String, Sendable, CaseIterable, Identifiable {
    case previous, playPause, next

    var id: String { rawValue }

    var title: String {
        switch self {
        case .previous: "Previous"
        case .playPause: "Play and Pause"
        case .next: "Next"
        }
    }

    var systemImage: String {
        switch self {
        case .previous: "backward.fill"
        case .playPause: "playpause.fill"
        case .next: "forward.fill"
        }
    }
}

/// A button's glass: a colour (automatic = colourless) and how strongly it is tinted, 0…1.
nonisolated struct ButtonLook: Sendable, Codable, Hashable {
    var tint: WidgetTint = .automatic
    var opacity: Double = 0.5

    init(tint: WidgetTint = .automatic, opacity: Double = 0.5) {
        self.tint = tint
        self.opacity = opacity
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tint = (try? container.decodeIfPresent(WidgetTint.self, forKey: .tint)) ?? .automatic
        opacity = min(max((try? container.decodeIfPresent(Double.self, forKey: .opacity)) ?? 0.5, 0), 1)
    }
}

/// A widget's accent colour. `automatic` is the kind's own (orange for the timer, the system
/// accent elsewhere).
nonisolated enum WidgetTint: String, Sendable, Codable, CaseIterable, Identifiable {
    case automatic, blue, purple, pink, red, orange, yellow, green, mint, teal, gray

    var id: String { rawValue }

    var title: String { self == .automatic ? "Automatic" : rawValue.capitalized }
}

nonisolated extension IslandWidgetKind {
    /// Which widgets can swap their two sides.
    var canMirror: Bool {
        switch self {
        case .nowPlaying, .timer, .stopwatch, .battery, .volume, .brightness, .keyboardBrightness: true
        default: false
        }
    }
}


/// The arrangement of the home page.
nonisolated struct WidgetBoard: Sendable, Codable, Equatable {
    /// Twelve columns by three rows gives near-square cells on the standard island, each row tall
    /// enough for one row of controls.
    static let columns = 12
    static let rows = 3

    private(set) var widgets: [IslandWidget]

    init(widgets: [IslandWidget]) {
        self.widgets = []
        for widget in widgets where !contains(widget.kind) && isFree(widget.frame, for: widget.kind) {
            self.widgets.append(widget)
        }
    }

    /// Now Playing on the left, the timer over the shelf on the right: the page this app shipped with.
    static let standard = WidgetBoard(widgets: [
        IslandWidget(kind: .nowPlaying, frame: GridRect(column: 0, row: 0, width: 7, height: 3),
                     options: IslandWidgetKind.nowPlaying.defaultOptions),
        IslandWidget(kind: .timer, frame: GridRect(column: 7, row: 0, width: 5, height: 2),
                     options: IslandWidgetKind.timer.defaultOptions),
        IslandWidget(kind: .shelf, frame: GridRect(column: 7, row: 2, width: 5, height: 1),
                     options: IslandWidgetKind.shelf.defaultOptions),
    ])

    func contains(_ kind: IslandWidgetKind) -> Bool { widgets.contains { $0.kind == kind } }

    func widget(_ kind: IslandWidgetKind) -> IslandWidget? { widgets.first { $0.kind == kind } }

    /// Inside the board, within the kind's size limits, and not over another widget.
    func isFree(_ rect: GridRect, for kind: IslandWidgetKind) -> Bool {
        isInBounds(rect) && fits(rect.size, kind) && !widgets.contains { $0.kind != kind && $0.frame.intersects(rect) }
    }

    func isInBounds(_ rect: GridRect) -> Bool {
        rect.column >= 0 && rect.row >= 0 && rect.width >= 1 && rect.height >= 1
            && rect.maxColumn <= Self.columns && rect.maxRow <= Self.rows
    }

    func fits(_ size: GridSize, _ kind: IslandWidgetKind) -> Bool {
        let lower = kind.minimumSize, upper = kind.maximumSize
        return (lower.width...upper.width).contains(size.width) && (lower.height...upper.height).contains(size.height)
    }

    /// The first free place, reading order, for the kind's default size, or failing that for any
    /// smaller size down to its minimum (largest area first).
    func freeSlot(for kind: IslandWidgetKind) -> GridRect? {
        let lower = kind.minimumSize, preferred = kind.defaultSize
        var sizes: [GridSize] = []
        for width in lower.width...preferred.width {
            for height in lower.height...preferred.height {
                sizes.append(GridSize(width: width, height: height))
            }
        }
        sizes.sort { ($0.width * $0.height, $0.width) > ($1.width * $1.height, $1.width) }
        for size in sizes {
            for row in 0...(Self.rows - size.height) {
                for column in 0...(Self.columns - size.width) {
                    let rect = GridRect(column: column, row: row, width: size.width, height: size.height)
                    if isFree(rect, for: kind) { return rect }
                }
            }
        }
        return nil
    }

    /// Where the kind fits at `size`, nearest to `anchor` (usually where it is now): the anchor's
    /// own corner when that is free, otherwise the free place closest to it, same row first.
    func placement(for kind: IslandWidgetKind, size: GridSize, near anchor: GridRect) -> GridRect? {
        guard fits(size, kind), size.width <= Self.columns, size.height <= Self.rows else { return nil }
        var best: (rect: GridRect, distance: Int)?
        for row in 0...(Self.rows - size.height) {
            for column in 0...(Self.columns - size.width) {
                let rect = GridRect(column: column, row: row, width: size.width, height: size.height)
                guard isFree(rect, for: kind) else { continue }
                let distance = abs(column - anchor.column) + 3 * abs(row - anchor.row)
                if best.map({ distance < $0.distance }) ?? true { best = (rect, distance) }
            }
        }
        return best?.rect
    }

    /// Adds the kind where there is room. False when it is already there or nothing fits.
    @discardableResult
    mutating func add(_ kind: IslandWidgetKind) -> Bool {
        guard !contains(kind), let rect = freeSlot(for: kind) else { return false }
        widgets.append(IslandWidget(kind: kind, frame: rect, options: kind.defaultOptions))
        return true
    }

    mutating func remove(_ kind: IslandWidgetKind) {
        widgets.removeAll { $0.kind == kind }
    }

    /// Moves or resizes; refused (false) when the new frame is not free.
    @discardableResult
    mutating func setFrame(_ rect: GridRect, for kind: IslandWidgetKind) -> Bool {
        guard let index = widgets.firstIndex(where: { $0.kind == kind }), isFree(rect, for: kind) else { return false }
        widgets[index].frame = rect
        return true
    }

    /// Changes a widget's style (tint, plate, mirroring); its frame and kind stay.
    mutating func update(_ kind: IslandWidgetKind, _ change: (inout IslandWidget) -> Void) {
        guard let index = widgets.firstIndex(where: { $0.kind == kind }) else { return }
        var widget = widgets[index]
        change(&widget)
        widget.kind = kind
        widget.frame = widgets[index].frame
        widget.sanitize()
        widgets[index] = widget
    }

    mutating func setOption(_ option: WidgetOption, _ on: Bool, for kind: IslandWidgetKind) {
        guard let index = widgets.firstIndex(where: { $0.kind == kind }), kind.options.contains(option) else { return }
        if on {
            widgets[index].options.insert(option)
        } else {
            widgets[index].options.remove(option)
        }
    }

    // Decoding drops anything invalid (a hand-edited or older plist), keeping the rest.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // One widget at a time: a widget this version does not know (or an old one that was
        // replaced) is dropped, never the whole board.
        let decoded = ((try? container.decode([Lossy<IslandWidget>].self, forKey: .widgets)) ?? []).compactMap(\.value)
        self.init(widgets: decoded.map { widget in
            var widget = widget
            widget.sanitize()
            return widget
        })
    }
}

nonisolated extension IslandWidget {
    /// Drops what the kind does not have: elements, sizes, a layout or a background.
    mutating func sanitize() {
        options.formIntersection(kind.options)
        sizes = sizes.filter { kind.options.contains($0.key) && $0.key.isSizable && $0.value != .medium }
        if !kind.layouts.contains(layout) { layout = .automatic }
        if !kind.backgrounds.contains(background) { background = .plate }
    }
}

/// Points ↔ cells for a board drawn in `size` with `gap` between cells.
nonisolated struct WidgetBoardGeometry: Sendable, Equatable {
    let size: CGSize
    let gap: CGFloat

    var cellWidth: CGFloat { (size.width - gap * CGFloat(WidgetBoard.columns - 1)) / CGFloat(WidgetBoard.columns) }
    var cellHeight: CGFloat { (size.height - gap * CGFloat(WidgetBoard.rows - 1)) / CGFloat(WidgetBoard.rows) }

    func frame(for rect: GridRect) -> CGRect {
        CGRect(
            x: CGFloat(rect.column) * (cellWidth + gap),
            y: CGFloat(rect.row) * (cellHeight + gap),
            width: CGFloat(rect.width) * cellWidth + CGFloat(rect.width - 1) * gap,
            height: CGFloat(rect.height) * cellHeight + CGFloat(rect.height - 1) * gap
        )
    }

    /// The column whose leading edge is nearest to `x` (0…columns).
    func columnEdge(nearest x: CGFloat) -> Int {
        min(max(Int((x / (cellWidth + gap)).rounded()), 0), WidgetBoard.columns)
    }

    func rowEdge(nearest y: CGFloat) -> Int {
        min(max(Int((y / (cellHeight + gap)).rounded()), 0), WidgetBoard.rows)
    }

    /// A widget of `size` dragged so its top-left corner is at `origin`: the nearest whole-cell
    /// position, kept inside the board.
    func snappedMove(origin: CGPoint, size: GridSize) -> GridRect {
        GridRect(
            column: min(columnEdge(nearest: origin.x), WidgetBoard.columns - size.width),
            row: min(rowEdge(nearest: origin.y), WidgetBoard.rows - size.height),
            width: size.width,
            height: size.height
        )
    }

    /// A widget whose edges were dragged to `frame`: each edge snaps to the nearest cell boundary,
    /// then the size is clamped to the kind's limits, holding the edge that was not dragged.
    func snappedResize(frame: CGRect, from rect: GridRect, kind: IslandWidgetKind,
                       movesLeading: Bool, movesTop: Bool) -> GridRect {
        let lower = kind.minimumSize, upper = kind.maximumSize
        var left = columnEdge(nearest: frame.minX), right = columnEdge(nearest: frame.maxX + gap)
        var top = rowEdge(nearest: frame.minY), bottom = rowEdge(nearest: frame.maxY + gap)
        if movesLeading {
            right = rect.maxColumn
            left = min(max(left, right - upper.width), right - lower.width)
            left = max(left, 0)
        } else {
            left = rect.column
            right = max(min(right, left + upper.width), left + lower.width)
            right = min(right, WidgetBoard.columns)
        }
        if movesTop {
            bottom = rect.maxRow
            top = min(max(top, bottom - upper.height), bottom - lower.height)
            top = max(top, 0)
        } else {
            top = rect.row
            bottom = max(min(bottom, top + upper.height), top + lower.height)
            bottom = min(bottom, WidgetBoard.rows)
        }
        return GridRect(column: left, row: top, width: right - left, height: bottom - top)
    }
}

/// Decodes a value, or nil where it cannot be decoded, so one bad element does not fail an array.
nonisolated struct Lossy<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: any Decoder) throws {
        value = try? Value(from: decoder)
    }
}
