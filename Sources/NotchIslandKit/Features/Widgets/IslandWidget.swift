import CoreGraphics
import CryptoKit
import Foundation

/// One widget on the board. A kind may be on the board more than once, each instance with its own
/// look; the id tells them apart.
nonisolated struct WidgetID: RawRepresentable, Hashable, Codable, Sendable, CustomStringConvertible {
    let rawValue: UUID

    init(rawValue: UUID) { self.rawValue = rawValue }

    /// A new instance.
    init() { rawValue = UUID() }

    /// A UUID derived from `name` (its SHA-256, with the version 8 and variant bits set): the same
    /// name gives the same id on every Mac and every launch.
    init(name: String) {
        var bytes = Array(SHA256.hash(data: Data(name.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x80
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        rawValue = UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                               bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    init?(string: String) {
        guard let uuid = UUID(uuidString: string) else { return nil }
        rawValue = uuid
    }

    /// The id of a widget from a board saved before ids (one widget per kind then), so migrating
    /// gives the same ids every time.
    static func legacy(_ kind: IslandWidgetKind) -> WidgetID { WidgetID(name: "notchisland.widget." + kind.rawValue) }

    var description: String { rawValue.uuidString }

    // As the UUID's string alone.
    init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(UUID.self)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

nonisolated struct IslandWidget: Sendable, Codable, Hashable, Identifiable {
    /// 1: elements only. 2: element sizes, layouts and backgrounds. 3: ids, style and settings.
    static let version = 3

    var id: WidgetID
    var kind: IslandWidgetKind
    var frame: GridRect
    /// The elements switched on.
    var options: Set<ElementID>
    /// Element sizes other than medium.
    var sizes: [ElementID: ElementSize] = [:]
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
    /// Its elements' and its own look (Customize); empty is the kind's own look.
    var style = WidgetStyle()
    /// What this instance shows (a time zone, a label, apps…).
    var config: WidgetConfig

    /// Without an id, the kind's legacy one: the first instance of a kind, as boards had them.
    init(kind: IslandWidgetKind, frame: GridRect, options: Set<ElementID>, id: WidgetID? = nil) {
        self.id = id ?? .legacy(kind)
        self.kind = kind
        self.frame = frame
        self.options = options
        config = kind.spec.defaultConfig
    }

    /// Switched on, or always drawn (`ElementSpec.isRequired`).
    func shows(_ element: ElementID) -> Bool {
        options.contains(element) || kind.spec.element(element)?.isRequired == true
    }

    func size(of element: ElementID) -> ElementSize { sizes[element] ?? .medium }

    /// Drawn on a plate (plain, tinted or the artwork), or straight on the island.
    var showsPlate: Bool {
        get { background != .none }
        set { background = newValue ? (background == .none ? .plate : background) : .none }
    }

    private enum CodingKeys: String, CodingKey {
        case version, id, kind, frame, options, sizes, tint, layout, background, backgroundOpacity, showsPlate, mirrored
        case plainButtons, buttonLooks, style, config
    }

    func look(of button: TransportButton) -> ButtonLook { buttonLooks[button.rawValue] ?? ButtonLook() }

    /// The background's strength as drawn.
    var effectiveBackgroundOpacity: Double { backgroundOpacity ?? background.defaultOpacity }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.version, forKey: .version)
        try container.encode(id, forKey: .id)
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
        if !style.isEmpty { try container.encode(style, forKey: .style) }
        if config != kind.spec.defaultConfig { try container.encode(config, forKey: .config) }
    }

    // Boards saved before a field existed decode with its default; one without ids (before
    // version 3) gets the kind's legacy id (`WidgetMigration`).
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(IslandWidgetKind.self, forKey: .kind)
        frame = try container.decode(GridRect.self, forKey: .frame)
        id = (try? container.decodeIfPresent(WidgetID.self, forKey: .id)).flatMap { $0 } ?? .legacy(kind)
        let version = (try? container.decodeIfPresent(Int.self, forKey: .version)) ?? 1
        options = Set((try? container.decode([String].self, forKey: .options))?.map(ElementID.init) ?? [])
        if version < 2 { options.formUnion(WidgetMigration.elementsAddedInVersion2(kind)) }
        let rawSizes = (try? container.decodeIfPresent([String: ElementSize].self, forKey: .sizes)) ?? [:]
        sizes = Dictionary(uniqueKeysWithValues: rawSizes.map { (ElementID(rawValue: $0.key), $0.value) })
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
        style = (try? container.decodeIfPresent(WidgetStyle.self, forKey: .style)).flatMap { $0 } ?? WidgetStyle()
        config = (try? container.decodeIfPresent(WidgetConfig.self, forKey: .config)).flatMap { $0 } ?? kind.spec.defaultConfig
    }

    /// Drops what the kind does not have: elements, sizes, a layout, a background, styles of
    /// elements it lacks; and clamps the style and settings to their ranges.
    mutating func sanitize() {
        let spec = kind.spec
        options.formIntersection(kind.options)
        sizes = sizes.filter { spec.element($0.key)?.isSizable == true && $0.value != .medium }
        if !spec.layouts.contains(layout) { layout = .automatic }
        if !spec.backgrounds.contains(background) { background = .plate }
        style.sanitize(for: kind)
        config.sanitize()
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
    /// Two colours (`SurfaceStyle.fill`, `fillEnd`), the widget's accent fading by default.
    case gradient
    /// A picture of the user's (`SurfaceStyle.imagePath`).
    case image

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "None"
        case .plate: "Plate"
        case .tinted: "Colour"
        case .artwork: "Artwork"
        case .gradient: "Gradient"
        case .image: "Picture"
        }
    }

    /// Whether it has a strength to set (None has nothing to draw).
    var hasOpacity: Bool { self != .none }

    /// Chosen in Customize, where its colours or picture are picked: a background bar shows it only
    /// while it is the widget's.
    var needsCustomize: Bool { self == .gradient || self == .image }

    /// The strength each background is drawn with until the user sets one (plate 40 %, as the
    /// user chose; colour and artwork as they looked before the setting existed).
    var defaultOpacity: Double {
        switch self {
        case .none: 0
        case .plate: 0.4
        case .tinted: 0.5
        case .artwork, .gradient, .image: 1
        }
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
