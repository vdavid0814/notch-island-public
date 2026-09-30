import CoreGraphics

/// What a widget is planned from: its kind, the size it is drawn at, its style and what it reads.
nonisolated struct PlanInput: Sendable {
    var spec: WidgetKindSpec
    /// The widget's size, in points as drawn.
    var size: CGSize
    var style: WidgetStyle
    /// The island's scale factor (`IslandScale.factor`): design sizes are multiplied by it.
    var scale: CGFloat
    /// Pixels per point, for rounding measured widths.
    var displayScale: CGFloat
    /// What each element may read now, beyond its spec's samples (a track's title, the time…).
    var samples: [ElementID: [String]]
    /// The elements switched on.
    var shown: Set<ElementID>
    /// Element sizes other than medium, from before styles (`IslandWidget.sizes`).
    var sizes: [ElementID: ElementSize]
    /// Between the widget's edge and its content.
    var padding: CGFloat

    init(spec: WidgetKindSpec, size: CGSize, style: WidgetStyle = WidgetStyle(), scale: CGFloat = 1, displayScale: CGFloat = 2,
         samples: [ElementID: [String]] = [:], shown: Set<ElementID>, sizes: [ElementID: ElementSize] = [:],
         padding: CGFloat = WidgetMetrics.padding) {
        self.spec = spec
        self.size = size
        self.style = style
        self.scale = scale
        self.displayScale = displayScale
        self.samples = samples
        self.shown = shown
        self.sizes = sizes
        self.padding = style.layout.padding.map { CGFloat($0) } ?? padding
    }

    init(widget: IslandWidget, size: CGSize, scale: CGFloat, displayScale: CGFloat = 2, samples: [ElementID: [String]] = [:]) {
        self.init(spec: widget.kind.spec, size: size, style: widget.style, scale: scale, displayScale: displayScale,
                  samples: samples, shown: widget.options, sizes: widget.sizes, padding: WidgetMetrics.padding(for: widget))
    }

    /// The element's size: the style's fixed points, else its S/M/L (`IslandWidget.sizes`).
    func textSize(_ id: ElementID) -> TextSize {
        let style = style.elements[id]
        let points = spec.element(id)?.role == .symbol ? style?.symbol.points : style?.text.points
        return points.map(TextSize.fixed) ?? .auto(sizes[id] ?? .medium)
    }

    /// What the element may read: the samples given for it, else its spec's.
    func samples(_ id: ElementID) -> [String] {
        samples[id] ?? spec.element(id)?.samples ?? []
    }

    /// The room inside the padding.
    var inner: CGSize { CGSize(width: max(size.width - 2 * padding, 0), height: max(size.height - 2 * padding, 0)) }
}

/// A type or symbol size as planned: one of the element sizes, fitted to the room (`auto`), or
/// exactly this many points (the style's).
nonisolated enum TextSize: Hashable, Sendable {
    case auto(ElementSize)
    case fixed(Double)
}

/// Every element's size in one widget, and why the others are not drawn.
nonisolated struct WidgetPlan: Equatable, Sendable {
    var elements: [ElementID: ElementPlan]
    var hidden: [ElementID: HiddenReason]
}

nonisolated struct ElementPlan: Equatable, Sendable {
    /// The type or symbol size it is drawn at; 0 for an element without one (a button, a line).
    var points: CGFloat
    /// The sizes the room allows it, the others staying as planned: the editor's size slider.
    var range: ClosedRange<CGFloat>
    /// The room it takes, in points.
    var size: CGSize
    /// Which of the element's forms it takes (0: the fullest); the kind's planner names them.
    var variant: Int
    /// Drawn smaller than the fixed size the user set, because the widget has no room for it.
    var isClamped: Bool
    /// Text's type (its size is `points`) and lines: what its frame's height follows from
    /// (`TextFit.frameHeight`). Nil for anything but text.
    var type: TypeSpec? = nil
    var lines = 1
    /// A symbol's name and weight: what its room follows from (`SymbolFit.size`).
    var symbol: SymbolSpec? = nil
}

nonisolated struct SymbolSpec: Hashable, Sendable {
    var name: String
    var weight: FontWeightChoice
}

nonisolated enum HiddenReason: String, Sendable {
    /// Switched off by the user.
    case switchedOff
    /// No room for it at this size.
    case noRoom
}

/// Plans a kind's elements for a size: the fitting engine's one entry point.
nonisolated protocol WidgetPlanner: Sendable {
    func plan(_ input: PlanInput) -> WidgetPlan
}

/// One element as a planner asks for it: what it draws, the size it would like, what it may not go
/// below.
nonisolated struct ElementDemand: Sendable {
    nonisolated enum Content: Sendable {
        case text(samples: [String], type: TypeSpec, lines: Int)
        case symbol(name: String, weight: FontWeightChoice)
        /// Not sizable (a button, a line, an image): this much room, or none.
        case box(CGSize)
    }

    var id: ElementID
    var content: Content
    /// Medium's size where there is room, in points (the kind's design size, scaled).
    var design: CGFloat
    var size: TextSize
    var priority: Int
    var minRoom: MinRoom?

    var isFixed: Bool {
        if case .fixed = size, !isBox { return true }
        return false
    }

    var isBox: Bool {
        if case .box = content { return true }
        return false
    }
}

nonisolated extension ElementDemand {
    /// An element as its spec describes it, with the style's choices: text in `type`, a symbol by
    /// the spec's name, anything else a box of `box`. `design` is in reference points; the island's
    /// scale and the style's content scale are applied here.
    init(_ element: ElementSpec, input: PlanInput, type: TypeSpec = TypeSpec(points: 0), design: CGFloat, box: CGSize = .zero) {
        let style = input.style.elements[element.id]
        let content: Content = switch element.role {
        case .text:
            .text(samples: input.samples(element.id), type: type.applying(style?.text ?? TextStyle()),
                  lines: style?.text.lineLimit ?? 1)
        case .symbol:
            .symbol(name: element.symbol, weight: style?.symbol.weight ?? type.weight)
        case .image, .line, .chart, .button, .feature:
            .box(box)
        }
        let contentScale = CGFloat(input.style.layout.contentScale ?? 1)
        self.init(id: element.id, content: content, design: design * input.scale * contentScale, size: input.textSize(element.id),
                  priority: element.priority, minRoom: element.minRoom)
    }
}

/// The plan of a kind without a planner of its own: its elements in one column (one row in a
/// widget over two and a half times as wide as tall), the main reading larger.
nonisolated struct DefaultWidgetPlanner: WidgetPlanner {
    func plan(_ input: PlanInput) -> WidgetPlan {
        let inner = input.inner
        let axis = input.style.layout.axis ?? (inner.width >= inner.height * 2.5 ? .horizontal : .vertical)
        var hidden: [ElementID: HiddenReason] = [:]
        var demands: [ElementDemand] = []
        for element in input.spec.elements {
            guard input.shown.contains(element.id) else {
                hidden[element.id] = .switchedOff
                continue
            }
            let box: CGSize = switch element.role {
            case .button: CGSize(width: 28, height: 28)
            case .line: CGSize(width: 24, height: 4)
            default: CGSize(width: 24, height: 24)
            }
            demands.append(ElementDemand(element, input: input, design: element.role == .symbol ? 18 : element.priority >= 90 ? 20 : 13,
                                         box: CGSize(width: box.width * input.scale, height: box.height * input.scale)))
        }
        let spacing = CGFloat(input.style.layout.spacing ?? 4) * input.scale
        var plan = StackPlanner(axis: axis, room: inner, spacing: spacing, displayScale: input.displayScale).plan(demands)
        plan.hidden.merge(hidden) { $1 }
        return plan
    }
}

/// Elements in one row or column: the rules every planner shares.
///
/// - Fixed sizes are reserved first and never shrunk; one the room cannot take is drawn as large as
///   it fits and flagged `isClamped`.
/// - Auto (S/M/L) elements share what is left, each capped at its design size: S, M and L take
///   0.72, 0.86 and all of the room they fit, so the three always differ.
/// - When the room runs out, the lowest-priority element that is not fixed goes first.
/// - An element's need is the larger of its `minRoom` and what it measures.
nonisolated struct StackPlanner: Sendable {
    var axis: LayoutAxis
    var room: CGSize
    var spacing: CGFloat
    var displayScale: CGFloat

    /// The smallest auto size, and the steps S, M and L keep above it.
    static let autoFloor: CGFloat = 7

    func plan(_ demands: [ElementDemand]) -> WidgetPlan {
        var kept = demands
        var hidden: [ElementID: HiddenReason] = [:]
        while true {
            switch attempt(kept) {
            case .planned(let elements):
                return WidgetPlan(elements: elements, hidden: hidden)
            case .drop(let id):
                hidden[id] = .noRoom
                kept.removeAll { $0.id == id }
            }
        }
    }

    // MARK: - One attempt

    private enum Attempt {
        case planned([ElementID: ElementPlan])
        case drop(ElementID)
    }

    private func attempt(_ kept: [ElementDemand]) -> Attempt {
        let mainRoom = main(room) - spacing * CGFloat(max(kept.count - 1, 0))
        let crossRoom = cross(room)
        // An element the widget cannot take across, even at its smallest, never fits.
        if let blocked = kept.filter({ !fitsAcross($0, crossRoom) }).min(by: lowerPriority) { return .drop(blocked.id) }
        let droppable = kept.filter { !$0.isFixed }

        var plans: [ElementID: ElementPlan] = [:]
        var reserved: CGFloat = 0
        for demand in kept where demand.isFixed || demand.isBox {
            let points = demand.isBox ? 0 : min(fixedPoints(demand), fit(demand, main: .infinity, cross: crossRoom) ?? 0)
            let need = need(demand, points: points, main: mainRoom)
            plans[demand.id] = ElementPlan(points: points, range: 0...0, size: need, variant: 0,
                                           isClamped: demand.isFixed && points < fixedPoints(demand))
            reserved += main(need)
        }
        if reserved > mainRoom + Self.tolerance {
            if let last = droppable.min(by: lowerPriority) { return .drop(last.id) }
            // Only fixed sizes left: each takes its share of the room, as large as fits there.
            for demand in kept {
                let share = mainRoom * main(plans[demand.id]!.size) / reserved
                guard let fit = fit(demand, main: share, cross: crossRoom) else { return .drop(demand.id) }
                let points = min(fit, plans[demand.id]!.points)
                plans[demand.id] = ElementPlan(points: points, range: 0...0, size: need(demand, points: points, main: share), variant: 0,
                                               isClamped: true)
            }
        }

        let autos = kept.filter { !$0.isFixed && !$0.isBox }
        let autoRoom = mainRoom - min(reserved, mainRoom)
        guard let sized = share(autoRoom, among: autos, cross: crossRoom) else {
            return .drop(droppable.min(by: lowerPriority)!.id)
        }
        plans.merge(sized) { $1 }

        // Each sizable element's range: what the room left by the others lets it take.
        let used = kept.reduce(0) { $0 + main(plans[$1.id]!.size) }
        for demand in kept where !demand.isBox {
            let others = used - main(plans[demand.id]!.size)
            let upper = fit(demand, main: mainRoom - others, cross: crossRoom) ?? TextFit.minimumPoints
            plans[demand.id]!.range = TextFit.minimumPoints...max(upper, TextFit.minimumPoints)
            switch demand.content {
            case .text(_, let type, let lines): (plans[demand.id]!.type, plans[demand.id]!.lines) = (type, lines)
            case .symbol(let name, let weight): plans[demand.id]!.symbol = SymbolSpec(name: name, weight: weight)
            case .box: break
            }
        }
        return .planned(plans)
    }

    /// The auto elements' sizes in `room`, or nil when they do not all fit. Room one element leaves
    /// under its design size goes to the others still limited by room, a few rounds.
    private func share(_ room: CGFloat, among autos: [ElementDemand], cross crossRoom: CGFloat) -> [ElementID: ElementPlan]? {
        guard !autos.isEmpty else { return [:] }
        let wishes = Dictionary(uniqueKeysWithValues: autos.map { ($0.id, max(main(need($0, points: wish($0), main: room)), 1)) })
        var shares = wishes.mapValues { room * $0 / wishes.values.reduce(0, +) }
        var plans: [ElementID: ElementPlan] = [:]
        for _ in 0..<4 {
            plans = [:]
            var limited: [ElementID] = []
            for demand in autos {
                let fit = fit(demand, main: shares[demand.id]!, cross: crossRoom) ?? 0
                let points = sized(demand, fit: fit)
                if points < wish(demand) { limited.append(demand.id) }
                plans[demand.id] = ElementPlan(points: points, range: 0...0, size: need(demand, points: points, main: shares[demand.id]!),
                                               variant: 0, isClamped: false)
            }
            let left = room - plans.values.reduce(0) { $0 + main($1.size) }
            guard left > Self.tolerance, !limited.isEmpty, limited.count < autos.count else { break }
            let weight = limited.reduce(0) { $0 + wishes[$1]! }
            // The others keep their share: at their design size, they take no more of it.
            for id in limited {
                shares[id] = main(plans[id]!.size) + left * wishes[id]! / weight
            }
        }
        let total = plans.values.reduce(0) { $0 + main($1.size) }
        let across = plans.values.allSatisfy { cross($0.size) <= crossRoom + Self.tolerance }
        return total <= room + Self.tolerance && across ? plans : nil
    }

    // MARK: - Sizes

    /// An auto element's size where there is room: its design size times S/M/L.
    private func wish(_ demand: ElementDemand) -> CGFloat {
        guard case .auto(let size) = demand.size else { return fixedPoints(demand) }
        return quarter(demand.design * size.factor)
    }

    /// An auto element's size where `fit` is the most the room takes.
    private func sized(_ demand: ElementDemand, fit: CGFloat) -> CGFloat {
        guard case .auto(let size) = demand.size else { return fixedPoints(demand) }
        let (share, step): (CGFloat, CGFloat) = switch size {
        case .small: (0.72, 0)
        case .medium: (0.86, 0.75)
        case .large: (1, 1.5)
        }
        return max(quarter(min(demand.design * size.factor, fit * share)), Self.autoFloor + step)
    }

    private func fixedPoints(_ demand: ElementDemand) -> CGFloat {
        guard case .fixed(let points) = demand.size else { return 0 }
        return CGFloat(points)
    }

    /// The smallest size the element is drawn at.
    private func floor(_ demand: ElementDemand) -> CGFloat {
        demand.isFixed ? TextFit.minimumPoints : sized(demand, fit: 0)
    }

    private func fitsAcross(_ demand: ElementDemand, _ crossRoom: CGFloat) -> Bool {
        cross(need(demand, points: demand.isBox ? 0 : floor(demand), main: main(room))) <= crossRoom + Self.tolerance
    }

    /// The largest size at which the element fits `main` × `cross`.
    private func fit(_ demand: ElementDemand, main: CGFloat, cross: CGFloat) -> CGFloat? {
        let main = min(main, 100_000)
        let room = axis == .vertical ? CGSize(width: cross, height: main) : CGSize(width: main, height: cross)
        // The element's own minimum is room it takes whatever its size.
        if let width = demand.minRoom?.width, width > room.width + Self.tolerance { return nil }
        if let height = demand.minRoom?.height, height > room.height + Self.tolerance { return nil }
        switch demand.content {
        case .text(let samples, let type, let lines):
            return TextFit.maxPoints(samples: samples, spec: type, room: room, lines: lines, scale: displayScale)
        case .symbol(let name, let weight):
            return SymbolFit.maxPoints(name, weight: weight, room: room, scale: displayScale)
        case .box(let size):
            return size.width <= room.width && size.height <= room.height ? 0 : nil
        }
    }

    /// The room the element takes at `points` given `main` along the stack: what it measures, at
    /// least its `minRoom`. Text of several lines wraps in the width it has there (across a column,
    /// its share along a row) and takes its widest line; text that needs more lines than it may
    /// have takes its one-line width, wider than the room, so it does not fit.
    private func need(_ demand: ElementDemand, points: CGFloat, main: CGFloat) -> CGSize {
        var size: CGSize = switch demand.content {
        case .text(let samples, let type, let lines):
            CGSize(width: textWidth(samples, type.at(points), lines: lines, room: axis == .vertical ? cross(room) : main),
                   height: CGFloat(lines) * WidgetTypography.lineHeight(type.at(points)))
        case .symbol(let name, let weight):
            SymbolFit.size(name, points: points, weight: weight, scale: displayScale)
        case .box(let size):
            size
        }
        if let width = demand.minRoom?.width { size.width = max(size.width, width) }
        if let height = demand.minRoom?.height { size.height = max(size.height, height) }
        return size
    }

    private func textWidth(_ samples: [String], _ type: TypeSpec, lines: Int, room: CGFloat) -> CGFloat {
        let single = samples.map { WidgetTypography.width($0, type, scale: displayScale) }.max() ?? 0
        guard lines > 1, single > room else { return single }
        let wrapped = samples.map { WidgetTypography.wrapped($0, type, width: room - 1 / displayScale, scale: displayScale) }
        return wrapped.allSatisfy { $0.lines <= lines } ? min(wrapped.map(\.width).max() ?? 0, room) : single
    }

    private func main(_ size: CGSize) -> CGFloat { axis == .vertical ? size.height : size.width }
    private func cross(_ size: CGSize) -> CGFloat { axis == .vertical ? size.width : size.height }
    private func quarter(_ value: CGFloat) -> CGFloat { (value / TextFit.step).rounded(.down) * TextFit.step }

    private func lowerPriority(_ a: ElementDemand, _ b: ElementDemand) -> Bool { a.priority < b.priority }

    static let tolerance: CGFloat = 0.01
}
