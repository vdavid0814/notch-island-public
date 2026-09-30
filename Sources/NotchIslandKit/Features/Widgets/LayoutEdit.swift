import CoreGraphics
import Foundation

// What the grid inside a widget is edited with (Customize ▸ Custom layout): each a pure change of a
// `CustomLayout`, in fractions of the widget, so the editor's every command is one value in and one
// value out — one undo step, and tested without a view.

nonisolated enum LayoutEdit {
    /// Aligning the picked elements: one alone to the widget, several to the rectangle around them.
    nonisolated enum Alignment: String, Sendable, CaseIterable {
        case left, centerX, right, top, centerY, bottom

        var title: String {
            switch self {
            case .left: String(localized: "Align Left")
            case .centerX: String(localized: "Align Centres")
            case .right: String(localized: "Align Right")
            case .top: String(localized: "Align Top")
            case .centerY: String(localized: "Align Middles")
            case .bottom: String(localized: "Align Bottom")
            }
        }

        var systemImage: String {
            switch self {
            case .left: "align.horizontal.left"
            case .centerX: "align.horizontal.center"
            case .right: "align.horizontal.right"
            case .top: "align.vertical.top"
            case .centerY: "align.vertical.center"
            case .bottom: "align.vertical.bottom"
            }
        }
    }

    /// The same space between three or more picked elements, the outer two staying.
    nonisolated enum Distribution: String, Sendable, CaseIterable {
        case horizontal, vertical

        var title: String {
            self == .horizontal ? String(localized: "Distribute Horizontally") : String(localized: "Distribute Vertically")
        }

        var systemImage: String { self == .horizontal ? "distribute.horizontal.center" : "distribute.vertical.center" }
    }

    nonisolated enum Order: String, Sendable, CaseIterable {
        case front, forward, backward, back

        var title: String {
            switch self {
            case .front: String(localized: "Bring to Front")
            case .forward: String(localized: "Bring Forward")
            case .backward: String(localized: "Send Backward")
            case .back: String(localized: "Send to Back")
            }
        }

        var systemImage: String {
            switch self {
            case .front: "square.3.layers.3d.top.filled"
            case .forward: "square.2.layers.3d.top.filled"
            case .backward: "square.2.layers.3d.bottom.filled"
            case .back: "square.3.layers.3d.bottom.filled"
            }
        }
    }

    // MARK: Frames

    /// The element's rectangle (clamped into the widget); nothing for one not placed.
    static func setRect(_ rect: UnitRect, of id: ElementID, in layout: inout CustomLayout) {
        guard let index = layout.items.firstIndex(where: { $0.id == id }) else { return }
        let rect = rect.clamped
        // Made taller or shorter, its type follows its rectangle from now on.
        if abs(rect.height - layout.items[index].rect.height) > 0.0005 { layout.items[index].points = nil }
        layout.items[index].rect = rect
    }

    /// The picked elements moved by a fraction of the widget, together: as far as the one nearest
    /// an edge can go, so they keep their places among themselves. Locked ones stay.
    static func move(_ ids: Set<ElementID>, dx: Double, dy: Double, in layout: inout CustomLayout) {
        let moving = layout.items.filter { ids.contains($0.id) && !$0.locked }
        guard !moving.isEmpty else { return }
        let dx = min(max(dx, -(moving.map(\.rect.x).min() ?? 0)), 1 - (moving.map { $0.rect.x + $0.rect.width }.max() ?? 1))
        let dy = min(max(dy, -(moving.map(\.rect.y).min() ?? 0)), 1 - (moving.map { $0.rect.y + $0.rect.height }.max() ?? 1))
        for index in layout.items.indices where ids.contains(layout.items[index].id) && !layout.items[index].locked {
            layout.items[index].rect.x += dx
            layout.items[index].rect.y += dy
        }
    }

    static func align(_ ids: Set<ElementID>, _ alignment: Alignment, in layout: inout CustomLayout) {
        let picked = layout.items.filter { ids.contains($0.id) && !$0.locked }
        guard !picked.isEmpty else { return }
        // One alone: to the widget.
        let frame = picked.count == 1 ? UnitRect(x: 0, y: 0, width: 1, height: 1) : union(picked.map(\.rect))
        for index in layout.items.indices where ids.contains(layout.items[index].id) && !layout.items[index].locked {
            var rect = layout.items[index].rect
            switch alignment {
            case .left: rect.x = frame.x
            case .centerX: rect.x = frame.x + (frame.width - rect.width) / 2
            case .right: rect.x = frame.x + frame.width - rect.width
            case .top: rect.y = frame.y
            case .centerY: rect.y = frame.y + (frame.height - rect.height) / 2
            case .bottom: rect.y = frame.y + frame.height - rect.height
            }
            layout.items[index].rect = rect.clamped
        }
    }

    /// Needs three: the first and the last (along the axis) stay, the others get equal gaps.
    static func distribute(_ ids: Set<ElementID>, _ axis: Distribution, in layout: inout CustomLayout) {
        func low(_ rect: UnitRect) -> Double { axis == .horizontal ? rect.x : rect.y }
        func length(_ rect: UnitRect) -> Double { axis == .horizontal ? rect.width : rect.height }
        let picked = layout.items.filter { ids.contains($0.id) && !$0.locked }.sorted { low($0.rect) < low($1.rect) }
        guard picked.count >= 3, let first = picked.first, let last = picked.last else { return }
        let span = low(last.rect) + length(last.rect) - low(first.rect)
        let gap = (span - picked.map { length($0.rect) }.reduce(0, +)) / Double(picked.count - 1)
        var position = low(first.rect)
        for item in picked {
            if let index = layout.items.firstIndex(where: { $0.id == item.id }) {
                if axis == .horizontal { layout.items[index].rect.x = position } else { layout.items[index].rect.y = position }
                layout.items[index].rect = layout.items[index].rect.clamped
            }
            position += length(item.rect) + gap
        }
    }

    /// The rectangle around several.
    static func union(_ rects: [UnitRect]) -> UnitRect {
        guard let first = rects.first else { return UnitRect(x: 0, y: 0, width: 1, height: 1) }
        var minX = first.x, minY = first.y, maxX = first.x + first.width, maxY = first.y + first.height
        for rect in rects.dropFirst() {
            minX = min(minX, rect.x)
            minY = min(minY, rect.y)
            maxX = max(maxX, rect.x + rect.width)
            maxY = max(maxY, rect.y + rect.height)
        }
        return UnitRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Mirrored left to right: every element, and the side it is pinned to.
    static func flipHorizontally(_ layout: inout CustomLayout) {
        for index in layout.items.indices {
            layout.items[index].rect.x = 1 - layout.items[index].rect.x - layout.items[index].rect.width
            layout.items[index].rect = layout.items[index].rect.clamped
            switch layout.items[index].pinX {
            case .leading: layout.items[index].pinX = .trailing
            case .trailing: layout.items[index].pinX = .leading
            case .center, .stretch, .scale: break
            }
        }
    }

    // MARK: Order

    /// The picked elements nearer the front or the back (the items are drawn back to front), their
    /// order among themselves kept.
    static func reorder(_ ids: Set<ElementID>, _ order: Order, in layout: inout CustomLayout) {
        var items = layout.items
        switch order {
        case .front:
            items = items.filter { !ids.contains($0.id) } + items.filter { ids.contains($0.id) }
        case .back:
            items = items.filter { ids.contains($0.id) } + items.filter { !ids.contains($0.id) }
        case .forward:
            // From the front, so two picked neighbours do not swap with each other.
            for index in items.indices.dropLast().reversed() where ids.contains(items[index].id) && !ids.contains(items[index + 1].id) {
                items.swapAt(index, index + 1)
            }
        case .backward:
            for index in items.indices.dropFirst() where ids.contains(items[index].id) && !ids.contains(items[index - 1].id) {
                items.swapAt(index, index - 1)
            }
        }
        layout.items = items
    }

    // MARK: Flags

    static func setLocked(_ locked: Bool, _ ids: Set<ElementID>, in layout: inout CustomLayout) {
        for index in layout.items.indices where ids.contains(layout.items[index].id) { layout.items[index].locked = locked }
    }

    static func setKeepsAspect(_ keeps: Bool, _ ids: Set<ElementID>, in layout: inout CustomLayout) {
        for index in layout.items.indices where ids.contains(layout.items[index].id) { layout.items[index].keepsAspect = keeps }
    }

    static func setPins(x: Pin? = nil, y: Pin? = nil, _ ids: Set<ElementID>, in layout: inout CustomLayout) {
        for index in layout.items.indices where ids.contains(layout.items[index].id) {
            if let x { layout.items[index].pinX = x }
            if let y { layout.items[index].pinY = y }
        }
    }

    // MARK: Hiding, showing, decorations

    /// Takes the picked elements off the widget: one of the kind's goes to the tray (it can be put
    /// back), a decoration goes for good.
    static func hide(_ ids: Set<ElementID>, in layout: inout CustomLayout) {
        for id in layout.items.map(\.id) where ids.contains(id) {
            layout.items.removeAll { $0.id == id }
            if id.isCustom {
                layout.decorations[id] = nil
            } else if !layout.parked.contains(id) {
                layout.parked.append(id)
            }
        }
    }

    /// An element switched on or off by its switch (Settings' Elements, the inspector's Shown), in
    /// every size's custom layout: off, it goes to the tray, as Delete sends it; on, it comes back
    /// on the widget — one never laid out there, in the middle, `role`'s size — so a switch turned
    /// on always shows it.
    static func setShown(_ id: ElementID, _ on: Bool, role: ElementRole, in arrangement: inout ElementArrangement?) {
        guard case .custom(var layouts)? = arrangement else { return }
        for (size, variant) in layouts.variants {
            guard case .custom(var layout) = variant else { continue }
            if on {
                let width = role == .text ? 0.5 : 0.35, height = role == .text ? 0.22 : 0.35
                place(id, at: UnitRect(x: (1 - width) / 2, y: (1 - height) / 2, width: width, height: height), in: &layout)
            } else {
                hide([id], in: &layout)
            }
            layouts.variants[size] = .custom(layout)
        }
        arrangement = .custom(layouts)
    }

    /// An element made smaller or larger by its size (Settings' Elements: S, M, L), in every size's
    /// custom layout: its rectangle `factor` times as large about its middle, kept inside the
    /// widget; its type follows the rectangle. In a custom layout an element's size is its
    /// rectangle, so this is what the size does there.
    static func scale(_ id: ElementID, by factor: Double, in arrangement: inout ElementArrangement?) {
        guard factor > 0, abs(factor - 1) > 0.0001, case .custom(var layouts)? = arrangement else { return }
        for (size, variant) in layouts.variants {
            guard case .custom(var layout) = variant, let index = layout.items.firstIndex(where: { $0.id == id }) else { continue }
            let rect = layout.items[index].rect
            let width = min(rect.width * factor, 1), height = min(rect.height * factor, 1)
            layout.items[index].rect = UnitRect(x: rect.x + (rect.width - width) / 2, y: rect.y + (rect.height - height) / 2,
                                                width: width, height: height).clamped
            layout.items[index].points = nil
            layouts.variants[size] = .custom(layout)
        }
        arrangement = .custom(layouts)
    }

    /// An element of the tray placed on the widget at `rect`, in front.
    static func place(_ id: ElementID, at rect: UnitRect, in layout: inout CustomLayout) {
        guard !layout.items.contains(where: { $0.id == id }) else { return }
        layout.parked.removeAll { $0 == id }
        layout.items.append(ElementFrame(id: id, rect: rect.clamped))
    }

    /// A new decoration at `rect`, in front; its id.
    @discardableResult
    static func add(_ decoration: Decoration, at rect: UnitRect, in layout: inout CustomLayout, id: ElementID = .custom()) -> ElementID {
        layout.decorations[id] = decoration
        // A divider stretches with the widget along its line; a label keeps its place.
        var frame = ElementFrame(id: id, rect: rect.clamped)
        if case .divider(let axis) = decoration {
            if axis == .horizontal { frame.pinX = .stretch } else { frame.pinY = .stretch }
        }
        if case .shape(.circle) = decoration { frame.keepsAspect = true }
        if case .symbol = decoration { frame.keepsAspect = true }
        layout.items.append(frame)
        return id
    }

    /// Copies of the picked decorations a little down and to the right, in front; the copies' ids,
    /// each under the id it was copied from (the kind's own elements are one of a kind).
    @discardableResult
    static func duplicate(_ ids: Set<ElementID>, offset: Double = 0.04, in layout: inout CustomLayout) -> [ElementID: ElementID] {
        var copies: [ElementID: ElementID] = [:]
        for item in layout.items where ids.contains(item.id) && item.id.isCustom {
            guard let decoration = layout.decorations[item.id] else { continue }
            let copy = ElementID.custom()
            var frame = item
            frame.id = copy
            frame.locked = false
            frame.rect = UnitRect(x: item.rect.x + offset, y: item.rect.y + offset, width: item.rect.width, height: item.rect.height).clamped
            layout.decorations[copy] = decoration
            copies[item.id] = copy
            // Appended after the loop's snapshot: `layout.items` is iterated by value.
            layout.items.append(frame)
        }
        return copies
    }

    // MARK: Grid

    /// The editing grid's density: an aid only, so nothing placed moves.
    nonisolated enum Density: String, Sendable, CaseIterable {
        case coarse, normal, fine

        var title: String {
            switch self {
            case .coarse: String(localized: "Coarse")
            case .normal: String(localized: "Normal")
            case .fine: String(localized: "Fine")
            }
        }

        /// Points of the widget per cell, where the widget is small enough for that many cells.
        var pitch: CGFloat {
            switch self {
            case .coarse: 16
            case .normal: 8
            case .fine: 4
            }
        }

        /// The most cells it draws: a wide widget's grid stays three different grids.
        var limit: (columns: Int, rows: Int) {
            switch self {
            case .coarse: (8, 4)
            case .normal: (16, 8)
            case .fine: (InnerGrid.columnRange.upperBound, InnerGrid.rowRange.upperBound)
            }
        }

        func grid(for size: CGSize) -> InnerGrid {
            InnerGrid(columns: min(Int((size.width / pitch).rounded()), limit.columns), rows: min(Int((size.height / pitch).rounded()), limit.rows))
        }
    }

    static func setDensity(_ density: Density, in layout: inout CustomLayout) {
        layout.grid = density.grid(for: layout.authoredSize)
    }

    /// The density the layout's grid is nearest to (the normal one on a tie).
    static func density(of layout: CustomLayout) -> Density {
        func distance(_ density: Density) -> Int {
            let grid = density.grid(for: layout.authoredSize)
            return abs(grid.columns - layout.grid.columns) + abs(grid.rows - layout.grid.rows)
        }
        return [Density.normal, .coarse, .fine].min { distance($0) < distance($1) } ?? .normal
    }

    // MARK: Baking

    /// The layout as it is drawn in a widget of `size` (points, at the island's `scale`, with
    /// `padding`), laid out again for exactly that size: every element where it is drawn now, so
    /// what is dragged there is what is stored. Pins, locks, the tray and the decorations stay; a
    /// layout authored at this size comes back as it is.
    static func baked(_ layout: CustomLayout, size: CGSize, padding: CGFloat, scale: CGFloat, contentScale: CGFloat = 1) -> CustomLayout {
        let authored = CGSize(width: size.width / scale, height: size.height / scale)
        let isAuthoredHere = abs(layout.authoredSize.width - authored.width) < 0.01 && abs(layout.authoredSize.height - authored.height) < 0.01
            && abs((layout.authoredPadding ?? padding / scale) - padding / scale) < 0.01 && contentScale == 1
        if isAuthoredHere { return layout }
        let frames = ElementLayoutGeometry.reflow(layout, to: size, padding: padding, contentScale: contentScale)
        var baked = layout
        baked.authoredSize = authored
        baked.authoredPadding = padding / scale
        baked.grid = density(of: layout).grid(for: authored)
        baked.items = layout.items.compactMap { item in
            guard let frame = frames.first(where: { $0.id == item.id })?.frame, size.width > 0, size.height > 0 else { return nil }
            var item = item
            // What draws at a size of its own keeps its proportion to its rectangle, each way.
            let old = CGSize(width: item.rect.width * layout.authoredSize.width, height: item.rect.height * layout.authoredSize.height)
            item.rect = UnitRect(frame, in: size).clamped
            item.points = item.points.flatMap { old.height > 0 ? $0 * Double(frame.height / scale / old.height) : nil }
            item.natural = item.natural.flatMap { natural in
                old.width > 0 && old.height > 0 ? CGSize(width: natural.width * frame.width / scale / old.width,
                                                         height: natural.height * frame.height / scale / old.height) : nil
            }
            return item
        }
        return baked
    }
}
