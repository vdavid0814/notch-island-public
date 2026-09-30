import CoreGraphics

/// A custom layout drawn at a size: where each element lands, which layout a size class draws, and
/// the rectangles an element may occupy.
nonisolated enum ElementLayoutGeometry {
    /// Every placed element's frame in a widget of `size`, back to front.
    ///
    /// The layout is scaled uniformly, `u = min(S/A)` inside the padding (times the content scale),
    /// and the room that leaves on one axis goes where each element's pin says; a scaled element
    /// grows with its own axis, is drawn at the content scale and centred in what that leaves. The
    /// padding band the layout was authored with (`authoredPadding`, else `padding`) maps onto the
    /// one drawn, so what sat inside the padding line stays inside it. The leftover is never
    /// negative, so an element inside the widget stays inside it at every size: guaranteed by the
    /// maths, not by a clamp. A content scale above 1 has no room to grow into and draws at 1.
    static func reflow(_ layout: CustomLayout, to size: CGSize, padding: CGFloat = 0,
                       contentScale: CGFloat = 1) -> [(id: ElementID, frame: CGRect)] {
        let authored = layout.authoredSize
        let authoredPadding = layout.authoredPadding ?? padding
        let x = Axis(authored: authored.width, size: size.width, authoredPadding: authoredPadding, padding: padding)
        let y = Axis(authored: authored.height, size: size.height, authoredPadding: authoredPadding, padding: padding)
        let contentScale = min(max(contentScale, 0), 1)
        let u = uniformScale(layout, to: size, padding: padding, contentScale: contentScale)
        return layout.items.map { item in
            let rect = item.rect
            let (minX, maxX) = x.place(rect.x * authored.width, (rect.x + rect.width) * authored.width, pin: item.pinX, u: u,
                                       contentScale: contentScale)
            let (minY, maxY) = y.place(rect.y * authored.height, (rect.y + rect.height) * authored.height, pin: item.pinY, u: u,
                                       contentScale: contentScale)
            var frame = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            if item.keepsAspect { frame = aspectFitted(frame, aspect: rect.width * authored.width / (rect.height * authored.height), item) }
            return (item.id, frame)
        }
    }

    /// The scale the whole layout is drawn at in a widget of `size`: its authored points to these.
    /// What an element draws at a size of its own (`ElementFrame.natural`) is drawn this much larger.
    static func uniformScale(_ layout: CustomLayout, to size: CGSize, padding: CGFloat = 0, contentScale: CGFloat = 1) -> CGFloat {
        let authoredPadding = layout.authoredPadding ?? padding
        let x = Axis(authored: layout.authoredSize.width, size: size.width, authoredPadding: authoredPadding, padding: padding)
        let y = Axis(authored: layout.authoredSize.height, size: size.height, authoredPadding: authoredPadding, padding: padding)
        let u = min(x.ratio, y.ratio)
        return (u.isFinite ? u : 1) * min(max(contentScale, 0), 1)
    }

    /// The part of a widget where text, symbols and buttons stay: inside the padding.
    static func safeRect(in size: CGSize, padding: CGFloat) -> CGRect {
        let inset = min(padding, size.width / 2, size.height / 2)
        return CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
    }

    /// Where an element may be placed: images, shapes and dividers to the widget's edge, the rest
    /// inside the padding.
    static func bounds(mayBleed: Bool, in size: CGSize, padding: CGFloat) -> CGRect {
        mayBleed ? CGRect(origin: .zero, size: size) : safeRect(in: size, padding: padding)
    }

    /// One axis of the reflow: the authored length and the drawn one, each padding band mapped onto
    /// the drawn one at both ends.
    private struct Axis {
        let authoredPadding: CGFloat
        let padding: CGFloat
        /// Inside the padding: as authored, and as drawn.
        let authored: CGFloat
        let size: CGFloat

        init(authored: CGFloat, size: CGFloat, authoredPadding: CGFloat, padding: CGFloat) {
            self.authoredPadding = max(min(authoredPadding, authored / 2), 0)
            self.padding = max(min(padding, size / 2), 0)
            self.authored = authored - 2 * self.authoredPadding
            self.size = size - 2 * self.padding
        }

        var ratio: CGFloat { authored > 0 ? size / authored : .infinity }

        /// An element's edges, from authored points to drawn ones.
        func place(_ low: CGFloat, _ high: CGFloat, pin: Pin, u: CGFloat, contentScale: CGFloat) -> (CGFloat, CGFloat) {
            let leftover = max(size - authored * u, 0)
            switch pin {
            case .leading: return (edge(low, u, 0), edge(high, u, 0))
            case .trailing: return (edge(low, u, leftover), edge(high, u, leftover))
            case .center: return (edge(low, u, leftover / 2), edge(high, u, leftover / 2))
            case .stretch: return (edge(low, u, 0), edge(high, u, leftover))
            case .scale:
                let scale = authored > 0 ? ratio * contentScale : 0
                let shift = max(size - authored * scale, 0) / 2
                return (edge(low, scale, shift), edge(high, scale, shift))
            }
        }

        /// A coordinate: its part inside the padding scaled and shifted, its part in either padding
        /// band in proportion with the drawn band. Laid out without padding, all of it is inside.
        private func edge(_ value: CGFloat, _ scale: CGFloat, _ shift: CGFloat) -> CGFloat {
            let inside = min(max(value - authoredPadding, 0), authored)
            guard authoredPadding > 0 else { return padding + inside * scale + shift }
            let bands = min(value, authoredPadding) + max(value - authoredPadding - authored, 0)
            return bands * padding / authoredPadding + inside * scale + shift
        }
    }

    /// The largest rectangle of `aspect` inside `frame`, where the pins hold it.
    private static func aspectFitted(_ frame: CGRect, aspect: CGFloat, _ item: ElementFrame) -> CGRect {
        guard aspect.isFinite, aspect > 0, frame.width > 0, frame.height > 0 else { return frame }
        let size = frame.width / frame.height > aspect
            ? CGSize(width: frame.height * aspect, height: frame.height)
            : CGSize(width: frame.width, height: frame.width / aspect)
        func origin(_ low: CGFloat, _ room: CGFloat, _ pin: Pin) -> CGFloat {
            switch pin {
            case .leading: low
            case .trailing: low + room
            case .center, .stretch, .scale: low + room / 2
            }
        }
        return CGRect(x: origin(frame.minX, frame.width - size.width, item.pinX),
                      y: origin(frame.minY, frame.height - size.height, item.pinY), width: size.width, height: size.height)
    }
}

// MARK: - Size classes

nonisolated extension LayoutClass {
    /// Short below 64 reference points (one row of the standard board), tall from 116 (three);
    /// narrow below 0.75 wide per tall, wide from 1.75.
    init(size: CGSize, scale: CGFloat) {
        let height = size.height / max(scale, 0.01)
        let aspect = size.width / max(size.height, 1)
        self.init(height: height < 64 ? .short : height < 116 ? .medium : .tall,
                  aspect: aspect < 0.75 ? .narrow : aspect < 1.75 ? .balanced : .wide)
    }

    /// Steps between two classes: height and aspect bands apart.
    func distance(to other: LayoutClass) -> Int {
        abs(Height.allCases.firstIndex(of: height)! - Height.allCases.firstIndex(of: other.height)!)
            + abs(Aspect.allCases.firstIndex(of: aspect)! - Aspect.allCases.firstIndex(of: other.aspect)!)
    }
}

/// What a widget of one size class draws.
nonisolated enum LayoutResolution: Equatable, Sendable {
    case automatic
    /// `layout`, laid out for `source`: another class than the one drawn when it is reflowed from it.
    case custom(CustomLayout, source: LayoutClass)
}

nonisolated extension CustomLayouts {
    /// The class's own variant; for a class without one, the nearest class's custom layout reflowed
    /// (the one it was first laid out in on a tie, then the nearer aspect) when it is one step away;
    /// automatic when there is none that near.
    func resolve(_ target: LayoutClass) -> LayoutResolution {
        if let variant = variants[target] {
            guard case .custom(let layout) = variant else { return .automatic }
            return .custom(layout, source: target)
        }
        let custom = variants.compactMap { size, variant -> (LayoutClass, CustomLayout)? in
            guard case .custom(let layout) = variant else { return nil }
            return (size, layout)
        }
        func rank(_ size: LayoutClass) -> (Int, Int, Int, Int) {
            (size.distance(to: target), size == authored ? 0 : 1,
             abs(LayoutClass.Aspect.allCases.firstIndex(of: size.aspect)! - LayoutClass.Aspect.allCases.firstIndex(of: target.aspect)!),
             LayoutClass.Height.allCases.firstIndex(of: size.height)! * 3 + LayoutClass.Aspect.allCases.firstIndex(of: size.aspect)!)
        }
        // Only from a neighbouring shape: squeezed into a far one (three rows into one) a layout
        // reads as a jumble; the kind's own stacks are laid out for it.
        guard let nearest = custom.min(by: { rank($0.0) < rank($1.0) }), nearest.0.distance(to: target) <= 1 else { return .automatic }
        return .custom(nearest.1, source: nearest.0)
    }
}

// MARK: - Bleeding

nonisolated extension ElementRole {
    /// May reach the widget's edge (images, lines); the rest stays inside the padding.
    var mayBleed: Bool { self == .image || self == .line }
}

nonisolated extension Decoration {
    /// Dividers and shapes may reach the widget's edge; labels and symbols stay inside the padding.
    var mayBleed: Bool {
        switch self {
        case .divider, .shape: true
        case .label, .symbol: false
        }
    }
}

// MARK: - The editing grid

/// A rectangle in cells of an `InnerGrid` (fractional: frames need not sit on the grid).
nonisolated struct CellRect: Hashable, Sendable {
    var column: Double
    var row: Double
    var width: Double
    var height: Double
}

nonisolated extension InnerGrid {
    /// The editing grid a layout starts with: one cell per `pitch` points of the widget.
    init(authoredSize: CGSize, pitch: CGFloat = 8) {
        self.init(columns: Int((authoredSize.width / pitch).rounded()), rows: Int((authoredSize.height / pitch).rounded()))
    }

    func cells(_ rect: UnitRect) -> CellRect {
        CellRect(column: rect.x * Double(columns), row: rect.y * Double(rows),
                 width: rect.width * Double(columns), height: rect.height * Double(rows))
    }

    func unit(_ cells: CellRect) -> UnitRect {
        UnitRect(x: cells.column / Double(columns), y: cells.row / Double(rows),
                 width: cells.width / Double(columns), height: cells.height / Double(rows))
    }

    /// The grid's lines in fractions of the widget, edges included.
    var columnLines: [Double] { (0...columns).map { Double($0) / Double(columns) } }
    var rowLines: [Double] { (0...rows).map { Double($0) / Double(rows) } }
}

nonisolated extension UnitRect {
    init(_ rect: CGRect, in size: CGSize) {
        self.init(x: rect.minX / size.width, y: rect.minY / size.height,
                  width: rect.width / size.width, height: rect.height / size.height)
    }

    func rect(in size: CGSize) -> CGRect {
        CGRect(x: x * size.width, y: y * size.height, width: width * size.width, height: height * size.height)
    }
}
