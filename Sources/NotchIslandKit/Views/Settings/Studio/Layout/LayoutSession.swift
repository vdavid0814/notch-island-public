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
        return widget.kind.spec.supportsCustomLayout && !WidgetMetrics.isRound(widget)
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
    /// layout these are the rectangles; in an automatic one, the frames the canvas measured.
    ///
    /// An element drawn at a size of its own (a button, a line, a chart) is where it draws, not the
    /// whole rectangle it has (`ElementFit`): picked, snapped to and resized by what is seen.
    var elementFrames: [(id: ElementID, frame: CGRect)] {
        if let items = arrangedItems {
            _ = fitsVersion
            // Text by its letters (`TextInkModel`): outlined, picked and aligned by what is seen.
            return items.map { ($0.id, textInk($0.id, in: $0.frame)?.ink(in: $0.frame) ?? hugged($0.id, $0.frame)) }
        }
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

    /// A text element's letters in its rectangle, as the canvas measured them; nil for anything
    /// else, or before it is measured. `rect`: its rectangle now (by default, where it is drawn).
    func textInk(_ id: ElementID, in rect: CGRect? = nil) -> TextInkModel? {
        guard elementSpec(id)?.role == .text, let letters = inks[id],
              let rect = rect ?? arrangedItems?.first(where: { $0.id == id })?.frame else { return nil }
        // The type it is drawn in now, as its letters were measured (what the probe keeps of the
        // stacks' drawing can be older), its lines as many as its frame holds. A size set in the
        // inspector holds whatever the rectangle.
        let line = WidgetTypography.lineHeight(letters.type)
        let lines = line > 0 ? max(1, Int((letters.box.height / line).rounded())) : 1
        return TextInkModel(rect: rect, letters: letters, type: letters.type, lines: lines,
                            isFixed: style.elements[id]?.text.points != nil)
    }

    /// `rect` narrowed to what the element draws in it. `anchor` holds an edge where it is dragged
    /// from (-1: the leading or top edge moved, so the other is held; 1: the trailing or bottom; 0:
    /// the centre); by default it is centred, as it is drawn.
    func hugged(_ id: ElementID, _ rect: CGRect, anchor: (x: Int, y: Int) = (0, 0)) -> CGRect {
        let object: CGSize
        // A lone button fills its rectangle: that is the object.
        if widget?.kind.spec.filledButtons.contains(id) == true { return rect }
        if let fit = fits.fit(id) {
            object = fit.object(in: rect.size)
        } else if let symbol = symbolObject(id, in: rect.size) {
            object = symbol
        } else {
            return rect
        }
        let x = anchor.x < 0 ? rect.maxX - object.width : anchor.x > 0 ? rect.minX : rect.midX - object.width / 2
        let y = anchor.y < 0 ? rect.maxY - object.height : anchor.y > 0 ? rect.minY : rect.midY - object.height / 2
        return CGRect(x: x, y: y, width: object.width, height: object.height)
    }

    /// The proportions of what an element draws, where it cannot stretch (a symbol): a handle that
    /// drags one side of it resizes the other with it. Nil for what stretches — a button takes any
    /// proportions, and a side dragged changes that side alone.
    func fixedAspect(_ id: ElementID) -> CGFloat? {
        // Text keeps its own rule (`TextInkModel.resized`).
        if textInk(id) != nil { return nil }
        guard case .symbol(let symbol, _, _)? = drawn[id] else { return nil }
        let unit = SymbolFit.size(symbol.name, points: 100, weight: symbol.weight, scale: 2)
        return unit.height > 0 ? unit.width / unit.height : nil
    }

    /// What a symbol draws in a rectangle of `size`: as large as fits it at its own proportions, or
    /// its fixed size (never more than the rectangle).
    private func symbolObject(_ id: ElementID, in size: CGSize) -> CGSize? {
        guard case .symbol(let symbol, _, _)? = drawn[id] else { return nil }
        let unit = SymbolFit.size(symbol.name, points: 100, weight: symbol.weight, scale: 2)
        guard unit.width > 0, unit.height > 0, size.width > 0, size.height > 0 else { return nil }
        if let points = style.elements[id]?.symbol.points {
            let fixed = SymbolFit.size(symbol.name, points: CGFloat(points), weight: symbol.weight, scale: 2)
            return CGSize(width: min(fixed.width, size.width), height: min(fixed.height, size.height))
        }
        let aspect = unit.width / unit.height
        return size.width / size.height > aspect ? CGSize(width: size.height * aspect, height: size.height)
                                                 : CGSize(width: size.width, height: size.width / aspect)
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
        case .label: CGSize(width: min(64, context.size.width * 0.6), height: 18)
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

/// Where a text element's letters are in its rectangle, from what the canvas measured as the drag
/// began. The type is as large as the rectangle lets it be (`CustomLayoutPlanner.textPoints`, in
/// quarter points); its frame is its lines' height, where it sat in the rectangle, as wide as its
/// line (or the rectangle, where it fills it); its letters from the capitals' tops to the last
/// baseline in that frame (`WidgetTypography.letters`), the one rule the canvas measures by too. The
/// editor shows, snaps and drags text by its letters; what it stores is the rectangle they are
/// drawn in (`rect(for:)`), so the type never shrinks to the letters and a drag shows exactly what
/// is drawn.
nonisolated struct TextInkModel: Equatable, Sendable {
    /// Its rectangle and the text's own frame when measured, and the type drawn then.
    var rect: CGRect
    var box: CGRect
    var type: TypeSpec
    var lines: Int
    /// A size of its own (the inspector's): the letters keep it whatever the rectangle.
    var isFixed: Bool

    init?(rect: CGRect, letters: TextLetters, type: TypeSpec, lines: Int, isFixed: Bool) {
        guard rect.height > 0, letters.box.width > 0, letters.box.height > 0, type.points > 0 else { return nil }
        self.rect = rect
        box = letters.box
        self.type = type
        self.lines = max(lines, 1)
        self.isFixed = isFixed
    }

    /// How much wider a line is at `points` than as measured: in proportion but for the font's
    /// optical sizes, measured on a sample of letters and figures.
    private func widthScale(_ points: CGFloat) -> CGFloat {
        guard points != type.points else { return 1 }
        let sample = "Hamburgefonstiv 0123456789:%"
        let now = WidgetTypography.width(sample, type, scale: 2), then = WidgetTypography.width(sample, type.at(points), scale: 2)
        return now > 0 ? then / now : points / type.points
    }

    /// Its frame's height at `points`: its lines, less what SwiftUI's frame falls short of them
    /// (as measured), so it sits in its rectangle as it did.
    private func boxHeight(_ points: CGFloat) -> CGFloat {
        guard points != type.points else { return box.height }
        let short = TextFit.frameHeight(points: type.points, lines: lines, spec: type) - box.height
        return max(TextFit.frameHeight(points: points, lines: lines, spec: type) - short, 1)
    }

    /// Where across the rectangle's room the text's frame sits (0 leading, ½ centred, 1 trailing).
    private var anchorX: CGFloat {
        let room = rect.width - box.width
        return room > 0.5 ? min(max((box.minX - rect.minX) / room, 0), 1) : 0
    }

    private var anchorY: CGFloat {
        let room = rect.height - box.height
        return room > 0.5 ? min(max((box.minY - rect.minY) / room, 0), 1) : 0
    }

    /// The type drawn in a rectangle `height` tall: as measured in its own height (the size it was
    /// unlocked at holds there, `ElementFrame.points`), else the largest its lines fit.
    func points(forHeight height: CGFloat) -> CGFloat {
        if isFixed || abs(height - rect.height) < 0.01 { return type.points }
        return max(CustomLayoutPlanner.textPoints(height: height, lines: lines, spec: type), TextFit.minimumPoints)
    }

    /// The text's frame in a rectangle `rect`.
    private func box(in rect: CGRect) -> (CGRect, TypeSpec) {
        let points = points(forHeight: rect.height)
        let spec = type.at(points)
        let height = boxHeight(points)
        let width = min(box.width * widthScale(points), rect.width)
        return (CGRect(x: rect.minX + anchorX * (rect.width - width), y: rect.minY + anchorY * (rect.height - height),
                       width: width, height: height), spec)
    }

    /// Where the letters are in a rectangle `rect`.
    func ink(in rect: CGRect) -> CGRect {
        let (box, spec) = box(in: rect)
        return WidgetTypography.letters(inBox: box, spec)
    }

    /// The rectangle a handle dragged to `proposed` (the letters' outline there) asks for. Its top,
    /// bottom or a corner sets the type (in quarter points) and the rectangle's width follows the
    /// letters, its room as much larger; a side alone sets the rectangle's width — room for a longer
    /// line, never narrower than the letters. The edges not dragged hold their letters where they are.
    /// `horizontal`, `vertical`: the side dragged (-1 leading or top, 1 trailing or bottom, 0 neither).
    func resized(horizontal: Int, vertical: Int, to proposed: CGRect) -> CGRect {
        let start = ink(in: rect)
        var height = rect.height
        if vertical != 0, !isFixed, start.height > 0 {
            let asked = type.points * proposed.height / start.height
            let points = max((asked / TextFit.step).rounded() * TextFit.step, TextFit.minimumPoints)
            if points != type.points { height = TextFit.frameHeight(points: points, lines: lines, spec: type) }
        }
        let points = points(forHeight: height)
        let letters = box.width * widthScale(points)
        let room = max(rect.width - box.width, 0) * points / type.points
        var width = letters + room
        if vertical == 0 {
            // A side alone: room for a longer line.
            if horizontal < 0 { width = max(width - (proposed.minX - start.minX), letters) }
            if horizontal > 0 { width = max(width + (proposed.maxX - start.maxX), letters) }
        }
        // The side not dragged held (a corner scales it as a whole, from the corner opposite).
        let minX = horizontal < 0 ? rect.maxX - width : horizontal > 0 ? rect.minX : rect.midX - width / 2
        // Down: the letters' baseline held where the top is dragged, their top otherwise.
        let placed = ink(in: CGRect(x: minX, y: 0, width: width, height: height))
        let minY = vertical < 0 ? start.maxY - placed.maxY : start.minY - placed.minY
        return CGRect(x: minX, y: minY, width: width, height: height)
    }
}
