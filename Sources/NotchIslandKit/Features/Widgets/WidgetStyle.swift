import CoreGraphics
import Foundation

/// One widget instance's own look, set in its Customize editor: each element's type, symbol,
/// image, line, button and colours, and the widget's surface, layout, behaviour and formats.
///
/// Every field is optional and nil is the kind's own look, so an empty style draws exactly what the
/// widget drew before styles existed. What the widget's own fields already hold — its layout,
/// mirroring, element sizes (S, M, L), tint, background and its strength, Now Playing's button
/// looks — stays there (`IslandWidget`) and is not repeated here. Decoding is lossy field by field: a value this build cannot
/// read (a hand-edited plist, a newer build's option) is left out, never the whole style.
/// There are deliberately no shadow, blur or animation options: they would cost CPU on every frame.
nonisolated struct WidgetStyle: Codable, Hashable, Sendable {
    var elements: [ElementID: ElementStyle] = [:]
    var surface = SurfaceStyle()
    var layout = LayoutStyle()
    var behaviour = BehaviourStyle()
    var format = FormatStyle()

    init() {}

    var isEmpty: Bool { self == WidgetStyle() }

    /// An element's style, its own look when it has none; set back to its own look, it is left out
    /// (a key path the editor binds through: `\.[element: id].text.weight`).
    subscript(element id: ElementID) -> ElementStyle {
        get { elements[id] ?? ElementStyle() }
        set { elements[id] = newValue == ElementStyle() ? nil : newValue }
    }

    private enum CodingKeys: String, CodingKey { case elements, surface, layout, behaviour, format }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        elements = (c.lossy([ElementID: Lossy<ElementStyle>].self, .elements) ?? [:]).compactMapValues(\.value)
        surface = c.lossy(SurfaceStyle.self, .surface) ?? SurfaceStyle()
        layout = c.lossy(LayoutStyle.self, .layout) ?? LayoutStyle()
        behaviour = c.lossy(BehaviourStyle.self, .behaviour) ?? BehaviourStyle()
        format = c.lossy(FormatStyle.self, .format) ?? FormatStyle()
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if !elements.isEmpty { try c.encode(elements, forKey: .elements) }
        if surface != SurfaceStyle() { try c.encode(surface, forKey: .surface) }
        if layout != LayoutStyle() { try c.encode(layout, forKey: .layout) }
        if behaviour != BehaviourStyle() { try c.encode(behaviour, forKey: .behaviour) }
        if format != FormatStyle() { try c.encode(format, forKey: .format) }
    }

    /// Clamps every value to its range and drops what the kind does not have: styles of elements
    /// it lacks (a decoration of its custom layout excepted), an order naming them, a layout it
    /// does not offer, a custom layout where it takes none.
    mutating func sanitize(for kind: IslandWidgetKind) {
        let spec = kind.spec
        if !spec.supportsCustomLayout { layout.arrangement = nil }
        layout.arrangement?.sanitize(for: kind)
        let known = spec.elementIDs.union(layout.arrangement?.decorationIDs ?? [])
        elements = elements.filter { known.contains($0.key) }.compactMapValues { style in
            var style = style
            style.sanitize()
            return style == ElementStyle() ? nil : style
        }
        surface.sanitize()
        layout.sanitize(known: known)
        behaviour.sanitize()
        format.sanitize()
    }
}

// MARK: - Elements

/// One element's look. Only the part for its role is used (`ElementSpec.role`): the type of a text,
/// the symbol of a symbol…
nonisolated struct ElementStyle: Codable, Hashable, Sendable {
    var text = TextStyle()
    var symbol = SymbolStyle()
    var image = ImageStyle()
    var line = LineStyle()
    var button = ButtonSpec()
    /// Its colours, by slot (`ElementSpec.colorSlots`).
    var colors: [ColorSlot: StyleColor] = [:]

    init() {}

    private enum CodingKeys: String, CodingKey { case text, symbol, image, line, button, colors }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = c.lossy(TextStyle.self, .text) ?? TextStyle()
        symbol = c.lossy(SymbolStyle.self, .symbol) ?? SymbolStyle()
        image = c.lossy(ImageStyle.self, .image) ?? ImageStyle()
        line = c.lossy(LineStyle.self, .line) ?? LineStyle()
        button = c.lossy(ButtonSpec.self, .button) ?? ButtonSpec()
        // By name, so a slot this build does not know is left out rather than every colour.
        let colors = c.lossy([String: Lossy<StyleColor>].self, .colors) ?? [:]
        self.colors = Dictionary(uniqueKeysWithValues: colors.compactMap { name, color in
            ColorSlot(rawValue: name).flatMap { slot in color.value.map { (slot, $0) } }
        })
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if text != TextStyle() { try c.encode(text, forKey: .text) }
        if symbol != SymbolStyle() { try c.encode(symbol, forKey: .symbol) }
        if image != ImageStyle() { try c.encode(image, forKey: .image) }
        if line != LineStyle() { try c.encode(line, forKey: .line) }
        if button != ButtonSpec() { try c.encode(button, forKey: .button) }
        if !colors.isEmpty { try c.encode(colors, forKey: .colors) }
    }

    mutating func sanitize() {
        text.sanitize()
        symbol.sanitize()
        image.sanitize()
        line.sanitize()
        button.sanitize()
        colors = colors.mapValues { $0.sanitized }
    }
}

nonisolated struct TextStyle: Codable, Hashable, Sendable {
    /// Exactly this many points; nil fits the element's size (`IslandWidget.sizes`) to the room.
    var points: Double?
    var design: FontDesignChoice?
    var weight: FontWeightChoice?
    var width: FontWidthChoice?
    var italic: Bool?
    /// Points between letters.
    var tracking: Double?
    var textCase: TextCaseChoice?
    var alignment: TextAlignmentChoice?
    var lineLimit: Int?
    var monospacedDigits: Bool?
    var truncation: TruncationChoice?
    var opacity: Double?
    /// The user's own wording in place of the element's (a label, a name).
    var labelOverride: String?

    static let pointRange: ClosedRange<Double> = 6...400
    static let trackingRange: ClosedRange<Double> = -2...10
    static let lineLimitRange = 1...12
    static let labelLimit = 60

    init() {}

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        points = c.lossy(Double.self, .points)
        design = c.lossy(FontDesignChoice.self, .design)
        weight = c.lossy(FontWeightChoice.self, .weight)
        width = c.lossy(FontWidthChoice.self, .width)
        italic = c.lossy(Bool.self, .italic)
        tracking = c.lossy(Double.self, .tracking)
        textCase = c.lossy(TextCaseChoice.self, .textCase)
        alignment = c.lossy(TextAlignmentChoice.self, .alignment)
        lineLimit = c.lossy(Int.self, .lineLimit)
        monospacedDigits = c.lossy(Bool.self, .monospacedDigits)
        truncation = c.lossy(TruncationChoice.self, .truncation)
        opacity = c.lossy(Double.self, .opacity)
        labelOverride = c.lossy(String.self, .labelOverride)
    }

    mutating func sanitize() {
        points = points.map(Self.pointRange.clamp)
        tracking = tracking.map(Self.trackingRange.clamp)
        lineLimit = lineLimit.map(Self.lineLimitRange.clamp)
        opacity = opacity.map(StyleRanges.unit.clamp)
        labelOverride = labelOverride.map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.labelLimit)) }
            .flatMap { $0.isEmpty ? nil : $0 }
    }
}

nonisolated struct SymbolStyle: Codable, Hashable, Sendable {
    /// Exactly this many points; nil fits the element's size to the room.
    var points: Double?
    var weight: FontWeightChoice?
    var rendering: SymbolRenderingChoice?
    /// The filled variant of the symbol.
    var filled: Bool?
    /// A shape behind it (its colour is the `backing` slot).
    var backing: SymbolBacking?

    init() {}

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        points = c.lossy(Double.self, .points)
        weight = c.lossy(FontWeightChoice.self, .weight)
        rendering = c.lossy(SymbolRenderingChoice.self, .rendering)
        filled = c.lossy(Bool.self, .filled)
        backing = c.lossy(SymbolBacking.self, .backing)
    }

    mutating func sanitize() {
        points = points.map(TextStyle.pointRange.clamp)
    }
}

/// The artwork, a photo, an app icon.
nonisolated struct ImageStyle: Codable, Hashable, Sendable {
    /// Fractions of the widget's inner width and height.
    var width: Double?
    var height: Double?
    var aspect: ImageAspect?
    var placement: ImagePlacement?
    /// Points it is moved by from its place.
    var offsetX: Double?
    var offsetY: Double?
    var corners: ImageCorners?
    /// The border's width in points (its colour is the `border` slot).
    var borderWidth: Double?
    var contentMode: ImageContentMode?
    var opacity: Double?
    /// A shadow under it, its blur in points (0 or nil: none).
    var shadow: Double?
    /// Its colours' strength: 0 is black and white, 1 as it is.
    var saturation: Double?

    static let sizeRange: ClosedRange<Double> = 0.1...1
    static let shadowRange: ClosedRange<Double> = 0...20
    static let offsetRange: ClosedRange<Double> = -40...40
    static let borderRange: ClosedRange<Double> = 0...6

    init() {}

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        width = c.lossy(Double.self, .width)
        height = c.lossy(Double.self, .height)
        aspect = c.lossy(ImageAspect.self, .aspect)
        placement = c.lossy(ImagePlacement.self, .placement)
        offsetX = c.lossy(Double.self, .offsetX)
        offsetY = c.lossy(Double.self, .offsetY)
        corners = c.lossy(ImageCorners.self, .corners)
        borderWidth = c.lossy(Double.self, .borderWidth)
        contentMode = c.lossy(ImageContentMode.self, .contentMode)
        opacity = c.lossy(Double.self, .opacity)
        shadow = c.lossy(Double.self, .shadow)
        saturation = c.lossy(Double.self, .saturation)
    }

    mutating func sanitize() {
        width = width.map(Self.sizeRange.clamp)
        height = height.map(Self.sizeRange.clamp)
        offsetX = offsetX.map(Self.offsetRange.clamp)
        offsetY = offsetY.map(Self.offsetRange.clamp)
        corners = corners?.sanitized
        shadow = shadow.map(Self.shadowRange.clamp)
        saturation = saturation.map(StyleRanges.unit.clamp)
        borderWidth = borderWidth.map(Self.borderRange.clamp)
        opacity = opacity.map(StyleRanges.unit.clamp)
    }
}

/// A progress bar, a ring, a slider's bar, the ruler, a chart's line.
nonisolated struct LineStyle: Codable, Hashable, Sendable {
    var thickness: Double?
    /// A fraction of the room it has.
    var length: Double?
    var placement: LinePlacement?
    var cap: LineCapChoice?
    /// Its fill's colours are the `fill` and `fillEnd` slots; the track's is `track`.
    var fill: LineFill?
    var trackOpacity: Double?
    /// A ring's start, in degrees clockwise from the top, and its direction.
    var ringStart: Double?
    var ringClockwise: Bool?
    /// Drawn as this many segments (1: one continuous line).
    var segments: Int?
    /// A knob where the fill ends (a bar's): its shape; nil, none. Its colour is the `knob` slot.
    var knob: KnobShape?

    static let thicknessRange: ClosedRange<Double> = 1...16
    static let lengthRange: ClosedRange<Double> = 0.1...1
    static let segmentRange = 1...60

    init() {}

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        thickness = c.lossy(Double.self, .thickness)
        length = c.lossy(Double.self, .length)
        placement = c.lossy(LinePlacement.self, .placement)
        cap = c.lossy(LineCapChoice.self, .cap)
        fill = c.lossy(LineFill.self, .fill)
        trackOpacity = c.lossy(Double.self, .trackOpacity)
        ringStart = c.lossy(Double.self, .ringStart)
        ringClockwise = c.lossy(Bool.self, .ringClockwise)
        segments = c.lossy(Int.self, .segments)
        knob = c.lossy(KnobShape.self, .knob)
    }

    mutating func sanitize() {
        thickness = thickness.map(Self.thicknessRange.clamp)
        length = length.map(Self.lengthRange.clamp)
        trackOpacity = trackOpacity.map(StyleRanges.unit.clamp)
        ringStart = ringStart.map { $0.truncatingRemainder(dividingBy: 360) }.map { $0 < 0 ? $0 + 360 : $0 }
        segments = segments.map(Self.segmentRange.clamp)
    }
}

/// A button's look (its tint is the `tint` slot).
nonisolated struct ButtonSpec: Codable, Hashable, Sendable {
    var look: ButtonLookChoice?
    /// How strongly the tint colours it, 0…1.
    var tintStrength: Double?
    var shape: ButtonShapeChoice?
    /// Points between buttons of one element.
    var spacing: Double?
    /// The symbol alone, or the symbol with its title.
    var iconOnly: Bool?
    /// The system's control size (nil: the one the widget's room gives it).
    var size: ControlSizeChoice?
    /// A rounded rectangle's corners, in points (nil: a quarter of its shorter side).
    var cornerRadius: Double?
    /// A seek button's jump, in seconds (nil: `standardSeconds`).
    var seconds: Double?

    static let spacingRange: ClosedRange<Double> = 0...24
    static let cornerRange: ClosedRange<Double> = 0...30
    static let secondsRange: ClosedRange<Double> = 1...600
    static let standardSeconds = 10.0

    init() {}

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        look = c.lossy(ButtonLookChoice.self, .look)
        tintStrength = c.lossy(Double.self, .tintStrength)
        shape = c.lossy(ButtonShapeChoice.self, .shape)
        spacing = c.lossy(Double.self, .spacing)
        iconOnly = c.lossy(Bool.self, .iconOnly)
        size = c.lossy(ControlSizeChoice.self, .size)
        cornerRadius = c.lossy(Double.self, .cornerRadius)
        seconds = c.lossy(Double.self, .seconds)
    }

    mutating func sanitize() {
        tintStrength = tintStrength.map(StyleRanges.unit.clamp)
        spacing = spacing.map(Self.spacingRange.clamp)
        cornerRadius = cornerRadius.map(Self.cornerRange.clamp)
        seconds = seconds.map(Self.secondsRange.clamp).map { $0.rounded() }
    }
}

// MARK: - The widget

/// What the widget's background (`IslandWidget.background`, at its `backgroundOpacity`) adds: a
/// border, its own corners, a gradient's colours, an image's picture, how far the artwork is dimmed.
nonisolated struct SurfaceStyle: Codable, Hashable, Sendable {
    var borderWidth: Double?
    var cornerRadius: Double?
    /// How far the artwork is darkened under the content, 0…1.
    var artworkDim: Double?
    /// A gradient's two colours (nil: the widget's accent, fading).
    var fill: StyleColor?
    var fillEnd: StyleColor?
    var border: StyleColor?
    /// The picture of an image background.
    var imagePath: String?

    static let borderRange: ClosedRange<Double> = 0...4
    static let cornerRange: ClosedRange<Double> = 0...40

    init() {}

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        borderWidth = c.lossy(Double.self, .borderWidth)
        cornerRadius = c.lossy(Double.self, .cornerRadius)
        artworkDim = c.lossy(Double.self, .artworkDim)
        fill = c.lossy(StyleColor.self, .fill)
        fillEnd = c.lossy(StyleColor.self, .fillEnd)
        border = c.lossy(StyleColor.self, .border)
        imagePath = c.lossy(String.self, .imagePath)
    }

    mutating func sanitize() {
        borderWidth = borderWidth.map(Self.borderRange.clamp)
        cornerRadius = cornerRadius.map(Self.cornerRange.clamp)
        artworkDim = artworkDim.map(StyleRanges.unit.clamp)
        fill = fill?.sanitized
        fillEnd = fillEnd?.sanitized
        border = border?.sanitized
        if imagePath?.isEmpty == true { imagePath = nil }
    }
}

/// How the elements are laid out inside the widget.
nonisolated struct LayoutStyle: Codable, Hashable, Sendable {
    var padding: Double?
    var spacing: Double?
    var alignment: NinePointAlignment?
    /// The elements in the order they are drawn (the kind's order when nil).
    var order: [ElementID]?
    var axis: LayoutAxis?
    /// Everything inside drawn larger or smaller.
    var contentScale: Double?
    /// Elements placed freely (the grid inside the widget); nil is automatic.
    var arrangement: ElementArrangement?

    static let paddingRange: ClosedRange<Double> = 0...24
    static let spacingRange: ClosedRange<Double> = 0...24
    static let contentScaleRange: ClosedRange<Double> = 0.5...1.5

    init() {}

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        padding = c.lossy(Double.self, .padding)
        spacing = c.lossy(Double.self, .spacing)
        alignment = c.lossy(NinePointAlignment.self, .alignment)
        order = c.lossy([Lossy<ElementID>].self, .order)?.compactMap(\.value)
        axis = c.lossy(LayoutAxis.self, .axis)
        contentScale = c.lossy(Double.self, .contentScale)
        arrangement = c.lossy(ElementArrangement.self, .arrangement)
    }

    mutating func sanitize(known: Set<ElementID>) {
        padding = padding.map(Self.paddingRange.clamp)
        spacing = spacing.map(Self.spacingRange.clamp)
        var seen = Set<ElementID>()
        order = order?.filter { known.contains($0) && seen.insert($0).inserted }
        contentScale = contentScale.map(Self.contentScaleRange.clamp)
    }
}

nonisolated struct BehaviourStyle: Codable, Hashable, Sendable {
    var tap: TapAction?
    /// Hidden while it has nothing to show (no music, no timer running).
    var showsOnlyWhenActive: Bool?
    var haptic: Bool?
    var dimsWhenInactive: Bool?

    init() {}

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tap = c.lossy(TapAction.self, .tap)
        showsOnlyWhenActive = c.lossy(Bool.self, .showsOnlyWhenActive)
        haptic = c.lossy(Bool.self, .haptic)
        dimsWhenInactive = c.lossy(Bool.self, .dimsWhenInactive)
    }

    mutating func sanitize() {
        tap = tap?.sanitized
    }
}

/// How numbers, times and dates read.
nonisolated struct FormatStyle: Codable, Hashable, Sendable {
    var clock24Hour: Bool?
    var showsSeconds: Bool?
    /// A `DateFormatter` template ("EEEE d MMMM").
    var dateTemplate: String?
    var percentDecimals: Int?
    var durationStyle: DurationStyleChoice?
    var temperature: TemperatureUnit?

    static let percentDecimalsRange = 0...2
    static let templateLimit = 40

    init() {}

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        clock24Hour = c.lossy(Bool.self, .clock24Hour)
        showsSeconds = c.lossy(Bool.self, .showsSeconds)
        dateTemplate = c.lossy(String.self, .dateTemplate)
        percentDecimals = c.lossy(Int.self, .percentDecimals)
        durationStyle = c.lossy(DurationStyleChoice.self, .durationStyle)
        temperature = c.lossy(TemperatureUnit.self, .temperature)
    }

    mutating func sanitize() {
        dateTemplate = dateTemplate.map { String($0.prefix(Self.templateLimit)) }.flatMap { $0.isEmpty ? nil : $0 }
        percentDecimals = percentDecimals.map(Self.percentDecimalsRange.clamp)
    }
}

// MARK: - Colours

/// Where a style colour goes on an element.
nonisolated enum ColorSlot: String, Codable, CodingKeyRepresentable, Hashable, Sendable, CaseIterable {
    /// Text, or a symbol's first colour.
    case primary
    /// A symbol's second colour.
    case secondary
    /// A line's or chart's fill, and its gradient's end.
    case fill, fillEnd
    case track
    /// The shape behind a symbol.
    case backing
    case border
    /// A button's glass.
    case tint
    /// A bar's knob (`LineStyle.knob`).
    case knob
}

/// A colour a style sets.
nonisolated enum StyleColor: Codable, Hashable, Sendable {
    /// The element's own colour.
    case automatic
    /// The widget's accent (its tint, or the kind's).
    case accent
    /// The island's theme colour.
    case theme
    /// The colour of the playing track's cover.
    case artwork
    case semantic(SemanticColor)
    case named(WidgetTint)
    case rgb(IslandTheme.RGB, alpha: Double)
    /// From the value shown: a charge from red to green, a load from green to red.
    case valueScale(ValueScale)

    var sanitized: StyleColor {
        guard case .rgb(let rgb, let alpha) = self else { return self }
        return .rgb(IslandTheme.RGB(red: StyleRanges.unit.clamp(rgb.red), green: StyleRanges.unit.clamp(rgb.green),
                                    blue: StyleRanges.unit.clamp(rgb.blue)), alpha: StyleRanges.unit.clamp(alpha))
    }
}

nonisolated enum SemanticColor: String, Codable, Hashable, Sendable, CaseIterable {
    case primary, secondary, tertiary, positive, warning, critical
}

nonisolated enum ValueScale: String, Codable, Hashable, Sendable, CaseIterable {
    /// Red when low, green when high (a charge).
    case rising
    /// Green when low, red when high (a load).
    case falling
}

// MARK: - Choices

nonisolated enum FontDesignChoice: String, Codable, Hashable, Sendable, CaseIterable { case standard, rounded, serif, monospaced }
nonisolated enum FontWeightChoice: String, Codable, Hashable, Sendable, CaseIterable {
    case ultraLight, thin, light, regular, medium, semibold, bold, heavy, black
}
nonisolated enum FontWidthChoice: String, Codable, Hashable, Sendable, CaseIterable { case compressed, condensed, standard, expanded }
nonisolated enum TextCaseChoice: String, Codable, Hashable, Sendable, CaseIterable { case asIs, uppercase, lowercase }
nonisolated enum TextAlignmentChoice: String, Codable, Hashable, Sendable, CaseIterable { case leading, center, trailing }
/// Where a line that does not fit is cut, or `shrink`: smaller type before it is cut.
nonisolated enum TruncationChoice: String, Codable, Hashable, Sendable, CaseIterable { case head, middle, tail, shrink }
nonisolated enum SymbolRenderingChoice: String, Codable, Hashable, Sendable, CaseIterable {
    case monochrome, hierarchical, palette, multicolor
}
nonisolated enum SymbolBacking: String, Codable, Hashable, Sendable, CaseIterable { case none, circle, roundedSquare, capsule }
nonisolated enum ImageAspect: String, Codable, Hashable, Sendable, CaseIterable { case original, square, wide, tall }
nonisolated enum ImagePlacement: String, Codable, Hashable, Sendable, CaseIterable { case leading, trailing, top, bottom, background }
nonisolated enum ImageContentMode: String, Codable, Hashable, Sendable, CaseIterable { case fill, fit }

/// An image's corners: concentric with the widget's, a radius of their own, or a circle.
nonisolated enum ImageCorners: Codable, Hashable, Sendable {
    case concentric
    case custom(Double)
    case circle

    static let radiusRange: ClosedRange<Double> = 0...40

    var sanitized: ImageCorners {
        guard case .custom(let radius) = self else { return self }
        return .custom(Self.radiusRange.clamp(radius))
    }
}

nonisolated enum LinePlacement: String, Codable, Hashable, Sendable, CaseIterable { case top, bottom, leading, trailing, behind }
nonisolated enum LineCapChoice: String, Codable, Hashable, Sendable, CaseIterable { case round, butt, square }
/// One colour, a gradient from `fill` to `fillEnd`, or the value's colour (`ValueScale`).
nonisolated enum LineFill: String, Codable, Hashable, Sendable, CaseIterable { case solid, gradient, valueScale }
/// A button's material: clear glass, glass filled with its colour, a flat solid face, an outline, none.
nonisolated enum ButtonLookChoice: String, Codable, Hashable, Sendable, CaseIterable { case glass, prominent, solid, bordered, plain }
/// The knob on a bar where its fill ends.
nonisolated enum KnobShape: String, Codable, Hashable, Sendable, CaseIterable { case none, circle, pill, square, line }
nonisolated enum ButtonShapeChoice: String, Codable, Hashable, Sendable, CaseIterable { case circle, capsule, roundedRectangle }
nonisolated enum ControlSizeChoice: String, Codable, Hashable, Sendable, CaseIterable { case mini, small, regular, large }
nonisolated enum NinePointAlignment: String, Codable, Hashable, Sendable, CaseIterable {
    case topLeading, top, topTrailing, leading, center, trailing, bottomLeading, bottom, bottomTrailing
}
nonisolated enum LayoutAxis: String, Codable, Hashable, Sendable, CaseIterable { case horizontal, vertical }
nonisolated enum DurationStyleChoice: String, Codable, Hashable, Sendable, CaseIterable { case positional, abbreviated, narrow }
nonisolated enum TemperatureUnit: String, Codable, Hashable, Sendable, CaseIterable { case celsius, fahrenheit }

/// What a tap on the widget does.
nonisolated enum TapAction: Codable, Hashable, Sendable {
    /// What the kind does.
    case standard
    /// Opens the app at this path.
    case app(String)
    case url(String)
    /// Runs the user's shortcut of this name.
    case shortcut(String)
    /// Shows one of the island's pages (`ExpandedPage`).
    case page(String)
    case none

    /// An empty name or a link that does not parse does what the kind does.
    var sanitized: TapAction {
        switch self {
        case .app(let value), .shortcut(let value), .page(let value): value.isEmpty ? .standard : self
        case .url(let value): URL(string: value)?.scheme == nil ? .standard : self
        case .standard, .none: self
        }
    }
}

nonisolated enum StyleRanges {
    static let unit: ClosedRange<Double> = 0...1
}

nonisolated extension ClosedRange {
    func clamp(_ value: Bound) -> Bound { Swift.min(Swift.max(value, lowerBound), upperBound) }
}

nonisolated extension KeyedDecodingContainer {
    /// The value at `key`, or nil when it is missing or cannot be read.
    func lossy<T: Decodable>(_ type: T.Type, _ key: Key) -> T? {
        (try? decodeIfPresent(type, forKey: key)).flatMap { $0 }
    }
}
