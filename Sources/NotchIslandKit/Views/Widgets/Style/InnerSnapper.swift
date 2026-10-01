import SwiftUI

/// Snapping for the grid inside a widget (Customize ▸ Custom layout), in the widget's own points.
///
/// A drag lands on the editing grid's lines, on the widget's edges, centre and padding line, and on
/// the other elements' edges and centres, within 4 screen points (so less of the widget's own the
/// more the canvas is magnified). ⌘ turns snapping off; the bounds, minimum sizes, aspect and the
/// overlap rule still hold.
nonisolated struct InnerSnapper {
    /// An element already placed.
    nonisolated struct Item: Sendable {
        var id: ElementID
        var rect: CGRect
        /// A button or a block (the scrubber, the ruler): two of them may never overlap.
        var isInteractive: Bool
    }

    /// Where a drag lands and the guides it draws. Refused when two interactive elements would
    /// overlap: drawn red, and not kept on release.
    nonisolated struct Placement: Sendable {
        var rect: CGRect
        var guides: [SnapGuide]
        var isRefused: Bool
    }

    var size: CGSize
    var grid: InnerGrid
    var padding: CGFloat
    var items: [Item]
    /// The canvas's magnification.
    var zoom: CGFloat

    static let screenThreshold: CGFloat = 4

    /// In the widget's points.
    var threshold: CGFloat { Self.screenThreshold / max(zoom, 0.01) }

    /// Every line a drag of `ids` may land on.
    func targets(excluding ids: Set<ElementID>) -> SnapTargets {
        func lines(_ length: CGFloat, grid: [Double], _ edges: (CGRect) -> [CGFloat], _ centre: (CGRect) -> CGFloat) -> [SnapLine] {
            var lines = grid.map { SnapLine(position: CGFloat($0) * length, kind: .grid) }
            lines += [0, length].map { SnapLine(position: $0, kind: .edge) }
            lines.append(SnapLine(position: length / 2, kind: .centre))
            lines += [padding, length - padding].map { SnapLine(position: $0, kind: .padding) }
            for item in items where !ids.contains(item.id) {
                lines += edges(item.rect).map { SnapLine(position: $0, kind: .itemEdge) }
                lines.append(SnapLine(position: centre(item.rect), kind: .itemCentre))
            }
            return lines
        }
        return SnapTargets(x: lines(size.width, grid: grid.columnLines, { [$0.minX, $0.maxX] }, \.midX),
                           y: lines(size.height, grid: grid.rowLines, { [$0.minY, $0.maxY] }, \.midY))
    }

    /// `ids` (the rectangle around them) dragged to `proposed`: snapped, then kept inside `bounds`.
    func move(_ ids: Set<ElementID>, to proposed: CGRect, bounds: CGRect, isInteractive: Bool, snapping: Bool = true) -> Placement {
        let targets = targets(excluding: ids)
        var rect = snapping ? snap(proposed, moving: .all, targets: targets, threshold: threshold).value : proposed
        rect.origin.x = max(min(rect.minX, bounds.maxX - rect.width), bounds.minX)
        rect.origin.y = max(min(rect.minY, bounds.maxY - rect.height), bounds.minY)
        return Placement(rect: rect, guides: snapping ? SnapMath.guides(rect, .all, targets) : [],
                         isRefused: refuses(rect, excluding: ids, isInteractive: isInteractive))
    }

    /// `id` at `original` resized by dragging `edges` to `proposed`: the dragged edges snapped, the
    /// others held; at least `minimum`, inside `bounds`, and at the original's aspect when it keeps it
    /// (a side handle then grows the other side about its centre).
    func resize(_ id: ElementID, from original: CGRect, to proposed: CGRect, edges: SnapEdges, minimum: CGSize,
                keepsAspect: Bool, bounds: CGRect, isInteractive: Bool, snapping: Bool = true) -> Placement {
        let targets = targets(excluding: [id])
        let snapped = snapping ? snap(proposed, moving: edges, targets: targets, threshold: threshold).value : proposed
        let movesX = !edges.isDisjoint(with: [.minX, .maxX]), movesY = !edges.isDisjoint(with: [.minY, .maxY])
        let leading = edges.contains(.minX), top = edges.contains(.minY)
        let heldX = leading ? original.maxX : original.minX, heldY = top ? original.maxY : original.minY
        var width = movesX ? max(leading ? heldX - snapped.minX : snapped.maxX - heldX, 0) : original.width
        var height = movesY ? max(top ? heldY - snapped.minY : snapped.maxY - heldY, 0) : original.height
        // The most each side may take: to the bounds from the held edge, or about the centre.
        let roomX = movesX ? (leading ? heldX - bounds.minX : bounds.maxX - heldX)
            : 2 * min(original.midX - bounds.minX, bounds.maxX - original.midX)
        let roomY = movesY ? (top ? heldY - bounds.minY : bounds.maxY - heldY)
            : 2 * min(original.midY - bounds.minY, bounds.maxY - original.midY)
        if keepsAspect, original.width > 0, original.height > 0 {
            // At least the minimum first: dragged past the held edge, the aspect has nothing to scale.
            width = max(width, minimum.width)
            height = max(height, minimum.height)
            let aspect = original.width / original.height
            if movesX, !movesY || width / original.width >= height / original.height {
                height = width / aspect
            } else {
                width = height * aspect
            }
            let grow = width > 0 && height > 0 ? max(minimum.width / width, minimum.height / height, 1) : 1
            let fit = min(roomX / max(width * grow, 0.001), roomY / max(height * grow, 0.001), 1)
            width *= grow * fit
            height *= grow * fit
        } else {
            width = min(max(width, minimum.width), roomX)
            height = min(max(height, minimum.height), roomY)
        }
        let rect = CGRect(x: movesX ? (leading ? heldX - width : heldX) : original.midX - width / 2,
                          y: movesY ? (top ? heldY - height : heldY) : original.midY - height / 2,
                          width: width, height: height)
        return Placement(rect: rect, guides: snapping ? SnapMath.guides(rect, edges, targets) : [],
                         isRefused: refuses(rect, excluding: [id], isInteractive: isInteractive))
    }

    /// Two interactive elements overlapping (touching is fine).
    func refuses(_ rect: CGRect, excluding ids: Set<ElementID>, isInteractive: Bool) -> Bool {
        guard isInteractive else { return false }
        return items.contains { item in
            guard item.isInteractive, !ids.contains(item.id) else { return false }
            let overlap = item.rect.intersection(rect)
            return !overlap.isNull && overlap.width > SnapMath.tieTolerance && overlap.height > SnapMath.tieTolerance
        }
    }

    /// A button, or a piece that cannot be split: never over another.
    static func isInteractive(_ element: ElementSpec) -> Bool { element.role == .button || element.isBlock }

    /// The smallest an element of `role` is resized to: a line of the smallest type, the mini button.
    static func minimumSize(_ role: ElementRole) -> CGSize {
        switch role {
        case .text:
            CGSize(width: 12, height: TextFit.frameHeight(points: TextFit.minimumPoints, spec: TypeSpec(points: TextFit.minimumPoints)))
        // A glyph that still reads.
        case .symbol: CGSize(width: 10, height: 10)
        case .button: CGSize(width: Metrics.Control.height(.mini), height: Metrics.Control.height(.mini))
        case .image, .chart, .feature: CGSize(width: 16, height: 16)
        case .line: CGSize(width: 2, height: 2)
        }
    }

    static func minimumSize(_ decoration: Decoration) -> CGSize {
        switch decoration {
        case .label: minimumSize(.text)
        case .symbol: minimumSize(.symbol)
        case .divider: CGSize(width: 1, height: 1)
        case .shape: CGSize(width: 4, height: 4)
        }
    }
}

/// Line snapping: the nearest line within the threshold — a move by whichever of its edges or
/// centre is nearest, a resize by each dragged edge.
nonisolated extension InnerSnapper {
    func snap(_ rect: CGRect, moving edges: SnapEdges, targets: SnapTargets, threshold: CGFloat) -> Snapped<CGRect> {
        var rect = rect
        if edges == .all {
            rect.origin.x += SnapMath.offset([rect.minX, rect.midX, rect.maxX], targets.x, threshold) ?? 0
            rect.origin.y += SnapMath.offset([rect.minY, rect.midY, rect.maxY], targets.y, threshold) ?? 0
        } else {
            if edges.contains(.minX), let offset = SnapMath.offset([rect.minX], targets.x, threshold) {
                rect = CGRect(x: rect.minX + offset, y: rect.minY, width: rect.width - offset, height: rect.height)
            }
            if edges.contains(.maxX), let offset = SnapMath.offset([rect.maxX], targets.x, threshold) { rect.size.width += offset }
            if edges.contains(.minY), let offset = SnapMath.offset([rect.minY], targets.y, threshold) {
                rect = CGRect(x: rect.minX, y: rect.minY + offset, width: rect.width, height: rect.height - offset)
            }
            if edges.contains(.maxY), let offset = SnapMath.offset([rect.maxY], targets.y, threshold) { rect.size.height += offset }
        }
        return Snapped(value: rect, guides: SnapMath.guides(rect, edges, targets))
    }

    func snap(_ point: CGPoint, targets: SnapTargets, threshold: CGFloat) -> Snapped<CGPoint> {
        let snapped = CGPoint(x: point.x + (SnapMath.offset([point.x], targets.x, threshold) ?? 0),
                              y: point.y + (SnapMath.offset([point.y], targets.y, threshold) ?? 0))
        return Snapped(value: snapped, guides: SnapMath.guides(at: snapped, targets))
    }
}
