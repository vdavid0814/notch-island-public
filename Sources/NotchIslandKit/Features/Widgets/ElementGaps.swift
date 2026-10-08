import CoreGraphics

/// The room between a part and its nearest neighbours in Customize's editor, so it can be put
/// exactly halfway between two others: on each side, the nearest part that faces it (overlaps it
/// across), in the widget's points.
nonisolated struct ElementGap: Equatable, Sendable {
    nonisolated enum Axis: Equatable, Sendable {
        /// Left or right of the part: measured along x.
        case horizontal
        /// Above or below it: measured along y.
        case vertical
    }

    var axis: Axis
    /// The two edges, along `axis`: `start < end`.
    var start: CGFloat
    var end: CGFloat
    /// Where across the axis the measure is drawn: the middle of where the two parts face.
    var across: CGFloat
    /// The gap on the part's other side (same axis) is as wide.
    var isEven = false

    var length: CGFloat { end - start }

    /// The gaps on every side that has a neighbour. Both sides of an axis equal (within a quarter
    /// point): `isEven`.
    static func around(_ frame: CGRect, among others: [CGRect]) -> [ElementGap] {
        func overlap(_ a: ClosedRange<CGFloat>, _ b: ClosedRange<CGFloat>) -> ClosedRange<CGFloat>? {
            let lower = max(a.lowerBound, b.lowerBound), upper = min(a.upperBound, b.upperBound)
            return lower < upper ? lower...upper : nil
        }
        let ys = frame.minY...frame.maxY, xs = frame.minX...frame.maxX
        var left: ElementGap?, right: ElementGap?, above: ElementGap?, below: ElementGap?
        for other in others {
            if let facing = overlap(ys, other.minY...other.maxY) {
                let middle = (facing.lowerBound + facing.upperBound) / 2
                if other.maxX <= frame.minX, frame.minX - other.maxX < left?.length ?? .infinity {
                    left = ElementGap(axis: .horizontal, start: other.maxX, end: frame.minX, across: middle)
                } else if other.minX >= frame.maxX, other.minX - frame.maxX < right?.length ?? .infinity {
                    right = ElementGap(axis: .horizontal, start: frame.maxX, end: other.minX, across: middle)
                }
            }
            if let facing = overlap(xs, other.minX...other.maxX) {
                let middle = (facing.lowerBound + facing.upperBound) / 2
                if other.maxY <= frame.minY, frame.minY - other.maxY < above?.length ?? .infinity {
                    above = ElementGap(axis: .vertical, start: other.maxY, end: frame.minY, across: middle)
                } else if other.minY >= frame.maxY, other.minY - frame.maxY < below?.length ?? .infinity {
                    below = ElementGap(axis: .vertical, start: frame.maxY, end: other.minY, across: middle)
                }
            }
        }
        for (first, second) in [(left, right), (above, below)] {
            guard let first, let second, abs(first.length - second.length) < 0.25 else { continue }
            if first.axis == .horizontal {
                left?.isEven = true
                right?.isEven = true
            } else {
                above?.isEven = true
                below?.isEven = true
            }
        }
        return [left, right, above, below].compactMap { $0 }.filter { $0.length > 0 }
    }
}
