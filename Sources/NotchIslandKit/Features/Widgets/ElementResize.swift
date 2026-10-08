import CoreGraphics

/// A part of a widget being resized by one of its eight handles in Customize's editor, in the
/// widget's own points.
///
/// A handle on a side moves that edge alone (its axis only); one in a corner moves the two edges
/// that meet there. The opposite edges stay put. A moved edge goes a whole point at a time and
/// sticks to the other parts' edges and the widget's centre lines like a dragged part does
/// (`ElementDrag.resolve`). With `keepsRatio` the part keeps its proportions: from a corner the
/// larger change wins, from a side the other axis follows, centred on where it was.
nonisolated struct ElementResize: Equatable, Sendable {
    let id: ElementID
    /// The vertical edge moved: -1 the leading one, 1 the trailing one, 0 neither; `vertical` the
    /// same for the horizontal edges (-1 the top).
    let horizontal: Int
    let vertical: Int
    /// Where the part was drawn when the resize began.
    let start: CGRect
    let others: [CGRect]
    let bounds: CGSize
    let release: CGFloat
    /// Never smaller than this on either axis.
    static let minimum: CGFloat = 4

    private(set) var frame: CGRect
    private(set) var stuckX: ElementDrag.Stick?
    private(set) var stuckY: ElementDrag.Stick?
    private var previous: CGSize = .zero

    init(id: ElementID, horizontal: Int, vertical: Int, start: CGRect, others: [CGRect], bounds: CGSize, release: CGFloat = 4) {
        self.id = id
        self.horizontal = horizontal
        self.vertical = vertical
        self.start = start
        self.others = others
        self.bounds = bounds
        self.release = release
        frame = start
    }

    /// The pointer `translation` (widget points) from where it was pressed.
    @discardableResult
    mutating func move(by translation: CGSize, keepsRatio: Bool = false) -> ElementDrag.Step {
        let wasStuck = (stuckX, stuckY)
        var minX = start.minX, maxX = start.maxX, minY = start.minY, maxY = start.maxY
        let edgesX = others.flatMap { [$0.minX, $0.maxX] } + [bounds.width / 2]
        let edgesY = others.flatMap { [$0.minY, $0.maxY] } + [bounds.height / 2]
        if horizontal != 0 {
            let edge = horizontal < 0 ? start.minX : start.maxX
            // The edge as a line of no width, kept inside the widget and off the opposite edge.
            let lower = horizontal < 0 ? 0 : start.minX + Self.minimum
            let upper = horizontal < 0 ? start.maxX - Self.minimum : bounds.width
            let moved = Self.edge(edge, raw: translation.width, previous: previous.width, lines: edgesX,
                                  within: lower...max(lower, upper), release: release, stuck: &stuckX)
            if horizontal < 0 { minX = moved } else { maxX = moved }
        }
        if vertical != 0 {
            let edge = vertical < 0 ? start.minY : start.maxY
            let lower = vertical < 0 ? 0 : start.minY + Self.minimum
            let upper = vertical < 0 ? start.maxY - Self.minimum : bounds.height
            let moved = Self.edge(edge, raw: translation.height, previous: previous.height, lines: edgesY,
                                  within: lower...max(lower, upper), release: release, stuck: &stuckY)
            if vertical < 0 { minY = moved } else { maxY = moved }
        }
        previous = translation
        var next = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        if keepsRatio, horizontal != 0, vertical != 0, start.width > 0, start.height > 0 {
            // The larger change wins; the other side follows, from the fixed corner.
            let ratio = max(next.width / start.width, next.height / start.height)
            let size = CGSize(width: start.width * ratio, height: start.height * ratio)
            next = CGRect(x: horizontal < 0 ? start.maxX - size.width : start.minX,
                          y: vertical < 0 ? start.maxY - size.height : start.minY, width: size.width, height: size.height)
            stuckX = nil
            stuckY = nil
        } else if keepsRatio, horizontal != 0 || vertical != 0, start.width > 0, start.height > 0 {
            // A side: the other axis grows with it, about its middle.
            let ratio = horizontal != 0 ? next.width / start.width : next.height / start.height
            if horizontal != 0 {
                let height = start.height * ratio
                next = CGRect(x: next.minX, y: start.midY - height / 2, width: next.width, height: height)
                stuckY = nil
            } else {
                let width = start.width * ratio
                next = CGRect(x: start.midX - width / 2, y: next.minY, width: width, height: next.height)
                stuckX = nil
            }
        }
        // On whole points, edges and size alike (the edges left in place too).
        let left = next.minX.rounded(), top = next.minY.rounded()
        next = CGRect(x: left, y: top, width: max(next.maxX.rounded() - left, Self.minimum),
                      height: max(next.maxY.rounded() - top, Self.minimum))
        guard next != frame else { return .none }
        frame = next
        let caught = (stuckX != nil && stuckX != wasStuck.0) || (stuckY != nil && stuckY != wasStuck.1)
        return caught ? .snapped : .moved
    }

    /// One edge at `edge`, moved by `raw`: sticky on the lines, a whole point at a time, inside
    /// `range`.
    private static func edge(_ edge: CGFloat, raw: CGFloat, previous: CGFloat, lines: [CGFloat],
                             within range: ClosedRange<CGFloat>, release: CGFloat, stuck: inout ElementDrag.Stick?) -> CGFloat {
        // An edge is a part of no width: `resolve` keeps it in 0…limit and snaps it as an edge.
        let offset = ElementDrag.resolve(raw: raw, previous: previous, baseMin: edge, length: 0, edges: lines, centres: [],
                                         limit: .greatestFiniteMagnitude, release: release, stuck: &stuck)
        let moved = edge + offset
        let clamped = min(max(moved, range.lowerBound), range.upperBound)
        if clamped != moved { stuck = nil }
        return clamped
    }

    /// The part's new scale and offset, for a part drawn at `frame` from `ink` in its layout box
    /// `box` (`ElementScale.applied`).
    static func transform(for frame: CGRect, ink: CGRect, box: CGRect) -> (scale: ElementScale, offset: ElementOffset) {
        let scale = ElementScale(x: ink.width > 0 ? frame.width / ink.width : 1, y: ink.height > 0 ? frame.height / ink.height : 1)
        let scaled = scale.applied(to: ink, in: box)
        return (scale, ElementOffset(x: frame.minX - scaled.minX, y: frame.minY - scaled.minY))
    }
}

/// What the editor's guides follow while a part is dragged or resized: where it is, the other
/// parts, the edge lines it holds to, and the centre lines its centre is on or near.
nonisolated struct EditGuide: Equatable, Sendable {
    var id: ElementID
    var frame: CGRect
    var others: [CGRect]
    var heldX: CGFloat?
    var heldY: CGFloat?
    var nearCentresX: [CGFloat]
    var nearCentresY: [CGFloat]
}
