import SwiftUI

// How an element takes its style. Each is given the element's id, what the kind draws it with and
// the widget's style (`\.widgetStyle`, read once by the element's view); for an element the style
// sets nothing on, it is exactly the kind's own modifier (the same `.font`, nothing else — no
// modifier of ours and no environment read on the island), so an empty style draws today's pixels
// (`WidgetSnapshotTests`). Everything here is resolved once per body evaluation: nothing ticks.

extension View {
    /// Text in the element's type. `type` is the kind's own, its size already fitted to the room;
    /// the style's fixed size replaces that size and is drawn exactly (no shrinking to fit).
    @ViewBuilder func widgetText(_ id: ElementID, _ type: TypeSpec, in style: ResolvedWidgetStyle) -> some View {
        if let element = style.element(id) {
            modifier(WidgetText(element: element, type: type))
        } else {
            font(type.systemFont)
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
        let spec = type.styled(element.text)
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

    /// The kind's type with the element's text style on it: the style's fixed size replaces the fitted one.
    func styled(_ text: TextStyle) -> TypeSpec { applying(text).at(text.points.map { CGFloat($0) } ?? points) }
}

private struct WidgetText: ViewModifier {
    let element: ElementStyle
    let type: TypeSpec

    @Environment(\.widgetArtworkColor) private var artwork

    func body(content: Content) -> some View {
        let text = element.text
        content
            .font(type.styled(text).font)
            .modifier(OptionalTracking(tracking: text.tracking.map { CGFloat($0) }))
            .transformEnvironment(\.textCase) { if let textCase = text.textCase { $0 = textCase.textCase } }
            .transformEnvironment(\.multilineTextAlignment) { if let alignment = text.alignment { $0 = alignment.textAlignment } }
            .transformEnvironment(\.lineLimit) { if let limit = text.lineLimit { $0 = limit } }
            .transformEnvironment(\.truncationMode) { if let mode = text.truncation?.truncationMode { $0 = mode } }
            .transformEnvironment(\.minimumScaleFactor) { factor in
                if text.points != nil { factor = 1 } else if text.truncation == .shrink { factor = 0.6 }
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
        let size = symbol.points.map { CGFloat($0) } ?? points
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
            .clipShape(shape)
            .overlay {
                if let width = image.borderWidth, width > 0 {
                    shape.stroke(element.colors[.border]?.shapeStyle(artwork: artwork) ?? AnyShapeStyle(.white.opacity(0.3)),
                                 lineWidth: width)
                }
            }
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
    @Environment(\.isWidgetPreview) private var isPreview
    @Environment(\.widgetRenderMode) private var renderMode

    func body(content: Content) -> some View {
        let button = element.button
        let tint = element.colors[.tint]?.color(artwork: artwork).map { $0.opacity(button.tintStrength ?? 1) }
        styled(content, look: button.look, shape: button.shape)
            .modifier(OptionalTint(color: tint))
            .modifier(OptionalLabelStyle(iconOnly: button.iconOnly))
    }

    /// Glass as the island draws it: a drawing on the canvas, the bordered button in a picture.
    @ViewBuilder private func styled(_ content: Content, look: ButtonLookChoice?, shape: ButtonShapeChoice?) -> some View {
        let shaped = Group {
            switch look {
            case nil: content
            case .plain: content.buttonStyle(.plain)
            case .bordered: content.buttonStyle(.bordered)
            case .glass, .prominent:
                let prominent = look == .prominent
                if renderMode == .canvas {
                    content.buttonStyle(GlassButtonPicture(prominent: prominent, shape: shape ?? .capsule))
                } else if isPreview {
                    if prominent { content.buttonStyle(.borderedProminent) } else { content.buttonStyle(.bordered) }
                } else {
                    if prominent { content.buttonStyle(.glassProminent) } else { content.buttonStyle(.glass) }
                }
            }
        }
        if let shape {
            shaped.buttonBorderShape(shape.borderShape)
        } else {
            shaped
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

    init(_ element: ElementStyle?) {
        let line = element?.line ?? LineStyle()
        thickness = line.thickness.map { CGFloat($0) }
        cap = line.cap
        fill = element?.colors[.fill]
        fillEnd = element?.colors[.fillEnd]
        track = element?.colors[.track]
        trackOpacity = line.trackOpacity
        mode = line.fill
    }

    /// The fill's one colour for `value` (0…1): the value's colour on a value scale, else the fill.
    func fillColor(value: Double, artwork: Color?) -> Color? {
        if mode == .valueScale, case .valueScale(let scale)? = fill { return scale.color(value) }
        return fill?.color(artwork: artwork, value: value)
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
