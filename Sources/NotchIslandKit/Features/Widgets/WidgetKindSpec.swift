import CoreGraphics
import Foundation

/// Everything the app knows about one kind of widget, as data: what the gallery shows, the sizes it
/// takes, the elements inside it and the looks it offers.
///
/// Each family of kinds keeps its specs in its own file (`Families/<Family>Spec.swift`), merged
/// here into one table, so a kind is added or changed by editing only its family's files.
nonisolated struct WidgetKindSpec: Sendable {
    var title: String
    /// One line for the widget store.
    var summary: String
    var symbol: String
    /// The app icon's gradient, top to bottom (`WidgetIcon`).
    var iconColors: [IslandTheme.RGB]
    var category: WidgetCategory
    var family: WidgetFamily
    /// In reference cells (the 12 × 3 board); `BoardGrid` converts them. Every widget works down to
    /// its minimum: below its default it drops what no longer fits (the artwork, the names, the
    /// value) instead of squeezing it.
    var minimumSize: GridSize
    var defaultSize: GridSize
    var maximumSize: GridSize
    /// In the order they are drawn.
    var elements: [ElementSpec]
    /// The arrangements the widget can be drawn in; empty when it has only one.
    var layouts: [WidgetLayout] = []
    var backgrounds: [WidgetBackground] = WidgetBackground.allCases.filter { $0 != .artwork }
    /// Its two sides can swap.
    var canMirror = false
    /// A new instance's settings (time zone, count…).
    var defaultConfig = WidgetConfig()
    /// Whether it works on this Mac (a private API, a sensor): the gallery hides it when not.
    var isAvailable: @Sendable () -> Bool = { true }
    /// What macOS asks for before it can show anything.
    var permission: WidgetPermission?
    /// False for a kind reserved but not built yet: hidden from the gallery, never placed by the
    /// app, drawn as a placeholder.
    var isImplemented = true
    /// Its elements can be placed freely (the grid inside the widget). Not for round 1 × 1
    /// widgets, controls drawn as a button, or Siri.
    var supportsCustomLayout = true

    func element(_ id: ElementID) -> ElementSpec? { elements.first { $0.id == id } }

    /// Every id a style or a custom layout may name: the elements and their parts.
    var elementIDs: Set<ElementID> { Set(elements.flatMap { [$0.id] + $0.parts }) }

    /// Every kind's spec, from the families' files.
    static let table: [IslandWidgetKind: WidgetKindSpec] = Dictionary(
        uniqueKeysWithValues: WidgetFamily.allCases.flatMap(\.specs)
    )
}

/// The kinds that share code: one spec file (`Families/`) and one view file
/// (`Views/Widgets/Families/`) each.
nonisolated enum WidgetFamily: String, Sendable, CaseIterable {
    case nowPlaying, timers, levels, battery, controls, time, system, tools, airPods

    var specs: [IslandWidgetKind: WidgetKindSpec] {
        switch self {
        case .nowPlaying: NowPlayingSpecs.all
        case .timers: TimerSpecs.all
        case .levels: LevelSpecs.all
        case .battery: BatterySpecs.all
        case .controls: ControlSpecs.all
        case .time: TimeSpecs.all
        case .system: SystemSpecs.all
        case .tools: ToolSpecs.all
        case .airPods: AirPodsSpecs.all
        }
    }
}

/// What macOS asks the user for before the widget can show anything.
nonisolated enum WidgetPermission: String, Sendable {
    case bluetooth, calendars
}

/// One element of a kind: what it is and what it needs.
nonisolated struct ElementSpec: Sendable, Hashable {
    var id: ElementID
    /// Its row in the editor.
    var title: String
    var symbol: String
    var role: ElementRole
    /// What it may read, for measuring: templates ("100%", "-88:88") or sample lines.
    var samples: [String]
    /// The colours a style may set on it.
    var colorSlots: [ColorSlot]
    /// Kept longer as room runs out: the lowest goes first.
    var priority: Int
    /// The room it needs, in points; below it the element is left out (today's thresholds).
    var minRoom: MinRoom?
    /// Switched on in a new widget.
    var defaultVisible: Bool
    /// Has a size of its own (buttons and switches do not).
    var isSizable: Bool
    /// Cannot be split or re-laid out inside (the timer's ruler, the shelf's strip, a scrubber).
    var isBlock: Bool
    /// Pieces a custom layout may place on their own (skip → previous and next).
    var parts: [ElementID]

    init(_ id: ElementID, _ title: String, symbol: String, role: ElementRole, samples: [String] = [],
         colorSlots: [ColorSlot]? = nil, priority: Int = 50, minRoom: MinRoom? = nil, defaultVisible: Bool = true,
         isSizable: Bool = true, isBlock: Bool = false, parts: [String] = []) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.role = role
        self.samples = samples
        self.colorSlots = colorSlots ?? role.colorSlots
        self.priority = priority
        self.minRoom = minRoom
        self.defaultVisible = defaultVisible
        self.isSizable = isSizable
        self.isBlock = isBlock
        self.parts = parts.map(id.part)
    }
}

nonisolated enum ElementRole: String, Sendable, CaseIterable {
    case text, symbol, image, line, chart, button, feature

    /// The colours an element of this role has.
    var colorSlots: [ColorSlot] {
        switch self {
        case .text: [.primary]
        case .symbol: [.primary, .secondary, .backing]
        case .image: [.border]
        case .line, .chart: [.fill, .fillEnd, .track]
        case .button: [.tint]
        case .feature: []
        }
    }
}

/// Room in points, per axis (nil: no limit on that axis).
nonisolated struct MinRoom: Sendable, Hashable {
    var width: CGFloat?
    var height: CGFloat?
}

nonisolated extension IslandTheme.RGB {
    /// Short, for the specs' icon colours.
    static func rgb(_ red: Double, _ green: Double, _ blue: Double) -> IslandTheme.RGB {
        IslandTheme.RGB(red: red, green: green, blue: blue)
    }
}

nonisolated extension ElementSpec {
    /// A reading with its caption and symbol: what a kind that shows one value starts with.
    static func reading(_ samples: [String], caption: String) -> [ElementSpec] {
        [ElementSpec(.value, "Value", symbol: "number", role: .text, samples: samples, priority: 90),
         ElementSpec(.label, "Caption", symbol: "textformat", role: .text, samples: [caption], priority: 40),
         ElementSpec(.symbol, "Symbol", symbol: "star", role: .symbol, priority: 60)]
    }
}
