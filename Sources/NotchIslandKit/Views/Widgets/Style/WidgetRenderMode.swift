import SwiftUI

/// How a widget is drawn: `live` on the island, or `canvas` — the Customize editor's canvas and the
/// stage — where it is a picture: its glass buttons and sliders drawn as plain shapes that take
/// exactly their room (`GlassButtonPicture`, `SliderPicture`), no clock or line ticking, and
/// nothing read from the system (`isWidgetPreview`). Laid out alike, so what the editor measures
/// on the canvas is where the elements are on the island.
nonisolated enum WidgetRenderMode: Sendable {
    case live, canvas
}

extension EnvironmentValues {
    @Entry var widgetRenderMode = WidgetRenderMode.live
    /// Set by the editor (and tests): where each tagged element (`editorElement`) is drawn. Nil on
    /// the island, where tagging costs nothing.
    @Entry var widgetFrameProbe: WidgetFrameProbe?
    /// A picture that still reads what costs nothing to ask and asks for no permission (the
    /// battery's details, the disk, the network): the Customize editor's canvas, where the widget
    /// is edited as it will be on the island. The gallery and the stage show samples.
    @Entry var widgetReadsLive = false
}

/// Where each element of one widget is, in the widget's own space (its top-left corner at 0, 0,
/// padding included), as laid out, and the type or symbol size it was drawn at: an unobserved
/// sink, so recording redraws nothing.
final class WidgetFrameProbe {
    /// The coordinate space `IslandWidgetView` names on its full frame in canvas mode.
    nonisolated static let space = "widgetFrameProbe"

    /// What an element was drawn with, beyond its frame.
    nonisolated enum Drawn: Equatable, Sendable {
        /// `fit`: the largest size the kind's layout gives it at this size (the editor's range).
        case text(TypeSpec, lines: Int, fit: CGFloat?)
        case symbol(SymbolSpec, points: CGFloat, fit: CGFloat?)
        /// A button (or a group of them) at this control size.
        case button(ControlSizeChoice)
    }

    private(set) var frames: [ElementID: CGRect] = [:]
    private(set) var drawn: [ElementID: Drawn] = [:]
    /// Where a text element's letters are: from its capitals' tops to its last line's baseline,
    /// across its line, and the text's own frame (`TextInk`). The editor outlines and aligns text by these.
    private(set) var inks: [ElementID: TextLetters] = [:]
    /// Called after every record or removal (the editor publishes what it measured, coalesced).
    var onChange: (() -> Void)?
    /// Elements drawn inside another's frame, in their own type (Now Playing's artist on the
    /// title's line): no frame of their own, but a size to keep.
    private(set) var companions: [ElementID: TypeSpec] = [:]

    /// The view that recorded each element last: a layout swapped for another (the kind's stacks
    /// for a custom one and back) draws the element in a new view before the old one goes, and the
    /// old one's going must not take the new one's frame with it.
    private var owners: [ElementID: UUID] = [:]

    func record(_ id: ElementID, _ frame: CGRect, drawn: Drawn? = nil, companion: (id: ElementID, type: TypeSpec)? = nil,
                owner: UUID? = nil) {
        owners[id] = owner
        frames[id] = frame
        if let drawn { self.drawn[id] = drawn }
        if let companion { companions[companion.id] = companion.type }
        onChange?()
    }

    func recordInk(_ id: ElementID, _ letters: TextLetters) {
        guard inks[id] != letters else { return }
        inks[id] = letters
        onChange?()
    }

    /// The widget unlocked where its stacks drew it (`LayoutConversion.unlock`), with everything
    /// the probe learned.
    ///
    /// `contentScale`: the style's content scale the stacks were drawn at (their frames are
    /// measured as seen, so every size is taken as seen too: the layout then draws at scale 1).
    func unlock(size: CGSize, padding: CGFloat, scale: CGFloat = 1, displayScale: CGFloat = 2, contentScale: CGFloat = 1) -> LayoutConversion.Unlocked {
        var plan = drawnPlan()
        var companions = companions
        if contentScale != 1 {
            plan.elements = plan.elements.mapValues { element in
                var element = element
                element.points *= contentScale
                element.type = element.type.map { $0.at($0.points * contentScale) }
                return element
            }
            companions = companions.mapValues { $0.at($0.points * contentScale) }
        }
        return LayoutConversion.unlock(plan: plan, probed: frames, drawn: drawn, companions: companions, size: size, padding: padding,
                                       scale: scale, displayScale: displayScale)
    }

    /// Laid out again without the element (hidden, no room): it has no frame.
    func remove(_ id: ElementID, owner: UUID? = nil) {
        if let owner, let current = owners[id], current != owner { return }
        owners[id] = nil
        frames[id] = nil
        drawn[id] = nil
        inks[id] = nil
        onChange?()
    }

    /// The widget as its stacks drew it, as a plan: every measured element at the size it was
    /// drawn, so unlocking it (`LayoutConversion.unlock`) keeps each size exactly.
    func drawnPlan(hidden: [ElementID: HiddenReason] = [:]) -> WidgetPlan {
        var elements: [ElementID: ElementPlan] = [:]
        for (id, frame) in frames {
            switch drawn[id] {
            case .text(let type, let lines, let fit)?:
                elements[id] = ElementPlan(points: type.points, range: Self.range(type.points, fit), size: frame.size, variant: 0,
                                           isClamped: false, type: type, lines: lines)
            case .symbol(let symbol, let points, let fit)?:
                elements[id] = ElementPlan(points: points, range: Self.range(points, fit), size: frame.size, variant: 0,
                                           isClamped: false, symbol: symbol)
            case .button?, nil:
                elements[id] = ElementPlan(points: 0, range: 0...0, size: frame.size, variant: 0, isClamped: false)
            }
        }
        return WidgetPlan(elements: elements, hidden: hidden.filter { frames[$0.key] == nil })
    }

    /// From the smallest size to the room's, or the drawn size alone when the room is not known.
    private static func range(_ points: CGFloat, _ fit: CGFloat?) -> ClosedRange<CGFloat> {
        guard let fit, fit.isFinite else { return points...points }
        let upper = max(min(fit, TextFit.maximumPoints), TextFit.minimumPoints)
        return min(TextFit.minimumPoints, points)...max(upper, points)
    }
}

extension View {
    /// Tags an element for the editor: with a probe (`\.widgetFrameProbe`, read once by the
    /// element's view) its frame is recorded, and what it is drawn with; without one — the island —
    /// this is the view itself.
    @ViewBuilder func editorElement(_ id: ElementID, in probe: WidgetFrameProbe?, drawn: WidgetFrameProbe.Drawn? = nil,
                                    companion: (id: ElementID, type: TypeSpec)? = nil) -> some View {
        if let probe {
            modifier(ProbedElement(id: id, probe: probe, drawn: drawn, companion: companion))
        } else {
            self
        }
    }

    /// A button element (or a group), tagged with the control size it is drawn at.
    func buttonElement(_ id: ElementID, in probe: WidgetFrameProbe?) -> some View {
        modifier(ButtonElementTag(id: id, probe: probe))
    }

    /// A text element: in its type with the style on it (`widgetText`) at the size the kind gives
    /// it, tagged with the type it is drawn in and the most the room gives it (`fit`).
    func widgetTextElement(_ id: ElementID, _ type: TypeSpec, lines: Int = 1, fit: CGFloat? = nil, in style: ResolvedWidgetStyle,
                           probe: WidgetFrameProbe?) -> some View {
        widgetText(id, type, in: style)
            .editorElement(id, in: probe, drawn: .text(style.drawnType(id, type), lines: style.element(id)?.text.lineLimit ?? lines,
                                                       fit: fit))
    }

    /// A symbol element, tagged with the size it is drawn at.
    func widgetSymbolElement(_ id: ElementID, _ name: String, points: CGFloat, weight: FontWeightChoice = .regular,
                             fit: CGFloat? = nil, in style: ResolvedWidgetStyle, probe: WidgetFrameProbe?) -> some View {
        widgetSymbol(id, points: points, weight: weight, in: style)
            .editorElement(id, in: probe, drawn: .symbol(SymbolSpec(name: name, weight: style.element(id)?.symbol.weight ?? weight),
                                                         points: points, fit: fit))
    }
}

extension ResolvedWidgetStyle {
    /// The type an element is drawn in: the kind's, with the element's style on it.
    func drawnType(_ id: ElementID, _ type: TypeSpec) -> TypeSpec {
        element(id).map { type.applying($0.text) } ?? type
    }
}

/// Records the element's frame for as long as this view draws it.
private struct ProbedElement: ViewModifier {
    let id: ElementID
    let probe: WidgetFrameProbe
    let drawn: WidgetFrameProbe.Drawn?
    let companion: (id: ElementID, type: TypeSpec)?

    @State private var owner = UUID()

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(WidgetFrameProbe.space)) } action: {
                probe.record(id, $0, drawn: drawn, companion: companion, owner: owner)
            }
            .onDisappear { probe.remove(id, owner: owner) }
    }
}

/// A glass button at rest, drawn with plain shapes: the label in the control size's font and the
/// system button's own padding (measured: every glass and bordered button of one control size takes
/// the same room), on a faint circle, capsule or rounded rectangle — or the tint, prominent.
struct GlassButtonPicture: ButtonStyle {
    var look: ButtonLookChoice = .glass
    let shape: ButtonShapeChoice
    /// The face's colour (a Now Playing button's look, the element's); nil is the plain glass, or the tint.
    var fill: Color?

    init(look: ButtonLookChoice, shape: ButtonShapeChoice, fill: Color? = nil) {
        self.look = look
        self.shape = shape
        self.fill = fill
    }

    init(prominent: Bool, shape: ButtonShapeChoice, fill: Color? = nil) {
        self.init(look: prominent ? .prominent : .glass, shape: shape, fill: fill)
    }

    private var prominent: Bool { look == .prominent }

    @Environment(\.controlSize) private var controlSize
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let (vertical, horizontal, round) = Self.padding(controlSize)
        configuration.label
            // The system button's own font where the button has none: AppKit's for its size (a
            // picture rendered off screen gets no font from the control size).
            .transformEnvironment(\.font) { font in
                if font == nil { font = .system(size: NSFont.systemFontSize(for: Self.appKitSize(controlSize))) }
            }
            .foregroundStyle(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.vertical, vertical)
            .padding(.horizontal, shape == .circle ? round : horizontal)
            .background { face }
            .opacity(isEnabled ? 1 : 0.5)
    }

    @ViewBuilder private var face: some View {
        switch look {
        case .plain: EmptyView()
        // Flat and outlined, as the system's bordered button: not glass.
        case .bordered: ButtonFace(shape: shape, fill: AnyShapeStyle(fill?.opacity(0.35) ?? .white.opacity(0.08)),
                                   stroke: fill ?? .white.opacity(0.35))
        case .glass, .prominent:
            ButtonFace(shape: shape, fill: fill.map(AnyShapeStyle.init) ?? (prominent ? AnyShapeStyle(.tint) : AnyShapeStyle(.white.opacity(0.14))))
        }
    }

    static func appKitSize(_ size: ControlSize) -> NSControl.ControlSize {
        switch size {
        case .mini: .mini
        case .small: .small
        case .large: .large
        case .extraLarge: .extraLarge
        default: .regular
        }
    }

    /// Around the label: above and below, beside it in a capsule, beside it in a circle.
    static func padding(_ size: ControlSize) -> (CGFloat, CGFloat, CGFloat) {
        switch size {
        case .mini: (1, 8, 1)
        case .small: (3, 10, 3)
        case .large: (6, 14, 6)
        case .extraLarge: (8, 16, 8)
        default: (4, 12, 4)
        }
    }
}

private struct ButtonElementTag: ViewModifier {
    let id: ElementID
    let probe: WidgetFrameProbe?

    @Environment(\.controlSize) private var controlSize

    func body(content: Content) -> some View {
        content.editorElement(id, in: probe, drawn: probe == nil ? nil : .button(ControlSizeChoice(controlSize)))
    }
}

/// A button's face in its shape: filled, and outlined for a bordered one. A rounded rectangle's
/// corners are `radius` (nil: the system button's 6 pt).
struct ButtonFace: View {
    let shape: ButtonShapeChoice
    let fill: AnyShapeStyle
    var stroke: Color? = nil
    var radius: CGFloat? = nil

    var body: some View {
        switch shape {
        case .circle: Circle().fill(fill).overlay { if let stroke { Circle().strokeBorder(stroke, lineWidth: 1) } }
        case .capsule: Capsule().fill(fill).overlay { if let stroke { Capsule().strokeBorder(stroke, lineWidth: 1) } }
        case .roundedRectangle:
            let rectangle = RoundedRectangle(cornerRadius: radius ?? 6, style: .continuous)
            rectangle.fill(fill).overlay { if let stroke { rectangle.strokeBorder(stroke, lineWidth: 1) } }
        }
    }
}
