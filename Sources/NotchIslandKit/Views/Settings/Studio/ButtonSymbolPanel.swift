import SwiftUI

/// Customize's band under the editor, while a button is picked: the button drawn large, its symbol
/// moved by dragging it (it holds to the middle lines) and sized by the eight handles round it, as
/// the editor's are (from its middle: a symbol keeps its proportions); beside
/// it the symbol's size, its edges, and putting it back in the middle. With nothing (or something
/// else) picked, a line on what it is for.
struct ButtonSymbolPanel: View {
    let widget: IslandWidget
    let editing: ElementEditing

    @Environment(AppModel.self) private var model
    @Environment(\.timeZone) private var here
    /// Where the symbol was when the drag began.
    @State private var dragStart: ElementOffset?
    /// Its size when the handle's drag began, and from its middle to the handles then.
    @State private var resizeStart: Double?
    @State private var resizeHalf: CGSize?
    /// The handle a press took (nil: the press moves the symbol, or nothing).
    @State private var pressHandle: Handle?
    /// Where the pointer is over the button: its cursor follows what a press there would take.
    @State private var hover: CGPoint?
    /// Held to the middle lines while dragged: drawn stronger.
    @State private var heldX = false
    @State private var heldY = false

    /// The middle lines hold the symbol this near them, as a share of the button.
    static let snap = 0.04
    static let controlsWidth: CGFloat = 210

    var body: some View {
        if let id = editing.selected, widget.kind.spec.buttons.contains(id) {
            let look = widget.buttonLook(of: id)
            HStack(spacing: 18) {
                canvas(id, look)
                controls(id, look)
                    .frame(width: Self.controlsWidth)
            }
            .padding(16)
        } else {
            VStack(spacing: 6) {
                Image(systemName: "square.on.circle")
                    .font(.system(size: 22))
                    .foregroundStyle(SettingsPalette.secondary)
                Text("Pick a button, the progress line or a shape in the editor to place and size it here.")
                    .font(.callout)
                    .foregroundStyle(SettingsPalette.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: The button, large

    private func canvas(_ id: ElementID, _ look: ButtonLook) -> some View {
        GeometryReader { proxy in
            let points = self.points(id)
            let natural = look.material.hasShape ? WidgetButtonLabel.size(of: look, points: points)
                : CGSize(width: points * 1.7, height: points * 1.7)
            // As large as the room allows, with room around it.
            let zoom = max(1, min((proxy.size.width - 40) / natural.width, (proxy.size.height - 40) / natural.height, 7))
            let size = CGSize(width: natural.width * zoom, height: natural.height * zoom)
            let symbol = self.symbol(id)
            let iconPoints = points * zoom * WidgetButtonLabel.iconScale(of: look, symbol: self.symbol(id))
            let canMove = look.material.hasShape
            let centre = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let iconCentre = canMove
                ? CGPoint(x: centre.x + look.iconOffset.x * size.width, y: centre.y + look.iconOffset.y * size.height)
                : centre
            ZStack {
                // The middle lines, stronger while the symbol holds to them.
                Path { path in
                    path.move(to: CGPoint(x: centre.x, y: 0))
                    path.addLine(to: CGPoint(x: centre.x, y: proxy.size.height))
                }
                .stroke(Color.red.opacity(heldX ? 0.8 : 0.22), lineWidth: 1)
                Path { path in
                    path.move(to: CGPoint(x: 0, y: centre.y))
                    path.addLine(to: CGPoint(x: proxy.size.width, y: centre.y))
                }
                .stroke(Color.red.opacity(heldY ? 0.8 : 0.22), lineWidth: 1)
                Group {
                    if isDial {
                        // The clock face's dial, as the widget draws it.
                        PanelTimelineView(.everyMinute) { context in
                            ClockFaceButton(date: context.date, zone: ClockFaceWidget.zone(widget.config, here: here),
                                            showsSeconds: widget.shows(.secondsHand),
                                            diameter: points * zoom * (look.material.hasShape ? 1.35 : 1), look: look)
                        }
                    } else {
                        WidgetButtonLabel(look: look, symbol: symbol, points: points * zoom)
                    }
                }
                .environment(\.widgetRenderMode, .canvas)
                .allowsHitTesting(false)
                .position(centre)
                // The symbol's box and the handles that size it (drawn only: the one gesture below
                // finds which a press is on).
                let box = iconBox(symbol: symbol, look: look, points: iconPoints, centre: iconCentre)
                Rectangle()
                    .strokeBorder(Color.white.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .frame(width: box.width + 2 * PanelHandles.pad, height: box.height + 2 * PanelHandles.pad)
                    .position(x: box.midX, y: box.midY)
                    .allowsHitTesting(false)
                PanelHandles.drawn(round: box)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
            .gesture(press(id, look, size: size, box: iconBox(symbol: symbol, look: look, points: iconPoints, centre: iconCentre),
                           canMove: canMove))
            .onContinuousHover { phase in
                if case .active(let point) = phase { hover = point } else { hover = nil }
            }
            .pointerStyle(pointer(box: iconBox(symbol: symbol, look: look, points: iconPoints, centre: iconCentre), canMove: canMove))
        }
        .background(Color.white.opacity(0.03), in: .rect(cornerRadius: 12, style: .continuous))
        .clipShape(.rect(cornerRadius: 12, style: .continuous))
        .accessibilityHidden(true)
    }

    /// Under the pointer: a handle's resize arrows, otherwise the open hand where the symbol moves.
    private func pointer(box: CGRect, canMove: Bool) -> PointerStyle? {
        if let pressHandle { return .frameResize(position: pressHandle.position) }
        if dragStart != nil { return .grabActive }
        guard let hover else { return nil }
        if let handle = PanelHandles.hit(hover, round: box) { return .frameResize(position: handle.position) }
        return canMove ? .grabIdle : nil
    }

    /// One gesture for the button: a press on a handle sizes the symbol; anywhere else it moves it
    /// (with a shape to move in).
    private func press(_ id: ElementID, _ look: ButtonLook, size: CGSize, box: CGRect, canMove: Bool) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if pressHandle == nil, dragStart == nil, resizeStart == nil,
                   let handle = PanelHandles.hit(value.startLocation, round: box) {
                    pressHandle = handle
                    resizeStart = look.iconScale
                    resizeHalf = CGSize(width: box.width / 2 + PanelHandles.pad, height: box.height / 2 + PanelHandles.pad)
                }
                if let handle = pressHandle {
                    resize(id, handle: handle, translation: value.translation)
                } else if canMove, hypot(value.translation.width, value.translation.height) >= 1 {
                    move(id, look, size: size, translation: value.translation)
                }
            }
            .onEnded { _ in
                pressHandle = nil
                resizeStart = nil
                resizeHalf = nil
                dragStart = nil
                heldX = false
                heldY = false
            }
    }

    /// The symbol moved by `translation` from where the press began, held to the middle lines.
    private func move(_ id: ElementID, _ look: ButtonLook, size: CGSize, translation: CGSize) {
        let start = dragStart ?? look.iconOffset
        if dragStart == nil { dragStart = start }
        var x = start.x + translation.width / max(size.width, 1)
        var y = start.y + translation.height / max(size.height, 1)
        heldX = abs(x) < Self.snap
        heldY = abs(y) < Self.snap
        if heldX { x = 0 }
        if heldY { y = 0 }
        updateLook(id) { $0.iconOffset = ElementOffset(x: x, y: y) }
    }

    /// A handle round the symbol: -1, 0 or 1 on each axis from its middle.
    struct Handle: Hashable {
        let x: Int
        let y: Int

        var position: FrameResizePosition {
            switch (x, y) {
            case (-1, -1): .topLeading
            case (0, -1): .top
            case (1, -1): .topTrailing
            case (-1, 0): .leading
            case (1, 0): .trailing
            case (-1, 1): .bottomLeading
            case (0, 1): .bottom
            default: .bottomTrailing
            }
        }
    }

    static let handles: [Handle] = [(-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1)]
        .map { Handle(x: $0.0, y: $0.1) }

    /// A handle away from the symbol's middle makes it larger, towards it smaller — about its
    /// middle, both ways alike: a side by its own axis, a corner by both — from the handles'
    /// distance when the press began.
    private func resize(_ id: ElementID, handle: Handle, translation: CGSize) {
        guard let start = resizeStart, let half = resizeHalf else { return }
        let width = max(half.width, 1), height = max(half.height, 1)
        var factors: [CGFloat] = []
        if handle.x != 0 { factors.append((width + CGFloat(handle.x) * translation.width) / width) }
        if handle.y != 0 { factors.append((height + CGFloat(handle.y) * translation.height) / height) }
        let factor = factors.reduce(0, +) / CGFloat(max(factors.count, 1))
        let scale = (start * Double(factor) * 20).rounded() / 20
        updateLook(id) { $0.iconScale = scale }
    }

    // MARK: Beside it

    @ViewBuilder private func controls(_ id: ElementID, _ look: ButtonLook) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Symbol").font(.subheadline.weight(.semibold))
                Text(look.material.hasShape ? "Drag it to place it in the button; its handles size it."
                     : "Regular has no shape: the symbol is the button. Its handles size it.")
                    .font(.caption)
                    .foregroundStyle(SettingsPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Text("Size").font(.callout)
                Slider(value: Binding(get: { look.iconScale }, set: { new in
                    let snapped = (new * 20).rounded() / 20
                    if snapped != look.iconScale { updateLook(id) { $0.iconScale = snapped } }
                }), in: look.iconScaleRange) { Text("Size") }
                .labelsHidden()
                .tint(Color.islandAccent)
                ReservedWidthText(look.iconScale.formatted(.percent.precision(.fractionLength(0))),
                                  fitting: [Double(6).formatted(.percent.precision(.fractionLength(0)))])
                    .foregroundStyle(SettingsPalette.secondary)
                    .monospacedDigit()
            }
            Text("Edges").font(.callout)
            Picker("Edges", selection: Binding(get: { look.iconEdges }, set: { edges in
                withAnimation(.spring(duration: 0.35, bounce: 0.12)) { updateLook(id) { $0.iconEdges = edges } }
            })) {
                ForEach(ButtonLook.IconEdges.allCases) { Text($0.title).tag($0) }
            }
            .choiceBar(width: Self.controlsWidth)
            .labelsHidden()
            .fixedSize()
            .help(hasEdges(symbol(id)) ? "Rounded or sharp corners on the symbol" : "This symbol keeps its own edges")
            .disabled(!hasEdges(symbol(id)))
            Button {
                withAnimation(.spring(duration: 0.4, bounce: 0.18)) {
                    updateLook(id) {
                        $0.iconOffset = .zero
                        $0.iconScale = 1
                    }
                }
            } label: {
                Label("Centre", systemImage: "scope").frame(maxWidth: .infinity)
            }
            .buttonBorderShape(.capsule)
            .disabled(look.iconOffset == .zero && look.iconScale == 1)
            .help("The symbol back in the middle, at its own size")
        }
        .frame(maxHeight: .infinity, alignment: .center)
    }

    // MARK: Pieces

    /// Whether the symbol is drawn by hand, so its edges can be rounded or sharp.
    private func hasEdges(_ symbol: String) -> Bool {
        MediaGlyph(symbol: symbol) != nil || DrawnSymbol(symbol: symbol) != nil
    }

    /// The symbol the button shows now.
    /// The clock face's button: its symbol is the dial (`ClockFaceButton.dial`), drawn as it is.
    private var isDial: Bool { widget.kind == .analogClock }

    private func symbol(_ id: ElementID) -> String { WidgetParts.buttonSymbol(of: id, in: widget, model: model) }

    /// Where the symbol's ink is, drawn at `points` about `centre`: a drawn glyph (sharp edges) fills
    /// its frame; a system symbol's ink sits off its frame's middle (play's to the right, previous'
    /// to the left), read once from a picture of it.
    private func iconBox(symbol: String, look: ButtonLook, points: CGFloat, centre: CGPoint) -> CGRect {
        if isDial {
            return CGRect(x: centre.x - points / 2, y: centre.y - points / 2, width: points, height: points)
        }
        if let drawn = DrawnSymbol(symbol: symbol) {
            let size = drawn.size(points: points)
            return CGRect(x: centre.x - size.width / 2, y: centre.y - size.height / 2, width: size.width, height: size.height)
        }
        if look.iconEdges == .sharp, let glyph = MediaGlyph(symbol: symbol) {
            let size = glyph.size(points: points)
            return CGRect(x: centre.x - size.width / 2, y: centre.y - size.height / 2, width: size.width, height: size.height)
        }
        let name = look.iconFill == .none ? WidgetButtonLabel.outlined(symbol) : symbol
        let ink = SymbolInk.bounds(of: name)
        return CGRect(x: centre.x + ink.minX * points, y: centre.y + ink.minY * points,
                      width: ink.width * points, height: ink.height * points)
    }

    /// The widget's own symbol size for the button.
    private func points(_ id: ElementID) -> CGFloat {
        let geometry = WidgetBoardGeometry(size: WidgetsSettingsPage.boardSize(model.layout), grid: model.editedWidgets.board.grid)
        let natural = geometry.laidSize(for: widget.frame)
        let padding = WidgetMetrics.padding(for: widget)
        return WidgetParts.buttonPoints(of: id, in: widget, inner: CGSize(width: natural.width - 2 * padding,
                                                                         height: natural.height - 2 * padding))
    }

    private func updateLook(_ id: ElementID, _ change: (inout ButtonLook) -> Void) {
        model.editedWidgets.update(widget.id) { widget in
            var look = widget.buttonLook(of: id)
            change(&look)
            look.sanitize()
            widget.setButtonLook(look, of: id)
        }
    }
}

/// Where a system symbol's ink is, from its frame's middle, in its points (a 1-point symbol's):
/// read once each from a picture of it at a large size.
@MainActor enum SymbolInk {
    private static var known: [String: CGRect] = [:]
    private static let reference: CGFloat = 100

    static func bounds(of symbol: String) -> CGRect {
        if let rect = known[symbol] { return rect }
        let renderer = ImageRenderer(content: Image(systemName: symbol).font(.system(size: reference)).foregroundStyle(.white))
        renderer.scale = 2
        var rect = CGRect(x: -0.5, y: -0.5, width: 1, height: 1)
        if let image = renderer.cgImage {
            let frame = CGRect(x: 0, y: 0, width: CGFloat(image.width) / 2, height: CGFloat(image.height) / 2)
            if let ink = ElementInk.bounds(in: image, scale: 2, boxes: [.artwork: frame])[.artwork] {
                rect = CGRect(x: (ink.minX - frame.midX) / reference, y: (ink.minY - frame.midY) / reference,
                              width: ink.width / reference, height: ink.height / reference)
            }
        }
        known[symbol] = rect
        return rect
    }
}
