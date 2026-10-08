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
    static let version = 4

    var id: WidgetID
    var kind: IslandWidgetKind
    var frame: GridRect
    /// The elements switched on.
    var options: Set<ElementID>
    var background: WidgetBackground = .plate
    /// The Colour background's colour; nil is the widget's own (the system's accent, Now Playing's
    /// cover).
    var backgroundColor: IslandTheme.RGB?
    /// How strongly the background is drawn, 0…1; nil is its own (`WidgetBackground.defaultOpacity`).
    var backgroundOpacity: Double?
    /// How far each moved part is from where the layout puts it, in points (Customize's editor);
    /// a part not in it is where the layout puts it.
    var offsets: [ElementID: ElementOffset] = [:]
    /// Which part is drawn over which where they overlap: higher over lower; a part not in it is
    /// at 0, and among equals the later one in `WidgetKindSpec.movable` is on top.
    var layers: [ElementID: Int] = [:]
    /// How much larger (or smaller) each resized part is drawn than the layout makes it, on each
    /// axis, from its layout box's top-leading corner; a part not in it is drawn as laid out.
    var scales: [ElementID: ElementScale] = [:]
    /// How each text part is set (`WidgetKindSpec.texts`); a part not in it is set as the widget
    /// sets it.
    var textStyles: [ElementID: TextStyle] = [:]
    /// How each button is drawn (`WidgetKindSpec.buttons`); a button not in it is drawn as the
    /// widget draws it.
    var buttonLooks: [ElementID: ButtonLook] = [:]
    /// How each playback line is drawn (`WidgetKindSpec.progressBars`); one not in it is drawn as
    /// the widget draws it.
    var progressLooks: [ElementID: ProgressLook] = [:]
    /// How each picture is sized (`WidgetKindSpec.images`); one not in it is sized as before.
    var imageLooks: [ElementID: ImageLook] = [:]
    /// How each chart is drawn (`WidgetKindSpec.charts`); one not in it is drawn as the widget draws it.
    var chartLooks: [ElementID: ChartLook] = [:]
    /// How each ruler is drawn (`WidgetKindSpec.rulers`), from Customize.
    var rulerLooks: [ElementID: RulerLook] = [:]
    /// How each grid of days is drawn (`WidgetKindSpec.dayGrids`), from Customize.
    var dayGridLooks: [ElementID: DayGridLook] = [:]
    /// The size its parts were placed and sized at in Customize (`offsets`, the texts' boxes and
    /// sizes); at any other it is drawn adapted (`adapted(keepsPlacement:)`). nil: the kind's own.
    var designSize: GridSize?
    /// Shapes added in Customize, drawn over the parts in this order (`WidgetFigure`).
    var figures: [WidgetFigure] = []
    /// How far Now Playing's back and forward buttons jump, in seconds; nil: 15.
    var seekSeconds: Int?
    /// What it shows, where its kind asks (`WidgetKindSpec.settings`): a world clock's city…
    var config = WidgetConfig()

    /// The jumps the back and forward buttons offer (each has its own system symbol).
    static let seekChoices = [5, 10, 15, 30, 45, 60, 75, 90]

    var effectiveSeekSeconds: Int { seekSeconds ?? 15 }

    /// Without an id, the kind's legacy one: the first instance of a kind, as boards had them.
    init(kind: IslandWidgetKind, frame: GridRect, options: Set<ElementID>, id: WidgetID? = nil) {
        self.id = id ?? .legacy(kind)
        self.kind = kind
        self.frame = frame
        self.options = options
    }

    /// Switched on, or always drawn (`ElementSpec.isRequired`).
    func shows(_ element: ElementID) -> Bool {
        options.contains(element) || kind.spec.element(element)?.isRequired == true
    }

    func offset(of element: ElementID) -> ElementOffset { offsets[element] ?? .zero }

    func layer(of element: ElementID) -> Int { layers[element] ?? 0 }

    func scale(of element: ElementID) -> ElementScale { scales[element] ?? .one }

    func textStyle(of element: ElementID) -> TextStyle { textStyles[element] ?? .plain }

    func buttonLook(of element: ElementID) -> ButtonLook { buttonLooks[element] ?? .plain }

    func progressLook(of element: ElementID) -> ProgressLook { progressLooks[element] ?? .plain }

    func imageLook(of element: ElementID) -> ImageLook { imageLooks[element] ?? .plain }

    func chartLook(of element: ElementID) -> ChartLook { chartLooks[element] ?? .plain }

    func rulerLook(of element: ElementID) -> RulerLook { rulerLooks[element] ?? .plain }

    func dayGridLook(of element: ElementID) -> DayGridLook { dayGridLooks[element] ?? .plain }

    /// `element` is drawn on Liquid Glass: a button's or a ruler's.
    func isGlass(_ element: ElementID) -> Bool {
        (kind.spec.buttons.contains(element) && ButtonLook.isGlass(buttonLook(of: element)))
            || (kind.spec.rulers.contains(element) && RulerLook.isGlass(rulerLook(of: element)))
            || (kind.spec.dayGrids.contains(element) && dayGridLook(of: element).isGlass)
    }

    /// The parts Customize moves: the kind's, then the shapes added.
    var movableElements: [ElementID] { kind.spec.movable + figures.map(\.id) }

    func figure(_ element: ElementID) -> WidgetFigure? { figures.first { $0.id == element } }

    /// The switch that shows `part` (Customize's Elements): its own, or the one of a pair it is in
    /// (previous and next, back and forward); nil where it has none.
    func switchElement(for part: ElementID) -> ElementID? {
        if kind.options.contains(part) { return part }
        let pair: ElementID? = switch part {
        case .previousButton, .nextButton: .skipButtons
        case .seekBackButton, .seekForwardButton: .seekButtons
        case .shelfTray: .shelfCount
        case .shelfAirDrop, .shelfClear: .shelfActions
        default: part.rawValue.hasPrefix("clipSymbol") && part.clipRow != nil ? .clipSymbols : nil
        }
        return pair.flatMap { kind.options.contains($0) ? $0 : nil }
    }

    /// Delete pressed on picked parts: a shape goes, any other part is switched off (its switch
    /// brings it back).
    mutating func delete(_ parts: Set<ElementID>) {
        for part in parts {
            if kind == .clipboard, let row = part.clipRow, part == .clipSymbol(row) {
                // One copy's symbol: that one goes, the others stay.
                removeClipSymbol(row)
            } else if figure(part) != nil {
                removeFigure(part)
            } else if let element = switchElement(for: part) {
                options.remove(element)
            }
        }
    }

    /// A shape gone, with where it was moved, its size and its layer.
    mutating func removeFigure(_ element: ElementID) {
        figures.removeAll { $0.id == element }
        offsets[element] = nil
        scales[element] = nil
        layers[element] = nil
    }

    /// Sets `element`'s look; the plain look is no look at all.
    mutating func setImageLook(_ look: ImageLook, of element: ElementID) {
        imageLooks[element] = look == .plain ? nil : look
    }

    mutating func setChartLook(_ look: ChartLook, of element: ElementID) {
        chartLooks[element] = look == .plain ? nil : look
    }

    mutating func setRulerLook(_ look: RulerLook, of element: ElementID) {
        rulerLooks[element] = look == .plain ? nil : look
    }

    mutating func setDayGridLook(_ look: DayGridLook, of element: ElementID) {
        dayGridLooks[element] = look == .plain ? nil : look
    }

    /// A picture grown to the edges or over the widget, moved or resized by hand: from where it is
    /// drawn in `drawn` (this widget with its pictures placed, `IslandWidgetView.resolved`), at
    /// its own size from then on.
    mutating func adoptDrawn(_ element: ElementID, from drawn: IslandWidget) {
        var look = imageLook(of: element)
        guard look.fit != .own else { return }
        scales[element] = drawn.scales[element]
        offsets[element] = drawn.offsets[element]
        look.fit = .own
        setImageLook(look, of: element)
    }

    /// Sets `element`'s look; the plain look is no look at all.
    mutating func setProgressLook(_ look: ProgressLook, of element: ElementID) {
        progressLooks[element] = look == .plain ? nil : look
    }

    /// Sets `element`'s look; the plain look is no look at all.
    mutating func setButtonLook(_ look: ButtonLook, of element: ElementID) {
        buttonLooks[element] = look == .plain ? nil : look
    }

    /// Sets `element`'s text style; the plain style is no style at all.
    mutating func setTextStyle(_ style: TextStyle, of element: ElementID) {
        textStyles[element] = style == .plain ? nil : style
    }

    /// Where a part is drawn: `ink` (where the layout draws it, within `box`, its layout box)
    /// resized by its scale and moved by its offset.
    func drawn(_ element: ElementID, ink: CGRect, box: CGRect) -> CGRect {
        scale(of: element).applied(to: ink, in: box).offsetBy(dx: offset(of: element).x, dy: offset(of: element).y)
    }

    /// The layer a group of parts (a row, a column) is drawn at among its neighbours: that of the
    /// part in it furthest from 0, raised before lowered. A group can only be over or under another
    /// as a whole.
    func layer(ofGroup elements: [ElementID]) -> Double {
        let values = elements.map(layer(of:))
        let highest = values.max() ?? 0, lowest = values.min() ?? 0
        return Double(highest >= -lowest ? highest : lowest)
    }

    /// Whether `element` is drawn over `other` where they overlap.
    func isDrawn(_ element: ElementID, over other: ElementID) -> Bool {
        let movable = movableElements
        let order = { (id: ElementID) in (self.layer(of: id), movable.firstIndex(of: id) ?? 0) }
        return order(element) > order(other)
    }

    /// Moved to `offset`; at zero, back where the layout puts it.
    mutating func setOffset(_ offset: ElementOffset, of element: ElementID) {
        offsets[element] = offset == .zero ? nil : offset
    }

    private enum CodingKeys: String, CodingKey {
        case version, id, kind, frame, options, background, showsPlate, backgroundColor, backgroundOpacity, offsets, layers, scales, textStyles, buttonLooks, progressLooks, imageLooks, chartLooks, rulerLooks, dayGridLooks, designSize, seekSeconds, figures, config
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.version, forKey: .version)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(frame, forKey: .frame)
        try container.encode(options.map(\.rawValue).sorted(), forKey: .options)
        try container.encode(background, forKey: .background)
        try container.encodeIfPresent(backgroundColor, forKey: .backgroundColor)
        try container.encodeIfPresent(backgroundOpacity, forKey: .backgroundOpacity)
        if !offsets.isEmpty {
            try container.encode(Dictionary(uniqueKeysWithValues: offsets.map { ($0.key.rawValue, $0.value) }), forKey: .offsets)
        }
        if !layers.isEmpty {
            try container.encode(Dictionary(uniqueKeysWithValues: layers.map { ($0.key.rawValue, $0.value) }), forKey: .layers)
        }
        if !scales.isEmpty {
            try container.encode(Dictionary(uniqueKeysWithValues: scales.map { ($0.key.rawValue, $0.value) }), forKey: .scales)
        }
        if !textStyles.isEmpty {
            try container.encode(Dictionary(uniqueKeysWithValues: textStyles.map { ($0.key.rawValue, $0.value) }), forKey: .textStyles)
        }
        if !buttonLooks.isEmpty {
            try container.encode(Dictionary(uniqueKeysWithValues: buttonLooks.map { ($0.key.rawValue, $0.value) }), forKey: .buttonLooks)
        }
        if !progressLooks.isEmpty {
            try container.encode(Dictionary(uniqueKeysWithValues: progressLooks.map { ($0.key.rawValue, $0.value) }), forKey: .progressLooks)
        }
        if !imageLooks.isEmpty {
            try container.encode(Dictionary(uniqueKeysWithValues: imageLooks.map { ($0.key.rawValue, $0.value) }), forKey: .imageLooks)
        }
        if !chartLooks.isEmpty {
            try container.encode(Dictionary(uniqueKeysWithValues: chartLooks.map { ($0.key.rawValue, $0.value) }), forKey: .chartLooks)
        }
        if !rulerLooks.isEmpty {
            try container.encode(Dictionary(uniqueKeysWithValues: rulerLooks.map { ($0.key.rawValue, $0.value) }), forKey: .rulerLooks)
        }
        if !dayGridLooks.isEmpty {
            try container.encode(Dictionary(uniqueKeysWithValues: dayGridLooks.map { ($0.key.rawValue, $0.value) }), forKey: .dayGridLooks)
        }
        try container.encodeIfPresent(designSize, forKey: .designSize)
        try container.encodeIfPresent(seekSeconds, forKey: .seekSeconds)
        if !figures.isEmpty { try container.encode(figures, forKey: .figures) }
        if config != WidgetConfig() { try container.encode(config, forKey: .config) }
    }

    // Boards saved before a field existed decode with its default; one without ids (before
    // version 3) gets the kind's legacy id (`WidgetMigration`). What earlier versions stored and this
    // one no longer has (colours, layouts, swapped sides, element sizes, styles) is left out, and a
    // background no longer offered (the artwork, a gradient, a picture) is the plate.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(IslandWidgetKind.self, forKey: .kind)
        frame = try container.decode(GridRect.self, forKey: .frame)
        id = (try? container.decodeIfPresent(WidgetID.self, forKey: .id)).flatMap { $0 } ?? .legacy(kind)
        let version = (try? container.decodeIfPresent(Int.self, forKey: .version)) ?? 1
        options = Set((try? container.decode([String].self, forKey: .options))?.map(ElementID.init) ?? [])
        if version < 2 { options.formUnion(WidgetMigration.elementsAddedInVersion2(kind)) }
        if version < 4 { options.formUnion(WidgetMigration.elementsSwitchableInVersion4(kind)) }
        if let background = try? container.decodeIfPresent(WidgetBackground.self, forKey: .background) {
            self.background = background
        } else {
            background = ((try? container.decodeIfPresent(Bool.self, forKey: .showsPlate)) ?? true) ? .plate : .none
        }
        backgroundColor = (try? container.decodeIfPresent(IslandTheme.RGB.self, forKey: .backgroundColor)).flatMap { $0 }
        backgroundOpacity = (try? container.decodeIfPresent(Double.self, forKey: .backgroundOpacity)).flatMap { $0 }
        let offsets = (try? container.decodeIfPresent([String: ElementOffset].self, forKey: .offsets)).flatMap { $0 } ?? [:]
        self.offsets = Dictionary(uniqueKeysWithValues: offsets.map { (ElementID(rawValue: $0.key), $0.value) })
        let layers = (try? container.decodeIfPresent([String: Int].self, forKey: .layers)).flatMap { $0 } ?? [:]
        self.layers = Dictionary(uniqueKeysWithValues: layers.map { (ElementID(rawValue: $0.key), $0.value) })
        let scales = (try? container.decodeIfPresent([String: ElementScale].self, forKey: .scales)).flatMap { $0 } ?? [:]
        self.scales = Dictionary(uniqueKeysWithValues: scales.map { (ElementID(rawValue: $0.key), $0.value) })
        let styles = (try? container.decodeIfPresent([String: TextStyle].self, forKey: .textStyles)).flatMap { $0 } ?? [:]
        textStyles = Dictionary(uniqueKeysWithValues: styles.map { (ElementID(rawValue: $0.key), $0.value) })
        let looks = (try? container.decodeIfPresent([String: ButtonLook].self, forKey: .buttonLooks)).flatMap { $0 } ?? [:]
        buttonLooks = Dictionary(uniqueKeysWithValues: looks.map { (ElementID(rawValue: $0.key), $0.value) })
        let lines = (try? container.decodeIfPresent([String: ProgressLook].self, forKey: .progressLooks)).flatMap { $0 } ?? [:]
        progressLooks = Dictionary(uniqueKeysWithValues: lines.map { (ElementID(rawValue: $0.key), $0.value) })
        let images = (try? container.decodeIfPresent([String: ImageLook].self, forKey: .imageLooks)).flatMap { $0 } ?? [:]
        imageLooks = Dictionary(uniqueKeysWithValues: images.map { (ElementID(rawValue: $0.key), $0.value) })
        let charts = (try? container.decodeIfPresent([String: ChartLook].self, forKey: .chartLooks)).flatMap { $0 } ?? [:]
        chartLooks = Dictionary(uniqueKeysWithValues: charts.map { (ElementID(rawValue: $0.key), $0.value) })
        let rulers = (try? container.decodeIfPresent([String: RulerLook].self, forKey: .rulerLooks)).flatMap { $0 } ?? [:]
        rulerLooks = Dictionary(uniqueKeysWithValues: rulers.map { (ElementID(rawValue: $0.key), $0.value) })
        let grids = (try? container.decodeIfPresent([String: DayGridLook].self, forKey: .dayGridLooks)).flatMap { $0 } ?? [:]
        dayGridLooks = Dictionary(uniqueKeysWithValues: grids.map { (ElementID(rawValue: $0.key), $0.value) })
        designSize = (try? container.decodeIfPresent(GridSize.self, forKey: .designSize)).flatMap { $0 }
        seekSeconds = (try? container.decodeIfPresent(Int.self, forKey: .seekSeconds)).flatMap { $0 }
        figures = (try? container.decodeIfPresent([WidgetFigure].self, forKey: .figures)).flatMap { $0 } ?? []
        config = (try? container.decodeIfPresent(WidgetConfig.self, forKey: .config)).flatMap { $0 } ?? WidgetConfig()
        sanitize()
    }

    /// The background's strength as drawn.
    var effectiveBackgroundOpacity: Double { backgroundOpacity ?? background.defaultOpacity }

    /// Drops the elements (and offsets) the kind does not have, and keeps the strength within 0…1.
    mutating func sanitize() {
        options.formIntersection(kind.options)
        // Shapes: each its own, up to the limit.
        var seen = Set<ElementID>()
        figures = Array(figures.filter { $0.id.rawValue.hasPrefix(WidgetFigure.prefix) && seen.insert($0.id).inserted }
            .prefix(WidgetFigure.limit))
        let movable = Set(movableElements)
        offsets = offsets.filter { movable.contains($0.key) && $0.value != .zero && $0.value.isFinite }
        layers = layers.filter { movable.contains($0.key) && $0.value != 0 }
        // A text part is resized by its box, never stretched.
        let texts = Set(kind.spec.texts)
        scales = scales.filter { movable.contains($0.key) && !texts.contains($0.key) && $0.value != .one && $0.value.isValid }
        let styled = texts.union(kind.spec.innerTexts)
        textStyles = textStyles.reduce(into: [:]) { result, entry in
            guard styled.contains(entry.key) else { return }
            var style = entry.value
            style.sanitize()
            if style != .plain { result[entry.key] = style }
        }
        let lines = Set(kind.spec.progressBars)
        progressLooks = progressLooks.reduce(into: [:]) { result, entry in
            guard lines.contains(entry.key) else { return }
            var look = entry.value
            look.sanitize()
            if look != .plain { result[entry.key] = look }
        }
        let buttons = Set(kind.spec.buttons)
        buttonLooks = buttonLooks.reduce(into: [:]) { result, entry in
            guard buttons.contains(entry.key) else { return }
            var look = entry.value
            look.sanitize()
            if look != .plain { result[entry.key] = look }
        }
        let images = Set(kind.spec.images)
        imageLooks = imageLooks.reduce(into: [:]) { result, entry in
            guard images.contains(entry.key) else { return }
            var look = entry.value
            look.sanitize()
            if look != .plain { result[entry.key] = look }
        }
        let charts = Set(kind.spec.charts)
        chartLooks = chartLooks.reduce(into: [:]) { result, entry in
            guard charts.contains(entry.key) else { return }
            var look = entry.value
            look.sanitize()
            if look != .plain { result[entry.key] = look }
        }
        let rulers = Set(kind.spec.rulers)
        rulerLooks = rulerLooks.reduce(into: [:]) { result, entry in
            guard rulers.contains(entry.key) else { return }
            var look = entry.value
            look.sanitize()
            if look != .plain { result[entry.key] = look }
        }
        let grids = Set(kind.spec.dayGrids)
        dayGridLooks = dayGridLooks.reduce(into: [:]) { result, entry in
            guard grids.contains(entry.key) else { return }
            var look = entry.value
            look.sanitize()
            if look != .plain { result[entry.key] = look }
        }
        backgroundOpacity = backgroundOpacity.map { min(max($0, 0), 1) }
        if let seconds = seekSeconds, !Self.seekChoices.contains(seconds) { seekSeconds = nil }
        // Only what the kind offers.
        config.sanitize()
        let settings = Set(kind.spec.settings)
        if !settings.contains(.timeZone) { config.timeZone = nil }
        if !settings.contains(.label) { config.label = nil }
        if !settings.contains(.count), !settings.contains(.files) { config.count = nil }
        if !settings.contains(.symbols) { config.symbolRows = nil }
    }
}

/// How far a part of a widget is moved from where the layout puts it, in points.
nonisolated struct ElementOffset: Sendable, Codable, Hashable {
    var x: Double
    var y: Double

    static let zero = ElementOffset(x: 0, y: 0)

    var isFinite: Bool { x.isFinite && y.isFinite }
}

/// How much larger a part is drawn than laid out, on each axis (1: as laid out).
nonisolated struct ElementScale: Sendable, Codable, Hashable {
    var x: Double
    var y: Double

    static let one = ElementScale(x: 1, y: 1)
    /// From a tenth to ten times.
    static let range = 0.1...10.0

    var isValid: Bool { Self.range.contains(x) && Self.range.contains(y) }

    /// `rect` (within `box`) as drawn at this scale, from the box's top-leading corner.
    func applied(to rect: CGRect, in box: CGRect) -> CGRect {
        CGRect(x: box.minX + (rect.minX - box.minX) * x, y: box.minY + (rect.minY - box.minY) * y,
               width: rect.width * x, height: rect.height * y)
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

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "None"
        case .plate: "Plate"
        case .tinted: "Colour"
        }
    }

    /// The strength each background is drawn with until the user sets one (the plate 40 %, the
    /// colour 50 %).
    var defaultOpacity: Double {
        switch self {
        case .none: 0
        case .plate: 0.4
        case .tinted: 0.5
        }
    }
}
