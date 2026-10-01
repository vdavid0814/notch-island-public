import AppKit
import SwiftUI

/// One drag on a custom layout's canvas: the elements moved (or the one resized) from where they
/// were, and where they land. Its steps are the session's (`moveDrag`, `resizeDrag`): the canvas
/// calls them with the pointer's travel, the tests with any, and both lay the widget out the same.
///
/// What is outlined is the element's rectangle, and the element is drawn in it: a picture fills it,
/// a symbol is as large as it holds, and text is set in its own type, its lines centred in it.
struct LayoutDrag: Equatable {
    /// nil while moving.
    var handle: ResizeHandle?
    /// The elements moved (or the one resized) where they were when the drag began.
    var starts: [ElementID: CGRect]
    /// The rectangle under the pointer (a resize's outline).
    var live: CGRect
    /// Where it lands.
    var landed: CGRect
    /// Text resized: its type and lines as the drag began.
    var text: TextStart?

    /// Text as a resize begins: what its rectangle's new size is turned into.
    struct TextStart: Equatable {
        /// In canvas points.
        var type: TypeSpec
        var lines: Int
        /// Made taller, it takes more lines (else larger type).
        var growsLines: Bool
    }
}

/// A rectangle's new size, and for text what it is set in there.
struct ResizedElement: Equatable {
    var rect: CGRect
    /// Text: its type size (canvas points) and lines.
    var points: CGFloat?
    var lines: Int?
}

extension EditorSession {
    /// No bounds: an element may be made as large as wanted, and reach past the widget's edges
    /// (the widget clips it there).
    static let unbounded = CGRect(x: -100_000, y: -100_000, width: 200_000, height: 200_000)

    // MARK: Moving

    /// A move of `id` (with the others picked, if it is one of them) begins: a draft of the layout at
    /// this size, and where each element is. Nil where nothing can move.
    func beginMoveDrag(_ id: ElementID) -> LayoutDrag? {
        if !selection.contains(id) { selection = [id] }
        guard let draft = makeDraft() else { return nil }
        layoutDraft = draft
        var starts: [ElementID: CGRect] = [:]
        for item in elementFrames where selection.contains(item.id) && draft.layout.items.contains(where: { $0.id == item.id }) {
            starts[item.id] = item.frame
        }
        guard !starts.isEmpty else {
            cancelDraft()
            return nil
        }
        let union = starts.values.reduce(CGRect.null) { $0.union($1) }
        return LayoutDrag(handle: nil, starts: starts, live: union, landed: union)
    }

    /// The moved elements `translation` (widget points) from where they began, snapped unless
    /// `snapping` is off; the draft follows.
    func moveDrag(_ drag: inout LayoutDrag, by translation: CGSize, zoom: CGFloat, snapping: Bool) {
        guard drag.handle == nil, let context = canvasContext, let layout = drawnLayout else { return }
        let union = drag.starts.values.reduce(CGRect.null) { $0.union($1) }
        let moving = Set(drag.starts.keys)
        let placement = layoutSnapper(layout, context: context, zoom: zoom)
            .move(moving, to: union.offsetBy(dx: translation.width, dy: translation.height), bounds: Self.unbounded,
                  isInteractive: false, snapping: snapping)
        let delta = CGSize(width: placement.rect.minX - union.minX, height: placement.rect.minY - union.minY)
        if !placement.guides.isEmpty, placement.guides != layoutGuides { SnapTick.perform() }
        drag.live = union.offsetBy(dx: translation.width, dy: translation.height)
        drag.landed = placement.rect
        layoutGuides = placement.guides
        isLayoutRefused = false
        let starts = drag.starts
        updateDraft { layout in
            for (id, rect) in starts {
                LayoutEdit.setRect(UnitRect(rect.offsetBy(dx: delta.width, dy: delta.height), in: context.size), of: id, in: &layout)
            }
        }
    }

    // MARK: Resizing

    /// A resize of `id` by `handle` begins. Nil where it cannot be resized.
    func beginResizeDrag(_ id: ElementID, handle: ResizeHandle) -> LayoutDrag? {
        guard let draft = makeDraft() else { return nil }
        layoutDraft = draft
        guard let frame = elementFrame(id) else {
            cancelDraft()
            return nil
        }
        return LayoutDrag(handle: handle, starts: [id: frame], live: frame, landed: frame, text: textStart(id))
    }

    /// What a text resize starts from; nil for anything else.
    func textStart(_ id: ElementID) -> LayoutDrag.TextStart? {
        textType(id).map { LayoutDrag.TextStart(type: $0, lines: textLines(id), growsLines: growsLines(id)) }
    }

    /// The handle dragged `translation` (widget points) from where it began: the dragged edges
    /// move, snapped unless `snapping` is off; the draft follows. An element that keeps its shape
    /// (or ⇧, `keepsAspect`) is scaled as a whole from the corner opposite.
    func resizeDrag(_ drag: inout LayoutDrag, _ id: ElementID, by translation: CGSize, zoom: CGFloat, keepsAspect: Bool, snapping: Bool) {
        guard let handle = drag.handle, let original = drag.starts[id], let context = canvasContext, let layout = drawnLayout else { return }
        let keeps = keepsAspect || layout.items.first { $0.id == id }?.keepsAspect == true
        drag.live = handle.resized(original, by: translation, minimum: CGSize(width: 1, height: 1))
        var edges: SnapEdges = []
        if handle.horizontal < 0 { edges.insert(.minX) } else if handle.horizontal > 0 { edges.insert(.maxX) }
        if handle.vertical < 0 { edges.insert(.minY) } else if handle.vertical > 0 { edges.insert(.maxY) }
        let placement = layoutSnapper(layout, context: context, zoom: zoom).resize(
            id, from: original, to: drag.live, edges: edges, minimum: CGSize(width: 2, height: 2), keepsAspect: keeps,
            bounds: Self.unbounded, isInteractive: false, snapping: snapping)
        // A tick as it snaps to a new line (not at every point it moves).
        if !placement.guides.isEmpty, placement.guides != layoutGuides { SnapTick.perform() }
        layoutGuides = placement.guides
        isLayoutRefused = false
        let resized = Self.resized(from: original, to: placement.rect, vertical: handle.vertical, keepsShape: keeps, text: drag.text)
        // Laid out again, at once, wherever it lands on a new place.
        if resized.rect != drag.landed {
            drag.landed = resized.rect
            draft(resized, of: id, in: context)
        }
    }

    /// `original` resized to `proposed` (`vertical`: the side dragged, -1 top, 1 bottom, 0 neither).
    /// Anything but text takes the rectangle. Text keeps its rectangle its lines' height:
    /// - kept in shape, its type grows or shrinks with the rectangle;
    /// - made wider or narrower, only its width changes: a longer line fits, or what does not fit
    ///   is cut or shrunk as it is drawn (`TextStyle.truncation`), its height kept;
    /// - made taller or shorter, it takes more or fewer lines, or — not growing lines — larger or
    ///   smaller type.
    /// The side not dragged holds; a corner scales from the corner opposite.
    static func resized(from original: CGRect, to proposed: CGRect, vertical: Int, keepsShape: Bool,
                        text: LayoutDrag.TextStart?) -> ResizedElement {
        guard let text, original.height > 0 else { return ResizedElement(rect: proposed) }
        var points = text.type.points, lines = text.lines
        if keepsShape {
            points = max((text.type.points * proposed.height / original.height / TextFit.step).rounded() * TextFit.step, TextFit.minimumPoints)
        } else if vertical != 0 {
            if text.growsLines {
                let line = WidgetTypography.lineHeight(text.type)
                if line > 0 { lines = ElementFrame.lineRange.clamp(Int((proposed.height / line).rounded())) }
            } else {
                points = max(TextFit.points(forFrameHeight: proposed.height, lines: lines, spec: text.type), TextFit.minimumPoints)
            }
        }
        let height = TextFit.frameHeight(points: points, lines: lines, spec: text.type)
        var rect = proposed
        // Exactly its lines' height, held where it is dragged from.
        rect.origin.y = vertical < 0 ? proposed.maxY - height : vertical > 0 ? proposed.minY : proposed.midY - height / 2
        rect.size.height = height
        return ResizedElement(rect: rect, points: points, lines: lines)
    }

    /// The draft takes a resized element: its rectangle, and text's type and lines.
    func draft(_ resized: ResizedElement, of id: ElementID, in context: CanvasContext) {
        updateDraft { layout in
            let unit = layoutUnit(layout, context)
            LayoutEdit.setRect(UnitRect(resized.rect, in: context.size), of: id, in: &layout)
            if resized.points != nil || resized.lines != nil {
                LayoutEdit.setText(points: resized.points.map { Double($0 * unit) }, lines: resized.lines, of: id, in: &layout)
            }
        }
    }

    // MARK: Commands

    /// A frame typed in the inspector (canvas points): text goes through the same rule as a handle
    /// dragged to it — a new height is lines (or type), never letters cut in half.
    func setFrame(_ rect: CGRect, of id: ElementID) {
        guard let frame = elementFrame(id), let context = canvasContext else { return }
        let rect = CGRect(x: rect.minX, y: rect.minY, width: max(rect.width, 1), height: max(rect.height, 1))
        let keeps = layoutItem(id)?.keepsAspect == true
        var proposed = rect
        if keeps, abs(rect.height - frame.height) > 0.01 || abs(rect.width - frame.width) > 0.01 {
            // The side typed sets the scale.
            let scale = abs(rect.width - frame.width) > 0.01 ? rect.width / max(frame.width, 1) : rect.height / max(frame.height, 1)
            proposed.size = CGSize(width: frame.width * scale, height: frame.height * scale)
        }
        let vertical = abs(proposed.height - frame.height) > 0.01 ? 1 : 0
        let resized = Self.resized(from: frame, to: proposed, vertical: vertical, keepsShape: keeps, text: textStart(id))
        commit(resized, of: id, in: context)
    }

    /// A text element's type size (canvas points): its rectangle as many lines tall at it, about
    /// its middle; kept in shape, as much wider too.
    func setTextPoints(_ points: CGFloat, of id: ElementID) {
        guard let frame = elementFrame(id), let context = canvasContext, let start = textStart(id), start.type.points > 0 else { return }
        let points = max(points, TextFit.minimumPoints)
        let height = TextFit.frameHeight(points: points, lines: start.lines, spec: start.type)
        var rect = CGRect(x: frame.minX, y: frame.midY - height / 2, width: frame.width, height: height)
        if layoutItem(id)?.keepsAspect == true {
            let width = frame.width * points / start.type.points
            rect = CGRect(x: frame.midX - width / 2, y: rect.minY, width: width, height: height)
        }
        commit(ResizedElement(rect: rect, points: points, lines: start.lines), of: id, in: context)
    }

    /// The most lines a text element wraps to: its rectangle as many lines tall, about its middle.
    func setTextLines(_ lines: Int, of id: ElementID) {
        guard let frame = elementFrame(id), let context = canvasContext, let start = textStart(id) else { return }
        let lines = ElementFrame.lineRange.clamp(lines)
        let height = TextFit.frameHeight(points: start.type.points, lines: lines, spec: start.type)
        commit(ResizedElement(rect: CGRect(x: frame.minX, y: frame.midY - height / 2, width: frame.width, height: height),
                              points: start.type.points, lines: lines), of: id, in: context)
    }

    /// Text's rectangle made its lines' height again in `type` (its font changed), about its middle.
    func refitText(_ id: ElementID, type: TypeSpec) {
        guard let frame = elementFrame(id), let context = canvasContext, layoutItem(id) != nil else { return }
        let lines = textLines(id)
        let height = TextFit.frameHeight(points: type.points, lines: lines, spec: type)
        guard abs(height - frame.height) > 0.25 else { return }
        commit(ResizedElement(rect: CGRect(x: frame.minX, y: frame.midY - height / 2, width: frame.width, height: height),
                              points: type.points, lines: lines), of: id, in: context)
    }

    /// One change stored at once: one undo step.
    private func commit(_ resized: ResizedElement, of id: ElementID, in context: CanvasContext) {
        editLayout { layout in
            let unit = layoutUnit(layout, context)
            LayoutEdit.setRect(UnitRect(resized.rect, in: context.size), of: id, in: &layout)
            if resized.points != nil || resized.lines != nil {
                LayoutEdit.setText(points: resized.points.map { Double($0 * unit) }, lines: resized.lines, of: id, in: &layout)
            }
        }
    }

    // MARK: Rules

    func layoutSnapper(_ layout: CustomLayout, context: CanvasContext, zoom: CGFloat) -> InnerSnapper {
        InnerSnapper(size: context.size, grid: layout.grid, padding: context.padding,
                     items: elementFrames.map { InnerSnapper.Item(id: $0.id, rect: $0.frame, isInteractive: false) },
                     zoom: zoom)
    }
}
