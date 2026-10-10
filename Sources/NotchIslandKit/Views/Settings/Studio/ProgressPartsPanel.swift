import SwiftUI

/// Customize's band under the editor, while a playback line is picked: the line and its times
/// drawn large, each picked by a click (the one under the pointer, or the nearest within a few
/// points), moved by dragging it — holding to the others' edges and centres, to the middle and to
/// even gaps, as the editor's parts do — and sized by the eight handles round it: the line's sides
/// its length, its top and bottom its thickness; a time's handles its type's size. Beside it its
/// size and position (typed over to set them), and putting it back where the layout puts it. None
/// of it moves the parts around the line in the widget (`ProgressLook`).
struct ProgressPartsPanel: View {
    let widget: IslandWidget
    let editing: ElementEditing
    let id: ElementID

    @Environment(AppModel.self) private var model
    @Environment(\.controlSize) private var controlSize
    @Environment(\.displayScale) private var displayScale
    /// Where each part is drawn, and the whole line, in the panel's points.
    @State private var frames: [ProgressLook.Part: CGRect] = [:]
    @State private var bounds: CGRect = .zero
    /// The part being dragged, and how (in the line's own points).
    @State private var drag: (part: ProgressLook.Part, geometry: ElementDrag, from: ElementOffset)?

    /// The part a drag has moved (not one only pressed): drawn by itself meanwhile.
    private var movingPart: ProgressLook.Part? {
        guard let drag, drag.geometry.offset != drag.from else { return nil }
        return drag.part
    }
    /// The press began on no part.
    @State private var pressMissed = false
    /// The part being resized: how (in the line's own points), and the look, its frame and a
    /// time's size when it began.
    @State private var resizing: Resizing?

    /// Where the pointer is over the line: its cursor follows what a press there would take.
    @State private var hover: CGPoint?

    private struct Resizing {
        var part: ProgressLook.Part
        let handle: ButtonSymbolPanel.Handle
        var geometry: ElementResize
        let look: ProgressLook
        let frame: CGRect
        let size: Double
    }

    static let controlsWidth: CGFloat = 180
    /// Round the line in its picture, for a part dragged off it.
    static let pictureMargin: CGFloat = 90
    /// A sample track, a third played, so the line's both colours show.
    static let duration: TimeInterval = 210
    /// A third in, standing still. One clock for good: made in `body` (`at: .now`), every redraw
    /// was a new clock, and the scrubber's `onChange(of: clock)` fired several times a frame
    /// (SwiftUI's "tried to update multiple times per frame", in the reports' logs).
    static let stoppedClock = PlaybackClock(elapsed: duration / 3, at: .distantPast, rate: 0)
    /// Off a part, a press this near it (on screen) still picks it.
    static let reach: CGFloat = 6
    /// As the editor's: lines hold a part lightly.
    static let release: CGFloat = 2.16

    var body: some View {
        let look = widget.progressLook(of: id)
        HStack(spacing: 14) {
            canvas(look)
            controls(look)
                .frame(width: Self.controlsWidth)
        }
        .padding(16)
    }

    // MARK: The line, large

    private func canvas(_ look: ProgressLook) -> some View {
        GeometryReader { proxy in
            let width = room.width
            let height = room.height
            // As large as the room allows, a little in from its edges.
            let zoom = max(1, min((proxy.size.width - 24) / width, (proxy.size.height - 24) / height, 6))
            // A part being dragged is drawn by itself over the picture, which is drawn without it:
            // each is a picture made on the CPU (and put on screen dot by dot, ~25 ms), so neither is
            // made again while the drag goes on — the part's own picture is only moved, by its layer.
            // The look is set once, when the drag ends (set at every step, the whole of Customize
            // followed it: six to eight steps a second, measured).
            let moving = movingPart
            let picture = PartsPicture(widget: widget, id: id, look: look, isRing: isRing, room: room, zoom: zoom, canvas: proxy.size,
                                       basePoints: basePoints, displayScale: displayScale, controlSize: controlSize)
            ZStack {
                picture.showing(.without(moving)).equatable()
                if let moving, let drag {
                    picture.showing(.only(moving)).equatable()
                        .offset(x: (drag.geometry.offset.x - drag.from.x) * zoom, y: (drag.geometry.offset.y - drag.from.y) * zoom)
                        .allowsHitTesting(false)
                }
                guides(zoom: zoom)
                    .allowsHitTesting(false)
                // Each part's box; the picked one's handles.
                ForEach(ProgressLook.Part.allCases) { part in
                    if let frame = drawn[part] {
                        let picked = editing.progressPart == part
                        Rectangle()
                            .strokeBorder(Color.white.opacity(picked ? 0.85 : 0.18),
                                          style: StrokeStyle(lineWidth: 1, dash: picked ? [] : [3, 3]))
                            .frame(width: frame.width + 4, height: frame.height + 4)
                            .position(x: frame.midX, y: frame.midY)
                            .allowsHitTesting(false)
                    }
                }
            }
            .overlay {
                if let part = editing.progressPart, let frame = drawn[part] {
                    PanelHandles.drawn(round: frame)
                }
            }
            .contentShape(Rectangle())
            // One gesture for all of it: a handle first, then a part, then nothing.
            .gesture(press(look, zoom: zoom))
            .onContinuousHover { phase in
                if case .active(let point) = phase { hover = point } else { hover = nil }
            }
            .pointerStyle(pointer)
            .coordinateSpace(.named(ProgressPartFramesKey.space))
            .onPreferenceChange(ProgressPartFramesKey.self) { frames = $0 }
            .onPreferenceChange(LineBoundsKey.self) { bounds = $0 }
        }
        .background(Color.white.opacity(0.03), in: .rect(cornerRadius: 12, style: .continuous))
        .clipShape(.rect(cornerRadius: 12, style: .continuous))
        .accessibilityHidden(true)
    }

    /// The line bent round, as its widget draws it at this size (`ProgressRing`): a level's, a
    /// load's, the fan's and the chip's dials — each with the texts inside it.
    static func isRing(_ id: ElementID, inner: CGSize) -> Bool {
        switch id {
        case .fanDial, .tempDial: true
        case .cpuLoad, .memoryLoad: inner.height >= 56
        case .levelSlider: LevelWidget.isRing(inner)
        default: false
        }
    }

    private var isRing: Bool { Self.isRing(id, inner: inner) }

    /// The widget's inside, as the board draws it.
    private var inner: CGSize {
        let geometry = WidgetBoardGeometry(size: WidgetsSettingsPage.boardSize(model.layout), grid: model.preferences.panel.grid)
        let natural = geometry.laidSize(for: widget.frame), padding = WidgetMetrics.padding(for: widget)
        return CGSize(width: max(0, natural.width - 2 * padding), height: max(0, natural.height - 2 * padding))
    }

    /// The room the line is drawn in here: as long as in the widget; a ring's square.
    private var room: CGSize {
        let box = editing.boxes[id]
        if isRing {
            let side = max(min(box?.width ?? 64, box?.height ?? 64), 24)
            return CGSize(width: side, height: side)
        }
        return CGSize(width: max(box?.width ?? 170, 40), height: 40)
    }

    /// While a part is dragged: the lines it holds to (yellow), the others' edges near it, the
    /// centres it is on (blue), and the line's own middle (red).
    private func guides(zoom: CGFloat) -> some View {
        Canvas { context, size in
            guard let drag = activeGuide, bounds.width > 0 else { return }
            func x(_ value: CGFloat) -> CGFloat { (bounds.minX + value * zoom).rounded() + 0.5 }
            func y(_ value: CGFloat) -> CGFloat { (bounds.minY + value * zoom).rounded() + 0.5 }
            func line(_ from: CGPoint, _ to: CGPoint, _ color: Color) {
                var path = Path()
                path.move(to: from)
                path.addLine(to: to)
                context.stroke(path, with: .color(color), lineWidth: 1)
            }
            let frame = drag.frame
            let heldX = drag.heldX, heldY = drag.heldY
            for edge in Set(drag.others.flatMap { [$0.minX, $0.maxX] })
            where edge == heldX || [frame.minX, frame.midX, frame.maxX].contains(where: { abs($0 - edge) <= ElementGuides.edgeReach }) {
                line(CGPoint(x: x(edge), y: 0), CGPoint(x: x(edge), y: size.height), .yellow.opacity(edge == heldX ? 0.9 : 0.3))
            }
            for edge in Set(drag.others.flatMap { [$0.minY, $0.maxY] })
            where edge == heldY || [frame.minY, frame.midY, frame.maxY].contains(where: { abs($0 - edge) <= ElementGuides.edgeReach }) {
                line(CGPoint(x: 0, y: y(edge)), CGPoint(x: size.width, y: y(edge)), .yellow.opacity(edge == heldY ? 0.9 : 0.3))
            }
            for centre in drag.nearCentresX { line(CGPoint(x: x(centre), y: 0), CGPoint(x: x(centre), y: size.height), .blue) }
            for centre in drag.nearCentresY { line(CGPoint(x: 0, y: y(centre)), CGPoint(x: size.width, y: y(centre)), .blue) }
            let middle = CGSize(width: bounds.width / zoom / 2, height: bounds.height / zoom / 2)
            line(CGPoint(x: x(middle.width), y: 0), CGPoint(x: x(middle.width), y: size.height),
                 .red.opacity(abs(frame.midX - middle.width) < 0.6 ? 1 : 0.35))
            line(CGPoint(x: 0, y: y(middle.height)), CGPoint(x: size.width, y: y(middle.height)),
                 .red.opacity(abs(frame.midY - middle.height) < 0.6 ? 1 : 0.35))
        }
    }

    /// What the guides follow: the part dragged, or resized.
    private var activeGuide: EditGuide? {
        if let drag {
            let near = drag.geometry.nearCentres()
            return EditGuide(id: id, frame: drag.geometry.frame, others: drag.geometry.others,
                             heldX: drag.geometry.stuckX?.line, heldY: drag.geometry.stuckY?.line,
                             nearCentresX: near.x, nearCentresY: near.y)
        }
        if let resizing {
            let frame = resizing.geometry.frame, others = resizing.geometry.others
            return EditGuide(id: id, frame: frame, others: others,
                             heldX: resizing.geometry.stuckX?.line, heldY: resizing.geometry.stuckY?.line,
                             nearCentresX: others.map(\.midX).filter { abs($0 - frame.midX) < 0.99 },
                             nearCentresY: others.map(\.midY).filter { abs($0 - frame.midY) < 0.99 })
        }
        return nil
    }

    /// The handle a press at `point` takes, round the picked part.
    private func handle(at point: CGPoint) -> (ProgressLook.Part, ButtonSymbolPanel.Handle)? {
        guard let part = editing.progressPart, let frame = drawn[part],
              let handle = PanelHandles.hit(point, round: frame) else { return nil }
        return (part, handle)
    }

    /// Under the pointer: a handle's resize arrows, a part's open hand, a held one's closed.
    private var pointer: PointerStyle? {
        if let resizing { return .frameResize(position: resizing.handle.position) }
        if drag != nil { return .grabActive }
        guard let hover else { return nil }
        if let (_, handle) = handle(at: hover) { return .frameResize(position: handle.position) }
        return part(at: hover) == nil ? nil : .grabIdle
    }

    /// A press on a handle of the picked part sizes it; elsewhere it picks the part under it (or the
    /// nearest within reach) and a drag moves it; a press on none picks none.
    private func press(_ look: ProgressLook, zoom: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if resizing == nil, drag == nil, !pressMissed, let (part, handle) = handle(at: value.startLocation) {
                    beginResize(part, look, handle: handle, zoom: zoom)
                }
                if var current = resizing {
                    if !editing.isPlacingLinePart { editing.isPlacingLinePart = true }
                    current.geometry.move(by: CGSize(width: value.translation.width / zoom, height: value.translation.height / zoom))
                    resizing = current
                    apply(current, handle: current.handle)
                    return
                }
                if drag == nil, !pressMissed {
                    guard let part = part(at: value.startLocation) else {
                        pressMissed = true
                        return
                    }
                    pick(part)
                    let others = ProgressLook.Part.allCases.filter { $0 != part }.compactMap { local($0) }
                    guard let frame = local(part) else { return }
                    let offset = look.offset(of: part)
                    drag = (part, ElementDrag(id: id, base: frame.offsetBy(dx: -offset.x, dy: -offset.y), start: offset,
                                              others: others, bounds: CGSize(width: bounds.width / zoom, height: bounds.height / zoom),
                                              release: max(Self.release / zoom, 0.6)), offset)
                }
                guard var current = drag, hypot(value.translation.width, value.translation.height) >= 2 else { return }
                current.geometry.move(by: CGSize(width: value.translation.width / zoom, height: value.translation.height / zoom))
                drag = current
                DragPace.shared.step()
            }
            .onEnded { _ in
                if pressMissed { pick(nil) }
                DragPace.shared.end("line part")
                if editing.isPlacingLinePart { editing.isPlacingLinePart = false }
                // Where the drag left it, set once.
                if let drag, drag.geometry.offset != drag.from {
                    let offset = drag.geometry.offset, part = drag.part
                    updateLine { $0.setOffset(offset, of: part) }
                }
                drag = nil
                resizing = nil
                pressMissed = false
            }
    }

    /// The part under `point`: the smallest whose box holds it, or the nearest within reach.
    private func part(at point: CGPoint) -> ProgressLook.Part? {
        let drawn = drawn
        let holding = drawn.filter { $0.value.insetBy(dx: -3, dy: -3).contains(point) }
        if let smallest = holding.min(by: { $0.value.width * $0.value.height < $1.value.width * $1.value.height }) {
            return smallest.key
        }
        func distance(_ rect: CGRect) -> CGFloat {
            hypot(max(rect.minX - point.x, 0, point.x - rect.maxX), max(rect.minY - point.y, 0, point.y - rect.maxY))
        }
        return drawn.filter { distance($0.value) <= Self.reach }.min { distance($0.value) < distance($1.value) }?.key
    }

    /// A part where it is drawn, in the line's own points (from its top-left corner).
    private func local(_ part: ProgressLook.Part) -> CGRect? {
        guard let frame = drawn[part], bounds.width > 0 else { return nil }
        let zoom = zoom
        return CGRect(x: ((frame.minX - bounds.minX) / zoom).rounded(), y: ((frame.minY - bounds.minY) / zoom).rounded(),
                      width: (frame.width / zoom).rounded(), height: (frame.height / zoom).rounded())
    }

    /// Each part where its ink is: a time's box is its line of type, taller than its digits (room
    /// above them for accents, below for descenders) — narrowed to its digits, from its font.
    private var drawn: [ProgressLook.Part: CGRect] {
        let zoom = zoom
        // The part being dragged: where its own picture has been moved to.
        let moved: (part: ProgressLook.Part, by: CGSize)? = drag.map {
            ($0.part, CGSize(width: ($0.geometry.offset.x - $0.from.x) * zoom, height: ($0.geometry.offset.y - $0.from.y) * zoom))
        }
        return frames.reduce(into: [:]) { result, entry in
            var entry = entry
            if let moved, moved.part == entry.key { entry.value = entry.value.offsetBy(dx: moved.by.width, dy: moved.by.height) }
            guard let text = entry.key.textID(in: id) else {
                result[entry.key] = entry.value
                return
            }
            let font = widget.textStyle(of: text).font(size: widget.textStyle(of: text).size.map { CGFloat($0) } ?? basePoints(entry.key),
                                                      weight: .medium)
            let line = font.lineHeight
            // The line's room over the font's ascender and under its descender, shared out.
            let spare = max(line - (font.ascender - font.descender), 0) / 2
            let top = (spare + font.ascender - font.capHeight) * zoom
            let bottom = (spare - font.descender) * zoom
            let frame = entry.value
            result[entry.key] = CGRect(x: frame.minX, y: frame.minY + top, width: frame.width,
                                       height: max(frame.height - top - bottom, 1))
        }
    }

    /// How large the line is drawn here.
    private var zoom: CGFloat {
        return bounds.width > 0 ? bounds.width / room.width : 1
    }

    private func pick(_ part: ProgressLook.Part?) {
        withAnimation(.spring(duration: 0.25)) { editing.progressPart = part }
    }

    /// The handle's edges follow the pointer (holding to the other parts' edges and the middle, as
    /// the editor's do), the opposite ones stay. The line: its sides its length, its top and bottom
    /// its thickness. A time: its type sized to the new height (or width, from a side).
    private func beginResize(_ part: ProgressLook.Part, _ look: ProgressLook, handle: ButtonSymbolPanel.Handle, zoom: CGFloat) {
        guard let frame = local(part), bounds.width > 0 else { return }
        let others = ProgressLook.Part.allCases.filter { $0 != part }.compactMap { local($0) }
        let size = part.textID(in: id).map { widget.textStyle(of: $0).size ?? Double(basePoints(part)) } ?? 0
        resizing = Resizing(part: part, handle: handle,
                            geometry: ElementResize(id: id, horizontal: handle.x, vertical: handle.y, start: frame, others: others,
                                                    bounds: CGSize(width: bounds.width / zoom, height: bounds.height / zoom),
                                                    release: max(Self.release / zoom, 0.6)),
                            look: look, frame: frame, size: size)
    }

    /// `resizing` as it stands, on the look.
    private func apply(_ resizing: Resizing, handle: ButtonSymbolPanel.Handle) {
        let frame = resizing.geometry.frame, start = resizing.frame, look = resizing.look
        guard start.width > 0, start.height > 0 else { return }
        switch resizing.part {
        case .bar where isRing:
            // A ring is sized as a whole, about its middle: the handle's opposite side stays.
            let factor = handle.x != 0 ? frame.width / start.width : frame.height / start.height
            let length = min(max(look.barLength * Double(factor), ProgressLook.barLengths.lowerBound), ProgressLook.barLengths.upperBound)
            let grown = start.width * CGFloat(length / look.barLength - 1) / 2
            updateLine { line in
                line.barLength = length
                line.barOffset = ElementOffset(x: (look.barOffset.x + CGFloat(handle.x) * grown).rounded(),
                                               y: (look.barOffset.y + CGFloat(handle.y) * grown).rounded())
            }
        case .bar:
            updateLine { line in
                line.barLength = look.barLength * Double(frame.width / start.width)
                line.barThickness = look.barThickness * Double(frame.height / start.height)
                // The line is laid out from its leading end and thickened about its middle.
                line.barOffset = ElementOffset(x: (look.barOffset.x + frame.minX - start.minX).rounded(),
                                               y: (look.barOffset.y + frame.midY - start.midY).rounded())
            }
        case .elapsed, .remaining:
            guard let text = resizing.part.textID(in: id) else { return }
            let factor = handle.y != 0 ? frame.height / start.height : frame.width / start.width
            let size = points(resizing.size * Double(factor))
            let scale = CGFloat(size / resizing.size)
            let width = start.width * scale, height = start.height * scale
            // Where it would be drawn at that size, unmoved: from its end of the line (elapsed the
            // left, remaining the right), about its row's middle.
            let laidX = resizing.part == .elapsed ? start.minX : start.maxX - width
            let laidY = start.midY - height / 2
            // Where the handle puts it: its opposite edges where they were.
            let wantX = handle.x < 0 ? start.maxX - width : handle.x > 0 ? start.minX : start.midX - width / 2
            let wantY = handle.y < 0 ? start.maxY - height : handle.y > 0 ? start.minY : start.midY - height / 2
            let from = look.offset(of: resizing.part)
            updateText(text) { $0.size = size }
            updateLine { $0.setOffset(ElementOffset(x: (from.x + wantX - laidX).rounded(), y: (from.y + wantY - laidY).rounded()),
                                      of: resizing.part) }
        }
    }

    // MARK: Beside it

    @ViewBuilder private func controls(_ look: ProgressLook) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let part = editing.progressPart {
                let frame = local(part)
                Text(part.title(in: id, isRing: isRing)).font(.subheadline.weight(.semibold))
                FramePair(title: "Size", first: ("W", frame?.width, { setWidth(part, $0) }),
                          second: ("H", frame?.height, { setHeight(part, $0) }), fieldWidth: 30)
                FramePair(title: "Position", first: ("X", frame?.minX, { setPosition(part, x: $0) }),
                          second: ("Y", frame?.minY, { setPosition(part, y: $0) }), fieldWidth: 30)
                if part == .bar {
                    slider(isRing ? LocalizedStringKey("Size") : "Length", value: look.barLength, in: ProgressLook.barLengths) { new in updateLine { $0.barLength = new } }
                    slider("Thickness", value: look.barThickness, in: ProgressLook.barThicknesses) { new in
                        updateLine { $0.barThickness = new }
                    }
                }
                if let text = part.textID(in: id) {
                    let size = min(widget.textStyle(of: text).size ?? Double(basePoints(part)), sizes.upperBound)
                    HStack(spacing: 8) {
                        Text("Size").font(.callout)
                        Slider(value: Binding(get: { size }, set: { new in
                            let points = new.rounded()
                            if points != size { updateText(text) { $0.size = points } }
                        }), in: sizes) { Text("Size") }
                        .labelsHidden()
                        .tint(Color.islandAccent)
                        ReservedWidthText("\(Int(size)) pt", fitting: ["48 pt"])
                            .foregroundStyle(SettingsPalette.secondary)
                            .monospacedDigit()
                    }
                }
                Button {
                    withAnimation(.spring(duration: 0.4, bounce: 0.18)) {
                        updateLine { line in
                            line.setOffset(.zero, of: part)
                            if part == .bar {
                                line.barLength = 1
                                line.barThickness = 1
                            }
                        }
                        if let text = part.textID(in: id) { updateText(text) { $0.size = nil } }
                    }
                } label: {
                    Label("Put Back", systemImage: "arrow.uturn.backward").frame(maxWidth: .infinity)
                }
                .buttonBorderShape(.capsule)
                .help("Where the layout puts it, at its own size")
            } else {
                Text(isRing ? "Ring and texts" : "Line and times").font(.subheadline.weight(.semibold))
                Text(isRing ? "Click the ring or a text in it to pick it; drag it to move it, its handles size it."
                     : "Click the line or a time to pick it; drag it to move it, its handles size it.")
                    .font(.caption)
                    .foregroundStyle(SettingsPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxHeight: .infinity, alignment: .center)
    }

    /// A share of the line's own length or thickness, by a slider, in twentieths.
    private func slider(_ title: LocalizedStringKey, value: Double, in range: ClosedRange<Double>,
                        set: @escaping (Double) -> Void) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.callout)
            Slider(value: Binding(get: { value }, set: { new in
                let snapped = (new * 20).rounded() / 20
                if snapped != value { set(snapped) }
            }), in: range) { Text(title) }
            .labelsHidden()
            .tint(Color.islandAccent)
            ReservedWidthText(value.formatted(.percent.precision(.fractionLength(0))),
                              fitting: [Double(4).formatted(.percent.precision(.fractionLength(0)))])
                .foregroundStyle(SettingsPalette.secondary)
                .monospacedDigit()
        }
    }

    /// The part's top-left corner moved to `x`, `y` (in the line's points).
    private func setPosition(_ part: ProgressLook.Part, x: CGFloat? = nil, y: CGFloat? = nil) {
        guard let frame = local(part) else { return }
        updateLine { line in
            var offset = line.offset(of: part)
            if let x { offset.x += x - frame.minX }
            if let y { offset.y += y - frame.minY }
            line.setOffset(offset, of: part)
        }
    }

    /// The line this long; a time's type sized so it is this wide.
    private func setWidth(_ part: ProgressLook.Part, _ width: CGFloat) {
        guard let frame = local(part), frame.width > 0, width > 0 else { return }
        if part == .bar {
            updateLine { $0.barLength *= Double(width / frame.width) }
        } else if let text = part.textID(in: id) {
            let size = widget.textStyle(of: text).size ?? Double(basePoints(part))
            updateText(text) { $0.size = points(size * Double(width / frame.width)) }
        }
    }

    /// The line this thick; a time's type sized so it is this tall.
    private func setHeight(_ part: ProgressLook.Part, _ height: CGFloat) {
        guard let frame = local(part), frame.height > 0, height > 0 else { return }
        if part == .bar {
            // A ring is as tall as it is wide.
            updateLine { if isRing { $0.barLength *= Double(height / frame.height) } else { $0.barThickness *= Double(height / frame.height) } }
        } else if let text = part.textID(in: id) {
            let size = widget.textStyle(of: text).size ?? Double(basePoints(part))
            updateText(text) { $0.size = points(size * Double(height / frame.height)) }
        }
    }

    // MARK: Pieces

    /// A type size, whole and within what a text style offers.
    private func points(_ size: Double) -> Double {
        min(max(size.rounded(), sizes.lowerBound), sizes.upperBound)
    }

    /// The sizes a text of this line takes: a text's own, but in a ring no larger than a ring's
    /// texts are drawn (`RingText.largest`) — the slider and the handles stop where the letters do.
    private var sizes: ClosedRange<Double> {
        isRing ? TextStyle.sizes.lowerBound...RingText.largest : TextStyle.sizes
    }

    /// The times' own size, as the line sets them.
    /// A text's own size at the line's ends: the times' from the control size, the system's from its rows.
    private func basePoints(_ part: ProgressLook.Part) -> CGFloat {
        guard isRing else { return basePoints }
        let side = room.width
        return switch (id, part) {
        case (.tempDial, .remaining), (.fanDial, .remaining): WidgetMetrics.points(side, ratio: 0.2, min: 8, max: 26)
        case (.fanDial, _), (.tempDial, _): WidgetMetrics.points(side, ratio: 0.095, min: 7, max: 12)
        case (_, .remaining): StatRing.valuePoints(diameter: side)
        default: StatRing.titlePoints(diameter: side)
        }
    }

    private var basePoints: CGFloat {
        if id == .cpuLoad || id == .memoryLoad {
            let geometry = WidgetBoardGeometry(size: WidgetsSettingsPage.boardSize(model.layout), grid: model.preferences.panel.grid)
            let natural = geometry.laidSize(for: widget.frame), padding = WidgetMetrics.padding(for: widget)
            return SystemStatsWidget.barTextSize(widget, inner: CGSize(width: natural.width - 2 * padding, height: natural.height - 2 * padding))
        }
        return Metrics.Control.smaller(controlSize) >= .large ? 12 : 10
    }

    private func updateLine(_ change: (inout ProgressLook) -> Void) {
        model.editedWidgets.update(widget.id) { widget in
            var look = widget.progressLook(of: id)
            change(&look)
            look.sanitize()
            widget.setProgressLook(look, of: id)
        }
    }

    private func updateText(_ text: ElementID, _ change: (inout TextStyle) -> Void) {
        model.editedWidgets.update(widget.id) { widget in
            var style = widget.textStyle(of: text)
            change(&style)
            style.sanitize()
            widget.setTextStyle(style, of: text)
        }
    }
}

/// The whole playback line in Customize's panel for it, in `ProgressPartFramesKey.space`.
private struct LineBoundsKey: PreferenceKey {
    static var defaultValue: CGRect { .zero }

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

/// How fast a drag's steps are taken, for the log: "line part drag: 212 steps in 4.9 s (43 a second)".
/// A drag that stutters is one whose steps each take longer than a frame; this says how many there were.
@MainActor final class DragPace {
    static let shared = DragPace()

    private var steps = 0
    private var began: TimeInterval = 0
    private var last: TimeInterval = 0

    func step() {
        let now = ProcessInfo.processInfo.systemUptime
        if steps == 0 { began = now }
        steps += 1
        last = now
    }

    func end(_ what: String) {
        defer { steps = 0 }
        guard steps >= 10, last > began else { return }
        let seconds = last - began
        Log.app.notice("\(what, privacy: .public) drag: \(self.steps) steps in \(seconds, format: .fixed(precision: 1)) s (\(Int(Double(self.steps - 1) / seconds)) a second)")
    }
}

/// What of a line's picture is drawn (`PartsPicture`): all of it, all but a part (the one being
/// dragged), or that part alone.
nonisolated enum ProgressPartFilter: Equatable, Sendable {
    case all
    case hiding(ProgressLook.Part)
    case only(ProgressLook.Part)

    static func without(_ part: ProgressLook.Part?) -> ProgressPartFilter { part.map { .hiding($0) } ?? .all }

    func shows(_ part: ProgressLook.Part) -> Bool {
        switch self {
        case .all: true
        case .hiding(let hidden): hidden != part
        case .only(let only): only == part
        }
    }

    /// What is no part of the line (a dial's fan, its thermometer) is drawn with the others.
    var showsTheRest: Bool { if case .only = self { false } else { true } }
}

extension EnvironmentValues {
    @Entry var progressPartFilter = ProgressPartFilter.all
}

extension View {
    /// What is drawn with a line but is none of its parts: left out of a picture of one part alone.
    func besideProgressParts() -> some View { modifier(BesideProgressParts()) }
}

private struct BesideProgressParts: ViewModifier {
    @Environment(\.progressPartFilter) private var filter

    func body(content: Content) -> some View { content.opacity(filter.showsTheRest ? 1 : 0) }
}

/// The line large, as its widget draws it, in one picture: the panel's own view of it. Equatable,
/// and used so: its picture is made on the CPU, and only when something it shows has changed.
private struct PartsPicture: View, Equatable {
    let widget: IslandWidget
    let id: ElementID
    let look: ProgressLook
    let isRing: Bool
    let room: CGSize
    let zoom: CGFloat
    let canvas: CGSize
    let basePoints: CGFloat
    let displayScale: CGFloat
    let controlSize: ControlSize
    var filter = ProgressPartFilter.all

    @Environment(AppModel.self) private var model

    nonisolated static func == (old: PartsPicture, new: PartsPicture) -> Bool {
        old.widget == new.widget && old.id == new.id && old.look == new.look && old.isRing == new.isRing && old.room == new.room
            && old.zoom == new.zoom && old.canvas == new.canvas && old.basePoints == new.basePoints
            && old.displayScale == new.displayScale && old.controlSize == new.controlSize && old.filter == new.filter
    }

    func showing(_ filter: ProgressPartFilter) -> PartsPicture {
        var picture = self
        picture.filter = filter
        return picture
    }

    /// One part alone reports nothing: the whole picture says where the parts are.
    private var reports: Bool { if case .only = filter { false } else { true } }

    var body: some View {
        let width = room.width, height = room.height
        Group {
            if isRing {
                ring(side: width)
            } else if id == .progress {
                PlaybackScrubber(clock: ProgressPartsPanel.stoppedClock, duration: ProgressPartsPanel.duration,
                                 isPlaying: false, look: look,
                                 elapsedStyle: widget.textStyles[.elapsedTime], remainingStyle: widget.textStyles[.remainingTime])
            } else if id == .cpuLoad || id == .memoryLoad {
                // The system's line with its name and value, as the widget draws it.
                StatBar(line: id, title: id == .cpuLoad ? "CPU" : "RAM", value: id == .cpuLoad ? 0.23 : 0.61,
                        textSize: basePoints, titleWidth: 0, look: look, reportsFrame: true,
                        titleStyle: widget.textStyles[id == .cpuLoad ? .cpuTitle : .memoryTitle],
                        valueStyle: widget.textStyles[id == .cpuLoad ? .cpuValue : .memoryValue])
            } else {
                // A line without times (the volume's): the line alone, a third full.
                ScrubTrack(position: 1, duration: 3, look: look, reportsFrame: true) { _ in } commit: {}
            }
        }
        .frame(width: width, height: isRing ? height : nil)
        .background {
            if reports {
                GeometryReader { line in
                    Color.clear.preference(key: LineBoundsKey.self, value: line.frame(in: .named(ProgressPartFramesKey.space)))
                }
            }
        }
        .controlSize(Metrics.Control.smaller(controlSize))
        .environment(\.widgetRenderMode, .canvas)
        .environment(\.isWidgetPreview, true)
        .environment(\.reportsProgressParts, true)
        .environment(\.progressPartFilter, filter)
        // Its pictures made at the resolution they are shown at.
        .environment(\.displayScale, displayScale * zoom)
        .allowsHitTesting(false)
        .scaleEffect(zoom)
        // Drawn as one picture at the size it is shown at, not its pixels enlarged (a line has no
        // glass to lose) — the line and some room round it for a part moved off it, not all of the
        // panel: the picture is put on screen on the CPU each time it is made.
        .frame(width: min(width * zoom + 2 * ProgressPartsPanel.pictureMargin, canvas.width),
               height: min(height * zoom + 2 * ProgressPartsPanel.pictureMargin, canvas.height))
        .drawingGroup()
        .frame(width: canvas.width, height: canvas.height)
    }

    @ViewBuilder private func ring(side: CGFloat) -> some View {
        switch id {
        case .fanDial:
            FanDial(fans: FanControlWidget.sample, held: nil, isManual: false, diameter: side,
                    number: widget.shows(.value) ? FanControlWidget.rpmText(FanControlWidget.sample) : nil,
                    name: FanControlWidget.nameText(manual: false, access: .unknown, showsMode: widget.shows(.label)),
                    look: look, nameStyle: widget.textStyles[.fanName], valueStyle: widget.textStyles[.value], reportsFrame: true,
                    set: { _ in }, automatic: {})
        case .tempDial:
            TemperatureDial(celsius: 46, diameter: side, number: FanControlWidget.degreeNumber(46, locale: .current),
                            unit: FanControlWidget.degreeUnit(locale: .current), look: look,
                            nameStyle: widget.textStyles[.tempName], valueStyle: widget.textStyles[.tempValue], reportsFrame: true)
        case .cpuLoad, .memoryLoad:
            StatRing(title: id == .cpuLoad ? "CPU" : "RAM", value: id == .cpuLoad ? 0.23 : 0.61, diameter: side, look: look,
                     reportsFrame: true, titleStyle: widget.textStyles[id == .cpuLoad ? .cpuTitle : .memoryTitle],
                     valueStyle: widget.textStyles[id == .cpuLoad ? .cpuValue : .memoryValue])
        default:
            // A level's ring, a third full; its symbol and value are the button and the text they are.
            LevelRing(value: 1.0 / 3, symbol: WidgetParts.buttonSymbol(of: .levelIcon, in: widget, model: model),
                      showsSymbol: widget.shows(.levelIcon), showsValue: widget.shows(.levelValue), size: CGSize(width: side, height: side),
                      look: look, symbolLook: widget.buttonLook(of: .levelIcon), valueStyle: widget.textStyles[.levelValue],
                      reportsFrame: true, set: { _ in })
        }
    }
}
