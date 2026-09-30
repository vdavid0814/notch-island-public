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
        if case .custom(let layouts) = widget.style.layout.arrangement {
            let padding = WidgetMetrics.padding(for: widget)
            let whole = CGSize(width: size.width + 2 * padding, height: size.height + 2 * padding)
            let scale = model.layout.scale.factor
            if case .custom(let layout, _) = layouts.resolve(LayoutClass(size: whole, scale: scale)) {
                let arrangement = ResolvedArrangement.resolve(layout, size: whole, padding: padding,
                                                              contentScale: CGFloat(widget.style.layout.contentScale ?? 1))
                let input = PlanInput(widget: widget, size: whole, scale: scale, displayScale: displayScale)
                CustomArrangementView(family: family, arrangement: arrangement, padding: padding)
                    .environment(\.widgetPlan, CustomLayoutPlanner(arrangement: arrangement, displayScale: displayScale).plan(family.demands(input)))
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

    @Environment(\.widgetFrameProbe) private var probe

    var body: some View {
        CustomElementLayout(origin: CGPoint(x: -padding, y: -padding)) {
            ForEach(arrangement.items) { item in
                family.element(item.id)
                    .editorElement(item.id, in: probe)
                    .layoutValue(key: ElementRect.self, value: item.frame)
            }
        }
    }
}

/// An element's rectangle in a custom layout.
nonisolated struct ElementRect: LayoutValueKey {
    static let defaultValue = CGRect.zero
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
    }

    var items: [Item]

    func frame(_ id: ElementID) -> CGRect? { items.first { $0.id == id }?.frame }

    static func resolve(_ layout: CustomLayout, size: CGSize, padding: CGFloat, contentScale: CGFloat = 1) -> ResolvedArrangement {
        let key = Key(layout: layout, width: size.width, height: size.height, padding: padding, contentScale: contentScale)
        if let resolved = cache.withLock({ $0[key] }) { return resolved }
        let items = ElementLayoutGeometry.reflow(layout, to: size, padding: padding, contentScale: contentScale).map {
            Item(id: $0.id, frame: CGRect(x: snapped($0.frame.minX), y: snapped($0.frame.minY),
                                          width: snapped($0.frame.width), height: snapped($0.frame.height)))
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
/// - Text fills its frame: the largest size whose lines fit its height (`TextFit.points(forFrameHeight:)`);
///   a fixed size is drawn exactly, or clamped to that and flagged.
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
        let room: CGFloat
        var type: TypeSpec?
        var lines = 1
        var symbol: SymbolSpec?
        switch demand.content {
        case .text(_, let spec, let limit):
            room = Self.textPoints(height: frame.height, lines: limit, spec: spec)
            (type, lines) = (spec, limit)
        case .symbol(let name, let weight):
            room = SymbolFit.maxPoints(name, weight: weight, room: frame.size, scale: displayScale) ?? 0
            symbol = SymbolSpec(name: name, weight: weight)
        case .box:
            return ElementPlan(points: 0, range: 0...0, size: frame.size, variant: 0, isClamped: false)
        }
        let points = fixed.map { min($0, room) } ?? room
        return ElementPlan(points: points, range: TextFit.minimumPoints...max(room, TextFit.minimumPoints), size: frame.size,
                           variant: 0, isClamped: fixed.map { points < $0 } ?? false, type: type, lines: lines, symbol: symbol)
    }

    /// The size text takes from a frame of `height`.
    static func textPoints(height: CGFloat, lines: Int, spec: TypeSpec) -> CGFloat {
        min(TextFit.points(forFrameHeight: height, lines: lines, spec: spec), TextFit.maximumPoints)
    }
}
