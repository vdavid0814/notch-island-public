import SwiftUI

/// Customize's editor: the widget as large as the room allows, its parts picked with a click and
/// dragged a point at a time (`ElementDrag`), a click of the trackpad for each point; the picked one
/// also moves with the arrow keys, a point a press (ten with Shift). Over a part, eight handles —
/// its corners and the middle of its sides — resize it (`ElementResize`): a side's handle along its
/// axis only, a corner's the two sides that meet there (with Shift, keeping its proportions; a
/// picture set to keep its shape always keeps them, `ImageLook.keepsShape`).
///
/// A part is where it is really drawn — its letters, its symbol, its picture (`ElementInk`) — not
/// the box the layout gives it: the outline, the lines and the snapping all hug what is seen.
///
/// Its guides: the widget's centre lines always, in red at half strength. While a part is dragged,
/// every other part's edges in yellow at half strength, across the whole widget (full strength the
/// one the part holds to), and in blue the other parts' centre lines the part's centre is on or near.
struct WidgetElementEditor: View {
    let widget: IslandWidget
    /// The widget's own size; it is drawn `scale` times larger.
    let natural: CGSize
    let scale: CGFloat
    /// Settled in place: the guides and clicks only then (not while it grows in).
    let isIn: Bool
    /// The picked part and where the parts are, shared with the bar over the editor.
    let editing: ElementEditing

    @Environment(AppModel.self) private var model
    @Environment(\.controlSize) private var controlSize
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    /// Where the layout puts each part, in the widget's points.
    @State private var frames: [ElementID: CGRect] = [:]
    /// Where each part is really drawn, without its offset, in the widget's points.
    @State private var ink: [ElementID: CGRect] = [:]
    @FocusState private var isFocused: Bool
    @State private var hovered: ElementID?
    @State private var drag: ElementDrag?
    @State private var resize: ElementResize?
    /// A text part being resized: its box as drawn when the resize began, and where its layout puts it.
    @State private var textBoxStart: (box: CGRect, layout: CGPoint)?
    /// The handle under the pointer, and whose.
    @State private var hoveredHandle: HandleHit?
    /// The press began off every part: the drag moves nothing.
    @State private var pressMissed = false
    @GestureState private var isDragging = false

    /// A handle answers this far from its middle, on screen.
    private static let handleReach: CGFloat = 6

    struct HandleHit: Equatable {
        var id: ElementID
        var handle: ResizeHandle
    }

    /// Off a small part (a button), a press this near it still picks it, in the widget's points.
    private static let reach: CGFloat = 3
    /// How far past a line the pointer goes before the part lets go of it, on screen.
    /// 64 % less than the 6 points it was (60 %, then 10 % less again): lines hold a part only
    /// lightly.
    private static let release: CGFloat = 2.16
    /// The picture the ink is read from, this many times the widget's size: a quarter point.
    private static let inkScale: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            let origin = origin(in: proxy.size)
            // As sharp as it is shown, its glass buttons' glass drawn as it is (`SharpZoom`).
            SharpZoom(widget: shown) { pass in
                IslandWidgetView(widget: shown, size: natural)
                    .environment(\.widgetRenderMode, .canvas)
                    .environment(\.isElementEditing, true)
                    .environment(\.linePreview, editing.linePreview)
                    .environment(\.elementOverlaps, overlaps)
                    // Its pictures (an app's icon) made at the resolution they are shown at.
                    .environment(\.displayScale, displayScale * max(scale, 1))
                    .frame(width: natural.width, height: natural.height)
                    .coordinateSpace(.named(ElementFramesKey.space))
                    .overlay {
                        // Without a background the widget has no edge of its own: a faint line shows
                        // where it ends (one point thick however large it is drawn).
                        if widget.background == .none, pass != .underlay {
                            UnevenRoundedRectangle(cornerRadii: IslandWidgetView.outerCorners(widget, size: natural, board: nil),
                                                   style: .continuous)
                                .strokeBorder(.white.opacity(0.18), lineWidth: 1 / max(scale, 0.01))
                                .frame(width: WidgetMetrics.isRound(widget) ? min(natural.width, natural.height) : natural.width,
                                       height: WidgetMetrics.isRound(widget) ? min(natural.width, natural.height) : natural.height)
                        }
                    }
                    .scaleEffect(scale * (isIn ? 1 : 0.9))
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .allowsHitTesting(false)
            .overlay {
                ElementGuides(frames: currentFrames(of: shown), active: activeGuide, selected: editing.selected,
                              grouped: editing.group,
                              hovered: hovered, handles: handleTargets, natural: natural, scale: scale, origin: origin)
                    .opacity(isIn ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(origin: origin))
            .finishingCancelledDrag(isDragging) { finish() }
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    hoveredHandle = handle(at: location, origin: origin)
                    hovered = hoveredHandle?.id ?? part(at: location, origin: origin)
                case .ended:
                    hovered = nil
                    hoveredHandle = nil
                }
            }
            .pointerStyle(pointer)
        }
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow], phases: [.down, .repeat]) { press in
            nudge(press) ? .handled : .ignored
        }
        // ⌘C ⌘V: the picked part copied, then pasted (`IslandWidget.paste`).
        .onKeyPress(phases: .down) { press in
            guard press.modifiers == .command else { return .ignored }
            switch press.characters.lowercased() {
            case "c": return copyPicked() ? .handled : .ignored
            case "v": return pasteCopied() ? .handled : .ignored
            default: return .ignored
            }
        }
        // Delete: picked shapes go, a Clipboard symbol alone, other picked parts are switched off.
        .onKeyPress(phases: .down) { press in
            let deletes = press.key == .delete || press.key == .deleteForward || press.characters == "\u{7F}" || press.characters == "\u{8}"
            return deletes && deletePicked() ? .handled : .ignored
        }
        .onDeleteCommand { _ = deletePicked() }
        .onPreferenceChange(ElementFramesKey.self) { frames = $0 }
        .onChange(of: frames, initial: true) { _, frames in editing.boxes = frames }
        .task(id: inkKey) {
            // Once the layout has settled (a switch, a new title), not at every step of it.
            try? await Task.sleep(for: .milliseconds(30))
            guard !Task.isCancelled else { return }
            measureInk()
        }
        .onChange(of: frames) { _, frames in
            // A part switched off (or gone at this size) is no longer picked.
            if let selected = editing.selected, frames[selected] == nil { editing.selected = nil }
        }
        // As drawn, a drag or a resize included: the inspector's frame follows it live.
        .onChange(of: currentFrames(of: shown), initial: true) { _, parts in editing.parts = parts }
    }

    /// The widget as drawn: the dragged or resized part where the gesture has it.
    private var shown: IslandWidget {
        var widget = widget
        if let drag {
            widget.adoptDrawn(drag.id, from: self.widget)
            widget.offsets[drag.id] = drag.offset
        }
        if let resize { apply(resize, to: &widget) }
        return widget
    }

    /// `resize` as it stands, on `widget`: a text part gets a box of its own (its edges moved as far
    /// as its ink's), its letters as they were; any other part is stretched.
    private func apply(_ resize: ElementResize, to widget: inout IslandWidget) {
        if let start = textBoxStart {
            let from = resize.start, to = resize.frame
            let box = CGRect(x: start.box.minX + to.minX - from.minX, y: start.box.minY + to.minY - from.minY,
                             width: start.box.width + to.width - from.width, height: start.box.height + to.height - from.height)
            var style = widget.textStyle(of: resize.id)
            // The edges dragged are the background's, where it has one: the text's box is inside it.
            let insets = style.background?.insets ?? .zero
            style.box = TextStyle.BoxSize(width: max(box.width - 2 * insets.width, ElementResize.minimum),
                                          height: max(box.height - 2 * insets.height, ElementResize.minimum))
            // Auto lines stays as the user set it: resizing the box never turns it on or off.
            widget.setTextStyle(style, of: resize.id)
            // A box hanging from its trailing corner is laid out further left as it widens: its
            // layout's corner moves with its width, the move is what is left over.
            let layoutX = widget.kind.spec.trailingTexts.contains(resize.id) ? start.layout.x + start.box.width - box.width : start.layout.x
            widget.setOffset(ElementOffset(x: box.minX - layoutX, y: box.minY - start.layout.y), of: resize.id)
        } else if let ink = parts[resize.id], let box = frames[resize.id] {
            // A picture grown to the edges or over the widget is at its own size once resized.
            widget.adoptDrawn(resize.id, from: self.widget)
            let transform = ElementResize.transform(for: resize.frame, ink: ink, box: box)
            widget.scales[resize.id] = transform.scale
            widget.setOffset(transform.offset, of: resize.id)
        }
    }

    /// What the guides follow: the part dragged or resized.
    private var activeGuide: EditGuide? {
        if let drag {
            let near = drag.nearCentres()
            return EditGuide(id: drag.id, frame: drag.frame, others: drag.others,
                             heldX: drag.stuckX?.feature == .centre ? nil : drag.stuckX?.line,
                             heldY: drag.stuckY?.feature == .centre ? nil : drag.stuckY?.line,
                             nearCentresX: near.x, nearCentresY: near.y)
        }
        if let resize {
            return EditGuide(id: resize.id, frame: resize.frame, others: resize.others,
                             heldX: resize.stuckX?.line, heldY: resize.stuckY?.line, nearCentresX: [], nearCentresY: [])
        }
        return nil
    }

    /// The parts whose handles are drawn: the one being resized, or the picked one and the one under
    /// the pointer (not while one is dragged).
    private var handleTargets: [ElementID] {
        // One cell that is its one part: nothing to size.
        if widget.isOneElement { return [] }
        if let resize { return [resize.id] }
        guard drag == nil else { return [] }
        return [editing.selected, hovered].compactMap { $0 }.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
    }

    private var pointer: PointerStyle? {
        if let resize { return ResizeHandle.allCases.first { $0.horizontal == resize.horizontal && $0.vertical == resize.vertical }?.pointer }
        if drag != nil { return .grabActive }
        if let hoveredHandle { return hoveredHandle.handle.pointer }
        return hovered != nil ? .grabIdle : nil
    }

    /// The handle under `location` (in the editor), of the parts that show them: the nearest within
    /// reach, of those shown (the picked part's first).
    private func handle(at location: CGPoint, origin: CGPoint) -> HandleHit? {
        guard isIn, drag == nil, resize == nil, !widget.isOneElement else { return nil }
        let current = currentFrames(of: shown)
        for id in [editing.selected, hovered].compactMap({ $0 }) {
            guard let frame = current[id] else { continue }
            let screen = CGRect(x: origin.x + frame.minX * scale, y: origin.y + frame.minY * scale,
                                width: frame.width * scale, height: frame.height * scale)
            let nearest = ResizeHandle.shown(on: screen, size: ElementGuides.handleSize)
                .map { handle in (handle, hypot(handle.position(on: screen).x - location.x, handle.position(on: screen).y - location.y)) }
                .filter { $0.1 <= Self.handleReach }
                .min { $0.1 < $1.1 }
            if let nearest { return HandleHit(id: id, handle: nearest.0) }
        }
        return nil
    }

    /// Where the parts overlap as drawn now: the one on top lifted, what of the other is under it
    /// faded (in that part's own layout box).
    private var overlaps: ElementOverlaps {
        let shown = shown, current = currentFrames(of: shown)
        var overlaps = ElementOverlaps()
        let ids = current.keys.sorted { $0.rawValue < $1.rawValue }
        for (index, first) in ids.enumerated() {
            for second in ids[(index + 1)...] {
                guard let a = current[first], let b = current[second] else { continue }
                let shared = a.intersection(b)
                guard !shared.isNull, shared.width > 0, shared.height > 0 else { continue }
                let (upper, lower) = shown.isDrawn(first, over: second) ? (first, second) : (second, first)
                guard let box = frames[lower] else { continue }
                let offset = shown.offset(of: lower), size = shown.scale(of: lower)
                overlaps.lifted.insert(upper)
                // In the part's own box, before its size and offset.
                overlaps.covered[lower, default: []].append(CGRect(x: (shared.minX - box.minX - offset.x) / size.x,
                                                                   y: (shared.minY - box.minY - offset.y) / size.y,
                                                                   width: shared.width / size.x, height: shared.height / size.y))
            }
        }
        return overlaps
    }

    /// The widget's top-leading corner in the editor.
    private func origin(in size: CGSize) -> CGPoint {
        CGPoint(x: (size.width - natural.width * scale) / 2, y: (size.height - natural.height * scale) / 2)
    }

    /// Each part where it is drawn without its offset: its ink, or its box until the ink is read. A
    /// text part is its box (or its background) from its font, not its ink: its ink moves in whole
    /// dots as the box grows, and two texts in different sizes could never be lined up by it. Its
    /// box narrowed to its letters — from its first line's capitals to its last line's baseline —
    /// so it lines up by them.
    private var parts: [ElementID: CGRect] {
        let texts = Set(widget.kind.spec.texts)
        return frames.reduce(into: [:]) { result, entry in
            result[entry.key] = texts.contains(entry.key) ? letters(entry.key, in: entry.value) : ink[entry.key] ?? entry.value
        }
    }

    /// A text part's box from its first line's capitals to its last line's baseline (a background
    /// of its own: all of it).
    private func letters(_ id: ElementID, in box: CGRect) -> CGRect {
        let style = widget.textStyle(of: id)
        // Letters fitted to a box of its own: the box is the part (they fit it, not it them).
        guard style.background == nil, style.box == nil || style.overflow != .shrink else { return box }
        let padding = WidgetMetrics.padding(for: widget)
        let inner = CGSize(width: max(0, natural.width - 2 * padding), height: max(0, natural.height - 2 * padding))
        let size = WidgetParts.textSize(of: id, in: widget, inner: inner)
        let weight = WidgetParts.weight(of: id, in: widget)
        let text = WidgetParts.text(of: id, in: widget, model: model)
        // As the label sets it: shrunk to its box's lines where it shrinks — without a box of its
        // own, as far as its lines in its width need (the system's shrinking, worked out alike).
        var fitting = style
        if fitting.box == nil {
            fitting.box = TextStyle.BoxSize(width: Double(box.width), height: Double(box.height))
            fitting.linesFillBox = false
        }
        // Tried on more lines (the editor's preview): as it is drawn then.
        let preview = editing.linePreview == id ? LabelFit.preview(text, style: style, size: size, weight: weight) : nil
        let (font, lines) = preview.map { ($0.font, $0.lines) } ?? (style.overflow == .shrink
            ? LabelFit.fitted(text, style: fitting, size: size, weight: weight, grows: style.box != nil)
            : (style.font(size: size, weight: weight), style.lineCount(lineHeight: style.font(size: size, weight: weight).lineHeight)))
        let line = font.lineHeight
        // A line's room over the font's ascender and under its descender, shared out.
        let spare = max(line - (font.ascender - font.descender), 0) / 2
        // Its lines from its box's top (all of the box where they grow with it); shrunk lines keep
        // the room their full size took under them.
        let height = style.overflow == .addLines ? box.height : min(box.height, CGFloat(lines) * line)
        let top = spare + font.ascender - font.capHeight
        let bottom = box.height - height + spare - font.descender
        guard box.height - top - bottom >= 1 else { return box }
        return CGRect(x: box.minX, y: box.minY + top, width: box.width, height: box.height - top - bottom)
    }

    /// Each part where it is drawn (sized and moved), in the widget's points: on whole points, so
    /// its handles, the gaps between parts and the inspector's numbers are too (its ink is read to a
    /// quarter point).
    private func currentFrames(of widget: IslandWidget) -> [ElementID: CGRect] {
        parts.reduce(into: [:]) { result, entry in
            result[entry.key] = Self.whole(widget.drawn(entry.key, ink: entry.value, box: frames[entry.key] ?? entry.value))
        }
    }

    /// A part sized as `widget` has it, before its offset, on whole points.
    private func sized(_ id: ElementID, in widget: IslandWidget) -> CGRect? {
        guard let ink = parts[id] else { return nil }
        return Self.whole(widget.scale(of: id).applied(to: ink, in: frames[id] ?? ink))
    }

    /// `rect` with its corner and its size on whole points (never empty).
    static func whole(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX.rounded(), y: rect.minY.rounded(),
               width: max(rect.width.rounded(), 1), height: max(rect.height.rounded(), 1))
    }

    /// What the ink depends on: the boxes, the widget as laid out (offsets move ink, never change
    /// it), and what is shown in it.
    private var inkKey: InkKey {
        var unmoved = widget
        unmoved.offsets = [:]
        unmoved.scales = [:]
        return InkKey(frames: frames, widget: unmoved, natural: natural, isPlaying: model.media.isPlaying,
                      title: model.media.item?.title, artist: model.media.item?.artist)
    }

    private struct InkKey: Equatable {
        var frames: [ElementID: CGRect]
        var widget: IslandWidget
        var natural: CGSize
        var isPlaying: Bool
        var title: String?
        var artist: String?
    }

    /// Draws the widget once more, without its background and offsets, and reads where each part's
    /// pixels are.
    private func measureInk() {
        guard !frames.isEmpty else { return }
        var unmoved = widget
        unmoved.offsets = [:]
        unmoved.scales = [:]
        // Buttons' shapes (and larger symbols) are drawn past their room, over their neighbours'
        // boxes (`WidgetButtonLabel`): the other parts are read from a picture with plain buttons
        // (which takes the same room), the buttons from the picture as it is.
        var plain = unmoved
        plain.buttonLooks = [:]
        guard let image = picture(of: unmoved) else { return }
        let plainImage = unmoved.buttonLooks.isEmpty ? image : (picture(of: plain) ?? image)
        let buttons = Set(widget.kind.spec.buttons), texts = Set(widget.kind.spec.texts)
        var ink = ElementInk.bounds(in: plainImage, scale: Self.inkScale,
                                    boxes: frames.filter { !buttons.contains($0.key) && !texts.contains($0.key) })
        // Each text from a picture of it alone (the others unseen): a title taller than its place
        // reaches over the artist's box, and was read as the artist's ink.
        for text in texts {
            guard let box = frames[text], let alone = picture(of: plain, inkText: text) else { continue }
            ink.merge(ElementInk.bounds(in: alone, scale: Self.inkScale, boxes: [text: box])) { $1 }
        }
        // A button with a shape is where its shape is drawn; one without, its symbol's ink, read
        // from a picture of it alone (a symbol grown over its neighbour's text was read with it).
        var boxes: [ElementID: CGRect] = [:]
        let padding = WidgetMetrics.padding(for: widget)
        let inner = CGSize(width: natural.width - 2 * padding, height: natural.height - 2 * padding)
        // One with a shape is where its shape is drawn, exactly: read from the picture, glass (which
        // draws nothing there) left only its symbol and whatever of a neighbour its room reaches over.
        var shaped: [ElementID: CGRect] = [:]
        for id in buttons {
            guard let room = frames[id] else { continue }
            let look = unmoved.buttonLook(of: id)
            let points = WidgetParts.buttonPoints(of: id, in: widget, inner: inner)
            let drawn = WidgetButtonLabel.drawnFrame(of: look, points: points, room: room, widget: natural)
            if look.material.hasShape { shaped[id] = drawn } else { boxes[id] = room.union(drawn) }
        }
        for (id, box) in boxes {
            guard let alone = picture(of: unmoved, inkPart: id) else { continue }
            ink.merge(ElementInk.bounds(in: alone, scale: Self.inkScale, boxes: [id: box])) { $1 }
        }
        ink.merge(shaped) { $1 }
        // A ruler is its whole box: its ends fade out unevenly (bright ticks on one side, dim on the
        // other), so its ink's middle was not its marker's — centred, the marker was not.
        for id in widget.kind.spec.rulers {
            if let box = frames[id] { ink[id] = box }
        }
        self.ink = ink
    }

    /// `widget` drawn without its background or offsets, `inkScale` times its size (with only
    /// `inkText` of its texts seen, where given).
    private func picture(of widget: IslandWidget, inkText: ElementID? = nil, inkPart: ElementID? = nil) -> CGImage? {
        let picture = IslandWidgetView(widget: widget, size: natural)
            .environment(\.inkText, inkText)
            .environment(\.inkPart, inkPart)
            .environment(\.widgetRenderMode, .canvas)
            .environment(\.isElementEditing, true)
            .environment(\.drawsWidgetSurface, false)
            .environment(\.controlSize, controlSize)
            .environment(\.colorScheme, colorScheme)
            .frame(width: natural.width, height: natural.height)
            .environment(model)
        let renderer = ImageRenderer(content: picture)
        renderer.scale = Self.inkScale
        return renderer.cgImage
    }

    /// The picked part a point further (ten with Shift), kept inside the widget.
    private func nudge(_ press: KeyPress) -> Bool {
        guard drag == nil, resize == nil, let id = editing.selected, let part = sized(id, in: widget) else { return false }
        var offset = widget.offset(of: id)
        let (dx, dy): (CGFloat, CGFloat) = switch press.key {
        case .leftArrow: (-1, 0)
        case .rightArrow: (1, 0)
        case .upArrow: (0, -1)
        case .downArrow: (0, 1)
        default: (0, 0)
        }
        guard dx != 0 || dy != 0 else { return false }
        let frame = part.offsetBy(dx: offset.x, dy: offset.y)
        let step: CGFloat
        if press.modifiers.contains(.shift) {
            step = 10
        } else if press.modifiers.contains(.option) {
            step = 1
        } else {
            // To the next line that way (another part's edge or centre, the widget's centre), so
            // a part among close lines can be put on the one meant; a point where none is near.
            let others = currentFrames(of: widget).filter { $0.key != id }.map(\.value)
            step = dx != 0
                ? Self.nextLine(from: frame.minX, length: frame.width, direction: dx,
                                lines: others.flatMap { [$0.minX, $0.midX, $0.maxX] } + [natural.width / 2])
                : Self.nextLine(from: frame.minY, length: frame.height, direction: dy,
                                lines: others.flatMap { [$0.minY, $0.midY, $0.maxY] } + [natural.height / 2])
        }
        offset.x += dx * step
        offset.y += dy * step
        offset.x = min(max(offset.x, -part.minX), max(natural.width - part.maxX, -part.minX))
        offset.y = min(max(offset.y, -part.minY), max(natural.height - part.maxY, -part.minY))
        // Its edges on whole points.
        offset.x = (part.minX + offset.x).rounded() - part.minX
        offset.y = (part.minY + offset.y).rounded() - part.minY
        model.editedWidgets.update(widget.id) {
            $0.adoptDrawn(id, from: widget)
            $0.setOffset(offset, of: id)
        }
        return true
    }

    /// How far a part at `start`, `length` long, goes `direction` (±1) to put its leading edge, its
    /// centre or its trailing edge on the nearest of `lines` a whole point or more that way (within
    /// `ElementGuides.edgeReach`); 1 where there is none.
    static func nextLine(from start: CGFloat, length: CGFloat, direction: CGFloat, lines: [CGFloat]) -> CGFloat {
        var best: CGFloat?
        for line in lines {
            for feature: CGFloat in [start, start + length / 2, start + length] {
                // The leading edge where the feature lands on the line, on a whole point.
                let landed: CGFloat = (start + line - feature).rounded()
                let step: CGFloat = (landed - start) * direction
                if step >= 1, step <= ElementGuides.edgeReach, step < (best ?? .infinity) { best = step }
            }
        }
        return best ?? 1
    }

    /// The part under `location` (in the editor): the smallest one there.
    private func part(at location: CGPoint, origin: CGPoint) -> ElementID? {
        let point = CGPoint(x: (location.x - origin.x) / scale, y: (location.y - origin.y) / scale)
        return currentFrames(of: shown)
            .filter { $0.value.insetBy(dx: -Self.reach, dy: -Self.reach).contains(point) }
            .min { $0.value.width * $0.value.height < $1.value.width * $1.value.height }?
            .key
    }

    private func dragGesture(origin: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .tracking($isDragging)
            .onChanged { value in
                if drag == nil, resize == nil, !pressMissed,
                   let hit = handle(at: value.startLocation, origin: origin), let start = currentFrames(of: widget)[hit.id] {
                    editing.selected = hit.id
                    isFocused = true
                    let others = currentFrames(of: widget).filter { $0.key != hit.id }.map(\.value)
                    resize = ElementResize(id: hit.id, horizontal: hit.handle.horizontal, vertical: hit.handle.vertical,
                                           start: start, others: others, bounds: natural, release: max(Self.release / scale, 0.6))
                    hoveredHandle = nil
                    // A text part: its box, where it is drawn now and where its layout puts it.
                    if widget.kind.spec.texts.contains(hit.id), let box = frames[hit.id] {
                        let offset = widget.offset(of: hit.id)
                        textBoxStart = (box.offsetBy(dx: offset.x, dy: offset.y), box.origin)
                    } else {
                        textBoxStart = nil
                    }
                }
                if var sizing = resize {
                    let step = sizing.move(by: CGSize(width: value.translation.width / scale, height: value.translation.height / scale),
                                           keepsRatio: NSEvent.modifierFlags.contains(.shift)
                                               || widget.imageLook(of: sizing.id).keepsShape)
                    resize = sizing
                    play(step)
                    return
                }
                if drag == nil, !pressMissed {
                    guard isIn, let id = part(at: value.startLocation, origin: origin), let base = sized(id, in: widget) else {
                        pressMissed = true
                        editing.selected = nil
                        editing.group = []
                        return
                    }
                    // ⌘-click: into the parts picked together, or out of them; nothing moves.
                    if NSEvent.modifierFlags.contains(.command) {
                        editing.toggle(id)
                        isFocused = true
                        pressMissed = true
                        return
                    }
                    if !editing.group.contains(id) { editing.group = [] }
                    editing.selected = id
                    isFocused = true
                    // One cell that is its one part: picked to be styled, never moved out of it.
                    if widget.isOneElement {
                        pressMissed = true
                        return
                    }
                    let others = currentFrames(of: widget).filter { $0.key != id }.map(\.value)
                    drag = ElementDrag(id: id, base: base, start: widget.offset(of: id), others: others,
                                       bounds: natural, release: max(Self.release / scale, 0.6))
                }
                guard var moving = drag else { return }
                let step = moving.move(by: CGSize(width: value.translation.width / scale,
                                                  height: value.translation.height / scale))
                drag = moving
                play(step)
            }
            .onEnded { _ in finish() }
    }

    /// A click of the trackpad for each point, a firmer one landing on a line.
    private func play(_ step: ElementDrag.Step) {
        switch step {
        case .moved: model.haptics.play(.tick)
        case .snapped: model.haptics.play(.snap)
        case .none: break
        }
    }

    /// Delete on the picked parts (`IslandWidget.delete`); false where nothing is picked.
    /// The picked part copied (one: the one picked last).
    private func copyPicked() -> Bool {
        guard let id = editing.selected else { return false }
        editing.copied = (id, widget)
        return true
    }

    /// The part copied pasted here: a new one picked, or its look set on the parts picked; a beep
    /// where it goes nowhere.
    private func pasteCopied() -> Bool {
        guard let copied = editing.copied else { return false }
        var pasted = IslandWidget.Pasted.nothing
        withAnimation(.spring(duration: 0.35, bounce: 0.12)) {
            model.editedWidgets.update(widget.id) { pasted = $0.paste(copied.id, from: copied.widget, onto: editing.picked) }
        }
        switch pasted {
        case .added(let id):
            editing.group = []
            editing.selected = id
        case .styled: break
        case .nothing: NSSound.beep()
        }
        return true
    }

    private func deletePicked() -> Bool {
        let picked = editing.picked
        guard !picked.isEmpty else { return false }
        withAnimation(.spring(duration: 0.35, bounce: 0.12)) {
            model.editedWidgets.update(widget.id) { $0.delete(picked) }
        }
        editing.selected = nil
        editing.group = []
        return true
    }

    /// The drag over: the part stays where it was let go (stored with the widget).
    private func finish() {
        pressMissed = false
        if let resize {
            if resize.frame != resize.start {
                model.editedWidgets.update(widget.id) { apply(resize, to: &$0) }
            }
            self.resize = nil
            textBoxStart = nil
        }
        guard let drag else { return }
        if drag.offset != drag.start {
            model.editedWidgets.update(widget.id) {
                $0.adoptDrawn(drag.id, from: widget)
                $0.setOffset(drag.offset, of: drag.id)
            }
        }
        self.drag = nil
    }
}

/// The editor's lines (`WidgetElementEditor`), drawn on screen over the enlarged widget, one point
/// thick however large it is.
struct ElementGuides: View {
    /// Each part where it is drawn, in the widget's points.
    let frames: [ElementID: CGRect]
    /// The part dragged or resized.
    let active: EditGuide?
    let selected: ElementID?
    /// Parts picked together (⌘-click): each outlined as the picked one is.
    var grouped: Set<ElementID> = []
    let hovered: ElementID?
    /// The parts showing their eight handles.
    let handles: [ElementID]
    let natural: CGSize
    let scale: CGFloat
    /// The widget's top-leading corner on screen.
    let origin: CGPoint

    var body: some View {
        let frames = frames, drag = active, selected = selected, hovered = hovered, handles = handles, grouped = grouped
        let natural = natural, scale = scale, origin = origin
        Canvas { context, size in
            func x(_ value: CGFloat) -> CGFloat { Self.crisp(origin.x + value * scale) }
            func y(_ value: CGFloat) -> CGFloat { Self.crisp(origin.y + value * scale) }
            let widgetX = x(0)...x(natural.width), widgetY = y(0)...y(natural.height)
            func vertical(_ at: CGFloat, _ span: ClosedRange<CGFloat>, _ color: Color) {
                var path = Path()
                path.move(to: CGPoint(x: at, y: span.lowerBound))
                path.addLine(to: CGPoint(x: at, y: span.upperBound))
                context.stroke(path, with: .color(color), lineWidth: 1)
            }
            func horizontal(_ at: CGFloat, _ span: ClosedRange<CGFloat>, _ color: Color) {
                var path = Path()
                path.move(to: CGPoint(x: span.lowerBound, y: at))
                path.addLine(to: CGPoint(x: span.upperBound, y: at))
                context.stroke(path, with: .color(color), lineWidth: 1)
            }

            if let drag {
                // The other parts' edges near the dragged part's edges or centre (the ones it can
                // land on now), across the widget: each line once — edges that meet on screen (two
                // buttons' tops) as one. Every other part's edges at once were a thicket of lines.
                let frame = drag.frame
                func near(_ edge: CGFloat, _ own: [CGFloat], held: CGFloat?) -> Bool {
                    edge == held || own.contains { abs($0 - edge) <= Self.edgeReach }
                }
                let columns = Self.merged(drag.others.flatMap { [$0.minX, $0.maxX] }
                    .filter { near($0, [frame.minX, frame.midX, frame.maxX], held: drag.heldX) }
                    .map { edge in (x(edge), drag.heldX == edge) })
                let rows = Self.merged(drag.others.flatMap { [$0.minY, $0.maxY] }
                    .filter { near($0, [frame.minY, frame.midY, frame.maxY], held: drag.heldY) }
                    .map { edge in (y(edge), drag.heldY == edge) })
                for (at, held) in columns { vertical(at, widgetY, .yellow.opacity(held ? 0.9 : 0.3)) }
                for (at, held) in rows { horizontal(at, widgetX, .yellow.opacity(held ? 0.9 : 0.3)) }
                // The centre lines its centre is on or near.
                for centre in drag.nearCentresX { vertical(x(centre), widgetY, .blue) }
                for centre in drag.nearCentresY { horizontal(y(centre), widgetX, .blue) }
            }

            // The widget's centre lines, across the editor; full strength while the dragged part's
            // centre is on them.
            let onCentreX = drag.map { abs($0.frame.midX - natural.width / 2) < 0.01 } ?? false
            let onCentreY = drag.map { abs($0.frame.midY - natural.height / 2) < 0.01 } ?? false
            vertical(x(natural.width / 2), 0...size.height, .red.opacity(onCentreX ? 1 : 0.5))
            horizontal(y(natural.height / 2), 0...size.width, .red.opacity(onCentreY ? 1 : 0.5))

            // The picked part, and the one under the pointer: a line just outside its ink.
            let together = grouped.filter { $0 != selected }.map { (Optional($0), 0.9) }
            for (id, opacity) in [(hovered == selected ? nil : hovered, 0.35), (selected, 0.9)] + together {
                guard let id, let frame = id == drag?.id ? drag?.frame : frames[id] else { continue }
                let rect = CGRect(x: x(frame.minX), y: y(frame.minY),
                                  width: x(frame.maxX) - x(frame.minX), height: y(frame.maxY) - y(frame.minY))
                context.stroke(Path(rect.insetBy(dx: -0.5, dy: -0.5)), with: .color(.white.opacity(opacity)), lineWidth: 1)
            }

            // The eight handles: small white squares on the corners and the middles of the sides.
            for id in handles {
                guard let frame = id == drag?.id ? drag?.frame : frames[id] else { continue }
                let rect = CGRect(x: x(frame.minX), y: y(frame.minY),
                                  width: x(frame.maxX) - x(frame.minX), height: y(frame.maxY) - y(frame.minY))
                    .insetBy(dx: -0.5, dy: -0.5)
                let strength = id == selected || id == drag?.id ? 1.0 : 0.6
                for handle in ResizeHandle.shown(on: rect, size: Self.handleSize) {
                    let centre = handle.position(on: rect)
                    let half = Self.handleSize / 2
                    let square = Path(roundedRect: CGRect(x: centre.x - half, y: centre.y - half, width: Self.handleSize, height: Self.handleSize),
                                      cornerRadius: 1.5)
                    context.fill(square, with: .color(.white.opacity(strength)))
                    context.stroke(square, with: .color(.black.opacity(0.6 * strength)), lineWidth: 1)
                }
            }

            // The room to its nearest neighbours, as green arrows with their length; brighter where
            // the two sides are even.
            if let id = drag?.id ?? selected, let subject = frames[id] {
                let others = frames.filter { $0.key != id }.map(\.value)
                var tags: [(frame: CGRect, text: GraphicsContext.ResolvedText, color: Color, away: CGVector)] = []
                for gap in ElementGap.around(subject, among: others) {
                    let color = Color.green.opacity(gap.isEven ? 1 : 0.75)
                    let horizontal = gap.axis == .horizontal
                    let start = horizontal ? CGPoint(x: x(gap.start), y: y(gap.across)) : CGPoint(x: x(gap.across), y: y(gap.start))
                    let end = horizontal ? CGPoint(x: x(gap.end), y: y(gap.across)) : CGPoint(x: x(gap.across), y: y(gap.end))
                    var path = Path()
                    path.move(to: start)
                    path.addLine(to: end)
                    // Heads where there is room for them.
                    if (horizontal ? end.x - start.x : end.y - start.y) > 12 {
                        for (tip, sign) in [(start, CGFloat(1)), (end, -1)] {
                            let head: CGFloat = 4
                            path.move(to: horizontal ? CGPoint(x: tip.x + sign * head, y: tip.y - head)
                                                     : CGPoint(x: tip.x - head, y: tip.y + sign * head))
                            path.addLine(to: tip)
                            path.addLine(to: horizontal ? CGPoint(x: tip.x + sign * head, y: tip.y + head)
                                                        : CGPoint(x: tip.x + head, y: tip.y + sign * head))
                        }
                    }
                    context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: gap.isEven ? 1.5 : 1, lineCap: .round))
                    // The length on a green tag beside the arrow: over it, or right of it.
                    let text = context.resolve(Text(Self.length(gap.length))
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.black))
                    let size = text.measure(in: CGSize(width: 200, height: 40))
                    let tag = CGSize(width: size.width + 8, height: size.height + 2)
                    // Wider than the gap: over the part, not over the symbols beside it.
                    let narrow = horizontal ? tag.width > end.x - start.x : tag.height > end.y - start.y
                    let centre = horizontal
                        ? CGPoint(x: (start.x + end.x) / 2,
                                  y: narrow ? y(subject.minY) - 3 - tag.height / 2 : start.y - tag.height / 2 - 4)
                        : CGPoint(x: narrow ? x(subject.maxX) + 3 + tag.width / 2 : start.x + tag.width / 2 + 5,
                                  y: (start.y + end.y) / 2)
                    tags.append((CGRect(x: centre.x - tag.width / 2, y: centre.y - tag.height / 2, width: tag.width, height: tag.height),
                                 text, color, Self.away(gap, from: subject)))
                }
                // No tag covers another: each that would moves on, away from the part (a left one
                // further left, one above further up…), until it is clear of those already placed.
                var placed: [CGRect] = []
                for index in tags.indices {
                    var frame = tags[index].frame
                    let away = tags[index].away
                    for _ in 0..<12 {
                        guard let other = placed.first(where: { $0.insetBy(dx: -3, dy: -3).intersects(frame) }) else { break }
                        let shift = away.dx < 0 ? frame.maxX + 3 - other.minX
                            : away.dx > 0 ? other.maxX + 3 - frame.minX
                            : away.dy < 0 ? frame.maxY + 3 - other.minY
                            : other.maxY + 3 - frame.minY
                        frame = frame.offsetBy(dx: away.dx * max(shift, 1), dy: away.dy * max(shift, 1))
                    }
                    tags[index].frame = frame
                    placed.append(frame)
                }
                for tag in tags {
                    context.fill(Path(roundedRect: tag.frame, cornerRadius: tag.frame.height / 2), with: .color(tag.color))
                    context.draw(tag.text, at: CGPoint(x: tag.frame.midX, y: tag.frame.midY))
                }
            }
        }
    }

    /// Lines on screen, sorted, those closer than a point and a half drawn as one (the held one where
    /// one of them is held).
    private static func merged(_ lines: [(CGFloat, Bool)]) -> [(CGFloat, Bool)] {
        var result: [(CGFloat, Bool)] = []
        for (at, held) in lines.sorted(by: { $0.0 < $1.0 }) {
            if let last = result.last, at - last.0 < 1.5 {
                if held { result[result.count - 1] = (at, true) }
            } else {
                result.append((at, held))
            }
        }
        return result
    }

    /// The way a gap's tag gives way: out on the gap's side of the part.
    private static func away(_ gap: ElementGap, from part: CGRect) -> CGVector {
        switch gap.axis {
        case .horizontal: gap.end <= part.minX ? CGVector(dx: -1, dy: 0) : CGVector(dx: 1, dy: 0)
        case .vertical: gap.end <= part.minY ? CGVector(dx: 0, dy: -1) : CGVector(dx: 0, dy: 1)
        }
    }

    /// How near (in the widget's points) another part's edge is to the dragged part's for its line
    /// to be drawn.
    static let edgeReach: CGFloat = 8
    /// A handle's side on screen.
    static let handleSize: CGFloat = 7

    /// A gap's length, in the steps a part moves by (the widget's points): whole, as the parts'
    /// frames are (to the widget's own edge it may be a fraction: it is rounded too).
    private static func length(_ value: CGFloat) -> String {
        "\(Int(value.rounded())) px"
    }

    /// On the middle of a pixel row, so a one-point line is sharp.
    private static func crisp(_ value: CGFloat) -> CGFloat { (value * 2).rounded() / 2 }
}
