import AppKit
import SwiftUI

// The grid inside the widget, as the Customize editor's session edits it: which layout the size on
// the canvas draws, the draft a drag changes, and the commands — each one undo step.

/// A custom layout while a drag changes it.
struct LayoutDraft: Equatable {
    var layout: CustomLayout
    /// The size class it is the layout of.
    var sizeClass: LayoutClass
    /// The style it is written into when the drag ends: the widget's, with what an unlock fixes
    /// (the sizes its stacks drew) already in it.
    var style: WidgetStyle

    /// The style with the layout in it: what the canvas draws, and what is stored.
    var resolvedStyle: WidgetStyle {
        var style = style
        style.setLayout(layout, for: sizeClass)
        return style
    }
}

/// What the canvas draws the widget with.
struct CanvasContext {
    /// The widget's size on the canvas before magnification, in points.
    var size: CGSize
    var padding: CGFloat
    /// The island's scale factor.
    var scale: CGFloat
    var displayScale: CGFloat
    /// The widget as its stacks draw it now, as a layout (`WidgetFrameProbe`).
    var unlock: () -> LayoutConversion.Unlocked?
}

/// How the size on the canvas is laid out.
enum LayoutState: Equatable {
    /// The kind cannot be laid out freely (a round one-cell widget, a control as its lone button).
    case unsupported
    /// The kind's own stacks, at every size.
    case automatic
    /// A layout of this size's own.
    case custom
    /// Another size's layout, reflowed to this one.
    case reflowed(from: LayoutClass)
    /// The kind's own stacks at this size, by choice, while other sizes are laid out freely.
    case automaticHere

    var isCustom: Bool { self == .custom || { if case .reflowed = self { true } else { false } }() }
}

extension WidgetStyle {
    /// `layout` as the layout of `sizeClass`: the first one makes the widget a freely laid out one.
    mutating func setLayout(_ layout: CustomLayout, for sizeClass: LayoutClass) {
        if case .custom(var layouts)? = self.layout.arrangement {
            layouts.variants[sizeClass] = .custom(layout)
            self.layout.arrangement = .custom(layouts)
        } else {
            self.layout.arrangement = .custom(CustomLayouts(authored: sizeClass, variants: [sizeClass: .custom(layout)]))
        }
    }
}

extension LayoutClass {
    /// "Short and wide".
    var title: String {
        let height = switch height {
        case .short: String(localized: "short")
        case .medium: String(localized: "medium")
        case .tall: String(localized: "tall")
        }
        let aspect = switch aspect {
        case .narrow: String(localized: "narrow")
        case .balanced: String(localized: "square")
        case .wide: String(localized: "wide")
        }
        return String(localized: "\(height) and \(aspect)")
    }
}

extension EditorSession {
    // MARK: What the canvas shows

    /// The size class of the size on the canvas.
    var sizeClass: LayoutClass? { canvasContext.map { LayoutClass(size: $0.size, scale: $0.scale) } }

    var supportsCustomLayout: Bool {
        guard let widget else { return false }
        // A control drawn as its lone button keeps it (`ControlFamily.allowsCustomLayout`): Custom
        // was offered and drew nothing new.
        let loneButton = widget.kind.spec.family == .controls && widget.layout == .button
        return widget.kind.spec.supportsCustomLayout && !WidgetMetrics.isRound(widget) && !loneButton
    }

    /// How the size on the canvas is laid out now.
    var layoutState: LayoutState {
        guard supportsCustomLayout else { return .unsupported }
        if layoutDraft != nil { return .custom }
        guard case .custom(let layouts)? = style.layout.arrangement, let sizeClass else { return .automatic }
        if case .automatic? = layouts.variants[sizeClass] { return .automaticHere }
        switch layouts.resolve(sizeClass) {
        case .automatic: return .automatic
        case .custom(_, let source): return source == sizeClass ? .custom : .reflowed(from: source)
        }
    }

    /// The layout the canvas draws: the draft, else the stored one this size resolves to. Nil while
    /// the kind's own stacks are drawn.
    var drawnLayout: CustomLayout? {
        if let layoutDraft { return layoutDraft.layout }
        guard supportsCustomLayout, case .custom(let layouts)? = style.layout.arrangement, let sizeClass,
              case .custom(let layout, _) = layouts.resolve(sizeClass) else { return nil }
        return layout
    }

    /// Where each placed element's rectangle is in the widget (points), back to front. In a custom
    /// layout these are the rectangles — what the editor outlines, snaps and resizes, and what the
    /// element is drawn in (text: its lines' height, its letters centred in it); in an automatic
    /// one, the frames the canvas measured.
    var elementFrames: [(id: ElementID, frame: CGRect)] {
        if let items = arrangedItems { return items.map { ($0.id, $0.frame) } }
        // Smallest last: drawn in front of what contains it, so a click picks it.
        return frames.sorted { $0.value.width * $0.value.height > $1.value.width * $1.value.height }.map { ($0.key, $0.value) }
    }

    func elementFrame(_ id: ElementID) -> CGRect? { elementFrames.first { $0.id == id }?.frame }

    /// The layout drawn, each element on its rectangle (points, in the widget).
    private var arrangedItems: [ResolvedArrangement.Item]? {
        guard let layout = drawnLayout, let context = canvasContext else { return nil }
        let scale = layoutDraft == nil ? CGFloat(style.layout.contentScale ?? 1) : CGFloat(layoutDraft?.style.layout.contentScale ?? 1)
        return ResolvedArrangement.resolve(layout, size: context.size, padding: context.padding, contentScale: scale).items
    }

    // MARK: Text

    /// A text element's type as the canvas drew it last (its size in canvas points); nil for
    /// anything else, or before it is measured.
    func textType(_ id: ElementID) -> TypeSpec? {
        guard isText(id) else { return nil }
        if let letters = inks[id] { return letters.type }
        if case .text(let type, _, _)? = drawn[id] { return type }
        return nil
    }

    func isText(_ id: ElementID) -> Bool { elementSpec(id)?.role == .text }

    /// The most lines a text element wraps to: the layout's, else the style's, else as drawn.
    func textLines(_ id: ElementID) -> Int {
        if let lines = layoutItem(id)?.lines { return lines }
        if let lines = style.elements[id]?.text.lineLimit { return lines }
        if case .text(_, let lines, _)? = drawn[id] { return max(lines, 1) }
        return 1
    }

    /// Made taller by a handle, it takes more lines (else larger type).
    func growsLines(_ id: ElementID) -> Bool { layoutItem(id)?.growsLines ?? true }

    /// The layout's points per canvas point (the layout is stored at the island's standard scale).
    func layoutUnit(_ layout: CustomLayout, _ context: CanvasContext) -> CGFloat {
        context.size.height > 0 && layout.authoredSize.height > 0 ? layout.authoredSize.height / context.size.height : 1
    }

    /// The element of the layout drawn, if it is placed.
    func layoutItem(_ id: ElementID) -> ElementFrame? { drawnLayout?.items.first { $0.id == id } }

    /// What an element is: the kind's, or a decoration of the layout drawn.
    func elementSpec(_ id: ElementID) -> ElementSpec? {
        if let spec = widget?.kind.spec.element(id) { return spec }
        if let spec = widget?.kind.spec.elements.first(where: { $0.parts.contains(id) }) { return spec }
        guard let decoration = decoration(id) else { return nil }
        return ElementSpec(id, decoration.title, symbol: decoration.systemImage, role: decoration.role,
                           samples: [decoration.text ?? "Label"], colorSlots: decoration.colorSlots, isSizable: false,
                           acceptsLabel: decoration.text != nil)
    }

    func decoration(_ id: ElementID) -> Decoration? {
        guard id.isCustom else { return nil }
        return drawnLayout?.decorations[id] ?? style.layout.arrangement?.decoration(id)
    }

    // MARK: Drafts

    /// The layout a change starts from at the size on the canvas, as a draft: the one in progress;
    /// else this size's own layout, or the one it reflows, laid out for exactly this size; else the
    /// widget unlocked where its stacks draw it. Nil when the kind cannot be laid out freely, or
    /// nothing has been measured yet.
    func makeDraft() -> LayoutDraft? {
        if let layoutDraft { return layoutDraft }
        guard var draft = freshDraft(), let context = canvasContext else { return nil }
        snugTexts(&draft.layout, in: context)
        return draft
    }

    /// Text made exactly its lines' height in the type it is drawn in, about its middle (where its
    /// letters are), its type and lines kept as its own: a handle then never jumps on first touch.
    /// What is snug already is left as it is.
    private func snugTexts(_ layout: inout CustomLayout, in context: CanvasContext) {
        let unit = layoutUnit(layout, context)
        for item in ResolvedArrangement.resolve(layout, size: context.size, padding: context.padding).items {
            guard let type = textType(item.id), type.points > 0,
                  let index = layout.items.firstIndex(where: { $0.id == item.id }) else { continue }
            let lines = layout.items[index].lines ?? textLines(item.id)
            let height = TextFit.frameHeight(points: type.points, lines: lines, spec: type)
            guard layout.items[index].points == nil || layout.items[index].lines == nil || abs(height - item.frame.height) > 0.25 else { continue }
            let rect = CGRect(x: item.frame.minX, y: item.frame.midY - height / 2, width: item.frame.width, height: height)
            layout.items[index].rect = UnitRect(rect, in: context.size).clamped
            layout.items[index].points = Double(type.points * unit)
            layout.items[index].lines = lines
        }
    }

    private func freshDraft() -> LayoutDraft? {
        guard supportsCustomLayout, let context = canvasContext, let sizeClass, context.size.width > 0, context.size.height > 0 else { return nil }
        var style = style
        let contentScale = CGFloat(style.layout.contentScale ?? 1)
        if case .custom(let layouts)? = style.layout.arrangement, case .custom(let layout, _) = layouts.resolve(sizeClass),
           layouts.variants[sizeClass] != .automatic {
            let baked = LayoutEdit.baked(layout, size: context.size, padding: context.padding, scale: context.scale, contentScale: contentScale)
            // Laid out for this size, the scale is in the rectangles.
            if contentScale != 1 { style.normalizeContentScale(contentScale) }
            return LayoutDraft(layout: baked, sizeClass: sizeClass, style: style)
        }
        guard let unlocked = context.unlock() else { return nil }
        let variants: [LayoutClass: LayoutVariant] = {
            if case .custom(let layouts)? = style.layout.arrangement { return layouts.variants } else { return [:] }
        }()
        unlocked.apply(to: &style, size: context.size, scale: context.scale)
        // The other sizes' layouts stay (this one was automatic by choice, or the first).
        if case .custom(var layouts)? = style.layout.arrangement, !variants.isEmpty {
            layouts.variants.merge(variants.filter { $0.key != sizeClass }) { current, _ in current }
            style.layout.arrangement = .custom(layouts)
        }
        if contentScale != 1 { style.layout.contentScale = nil }
        var layout = unlocked.layout
        LayoutEdit.setDensity(.normal, in: &layout)
        return LayoutDraft(layout: layout, sizeClass: sizeClass, style: style)
    }

    /// A drag's step: the draft changed, drawn at once, stored when the drag ends (`commitDraft`).
    func updateDraft(_ edit: (inout CustomLayout) -> Void) {
        guard var draft = makeDraft() else { return }
        edit(&draft.layout)
        if draft != layoutDraft { layoutDraft = draft }
    }

    /// The drag ended: its layout stored, as one undo step. A refused one (two buttons over each
    /// other) is dropped.
    func commitDraft() {
        guard let draft = layoutDraft else { return }
        let refused = isLayoutRefused
        layoutDraft = nil
        layoutGuides = []
        isLayoutRefused = false
        guard !refused else {
            NSSound.beep()
            return
        }
        store(draft)
    }

    func cancelDraft() {
        layoutDraft = nil
        layoutGuides = []
        isLayoutRefused = false
    }

    /// A command: the layout changed and stored at once, one undo step.
    func editLayout(_ edit: (inout CustomLayout) -> Void) {
        guard var draft = makeDraft() else {
            NSSound.beep()
            return
        }
        edit(&draft.layout)
        layoutDraft = nil
        store(draft)
    }

    private func store(_ draft: LayoutDraft) {
        let style = draft.resolvedStyle
        let placed = Set(draft.layout.items.map(\.id))
        change(\IslandWidget.style.layout.arrangement) { widget in
            widget.style = style
            // An element placed on the widget is one it shows.
            for id in placed where widget.kind.options.contains(id) { widget.options.insert(id) }
        }
        // What is gone cannot stay picked.
        selection = selection.filter { id in placed.contains(id) || (!id.isCustom && widget?.kind.spec.elementIDs.contains(id) == true) }
    }

    // MARK: Commands

    /// Automatic ↔ Custom for the whole widget: Custom unlocks it where its stacks draw it, at the
    /// size on the canvas; Automatic gives every size back to the kind's own stacks.
    func setCustomLayout(_ custom: Bool) {
        if custom {
            guard !layoutState.isCustom else { return }
            editLayout { _ in }
        } else {
            cancelDraft()
            change(\IslandWidget.style.layout.arrangement) { $0.style.layout.arrangement = nil }
            selection = selection.filter { !$0.isCustom }
        }
    }

    /// The kind's own stacks at the size on the canvas; the other sizes keep their layouts.
    func useAutomaticHere() {
        guard let sizeClass, case .custom(var layouts)? = style.layout.arrangement else { return }
        cancelDraft()
        layouts.variants[sizeClass] = .automatic
        // Nothing laid out freely any more: automatic altogether.
        let anyCustom = layouts.variants.values.contains { if case .custom = $0 { true } else { false } }
        change(\IslandWidget.style.layout.arrangement) { $0.style.layout.arrangement = anyCustom ? .custom(layouts) : nil }
    }

    /// A layout of its own for the size on the canvas: what it draws now (reflowed, or its stacks),
    /// laid out for exactly this size.
    func customizeThisSize() {
        if case .custom(var layouts)? = style.layout.arrangement, let sizeClass, layouts.variants[sizeClass] == .automatic {
            // Automatic here by choice: from its stacks again.
            layouts.variants[sizeClass] = nil
            guard let context = canvasContext, let unlocked = context.unlock() else { return }
            var next = style
            let kept = layouts.variants
            unlocked.apply(to: &next, size: context.size, scale: context.scale)
            if case .custom(var made)? = next.layout.arrangement {
                made.variants.merge(kept) { current, _ in current }
                made.authored = layouts.authored
                next.layout.arrangement = .custom(made)
            }
            change(\IslandWidget.style.layout.arrangement) { $0.style = next }
        } else {
            editLayout { _ in }
        }
    }

    /// The picked elements nudged by points of the widget.
    func nudge(dx: CGFloat, dy: CGFloat) {
        guard let context = canvasContext, !selection.isEmpty else { return }
        editLayout { LayoutEdit.move(selection, dx: Double(dx / context.size.width), dy: Double(dy / context.size.height), in: &$0) }
    }

    /// Delete: the picked elements off the widget (a decoration for good, one of the kind's to the tray).
    func hideSelection() {
        guard !selection.isEmpty else { return }
        let ids = selection
        editLayout { LayoutEdit.hide(ids, in: &$0) }
        change(\IslandWidget.style.elements) { widget in
            for id in ids where id.isCustom { widget.style.elements[id] = nil }
        }
    }

    /// ⌘D: copies of the picked decorations, picked in their place.
    func duplicateSelection() {
        let ids = selection.filter(\.isCustom)
        guard !ids.isEmpty else {
            NSSound.beep()
            return
        }
        var copies: [ElementID: ElementID] = [:]
        editLayout { copies = LayoutEdit.duplicate(ids, in: &$0) }
        // Each copy looks like the one it was copied from.
        change(\IslandWidget.style.elements) { widget in
            for (source, copy) in copies { widget.style.elements[copy] = widget.style.elements[source] }
        }
        selection = Set(copies.values)
    }

    /// A new decoration in the middle of the widget, picked.
    func addDecoration(_ decoration: Decoration) {
        guard let context = canvasContext else { return }
        let size: CGSize = switch decoration {
        case .label: CGSize(width: min(64, context.size.width * 0.6),
                            height: TextFit.frameHeight(points: CGFloat(LayoutEdit.labelPoints) * context.scale, spec: DecorationView.labelType))
        case .symbol: CGSize(width: 20, height: 20)
        case .divider(let axis): axis == .horizontal ? CGSize(width: context.size.width * 0.6, height: 1)
                                                    : CGSize(width: 1, height: context.size.height * 0.6)
        case .shape: CGSize(width: min(40, context.size.width * 0.4), height: min(40, context.size.height * 0.4))
        }
        let rect = CGRect(x: (context.size.width - size.width) / 2, y: (context.size.height - size.height) / 2,
                          width: size.width, height: size.height)
        var added: ElementID?
        editLayout { added = LayoutEdit.add(decoration, at: UnitRect(rect, in: context.size), in: &$0) }
        if let added { selection = [added] }
    }

    /// An element of the tray put on the widget, in the middle of its safe area, picked.
    func placeFromTray(_ id: ElementID) {
        guard let context = canvasContext, let spec = widget?.kind.spec.element(id) else { return }
        let safe = ElementLayoutGeometry.bounds(mayBleed: spec.role.mayBleed, in: context.size, padding: context.padding)
        let minimum = InnerSnapper.minimumSize(spec.role)
        let size = CGSize(width: min(max(safe.width * 0.4, minimum.width, spec.minRoom?.width ?? 0), safe.width),
                          height: min(max(spec.role == .text ? 18 : safe.height * 0.35, minimum.height, spec.minRoom?.height ?? 0), safe.height))
        let rect = CGRect(x: safe.midX - size.width / 2, y: safe.midY - size.height / 2, width: size.width, height: size.height)
        editLayout { LayoutEdit.place(id, at: UnitRect(rect, in: context.size), in: &$0) }
        selection = [id]
    }

    /// Buttons of the kind that are switched off and can be added from the canvas's Add menu.
    var addableElements: [ElementSpec] {
        guard let widget else { return [] }
        return widget.kind.spec.elements.filter { $0.role == .button && !$0.defaultVisible && !widget.shows($0.id) }
    }

    /// One of the kind's elements switched on: on the widget (laid out freely, in a free spot), picked.
    func showElement(_ id: ElementID) {
        guard let element = widget?.kind.spec.element(id) else { return }
        change(\IslandWidget.self) { widget in
            widget.options.insert(id)
            LayoutEdit.setShown(id, true, role: element.role, parts: element.parts, in: &widget.style.layout.arrangement)
        }
        selection = [id]
    }

    /// The elements in the tray: hidden, or without room when the widget was unlocked.
    var trayElements: [ElementSpec] {
        guard let layout = drawnLayout, let widget else { return [] }
        return layout.parked.compactMap { widget.kind.spec.element($0) }
    }
}

private extension WidgetStyle {
    /// The content scale taken out, its effect on fixed type and symbol sizes kept.
    mutating func normalizeContentScale(_ scale: CGFloat) {
        layout.contentScale = nil
        for id in Array(elements.keys) {
            if let points = elements[id]?.text.points { elements[id]?.text.points = points * Double(scale) }
            if let points = elements[id]?.symbol.points { elements[id]?.symbol.points = points * Double(scale) }
        }
    }
}

extension Decoration {
    /// The colours a decoration has.
    var colorSlots: [ColorSlot] {
        switch self {
        case .label: [.primary]
        case .symbol: [.primary, .secondary, .backing]
        case .divider: [.fill]
        case .shape: [.fill, .border]
        }
    }
}
