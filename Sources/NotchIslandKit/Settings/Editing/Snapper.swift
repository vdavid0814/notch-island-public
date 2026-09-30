import CoreGraphics

// Snapping while dragging, shared by the board's editor (widgets on the panel) and the Customize
// canvas (elements inside a widget). Pure geometry, in the editor's own points.

/// A line a drag may land on.
nonisolated struct SnapLine: Hashable, Sendable {
    nonisolated enum Kind: Hashable, Sendable {
        /// The grid: it shows itself, so landing on it draws no guide.
        case grid
        /// The container's edge, its centre, its padding line.
        case edge, centre, padding
        /// Another item's edge or centre.
        case itemEdge, itemCentre
    }

    var position: CGFloat
    var kind: Kind

    /// Drawn as a guide when landed on; guides win over the grid at the same distance.
    var isGuide: Bool { kind != .grid }
}

/// The lines on each axis: `x` are vertical lines, `y` horizontal ones.
nonisolated struct SnapTargets: Sendable {
    var x: [SnapLine] = []
    var y: [SnapLine] = []
}

/// A guide to draw: the line landed on.
nonisolated struct SnapGuide: Hashable, Sendable {
    nonisolated enum Axis: Hashable, Sendable {
        /// A vertical line at `position` on x.
        case vertical
        /// A horizontal line at `position` on y.
        case horizontal
    }

    var axis: Axis
    var position: CGFloat
    var kind: SnapLine.Kind
}

nonisolated struct Snapped<Value> {
    var value: Value
    var guides: [SnapGuide]
}

/// The edges a drag moves: all four for a move, the dragged ones for a resize.
nonisolated struct SnapEdges: OptionSet, Hashable, Sendable {
    let rawValue: Int

    static let minX = SnapEdges(rawValue: 1 << 0)
    static let maxX = SnapEdges(rawValue: 1 << 1)
    static let minY = SnapEdges(rawValue: 1 << 2)
    static let maxY = SnapEdges(rawValue: 1 << 3)
    static let all: SnapEdges = [.minX, .maxX, .minY, .maxY]
}

nonisolated enum SnapMath {
    /// How far to move so the nearest of `anchors` lands on its nearest line within `threshold`; nil
    /// when none is that near. At the same distance a guide wins over the grid.
    static func offset(_ anchors: [CGFloat], _ lines: [SnapLine], _ threshold: CGFloat) -> CGFloat? {
        var best: (offset: CGFloat, distance: CGFloat, isGuide: Bool)?
        for anchor in anchors {
            for line in lines {
                let distance = abs(line.position - anchor)
                guard distance <= threshold else { continue }
                if let current = best {
                    let nearer = distance < current.distance - tieTolerance
                    let tiedGuide = abs(distance - current.distance) <= tieTolerance && line.isGuide && !current.isGuide
                    guard nearer || tiedGuide else { continue }
                }
                best = (line.position - anchor, distance, line.isGuide)
            }
        }
        return best?.offset
    }

    /// The guide lines `rect`'s moved edges (and, for a move, its centre) lie on.
    static func guides(_ rect: CGRect, _ edges: SnapEdges, _ targets: SnapTargets) -> [SnapGuide] {
        let isMove = edges == .all
        var xs: [CGFloat] = [], ys: [CGFloat] = []
        if edges.contains(.minX) { xs.append(rect.minX) }
        if edges.contains(.maxX) { xs.append(rect.maxX) }
        if edges.contains(.minY) { ys.append(rect.minY) }
        if edges.contains(.maxY) { ys.append(rect.maxY) }
        if isMove {
            xs.append(rect.midX)
            ys.append(rect.midY)
        }
        return lying(on: targets.x, xs, .vertical) + lying(on: targets.y, ys, .horizontal)
    }

    static func guides(at point: CGPoint, _ targets: SnapTargets) -> [SnapGuide] {
        lying(on: targets.x, [point.x], .vertical) + lying(on: targets.y, [point.y], .horizontal)
    }

    /// Two positions this close are the same line.
    static let tieTolerance: CGFloat = 0.001

    private static func lying(on lines: [SnapLine], _ positions: [CGFloat], _ axis: SnapGuide.Axis) -> [SnapGuide] {
        // One guide per line position, whatever else lies on it.
        var seen = Set<CGFloat>()
        return lines.filter(\.isGuide).compactMap { line in
            guard positions.contains(where: { abs($0 - line.position) <= tieTolerance }),
                  seen.insert(line.position).inserted else { return nil }
            return SnapGuide(axis: axis, position: line.position, kind: line.kind)
        }
    }
}
