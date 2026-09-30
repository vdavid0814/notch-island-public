import AppKit
import SwiftUI

/// One drag on a custom layout's canvas: the elements moved (or the one resized) from where they
/// were, and where they land. Its steps are the session's (`moveDrag`, `resizeDrag`): the canvas
/// calls them with the pointer's travel, the tests with any, and both lay the widget out the same.
struct LayoutDrag: Equatable {
    /// nil while moving.
    var handle: ResizeHandle?
    /// The elements moved (or the one resized) where they were drawn when the drag began.
    var starts: [ElementID: CGRect]
    /// The rectangle under the pointer (a resize's outline).
    var live: CGRect
    /// Where it lands, as drawn.
    var landed: CGRect
    /// The text among them, by its letters (`TextInkModel`) as it was when the drag began: what
    /// is stored is the rectangle the letters are drawn in.
    var texts: [ElementID: TextInkModel] = [:]

    /// The rectangle stored for an element moved `delta` from where it began: text by its
    /// rectangle, which the letters sit in.
    func moved(_ id: ElementID, by delta: CGSize) -> CGRect? {
        (texts[id]?.rect ?? starts[id])?.offsetBy(dx: delta.width, dy: delta.height)
    }
}

extension EditorSession {
    // MARK: Moving

    /// A move of `id` (with the others picked, if it is one of them) begins: a draft of the layout at
    /// this size, and where each unlocked element is drawn. Nil where nothing can move.
    func beginMoveDrag(_ id: ElementID) -> LayoutDrag? {
        if !selection.contains(id) { selection = [id] }
        guard let draft = makeDraft() else { return nil }
        layoutDraft = draft
        var starts: [ElementID: CGRect] = [:]
        for item in elementFrames where selection.contains(item.id) && draft.layout.items.first(where: { $0.id == item.id })?.locked != true {
            starts[item.id] = item.frame
        }
        guard !starts.isEmpty else {
            cancelDraft()
            return nil
        }
        let union = starts.values.reduce(CGRect.null) { $0.union($1) }
        return LayoutDrag(handle: nil, starts: starts, live: union, landed: union,
                          texts: starts.keys.reduce(into: [:]) { texts, id in texts[id] = textInk(id) })
    }

    /// The moved elements `translation` (widget points) from where they began, snapped unless
    /// `snapping` is off, kept inside where each may be; the draft follows.
    func moveDrag(_ drag: inout LayoutDrag, by translation: CGSize, zoom: CGFloat, snapping: Bool) {
        guard drag.handle == nil, let context = canvasContext, let layout = drawnLayout else { return }
        let union = drag.starts.values.reduce(CGRect.null) { $0.union($1) }
        // As far as the element nearest its own bounds may go: text inside the padding, pictures
        // and lines to the widget's edge.
        var low = CGPoint(x: -CGFloat.infinity, y: -CGFloat.infinity), high = CGPoint(x: CGFloat.infinity, y: CGFloat.infinity)
        for (id, rect) in drag.starts {
            let bounds = layoutBounds(id, in: context)
            low.x = max(low.x, min(bounds.minX - rect.minX, 0))
            low.y = max(low.y, min(bounds.minY - rect.minY, 0))
            high.x = min(high.x, max(bounds.maxX - rect.maxX, 0))
            high.y = min(high.y, max(bounds.maxY - rect.maxY, 0))
        }
        let room = CGRect(x: union.minX + low.x, y: union.minY + low.y, width: union.width + high.x - low.x, height: union.height + high.y - low.y)
        let snapper = layoutSnapper(layout, context: context, zoom: zoom)
        let moving = Set(drag.starts.keys)
        let placement = snapper.move(moving, to: union.offsetBy(dx: translation.width, dy: translation.height), bounds: room,
                                     isInteractive: false, snapping: snapping)
        let delta = CGSize(width: placement.rect.minX - union.minX, height: placement.rect.minY - union.minY)
        let refused = drag.starts.contains { id, rect in
            snapper.refuses(rect.offsetBy(dx: delta.width, dy: delta.height), excluding: moving, isInteractive: isLayoutInteractive(id))
        }
        if !placement.guides.isEmpty, placement.guides != layoutGuides { SnapTick.perform() }
        drag.live = union.offsetBy(dx: translation.width, dy: translation.height)
        drag.landed = placement.rect
        layoutGuides = placement.guides
        isLayoutRefused = refused
        let moved = drag
        updateDraft { layout in
            for id in moved.starts.keys {
                guard let rect = moved.moved(id, by: delta) else { continue }
                LayoutEdit.setRect(UnitRect(rect, in: context.size), of: id, in: &layout)
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
        return LayoutDrag(handle: handle, starts: [id: frame], live: frame, landed: frame, texts: textInk(id).map { [id: $0] } ?? [:])
    }

    /// The handle dragged `translation` (widget points) from where it began: the dragged edges
    /// move, snapped unless `snapping` is off; the draft follows. `keepsAspect` (⇧) keeps its
    /// proportions; what cannot stretch (a symbol, text) always does.
    func resizeDrag(_ drag: inout LayoutDrag, _ id: ElementID, by translation: CGSize, zoom: CGFloat, keepsAspect: Bool, snapping: Bool) {
        guard let handle = drag.handle, let original = drag.starts[id], let context = canvasContext, let layout = drawnLayout else { return }
        drag.live = handle.resized(original, by: translation, minimum: CGSize(width: 1, height: 1))
        var edges: SnapEdges = []
        if handle.horizontal < 0 { edges.insert(.minX) } else if handle.horizontal > 0 { edges.insert(.maxX) }
        if handle.vertical < 0 { edges.insert(.minY) } else if handle.vertical > 0 { edges.insert(.maxY) }
        let item = layout.items.first { $0.id == id }
        let text = drag.texts[id]
        // Never more than it is (a minimum over its size made it jump); text's least is its type's.
        let least = text != nil ? CGSize(width: 1, height: 1) : layoutMinimum(id)
        let minimum = CGSize(width: min(least.width, original.width), height: min(least.height, original.height))
        let placement = layoutSnapper(layout, context: context, zoom: zoom).resize(
            id, from: original, to: drag.live, edges: edges, minimum: minimum,
            keepsAspect: item?.keepsAspect == true || keepsAspect,
            bounds: layoutBounds(id, in: context), isInteractive: isLayoutInteractive(id), snapping: snapping)
        // A tick as it snaps to a new line (not at every point it moves).
        if !placement.guides.isEmpty, placement.guides != layoutGuides { SnapTick.perform() }
        layoutGuides = placement.guides
        isLayoutRefused = placement.isRefused
        // Dragged by one side, what cannot stretch grows as a whole: the other side follows,
        // about its middle, as far as the widget lets it.
        var proposed = placement.rect
        if let aspect = fixedAspect(id), aspect > 0 {
            let room = layoutBounds(id, in: context)
            if handle.vertical == 0 {
                let height = min(proposed.width / aspect, room.height)
                proposed = CGRect(x: proposed.minX, y: min(max(proposed.midY - height / 2, room.minY), room.maxY - height),
                                  width: proposed.width, height: height)
            } else if handle.horizontal == 0 {
                let width = min(proposed.height * aspect, room.width)
                proposed = CGRect(x: min(max(proposed.midX - width / 2, room.minX), room.maxX - width), y: proposed.minY,
                                  width: width, height: proposed.height)
            }
        }
        // What it draws there, the edge held where it is dragged from: the outline is the object.
        // Text: the rectangle whose type draws its letters nearest, and those letters.
        let stored: CGRect, landed: CGRect
        if let text {
            stored = text.resized(horizontal: handle.horizontal, vertical: handle.vertical, to: proposed)
            landed = text.ink(in: stored)
        } else {
            landed = hugged(id, proposed, anchor: (handle.horizontal, handle.vertical))
            stored = landed
        }
        // Laid out again, at once, wherever it lands on a new place.
        if landed != drag.landed {
            drag.landed = landed
            updateDraft { LayoutEdit.setRect(UnitRect(stored, in: context.size), of: id, in: &$0) }
        }
    }

    // MARK: Rules

    func layoutSnapper(_ layout: CustomLayout, context: CanvasContext, zoom: CGFloat) -> InnerSnapper {
        InnerSnapper(size: context.size, grid: layout.grid, padding: context.padding,
                     items: elementFrames.map { InnerSnapper.Item(id: $0.id, rect: $0.frame, isInteractive: isLayoutInteractive($0.id)) },
                     zoom: zoom)
    }

    func isLayoutInteractive(_ id: ElementID) -> Bool {
        guard !id.isCustom, let spec = elementSpec(id) else { return false }
        return InnerSnapper.isInteractive(spec)
    }

    /// Where the element may be: text, symbols and buttons inside the padding, pictures, lines,
    /// dividers and shapes to the widget's edge.
    func layoutBounds(_ id: ElementID, in context: CanvasContext) -> CGRect {
        let mayBleed = decoration(id)?.mayBleed ?? elementSpec(id)?.role.mayBleed ?? false
        return ElementLayoutGeometry.bounds(mayBleed: mayBleed, in: context.size, padding: context.padding)
    }

    /// The smallest it is resized to: its role's own, and for what draws at a size of its own the
    /// least it is scaled down to. (Not the kind's `minRoom`: that is room the widget needs for it,
    /// and as a least size it made the first drag of a handle jump.)
    func layoutMinimum(_ id: ElementID) -> CGSize {
        if let decoration = decoration(id) { return InnerSnapper.minimumSize(decoration) }
        guard let spec = elementSpec(id) else { return CGSize(width: 8, height: 8) }
        let role = InnerSnapper.minimumSize(spec.role)
        guard let fit = fits.fit(id) else { return role }
        return CGSize(width: max(role.width, fit.minWidth * FitToRect.scales.lowerBound),
                      height: max(role.height, fit.natural.height * FitToRect.scales.lowerBound))
    }
}
