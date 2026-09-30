import CoreGraphics

/// From the kind's own stacks to a custom layout, without a jump: the first drag in automatic mode
/// unlocks the widget where its elements are drawn.
nonisolated enum LayoutConversion {
    /// A custom layout that draws what the stacks drew, and the fixed sizes that keep it so.
    nonisolated struct Unlocked: Equatable, Sendable {
        var layout: CustomLayout
        /// Text and symbols whose frame alone would give another size (several sizes share a text
        /// frame's height; a symbol's room is rounded to the pixel): their sizes as drawn, to
        /// store as the elements' fixed sizes.
        var points: [ElementID: CGFloat]
        var symbolPoints: [ElementID: CGFloat]

        /// The style laid out freely at `size`'s class with this layout, and those sizes fixed.
        func apply(to style: inout WidgetStyle, size: CGSize, scale: CGFloat) {
            let sizeClass = LayoutClass(size: size, scale: scale)
            style.layout.arrangement = .custom(CustomLayouts(authored: sizeClass, variants: [sizeClass: .custom(layout)]))
            for (id, points) in points { style.elements[id, default: ElementStyle()].text.points = Double(points) }
            for (id, points) in symbolPoints { style.elements[id, default: ElementStyle()].symbol.points = Double(points) }
        }
    }

    /// The elements where `probed` measured them on the canvas (`WidgetFrameProbe`), in a widget of
    /// `size` with `padding`, at the island's `scale`:
    ///
    /// - positions and widths are the measured ones;
    /// - text is as tall as its lines at its planned size (`TextFit.frameHeight`), a symbol at least
    ///   as large as it measures (`SymbolFit.size`), each centred where it was measured, and stores
    ///   its size where the frame would give back another;
    /// - an element planned but not drawn (no room), or not measured, goes to the tray (`parked`);
    /// - the padding it was laid out with is recorded, so a reflow keeps what sat inside it inside.
    static func unlock(plan: WidgetPlan, probed: [ElementID: CGRect], size: CGSize, padding: CGFloat,
                       scale: CGFloat = 1, displayScale: CGFloat = 2, pitch: CGFloat = 8) -> Unlocked {
        var items: [ElementFrame] = []
        var points: [ElementID: CGFloat] = [:]
        var symbolPoints: [ElementID: CGFloat] = [:]
        let placed = probed.filter { plan.elements[$0.key] != nil }
            .sorted { ($0.value.minY, $0.value.minX, $0.key.rawValue) < ($1.value.minY, $1.value.minX, $1.key.rawValue) }
        for (id, measured) in placed {
            var frame = measured
            if let element = plan.elements[id], let type = element.type {
                let height = TextFit.frameHeight(points: element.points, lines: element.lines, spec: type)
                frame.origin.y = min(max(measured.midY - height / 2, 0), max(size.height - height, 0))
                frame.size.height = height
                if CustomLayoutPlanner.textPoints(height: height, lines: element.lines, spec: type) != element.points {
                    points[id] = element.points
                }
            } else if let element = plan.elements[id], let symbol = element.symbol {
                let room = SymbolFit.size(symbol.name, points: element.points, weight: symbol.weight, scale: displayScale)
                frame = frame.insetBy(dx: min(frame.width - room.width, 0) / 2, dy: min(frame.height - room.height, 0) / 2)
                if SymbolFit.maxPoints(symbol.name, weight: symbol.weight, room: frame.size, scale: displayScale) != element.points {
                    symbolPoints[id] = element.points
                }
            }
            items.append(ElementFrame(id: id, rect: UnitRect(frame, in: size)))
        }
        let parked = plan.hidden.filter { $0.value == .noRoom }.map(\.key)
            + plan.elements.keys.filter { probed[$0] == nil }
        let authored = CGSize(width: size.width / scale, height: size.height / scale)
        let layout = CustomLayout(authoredSize: authored, grid: InnerGrid(authoredSize: authored, pitch: pitch), items: items,
                                  parked: parked.sorted { $0.rawValue < $1.rawValue }, authoredPadding: padding / scale)
        return Unlocked(layout: layout, points: points, symbolPoints: symbolPoints)
    }
}
