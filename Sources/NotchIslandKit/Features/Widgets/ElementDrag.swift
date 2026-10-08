import CoreGraphics

/// A part of a widget being dragged in Customize's editor, in the widget's own points.
///
/// It moves a whole point at a time, its leading and top edges always on whole points. Its edges
/// stick to the other parts' edges, and its centre to
/// their centres and to the widget's: a line is caught when the part reaches it (or jumps over it),
/// and let go only once the pointer is `release` points past it — so it is a little harder to drag
/// away from a line than to drag along. Pure geometry; the editor draws the lines and plays the
/// clicks.
nonisolated struct ElementDrag: Equatable, Sendable {
    /// What happened on a move: the part went a point further, or landed on a line.
    nonisolated enum Step: Equatable, Sendable {
        case none, moved, snapped
    }

    let id: ElementID
    /// Where the layout puts the part, without its offset.
    let base: CGRect
    /// The offset it had when the drag began.
    let start: ElementOffset
    /// The other parts where they are drawn.
    let others: [CGRect]
    /// The whole widget: the part stays inside it.
    let bounds: CGSize
    /// How far past a line the pointer goes before the part lets go of it.
    let release: CGFloat

    /// Where the part is drawn now.
    private(set) var offset: ElementOffset
    private(set) var stuckX: Stick?
    private(set) var stuckY: Stick?
    private var previous: CGPoint

    init(id: ElementID, base: CGRect, start: ElementOffset, others: [CGRect], bounds: CGSize, release: CGFloat = 4) {
        self.id = id
        self.base = base
        self.start = start
        self.others = others
        self.bounds = bounds
        self.release = release
        offset = start
        previous = CGPoint(x: start.x, y: start.y)
    }

    /// A line the part holds to: which of its own lines (`feature`) lies on `line`.
    nonisolated struct Stick: Equatable, Sendable {
        var line: CGFloat
        var feature: Feature
    }

    nonisolated enum Feature: Equatable, Sendable {
        case min, centre, max
    }

    /// The part where it is drawn now.
    var frame: CGRect { base.offsetBy(dx: offset.x, dy: offset.y) }

    /// To where the pointer has taken it: `translation` in the widget's points since the drag began.
    @discardableResult
    mutating func move(by translation: CGSize) -> Step {
        let raw = CGPoint(x: start.x + translation.width, y: start.y + translation.height)
        let wasStuck = (stuckX, stuckY)
        let even = evenLines(at: raw)
        let x = Self.resolve(raw: raw.x, previous: previous.x, baseMin: base.minX, length: base.width,
                             edges: others.flatMap { [$0.minX, $0.maxX] },
                             centres: others.map(\.midX) + [bounds.width / 2] + even.x,
                             limit: bounds.width, release: release, stuck: &stuckX)
        let y = Self.resolve(raw: raw.y, previous: previous.y, baseMin: base.minY, length: base.height,
                             edges: others.flatMap { [$0.minY, $0.maxY] },
                             centres: others.map(\.midY) + [bounds.height / 2] + even.y,
                             limit: bounds.height, release: release, stuck: &stuckY)
        previous = raw
        let next = ElementOffset(x: x, y: y)
        guard abs(next.x - offset.x) > 0.001 || abs(next.y - offset.y) > 0.001 else { return .none }
        offset = next
        let caught = (stuckX != nil && stuckX != wasStuck.0) || (stuckY != nil && stuckY != wasStuck.1)
        return caught ? .snapped : .moved
    }

    /// Halfway between the neighbours on both sides (`ElementGap`), where the part's centre makes
    /// the two gaps even: one on each axis that has a neighbour on both sides.
    private func evenLines(at raw: CGPoint) -> (x: [CGFloat], y: [CGFloat]) {
        let gaps = ElementGap.around(base.offsetBy(dx: raw.x, dy: raw.y), among: others)
        func line(_ axis: ElementGap.Axis) -> [CGFloat] {
            let sides = gaps.filter { $0.axis == axis }
            guard sides.count == 2 else { return [] }
            return [(sides[0].start + sides[1].end) / 2]
        }
        return (line(.horizontal), line(.vertical))
    }

    /// One axis: held on its line while the pointer stays within `release` of it; otherwise caught
    /// by the nearest line it reached or jumped over since the last move; otherwise free, on a whole
    /// point. Always inside `0…limit`.
    static func resolve(raw: CGFloat, previous: CGFloat, baseMin: CGFloat, length: CGFloat,
                                edges: [CGFloat], centres: [CGFloat], limit: CGFloat, release: CGFloat,
                                stuck: inout Stick?) -> CGFloat {
        func position(_ feature: Feature, at offset: CGFloat) -> CGFloat {
            switch feature {
            case .min: baseMin + offset
            case .centre: baseMin + length / 2 + offset
            case .max: baseMin + length + offset
            }
        }
        func offset(putting feature: Feature, on line: CGFloat) -> CGFloat { line - position(feature, at: 0) }

        // Every position on a whole point: the part's leading (top) edge where it lands.
        func whole(_ offset: CGFloat) -> CGFloat { (baseMin + offset).rounded() - baseMin }
        if let held = stuck {
            if abs(position(held.feature, at: raw) - held.line) <= release {
                return clamp(whole(offset(putting: held.feature, on: held.line)), baseMin: baseMin, length: length, limit: limit)
            }
            stuck = nil
        }
        var best: (distance: CGFloat, stick: Stick)?
        let candidates = [(Feature.min, edges), (.max, edges), (.centre, centres)]
        for (feature, lines) in candidates {
            let now = position(feature, at: raw), before = position(feature, at: previous)
            for line in lines {
                let distance = abs(now - line)
                // Reached (within half a point) or jumped over since the last move.
                let reached = distance < 0.5 || (before - line) * (now - line) <= 0
                if reached, distance < (best?.distance ?? .infinity) {
                    best = (distance, Stick(line: line, feature: feature))
                }
            }
        }
        if let best {
            let snapped = whole(offset(putting: best.stick.feature, on: best.stick.line))
            // A line the part cannot reach inside the widget is not held.
            if clamp(snapped, baseMin: baseMin, length: length, limit: limit) == snapped {
                stuck = best.stick
                return snapped
            }
        }
        return clamp(whole(raw), baseMin: baseMin, length: length, limit: limit)
    }

    /// Inside `0…limit`, on whole points.
    private static func clamp(_ offset: CGFloat, baseMin: CGFloat, length: CGFloat, limit: CGFloat) -> CGFloat {
        // The leading edge from 0 to the last whole point the part still fits by.
        let lower = -baseMin, upper = (limit - length).rounded(.down) - baseMin
        guard lower <= upper else { return offset }
        return min(max(offset, lower), upper)
    }

    /// The other parts' centre lines the dragged part's centre is on (within `near` points: on
    /// whole points, centres of sizes odd and even are half a point apart at best, and rounding may
    /// leave it under a point): vertical ones (x) and horizontal ones (y). Only when on it, so the
    /// line is never there to drag along. The widget's own centre is not among them (it is always
    /// drawn).
    func nearCentres(within near: CGFloat = 0.99) -> (x: [CGFloat], y: [CGFloat]) {
        let frame = frame
        let x = others.map(\.midX).filter { abs($0 - frame.midX) <= near }
        let y = others.map(\.midY).filter { abs($0 - frame.midY) <= near }
        return (Array(Set(x)).sorted(), Array(Set(y)).sorted())
    }
}
