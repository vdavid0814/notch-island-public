import Synchronization
import SwiftUI

// A custom layout (the grid inside a widget) drawn: each element on its own rectangle, in one
// layout pass — no geometry reader, no `ViewThatFits`, cheaper than a kind's stacks.

/// What a family draws its elements with, one by one: each element alone, as its automatic stacks
/// draw it, so a custom layout places the very views the widget always had. In a custom layout an
/// element is proposed its rectangle's size and reads its planned size from `\.widgetPlan`.
protocol WidgetFamilyElements {
    associatedtype Element: View

    /// What each shown element asks for (its type, symbol or room), for planning its sizes.
    func demands(_ input: PlanInput) -> [ElementDemand]

    @ViewBuilder func element(_ id: ElementID) -> Element

    /// Whether this widget, at this size, is laid out freely when its style says so (a control drawn
    /// as its lone button is not).
    func allowsCustomLayout(_ size: CGSize) -> Bool
}

extension WidgetFamilyElements {
    func allowsCustomLayout(_ size: CGSize) -> Bool { true }
}

extension EnvironmentValues {
    /// The sizes the elements of a custom layout are drawn at (`CustomLayoutPlanner`).
    @Entry var widgetPlan: WidgetPlan?
}

/// A family's widget: its own stacks, or — when its style lays it out freely at this size — its
/// elements on their rectangles. `size` is the room inside the padding, as the family is given.
struct ArrangedFamily<Family: View & WidgetFamilyElements>: View {
    let family: Family
    let widget: IslandWidget
    let size: CGSize

    @Environment(AppModel.self) private var model
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        if case .custom(let layouts) = widget.style.layout.arrangement, family.allowsCustomLayout(size) {
            let padding = WidgetMetrics.padding(for: widget)
            let whole = CGSize(width: size.width + 2 * padding, height: size.height + 2 * padding)
            let scale = model.layout.scale.factor
            if case .custom(let layout, _) = layouts.resolve(LayoutClass(size: whole, scale: scale)) {
                var arrangement = ResolvedArrangement.resolve(layout, size: whole, padding: padding,
                                                              contentScale: CGFloat(widget.style.layout.contentScale ?? 1))
                // What the widget does not show is not drawn, wherever its rectangle is (an element
                // switched off by the options alone, before the outline's eye parked it too).
                let _ = arrangement.items.removeAll { !$0.id.isCustom && !widget.showsElementOrPart($0.id) }
                // `widget` is already as drawn (`drawn(_:size:scale:)`): planned at the sizes the
                // elements were unlocked at.
                let input = PlanInput(widget: widget, size: whole, scale: scale, displayScale: displayScale)
                // What the user added is planned like the kind's own: a label and a symbol take
                // their sizes from their rectangles.
                let demands = family.demands(input) + layout.decorations.sorted { $0.key.rawValue < $1.key.rawValue }.map {
                    ElementDemand(decoration: $0.value, id: $0.key, input: input)
                }
                CustomArrangementView(family: family, arrangement: arrangement, padding: padding, size: whole,
                                      images: Set(widget.kind.spec.elements.filter { $0.role == .image }.map(\.id)),
                                      boxes: widget.kind.spec.boxElements, filled: widget.kind.spec.filledButtons,
                                      decorations: layout.decorations)
                    .environment(\.widgetPlan, CustomLayoutPlanner(arrangement: arrangement, displayScale: displayScale).plan(demands))
            } else {
                family
            }
        } else {
            family
        }
    }
}

/// The elements on their rectangles, in the widget's space: laid out inside the padding, so the
/// rectangles' origin is the widget's corner, `padding` up and to the left.
struct CustomArrangementView<Family: WidgetFamilyElements>: View {
    let family: Family
    let arrangement: ResolvedArrangement
    let padding: CGFloat
    /// The whole widget, padding included (the rectangles' space).
    var size: CGSize = .zero
    /// The kind's pictures (a cover, a photo): concentric with a widget corner they reach.
    var images: Set<ElementID> = []
    /// Its lines, controls and groups of buttons: made as large as their rectangles (`FittedElement`).
    var boxes: Set<ElementID> = []
    /// Its lone buttons: each fills its rectangle (`elementFill`).
    var filled: Set<ElementID> = []
    /// What the user added (`custom.<uuid>`): drawn here, not by the family.
    var decorations: [ElementID: Decoration] = [:]

    @Environment(\.widgetFrameProbe) private var probe
    @Environment(\.widgetCorners) private var corners
    @Environment(\.elementFitStore) private var fitStore

    var body: some View {
        CustomElementLayout(origin: CGPoint(x: -padding, y: -padding)) {
            ForEach(arrangement.items) { item in
                Group {
                    if let decoration = decorations[item.id] {
                        DecorationView(id: item.id, decoration: decoration, frame: item.frame)
                            // A shape in a widget corner takes the corner's curve.
                            .environment(\.elementCorners, decoration.mayBleed
                                         ? ConcentricGeometry.corners(element: item.frame, in: size, outer: corners.outer, padding: padding,
                                                                      otherwise: 0)
                                         : nil)
                    } else if filled.contains(item.id) {
                        // A lone button: its face is its whole rectangle (`FilledButtonStyle`) — but
                        // at its own size, as the stacks drew it there.
                        family.element(item.id)
                            .environment(\.elementFill, item.isAtNaturalSize ? nil : item.fillSize)
                            .frame(width: item.frame.width, height: item.frame.height)
                    } else if boxes.contains(item.id) {
                        FittedElement(size: item.frame.size, natural: item.isProportional ? item.natural : nil,
                                      report: fitStore.map { FitReport(store: $0, id: item.id) }) { family.element(item.id) }
                    } else {
                        family.element(item.id)
                            .environment(\.elementCorners, images.contains(item.id)
                                         ? ConcentricGeometry.corners(element: item.frame, in: size, outer: corners.outer, padding: padding,
                                                                      otherwise: min(item.frame.width, item.frame.height) < 44 ? 6 : 12)
                                         : nil)
                    }
                }
                .editorElement(item.id, in: probe)
                .layoutValue(key: ElementRect.self, value: item.frame)
            }
        }
    }
}

extension EnvironmentValues {
    /// A picture's corners in a custom layout: concentric with the widget's where it reaches one.
    @Entry var elementCorners: RectangleCornerRadii?
}

/// An element's rectangle in a custom layout.
nonisolated struct ElementRect: LayoutValueKey {
    static let defaultValue = CGRect.zero
}

nonisolated extension WidgetKindSpec {
    /// The elements drawn at a size of their own inside their rectangles (lines, charts, controls,
    /// groups of buttons), which a custom layout scales to fill them.
    var boxElements: Set<ElementID> {
        // Not a chart: it takes any proportions, drawn as large as its rectangle each way.
        Set(elements.filter { [.button, .line, .feature].contains($0.role) }.flatMap { [$0.id] + $0.parts })
            .subtracting(filledButtons)
    }

    /// The buttons: each fills its rectangle in a custom layout — wider, a wider capsule; taller, a
    /// taller one; square, a circle — so a side dragged changes that side alone. A part of a split
    /// group is one; a group drawn as one element (Start and Cancel) shares its rectangle among the
    /// buttons it shows (`TimerActions`). A control's round button too.
    var filledButtons: Set<ElementID> {
        var ids = Set(elements.filter { $0.role == .button }.flatMap { [$0.id] + $0.parts })
        if elements.contains(where: { $0.id == .controlButton }) { ids.insert(.controlButton) }
        return ids
    }

    /// Elements that draw several buttons side by side.
    static let buttonGroups: Set<ElementID> = [ElementID(rawValue: "timerActions"), ElementID(rawValue: "shelfActions")]
}

extension EnvironmentValues {
    /// A lone button's rectangle in a custom layout: its face fills it (`FilledButtonStyle`).
    @Entry var elementFill: CGSize?
}

/// A lone button in a custom layout: its face is its whole rectangle — a circle when square, a
/// capsule wider or taller, or the rounded rectangle its shape says — and its symbol grows with the
/// shorter side. The island's glass, the canvas's drawing of it (and a picture's plain fill) alike;
/// a bordered button is flat and outlined; a plain button keeps no face.
struct FilledButtonStyle: ButtonStyle {
    enum Face { case glass, prominent, solid, plain, bordered }

    let size: CGSize
    var face: Face = .glass
    var shape: ButtonShapeChoice = .capsule
    /// The face's colour (a Now Playing button's look, the element's).
    var tint: Color? = nil
    /// A rounded rectangle's corners (nil: a quarter of its shorter side).
    var radius: CGFloat? = nil

    @Environment(\.widgetRenderMode) private var renderMode
    @Environment(\.isWidgetPreview) private var isPreview
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let side = min(size.width, size.height)
        // A circle when square (as the island's round buttons), a capsule otherwise.
        let outline = shape == .roundedRectangle ? AnyShape(RoundedRectangle(cornerRadius: radius ?? side * 0.25, style: .continuous))
            : AnyShape(Capsule())
        let label = configuration.label
            .font(.system(size: max(side * 0.4, 6), weight: .semibold))
            .foregroundStyle(face == .prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .lineLimit(1)
            .padding(.horizontal, size.width > size.height * 1.4 ? side * 0.35 : 0)
            .frame(width: size.width, height: size.height)
            .contentShape(outline)
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.5)
        Group {
            switch face {
            case .plain:
                label
            case .solid:
                label.background(outline.fill(tint ?? Color(white: 0.3)))
            case .bordered:
                label.background {
                    outline.fill(tint?.opacity(0.35) ?? .white.opacity(0.08))
                        .overlay { outline.stroke(tint ?? .white.opacity(0.35), lineWidth: 1) }
                }
            case .glass, .prominent:
                let fill: AnyShapeStyle = face == .prominent ? (tint.map(AnyShapeStyle.init) ?? AnyShapeStyle(.tint))
                    : tint.map(AnyShapeStyle.init) ?? AnyShapeStyle(.white.opacity(0.14))
                if renderMode == .canvas || isPreview {
                    label.background(outline.fill(fill))
                } else if face == .prominent {
                    label.background(outline.fill(fill)).glassEffect(.regular.interactive(), in: outline)
                } else {
                    label.glassEffect(Glass.regular.tint(tint).interactive(), in: outline)
                }
            }
        }
    }
}

/// An element that draws at a size of its own — a button, the scrubber, a chart — made as large as
/// its rectangle, uniformly: its height sets the scale, and it is laid out again across the width
/// that leaves, so a line still runs the whole width while its thickness and its type grow with the
/// rectangle. Resizing it always resizes what is drawn (`ElementFit`); the editor's outline is
/// what it draws (`ElementFitStore`). What already fills its rectangle (a chart that takes any
/// size) is drawn as it is.
///
/// Scaled in one pass (`visualEffect` reads the size `FitToRect` laid it out at): no state, so a
/// picture rendered once (`ImageRenderer`) draws it scaled too.
struct FittedElement<Content: View>: View {
    let size: CGSize
    /// Its own size where it was unlocked (`ElementFrame.natural`); nil: measured.
    var natural: CGSize? = nil
    /// Where the editor hears what it draws; nil on the island.
    var report: FitReport? = nil
    @ViewBuilder let content: Content

    var body: some View {
        let target = size
        let layout = FitToRect(target: target, natural: natural, report: report)
        if let natural, abs(natural.height - size.height) < 0.5, abs(natural.width - size.width) < 0.5 {
            // In its own rectangle (where it was unlocked, or reflowed with it): laid out there, not
            // scaled — the very pixels the stacks drew (a scaling layer, even at 1, aligns type differently).
            layout { content }
                .frame(width: size.width, height: size.height)
        } else {
            layout { content }
                .visualEffect { effect, proxy in
                    effect.scaleEffect(FitToRect.scale(proxy.size, in: target))
                }
                .frame(width: size.width, height: size.height)
        }
    }
}

/// What an element drawn at a size of its own draws in a rectangle of any size: measured on the
/// canvas, so the editor's outline and resizing follow what is drawn, never an empty frame.
nonisolated struct ElementFit: Equatable, Sendable {
    /// What it is laid out at, scale 1: its size where it was unlocked, or as it measures.
    var natural: CGSize
    /// The least width it needs at that height (its times, its buttons side by side).
    var minWidth: CGFloat
    /// The most width it takes at that height; nil for one that runs across any width (a line).
    var maxWidth: CGFloat?
    /// The least height it takes (a button's smallest size): in a shorter rectangle it is scaled
    /// down to fit, never drawn over what lies beside it.
    var minHeight: CGFloat = 0

    /// The scale it is drawn at in a rectangle of `size`: its height's, as far as its width fits.
    /// Exactly 1 at its own height where the width lets it.
    func scale(in size: CGSize) -> CGFloat {
        guard natural.height > 0 else { return 1 }
        let isOwn = abs(size.height - natural.height) < 0.5
        var scale = isOwn ? 1 : size.height / natural.height
        if minWidth > 0, size.width / scale < natural.width - 0.5 { scale = min(scale, size.width / minWidth) }
        // Where it was unlocked it is drawn as there, whatever it measures.
        if minHeight > 0, !(isOwn && abs(size.width - natural.width) < 0.5) { scale = min(scale, size.height / minHeight) }
        return min(max(scale, FitToRect.scales.lowerBound), FitToRect.scales.upperBound)
    }

    /// What it draws in a rectangle of `size`, centred in it.
    func object(in size: CGSize) -> CGSize {
        let scale = scale(in: size)
        let width = maxWidth.map { min(size.width, $0 * scale) } ?? size.width
        return CGSize(width: min(width, size.width), height: min(natural.height * scale, size.height))
    }
}

/// Where the canvas tells the editor what each such element draws (`EditorSession.fits`).
nonisolated final class ElementFitStore: @unchecked Sendable {
    private let fits = Mutex<[ElementID: ElementFit]>([:])
    /// Called (on any thread) when one changes.
    let onChange: @Sendable () -> Void

    init(onChange: @escaping @Sendable () -> Void = {}) {
        self.onChange = onChange
    }

    func fit(_ id: ElementID) -> ElementFit? { fits.withLock { $0[id] } }

    func record(_ id: ElementID, _ fit: ElementFit?) {
        let changed = fits.withLock { fits in
            guard fits[id] != fit else { return false }
            fits[id] = fit
            return true
        }
        if changed { onChange() }
    }
}

/// One element's line to the editor.
nonisolated struct FitReport: @unchecked Sendable {
    var store: ElementFitStore
    var id: ElementID
}

extension EnvironmentValues {
    /// Set by the Customize canvas: where fitted elements report what they draw.
    @Entry var elementFitStore: ElementFitStore?
}

/// Lays its one subview out at the size that, scaled uniformly, fills `target` (`FittedElement`).
nonisolated struct FitToRect: Layout {
    var target: CGSize
    var natural: CGSize? = nil
    var report: FitReport? = nil

    /// No more than four times larger or 0.4 times smaller than the element's own size.
    static let scales: ClosedRange<CGFloat> = 0.4...4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        subviews.first.map(laidOut) ?? .zero
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let subview = subviews.first else { return }
        subview.place(at: CGPoint(x: bounds.midX, y: bounds.midY), anchor: .center, proposal: ProposedViewSize(laidOut(subview)))
    }

    /// What the element draws at, and in what widths (nil: it fills any rectangle as it is).
    func fit(_ subview: LayoutSubview) -> ElementFit? {
        guard target.width > 0, target.height > 0 else { return nil }
        let natural: CGSize
        if let own = self.natural, own.width > 0, own.height > 0 {
            natural = own
        } else {
            let whole = subview.sizeThatFits(ProposedViewSize(target))
            guard whole.width > 0, whole.height > 0,
                  abs(whole.width - target.width) > 0.5 || abs(whole.height - target.height) > 0.5 else { return nil }
            natural = whole
        }
        let least = subview.sizeThatFits(ProposedViewSize(width: nil, height: natural.height)).width
        let most = subview.sizeThatFits(ProposedViewSize(width: 100_000, height: natural.height)).width
        let lowest = subview.sizeThatFits(ProposedViewSize(width: natural.width, height: 0)).height
        return ElementFit(natural: natural, minWidth: min(least, natural.width), maxWidth: most >= 50_000 ? nil : most,
                          minHeight: lowest > natural.height + 0.5 ? lowest : 0)
    }

    /// The size the element is laid out at before it is scaled to the target.
    func laidOut(_ subview: LayoutSubview) -> CGSize {
        let fit = fit(subview)
        report.map { $0.store.record($0.id, fit) }
        guard let fit else { return target }
        let scale = fit.scale(in: target)
        return abs(scale - 1) < 0.001 ? target : CGSize(width: target.width / scale, height: target.height / scale)
    }

    /// The scale that fits a laid-out `size` into `target`. Within a pixel of the target it is 1:
    /// the size read back is rounded to the pixel, and 0.997 would draw everything resampled.
    static func scale(_ size: CGSize, in target: CGSize) -> CGFloat {
        guard size.width > 0, size.height > 0 else { return 1 }
        let scale = min(max(min(target.width / size.width, target.height / size.height), scales.lowerBound), scales.upperBound)
        let slack = 1 / max(min(size.width, size.height), 1)
        return abs(scale - 1) <= slack ? 1 : scale
    }
}

/// Each subview proposed its rectangle's size (`ElementRect`) and centred on it: text shorter than
/// its frame (a line is never taller than `TextFit.frameHeight`) sits where it was measured.
nonisolated struct CustomElementLayout: Layout {
    /// Where the rectangles' origin is in the bounds.
    var origin: CGPoint = .zero

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            let rect = subview[ElementRect.self]
            subview.place(at: CGPoint(x: bounds.minX + origin.x + rect.midX, y: bounds.minY + origin.y + rect.midY),
                          anchor: .center, proposal: ProposedViewSize(rect.size))
        }
    }
}

/// A custom layout at one size: each placed element's rectangle in the widget, back to front
/// (`ElementLayoutGeometry.reflow`), on a 1/1024-point grid so a rectangle stored as fractions
/// comes back exactly where it was measured. Memoised per layout and size.
nonisolated struct ResolvedArrangement: Equatable, Sendable {
    nonisolated struct Item: Equatable, Sendable, Identifiable {
        var id: ElementID
        var frame: CGRect
        /// The size it draws at before it is scaled to its frame (`ElementFrame.natural`), as drawn here.
        var natural: CGSize? = nil
        /// Its rectangle kept its proportions from the layout's (the layout is drawn at its own
        /// size, or uniformly larger or smaller); false where a reflow stretched it one way.
        var isProportional = true
        /// Its rectangle's proportions in the layout (width over height).
        var aspect: CGFloat? = nil
        /// The type or symbol size it was unlocked at (`ElementFrame.points`), as drawn here.
        var points: CGFloat? = nil
        /// Text: the most lines it wraps to (`ElementFrame.lines`).
        var lines: Int? = nil

        /// Its rectangle, or where a reflow stretched it one way, the largest of its own proportions
        /// inside it: a lone button keeps its shape in another widget's size.
        var fillSize: CGSize {
            guard !isProportional, let aspect, aspect > 0, frame.width > 0, frame.height > 0 else { return frame.size }
            return frame.width / frame.height > aspect ? CGSize(width: frame.height * aspect, height: frame.height)
                                                       : CGSize(width: frame.width, height: frame.width / aspect)
        }

        /// Its rectangle is the one it was unlocked in: drawn as it was there.
        var isAtNaturalSize: Bool {
            isProportional && natural.map { abs($0.width - frame.width) < 0.5 && abs($0.height - frame.height) < 0.5 } ?? false
        }
    }

    var items: [Item]

    func frame(_ id: ElementID) -> CGRect? { items.first { $0.id == id }?.frame }

    static func resolve(_ layout: CustomLayout, size: CGSize, padding: CGFloat, contentScale: CGFloat = 1) -> ResolvedArrangement {
        let key = Key(layout: layout, width: size.width, height: size.height, padding: padding, contentScale: contentScale)
        if let resolved = cache.withLock({ $0[key] }) { return resolved }
        // What draws at a size of its own keeps its proportion to its rectangle, each way: reflowed to
        // another size, it is laid out in its new rectangle as it was in its own, never magnified.
        let authored = Dictionary(layout.items.map { ($0.id, $0) }) { first, _ in first }
        let items = ElementLayoutGeometry.reflow(layout, to: size, padding: padding, contentScale: contentScale).map { placed in
            var natural: CGSize?
            var isProportional = true
            var aspect: CGFloat?
            var points: CGFloat?
            if let item = authored[placed.id] {
                let width = item.rect.width * layout.authoredSize.width, height = item.rect.height * layout.authoredSize.height
                if width > 0, height > 0 {
                    let x = placed.frame.width / width, y = placed.frame.height / height
                    natural = item.natural.map { CGSize(width: snapped($0.width * x), height: snapped($0.height * y)) }
                    isProportional = abs(x - y) <= 0.005 * max(x, y)
                    aspect = width / height
                    // Its type as much larger as its rectangle is taller; in its own rectangle (up to
                    // the rounding of the reflow), exactly as it was unlocked.
                    points = item.points.map { abs(y - 1) < 0.002 ? CGFloat($0) : snapped(CGFloat($0) * y) }
                }
            }
            return Item(id: placed.id, frame: CGRect(x: snapped(placed.frame.minX), y: snapped(placed.frame.minY),
                                                     width: snapped(placed.frame.width), height: snapped(placed.frame.height)),
                        natural: natural, isProportional: isProportional, aspect: aspect, points: points,
                        lines: authored[placed.id]?.lines)
        }
        let resolved = ResolvedArrangement(items: items)
        cache.withLock { $0[key] = resolved }
        return resolved
    }

    static func snapped(_ value: CGFloat) -> CGFloat { (value * 1024).rounded() / 1024 }

    private struct Key: Hashable {
        var layout: CustomLayout
        var width: CGFloat
        var height: CGFloat
        var padding: CGFloat
        var contentScale: CGFloat
    }

    private static let cache = Mutex(MeasureCache<Key, ResolvedArrangement>())
}

/// The sizes of a custom layout's elements, from their rectangles: the same `WidgetPlan` a kind's
/// planner gives, so the editor's size ranges and clamp badges work alike.
///
/// - Text is drawn at its own size (`ElementFrame.points`, or the style's) exactly: its rectangle is
///   its lines' height, and what is too long for it is cut or shrunk (`TextStyle.truncation`). Text
///   without a size of its own fills its frame: the largest size whose lines fit its height.
/// - A symbol is the largest that fits its rectangle; a fixed one is clamped and flagged the same way.
/// - Anything else (a button, a line, an image) takes its rectangle.
/// - An element without a rectangle is not drawn (it did not fit when unlocked, or was parked).
nonisolated struct CustomLayoutPlanner: Sendable {
    var arrangement: ResolvedArrangement
    var displayScale: CGFloat

    func plan(_ demands: [ElementDemand]) -> WidgetPlan {
        var elements: [ElementID: ElementPlan] = [:]
        var hidden: [ElementID: HiddenReason] = [:]
        for demand in demands {
            guard let frame = arrangement.frame(demand.id) else {
                hidden[demand.id] = .noRoom
                continue
            }
            elements[demand.id] = plan(demand, in: frame)
        }
        return WidgetPlan(elements: elements, hidden: hidden)
    }

    private func plan(_ demand: ElementDemand, in frame: CGRect) -> ElementPlan {
        let fixed: CGFloat? = if case .fixed(let points) = demand.size { CGFloat(points) } else { nil }
        var room: CGFloat
        var type: TypeSpec?
        var lines = 1
        var symbol: SymbolSpec?
        switch demand.content {
        case .text(let samples, let spec, let limit):
            room = Self.textPoints(height: frame.height, lines: limit, spec: spec)
            if let fixed {
                // Its own size, whatever the rectangle: the editor keeps the rectangle its lines' height.
                return ElementPlan(points: fixed, range: TextFit.minimumPoints...max(fixed, room, TextFit.minimumPoints), size: frame.size,
                                   variant: 0, isClamped: false, type: spec, lines: limit)
            }
            if limit == 1, let sample = samples.first { room = Self.widened(room, sample: sample, spec: spec, width: frame.width, scale: displayScale) }
            (type, lines) = (spec, limit)
        case .symbol(let name, let weight):
            room = SymbolFit.maxPoints(name, weight: weight, room: frame.size, scale: displayScale) ?? 0
            symbol = SymbolSpec(name: name, weight: weight)
        case .box:
            return ElementPlan(points: 0, range: 0...0, size: frame.size, variant: 0, isClamped: false)
        }
        // A fixed size within a step of its room is drawn as set: the room is measured in steps and
        // rounded to the pixel, and a size unlocked from the stacks sits right at it. A symbol's room
        // is measured with the spec's symbol, which the one drawn (a level's own) may be a third
        // narrower or wider than.
        let slack = symbol == nil ? TextFit.step : room * 0.35 + TextFit.step
        let points = fixed.map { $0 <= room + slack ? $0 : room } ?? room
        return ElementPlan(points: points, range: TextFit.minimumPoints...max(room, TextFit.minimumPoints), size: frame.size,
                           variant: 0, isClamped: fixed.map { points < $0 } ?? false, type: type, lines: lines, symbol: symbol)
    }

    /// `points` made smaller as far as the style's wider letters (more space between them, Expanded,
    /// capitals) would no longer fit `width` where the plain letters do: a "5:00" with 10 pt between
    /// its letters read "5 : …". Text no wider than it is plainly (or the kind's own) is left as it
    /// is, so a layout just unlocked draws what it drew.
    static func widened(_ points: CGFloat, sample: String, spec: TypeSpec, width: CGFloat, scale: CGFloat) -> CGFloat {
        guard !sample.isEmpty, width > 0 else { return points }
        var plain = spec
        plain.tracking = min(spec.tracking, 0)
        plain.textCase = .asIs
        if spec.width == .expanded { plain.width = .standard }
        let allowed = max(width, WidgetTypography.width(sample, plain.at(points), scale: scale))
        var fitted = points
        while fitted > TextFit.minimumPoints, WidgetTypography.width(sample, spec.at(fitted), scale: scale) > allowed + 0.5 {
            fitted -= TextFit.step
        }
        return fitted
    }

    /// The size text takes from a frame of `height`.
    static func textPoints(height: CGFloat, lines: Int, spec: TypeSpec) -> CGFloat {
        min(TextFit.points(forFrameHeight: height, lines: lines, spec: spec), TextFit.maximumPoints)
    }
}

extension IslandWidget {
    /// The widget as a custom layout draws it in `size` (its room inside the padding): each placed
    /// element's unlocked size (`ElementFrame.points`) as its fixed one, where its style sets none.
    /// Its family is made from this widget, so an element that reads its own widget's style draws
    /// at that size as well as one that reads the environment's. Itself where no layout applies (a
    /// control drawn as its lone button, as `allowsCustomLayout`).
    func drawn(in size: CGSize, scale: CGFloat) -> IslandWidget {
        guard case .custom(let layouts) = style.layout.arrangement,
              kind.spec.family != .controls || (!WidgetMetrics.isRound(self) && layout != .button) else { return self }
        let padding = WidgetMetrics.padding(for: self)
        let whole = CGSize(width: size.width + 2 * padding, height: size.height + 2 * padding)
        guard case .custom(let layout, _) = layouts.resolve(LayoutClass(size: whole, scale: scale)),
              layout.items.contains(where: { $0.points != nil || $0.lines != nil }) else { return self }
        let arrangement = ResolvedArrangement.resolve(layout, size: whole, padding: padding,
                                                      contentScale: CGFloat(style.layout.contentScale ?? 1))
        var widget = self
        for item in arrangement.items {
            // By its role; one the kind does not name gets both, and draws with the one it reads.
            let role = widget.kind.spec.element(item.id)?.role
            let isText = role == .text || role == nil && layout.decorations[item.id]?.text != nil
            if let lines = item.lines, isText {
                widget.style.elements[item.id, default: ElementStyle()].text.lineLimit = lines
            }
            guard let points = item.points else { continue }
            // Text: its own size in this layout, over the style's (a resize sets it).
            if isText {
                widget.style.elements[item.id, default: ElementStyle()].text.points = Double(points)
            } else if role != .symbol, widget.style.elements[item.id]?.text.points == nil {
                widget.style.elements[item.id, default: ElementStyle()].text.points = Double(points)
            }
            if role == .symbol || role == nil, widget.style.elements[item.id]?.symbol.points == nil {
                widget.style.elements[item.id, default: ElementStyle()].symbol.points = Double(points)
            }
        }
        return widget
    }
}
