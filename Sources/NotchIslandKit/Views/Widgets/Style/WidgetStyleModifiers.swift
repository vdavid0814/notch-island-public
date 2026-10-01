import SwiftUI

// How an element takes its style. Each is given the element's id, what the kind draws it with and
// the widget's style (`\.widgetStyle`, read once by the element's view); for an element the style
// sets nothing on, it is exactly the kind's own modifier (the same `.font`, nothing else — no
// modifier of ours and no environment read on the island), so an empty style draws today's pixels
// (`WidgetSnapshotTests`). Everything here is resolved once per body evaluation: nothing ticks.
//
// Sizes are the kind's to decide: it asks the style for an element's size (`textPoints`,
// `symbolPoints`) — its fixed size where it sets one, never more than the room takes — and hands
// that size in. The modifiers draw it as given.

extension View {
    /// Text in the element's type. `type` is the kind's own at the size it is drawn at
    /// (`ResolvedWidgetStyle.textPoints`); a fixed size is drawn exactly (no shrinking to fit).
    @ViewBuilder func widgetText(_ id: ElementID, _ type: TypeSpec, in style: ResolvedWidgetStyle) -> some View {
        if let element = style.element(id) {
            modifier(WidgetText(element: element, type: type))
                .modifier(TextInk(id: id, type: type.applying(element.text)))
        } else {
            font(type.systemFont)
                .modifier(TextInk(id: id, type: type))
        }
    }

    /// A symbol at the element's size, weight, rendering, colours and backing.
    @ViewBuilder func widgetSymbol(_ id: ElementID, points: CGFloat, weight: FontWeightChoice = .regular,
                                   in style: ResolvedWidgetStyle) -> some View {
        if let element = style.element(id) {
            modifier(WidgetSymbol(element: element, points: points, weight: weight))
        } else {
            font(.system(size: points, weight: weight.fontWeight))
        }
    }

    /// A picture (the cover, an icon) with the element's corners, border, offset and opacity.
    @ViewBuilder func widgetImage(_ id: ElementID, in style: ResolvedWidgetStyle) -> some View {
        if let element = style.element(id) {
            modifier(WidgetImage(element: element))
        } else {
            self
        }
    }

    /// A button in the element's look, shape, tint and label. Put inside the kind's own button
    /// style (`islandButton`): the nearest style wins.
    @ViewBuilder func widgetButton(_ id: ElementID, in style: ResolvedWidgetStyle) -> some View {
        if let element = style.element(id) {
            modifier(WidgetButton(element: element))
        } else {
            self
        }
    }
}

extension Text {
    /// `string` as one run of a line elements share (`Text + Text`: Now Playing's title and artist
    /// on one line), in the element's type: what a run takes — size, font, tracking, case, colour
    /// and opacity; the line keeps its own limit, alignment and shrinking. `color` is the kind's
    /// own (nil: the line's). For an element the style sets nothing on, exactly the kind's run.
    static func widgetRun(_ string: String, _ id: ElementID, _ type: TypeSpec, color: AnyShapeStyle? = nil,
                          style: ResolvedWidgetStyle, artwork: Color?) -> Text {
        guard let element = style.element(id) else {
            let run = Text(string).font(type.systemFont)
            return color.map { run.foregroundStyle($0) } ?? run
        }
        let spec = type.applying(element.text)
        var run = Text(spec.cased(string)).font(spec.font)
        if let tracking = element.text.tracking { run = run.tracking(CGFloat(tracking)) }
        let paint = element.colors[.primary]?.shapeStyle(artwork: artwork) ?? color
        if let opacity = element.text.opacity {
            run = run.foregroundStyle((paint ?? AnyShapeStyle(.primary)).opacity(opacity))
        } else if let paint {
            run = run.foregroundStyle(paint)
        }
        return run
    }
}

nonisolated extension TypeSpec {
    /// The system font it names, as the kinds have always set it (`Font.system`).
    var systemFont: Font {
        let font = Font.system(size: points, weight: weight.fontWeight, design: design.fontDesign)
        return monospacedDigits ? font.monospacedDigit() : font
    }

    /// Its font: the system font where that can name the type, so a size alone draws as the kind's type.
    var font: Font { width == .standard && !italic ? systemFont : WidgetTypography.font(self) }


}

extension ResolvedWidgetStyle {
    /// The size a text element is drawn at: the style's fixed size, as large as the room lets it
    /// be (`fit`, the most the kind's layout gives it); else the kind's own `auto` size.
    func textPoints(_ id: ElementID, auto: CGFloat, fit: CGFloat) -> CGFloat {
        guard let fixed = element(id)?.text.points else { return auto }
        return max(min(CGFloat(fixed), fit), TextFit.minimumPoints)
    }

    /// The same for a symbol.
    func symbolPoints(_ id: ElementID, auto: CGFloat, fit: CGFloat) -> CGFloat {
        guard let fixed = element(id)?.symbol.points else { return auto }
        return max(min(CGFloat(fixed), fit), TextFit.minimumPoints)
    }

    /// Whether the style sets its own size on the element (text or symbol).
    func isFixed(_ id: ElementID) -> Bool { element(id).map { $0.text.points != nil || $0.symbol.points != nil } ?? false }
}

private struct WidgetText: ViewModifier {
    let element: ElementStyle
    let type: TypeSpec

    @Environment(\.widgetArtworkColor) private var artwork
    /// In a custom layout (the grid inside the widget) its frame was measured around the text as
    /// the stacks drew it, squeezed a hair where they let it: the same squeeze is let there, rather
    /// than a "…" at a fraction of a point.
    @Environment(\.widgetPlan) private var plan

    func body(content: Content) -> some View {
        let text = element.text
        content
            .font(type.applying(text).font)
            .modifier(OptionalTracking(tracking: text.tracking.map { CGFloat($0) }))
            .transformEnvironment(\.textCase) { if let textCase = text.textCase { $0 = textCase.textCase } }
            .transformEnvironment(\.multilineTextAlignment) { if let alignment = text.alignment { $0 = alignment.textAlignment } }
            .transformEnvironment(\.lineLimit) { if let limit = text.lineLimit { $0 = limit } }
            .transformEnvironment(\.truncationMode) { if let mode = text.truncation?.truncationMode { $0 = mode } }
            .transformEnvironment(\.minimumScaleFactor) { factor in
                if plan != nil, let truncation = text.truncation {
                    // Laid out freely and told what to do when too long for its rectangle: shrink as
                    // far as it must, or be cut — its rectangle's height never changes. Not told, as
                    // the kind draws it (so a layout just unlocked draws what it drew).
                    factor = truncation == .shrink ? 0.05 : 1
                } else if text.truncation == .shrink { factor = 0.6 } else if text.points != nil, plan == nil { factor = 1 }
            }
            .modifier(OptionalForeground(primary: element.colors[.primary]?.shapeStyle(artwork: artwork)))
            .opacity(text.opacity ?? 1)
    }
}

private struct WidgetSymbol: ViewModifier {
    let element: ElementStyle
    let points: CGFloat
    let weight: FontWeightChoice

    @Environment(\.widgetArtworkColor) private var artwork

    func body(content: Content) -> some View {
        let symbol = element.symbol
        let size = points
        content
            .font(.system(size: size, weight: (symbol.weight ?? weight).fontWeight))
            .modifier(OptionalSymbolLook(rendering: symbol.rendering, filled: symbol.filled))
            .modifier(OptionalForeground(primary: element.colors[.primary]?.shapeStyle(artwork: artwork),
                                         secondary: element.colors[.secondary]?.shapeStyle(artwork: artwork)))
            .background {
                if let backing = symbol.backing, backing != .none {
                    let fill = element.colors[.backing]?.shapeStyle(artwork: artwork) ?? AnyShapeStyle(.white.opacity(0.14))
                    SymbolBackingShape(backing: backing).fill(fill).padding(-size * 0.3)
                }
            }
    }
}

/// The shape behind a symbol.
private nonisolated struct SymbolBackingShape: Shape {
    let backing: SymbolBacking

    func path(in rect: CGRect) -> Path {
        switch backing {
        case .none: Path()
        case .circle: Circle().path(in: rect)
        case .roundedSquare: RoundedRectangle(cornerRadius: min(rect.width, rect.height) * 0.28, style: .continuous).path(in: rect)
        case .capsule: Capsule().path(in: rect)
        }
    }
}

private struct WidgetImage: ViewModifier {
    let element: ElementStyle

    @Environment(\.widgetCorners) private var corners
    @Environment(\.widgetArtworkColor) private var artwork

    func body(content: Content) -> some View {
        let image = element.image
        let shape = ImageCornerShape(corners: image.corners, concentric: corners.inner)
        content
            .modifier(OptionalSaturation(saturation: image.saturation))
            .clipShape(shape)
            .overlay {
                if let width = image.borderWidth, width > 0 {
                    shape.stroke(element.colors[.border]?.shapeStyle(artwork: artwork) ?? AnyShapeStyle(.white.opacity(0.3)),
                                 lineWidth: width)
                }
            }
            .modifier(OptionalShadow(radius: image.shadow))
            .opacity(image.opacity ?? 1)
            .offset(x: image.offsetX ?? 0, y: image.offsetY ?? 0)
    }
}

/// An image's corners: the widget's inner corners (it sits inside the padding), its own radius, a
/// circle; unset, the rectangle it is drawn in.
private nonisolated struct ImageCornerShape: Shape {
    let corners: ImageCorners?
    let concentric: RectangleCornerRadii

    func path(in rect: CGRect) -> Path {
        switch corners {
        case nil: Rectangle().path(in: rect)
        case .concentric: UnevenRoundedRectangle(cornerRadii: concentric, style: .continuous).path(in: rect)
        case .custom(let radius): RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect)
        case .circle: Circle().path(in: rect)
        }
    }
}

private struct WidgetButton: ViewModifier {
    let element: ElementStyle

    @Environment(\.widgetArtworkColor) private var artwork
    @Environment(\.elementFill) private var fill

    func body(content: Content) -> some View {
        let button = element.button
        let tint = element.colors[.tint]?.color(artwork: artwork).map { $0.opacity(button.tintStrength ?? 1) }
        // Its title shown: a capsule, whatever shape it had (a circle holds a symbol alone).
        let shape = button.iconOnly == false && button.shape != .roundedRectangle ? ButtonShapeChoice.capsule : button.shape
        let icon = element.colors[.primary]?.color(artwork: artwork)
        styled(content, look: button.look, shape: shape)
            // Said nearest the button: over a Now Playing button's colour and the island's look.
            .buttonAppearance(look: button.look, shape: shape, tint: tint, radius: button.cornerRadius.map { CGFloat($0) }, icon: icon)
            // For a button whose own style draws it (not ours): its label's colour from outside.
            .modifier(OptionalForeground(primary: icon.map(AnyShapeStyle.init)))
            .modifier(OptionalTint(color: tint))
            .modifier(OptionalLabelStyle(iconOnly: button.iconOnly))
            .transformEnvironment(\.controlSize) { if let size = button.size { $0 = size.controlSize } }
    }

    /// Drawn as said (`WidgetButtonStyle`) where the style picks a look or a shape: a button the
    /// island does not style itself takes it too. Otherwise the button's own style, in its colour.
    @ViewBuilder private func styled(_ content: Content, look: ButtonLookChoice?, shape: ButtonShapeChoice?) -> some View {
        if look != nil || shape != nil || fill != nil || element.button.cornerRadius != nil {
            content.buttonStyle(WidgetButtonStyle())
        } else {
            content
        }
    }
}

private struct OptionalSaturation: ViewModifier {
    let saturation: Double?

    func body(content: Content) -> some View {
        if let saturation, saturation < 1 { content.saturation(saturation) } else { content }
    }
}

private struct OptionalShadow: ViewModifier {
    let radius: Double?

    func body(content: Content) -> some View {
        if let radius, radius > 0 {
            content.shadow(color: .black.opacity(0.45), radius: CGFloat(radius), y: CGFloat(radius) / 3)
        } else {
            content
        }
    }
}

private struct OptionalTracking: ViewModifier {
    let tracking: CGFloat?

    func body(content: Content) -> some View {
        if let tracking { content.tracking(tracking) } else { content }
    }
}

/// A symbol's rendering and fill where the style sets them.
private struct OptionalSymbolLook: ViewModifier {
    let rendering: SymbolRenderingChoice?
    let filled: Bool?

    func body(content: Content) -> some View {
        switch (rendering, filled) {
        case (nil, nil): content
        case (let rendering?, nil): content.symbolRenderingMode(rendering.renderingMode)
        case (nil, let filled?): content.symbolVariant(filled ? .fill : .none)
        case (let rendering?, let filled?): content.symbolRenderingMode(rendering.renderingMode).symbolVariant(filled ? .fill : .none)
        }
    }
}

/// The style's colours where it sets any; the kind's own otherwise.
private struct OptionalForeground: ViewModifier {
    let primary: AnyShapeStyle?
    var secondary: AnyShapeStyle?

    func body(content: Content) -> some View {
        if let secondary {
            content.foregroundStyle(primary ?? AnyShapeStyle(.primary), secondary)
        } else if let primary {
            content.foregroundStyle(primary)
        } else {
            content
        }
    }
}

private struct OptionalLabelStyle: ViewModifier {
    let iconOnly: Bool?

    func body(content: Content) -> some View {
        switch iconOnly {
        case true?: content.labelStyle(.iconOnly)
        case false?: content.labelStyle(.titleAndIcon)
        case nil: content
        }
    }
}

/// A line's style (progress, a ring, a bar) as drawn: its thickness, cap and colours, each the
/// kind's own where the style sets none.
struct ResolvedLine: Equatable {
    var thickness: CGFloat?
    var cap: LineCapChoice?
    var fill: StyleColor?
    var fillEnd: StyleColor?
    var track: StyleColor?
    var trackOpacity: Double?
    var mode: LineFill?
    var knob: KnobShape?
    var knobFill: StyleColor?

    init(_ element: ElementStyle?) {
        let line = element?.line ?? LineStyle()
        thickness = line.thickness.map { CGFloat($0) }
        cap = line.cap
        fill = element?.colors[.fill]
        fillEnd = element?.colors[.fillEnd]
        track = element?.colors[.track]
        trackOpacity = line.trackOpacity
        mode = line.fill
        knob = line.knob
        knobFill = element?.colors[.knob]
    }

    /// A straight line's ends as a part of its thickness: round (the kinds' own capsule), square
    /// (its corners just softened) or flat (cut straight).
    var endRounding: CGFloat {
        switch cap {
        case .butt?: 0
        case .square?: 0.2
        default: 0.5
        }
    }

    /// A straight line `height` thick with its ends: round, the capsule it always was.
    func barShape(height: CGFloat) -> AnyShape {
        endRounding == 0.5 ? AnyShape(Capsule()) : AnyShape(RoundedRectangle(cornerRadius: height * endRounding, style: .continuous))
    }

    /// The fill's one colour for `value` (0…1): the value's colour on a value scale, else the fill.
    func fillColor(value: Double, artwork: Color?) -> Color? {
        if mode == .valueScale, case .valueScale(let scale)? = fill { return scale.color(value) }
        return fill?.color(artwork: artwork, value: value)
    }

    /// The fill as drawn: Gradient from Fill to Fill End along the line (around a ring), else its
    /// one colour (`fillColor`). The end alone fades from its own colour; nil: the kind's.
    func fillStyle(value: Double, artwork: Color?, ring: Bool = false) -> AnyShapeStyle? {
        guard mode == .gradient else { return fillColor(value: value, artwork: artwork).map(AnyShapeStyle.init) }
        let start = fill?.color(artwork: artwork, value: value)
        let end = fillEnd?.color(artwork: artwork, value: value)
        guard let from = start ?? end.map({ $0.opacity(0.35) }) else { return nil }
        let to = end ?? from.opacity(0.35)
        if ring {
            return AnyShapeStyle(AngularGradient(colors: [from, to], center: .center, startAngle: .degrees(0),
                                                 endAngle: .degrees(360 * max(value, 0.02))))
        }
        return AnyShapeStyle(LinearGradient(colors: [from, to], startPoint: .leading, endPoint: .trailing))
    }

    /// The track: its colour at its opacity, or the kind's `standard`.
    func trackStyle(_ standard: Color, artwork: Color?) -> Color {
        let color = track?.color(artwork: artwork) ?? standard
        return trackOpacity.map { color.opacity($0) } ?? color
    }
}

extension ButtonShapeChoice {
    var borderShape: ButtonBorderShape {
        switch self {
        case .circle: .circle
        case .capsule: .capsule
        case .roundedRectangle: .roundedRectangle
        }
    }
}

nonisolated extension FontWeightChoice {
    var fontWeight: Font.Weight {
        switch self {
        case .ultraLight: .ultraLight
        case .thin: .thin
        case .light: .light
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        case .black: .black
        }
    }
}

nonisolated extension FontDesignChoice {
    var fontDesign: Font.Design {
        switch self {
        case .standard: .default
        case .rounded: .rounded
        case .serif: .serif
        case .monospaced: .monospaced
        }
    }
}

nonisolated extension TextCaseChoice {
    var textCase: Text.Case? {
        switch self {
        case .asIs: nil
        case .uppercase: .uppercase
        case .lowercase: .lowercase
        }
    }
}

nonisolated extension TextAlignmentChoice {
    var textAlignment: TextAlignment {
        switch self {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }
}

nonisolated extension TruncationChoice {
    /// nil for `shrink`: smaller type (`minimumScaleFactor`) rather than a cut.
    var truncationMode: Text.TruncationMode? {
        switch self {
        case .head: .head
        case .middle: .middle
        case .tail: .tail
        case .shrink: nil
        }
    }
}

nonisolated extension SymbolRenderingChoice {
    var renderingMode: SymbolRenderingMode {
        switch self {
        case .monochrome: .monochrome
        case .hierarchical: .hierarchical
        case .palette: .palette
        case .multicolor: .multicolor
        }
    }
}

extension ControlSize {
    /// The largest control size whose button is no taller than `height` (a custom layout's
    /// rectangle): a button there is never cut, and grows with its rectangle.
    static func fitting(height: CGFloat) -> ControlSize {
        for size in [ControlSize.large, .regular, .small] where Metrics.Control.height(size) <= height + 0.5 {
            return size
        }
        return .mini
    }
}

nonisolated extension TextAlignmentChoice {
    /// Where a line of this alignment sits in a frame wider than it.
    var frameAlignment: Alignment {
        switch self {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }
}

nonisolated extension ControlSizeChoice {
    var controlSize: ControlSize {
        switch self {
        case .mini: .mini
        case .small: .small
        case .regular: .regular
        case .large: .large
        }
    }

    init(_ size: ControlSize) {
        switch size {
        case .mini: self = .mini
        case .small: self = .small
        case .large, .extraLarge: self = .large
        default: self = .regular
        }
    }
}

extension ResolvedWidgetStyle {
    /// A button element's control size in a custom layout: the style's (set when it was unlocked from
    /// the stacks), else the largest its rectangle takes.
    func controlSize(_ id: ElementID, height: CGFloat) -> ControlSize {
        element(id)?.button.size?.controlSize ?? .fitting(height: height)
    }
}

/// A text's letters (`ink`: the capitals' tops to the last baseline, across the line), its own
/// frame (`box`), in the widget, and the type it is drawn in there.
nonisolated struct TextLetters: Equatable, Sendable {
    var box: CGRect
    var ink: CGRect
    var type: TypeSpec
}

/// On the editor's canvas: where the text's letters are, for the editor to outline and align it by
/// (`WidgetFrameProbe.inks`) — from the capitals' tops to the last line's baseline, across the line
/// it lays out to. Nothing on the island (no probe).
private struct TextInk: ViewModifier {
    let id: ElementID
    let type: TypeSpec

    @Environment(\.widgetFrameProbe) private var probe

    func body(content: Content) -> some View {
        if let probe {
            content.onGeometryChange(for: CGRect.self) { $0.frame(in: .named(WidgetFrameProbe.space)) } action: { box in
                probe.recordInk(id, TextLetters(box: box, ink: Self.ink(of: box, type: type), type: type))
            }
        } else {
            content
        }
    }
    /// The letters in a text's frame `box`, laid out in `type` (`WidgetTypography.letters`).
    nonisolated static func ink(of box: CGRect, type: TypeSpec) -> CGRect { WidgetTypography.letters(inBox: box, type) }
}
