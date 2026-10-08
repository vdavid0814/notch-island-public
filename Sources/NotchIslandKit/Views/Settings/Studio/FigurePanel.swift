import SwiftUI

/// Customize's band under the editor, while a shape is picked: the shape drawn large, turned as it
/// is, with handles round it that size it from its middle (along its own sides, however it is
/// turned; Shift keeps its proportions) and a knob over it that turns it (holding at every 15°, and
/// only at them with Shift); beside it its turn, a quarter turn either way, and straight again.
struct FigurePanel: View {
    let widget: IslandWidget
    let figure: WidgetFigure

    @Environment(AppModel.self) private var model
    /// What a press began: a handle's sizing, or the knob's turning.
    @State private var grip: Grip?
    @State private var hover: CGPoint?
    /// The zoom while a handle sizes it: kept, so the shape grows under the pointer.
    @State private var heldZoom: CGFloat?

    private enum Grip: Equatable {
        /// From this handle, at this scale and half size on screen when it began.
        case size(ButtonSymbolPanel.Handle, ElementScale, CGSize)
        /// From this angle of the pointer about the middle, at this turn when it began.
        case turn(Double, Double)
    }

    /// The knob's distance over the shape's top edge, on screen.
    private static let knobGap: CGFloat = 22
    private static let knobSize: CGFloat = 9
    /// A press this near a handle or the knob takes it.
    private static let reach: CGFloat = 7
    /// Turning holds at every 15° within this many degrees.
    private static let hold = 3.0

    var body: some View {
        HStack(spacing: 18) {
            canvas
            controls
                .frame(width: ButtonSymbolPanel.controlsWidth)
        }
        .padding(16)
    }

    // MARK: The shape, large

    /// The shape's own size in the widget (before it is turned).
    private var drawn: CGSize {
        let base = figure.kind.size, scale = widget.scale(of: figure.id)
        return CGSize(width: base.width * scale.x, height: base.height * scale.y)
    }

    private var canvas: some View {
        GeometryReader { proxy in
            let size = drawn
            let room = CGSize(width: proxy.size.width - 2 * (Self.knobGap + 24), height: proxy.size.height - 2 * (Self.knobGap + 24))
            // As large as the room allows with its turn, never smaller than it is.
            let span = max(hypot(size.width, size.height), 1)
            let zoom = heldZoom ?? max(1, min(room.width / span, room.height / span, 8))
            let centre = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let half = CGSize(width: size.width * zoom / 2, height: size.height * zoom / 2)
            let angle = figure.rotation * .pi / 180
            ZStack {
                // The middle lines.
                Path { path in
                    path.move(to: CGPoint(x: centre.x, y: 0))
                    path.addLine(to: CGPoint(x: centre.x, y: proxy.size.height))
                    path.move(to: CGPoint(x: 0, y: centre.y))
                    path.addLine(to: CGPoint(x: proxy.size.width, y: centre.y))
                }
                .stroke(Color.red.opacity(0.22), lineWidth: 1)
                WidgetFigureView(figure: figure, scale: widget.scale(of: figure.id), zoom: zoom)
                    .frame(width: size.width * zoom, height: size.height * zoom, alignment: .topLeading)
                    .position(centre)
                    .allowsHitTesting(false)
                // Its frame, turned with it, the handles on it and the knob over it.
                Rectangle()
                    .strokeBorder(Color.white.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .frame(width: half.width * 2 + 4, height: half.height * 2 + 4)
                    .rotationEffect(.radians(angle))
                    .position(centre)
                    .allowsHitTesting(false)
                Path { path in
                    path.move(to: Self.point(0, -half.height, centre, angle))
                    path.addLine(to: Self.point(0, -half.height - Self.knobGap, centre, angle))
                }
                .stroke(Color.white.opacity(0.7), lineWidth: 1)
                ForEach(ButtonSymbolPanel.handles, id: \.self) { handle in
                    Rectangle()
                        .fill(.white)
                        .frame(width: PanelHandles.size, height: PanelHandles.size)
                        .overlay { Rectangle().strokeBorder(.black.opacity(0.5), lineWidth: 1) }
                        .rotationEffect(.radians(angle))
                        .position(handlePoint(handle, half: half, centre: centre, angle: angle))
                }
                .allowsHitTesting(false)
                Circle()
                    .fill(.white)
                    .overlay { Circle().strokeBorder(.black.opacity(0.5), lineWidth: 1) }
                    .frame(width: Self.knobSize, height: Self.knobSize)
                    .position(Self.point(0, -half.height - Self.knobGap, centre, angle))
                    .allowsHitTesting(false)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
            .gesture(press(centre: centre, half: half, zoom: zoom, angle: angle))
            .onContinuousHover { phase in
                if case .active(let point) = phase { hover = point } else { hover = nil }
            }
            .pointerStyle(pointer(centre: centre, half: half, angle: angle))
        }
        .background(Color.white.opacity(0.03), in: .rect(cornerRadius: 12, style: .continuous))
        .clipShape(.rect(cornerRadius: 12, style: .continuous))
        .accessibilityHidden(true)
    }

    /// `x`, `y` from the middle along the shape's own sides, on screen.
    private static func point(_ x: CGFloat, _ y: CGFloat, _ centre: CGPoint, _ angle: Double) -> CGPoint {
        let cosine = CGFloat(cos(angle)), sine = CGFloat(sin(angle))
        return CGPoint(x: centre.x + x * cosine - y * sine, y: centre.y + x * sine + y * cosine)
    }

    private func handlePoint(_ handle: ButtonSymbolPanel.Handle, half: CGSize, centre: CGPoint, angle: Double) -> CGPoint {
        Self.point(CGFloat(handle.x) * (half.width + 2), CGFloat(handle.y) * (half.height + 2), centre, angle)
    }

    /// What a press at `point` takes: the knob, a handle, or nothing.
    private func grip(at point: CGPoint, centre: CGPoint, half: CGSize, angle: Double) -> Grip? {
        let knob = Self.point(0, -half.height - Self.knobGap, centre, angle)
        if hypot(knob.x - point.x, knob.y - point.y) <= Self.reach {
            return .turn(Self.bearing(of: point, from: centre), figure.rotation)
        }
        let nearest = ButtonSymbolPanel.handles
            .map { ($0, hypot(handlePoint($0, half: half, centre: centre, angle: angle).x - point.x,
                              handlePoint($0, half: half, centre: centre, angle: angle).y - point.y)) }
            .filter { $0.1 <= Self.reach }
            .min { $0.1 < $1.1 }
        return nearest.map { .size($0.0, widget.scale(of: figure.id), half) }
    }

    /// The pointer's angle about the middle, in degrees, clockwise from the right.
    private static func bearing(of point: CGPoint, from centre: CGPoint) -> Double {
        atan2(Double(point.y - centre.y), Double(point.x - centre.x)) * 180 / .pi
    }

    private func press(centre: CGPoint, half: CGSize, zoom: CGFloat, angle: Double) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if grip == nil {
                    grip = grip(at: value.startLocation, centre: centre, half: half, angle: angle)
                    if case .size = grip { heldZoom = zoom }
                }
                switch grip {
                case .turn(let start, let from):
                    var degrees = from + Self.bearing(of: value.location, from: centre) - start
                    let nearest = (degrees / 15).rounded() * 15
                    if NSEvent.modifierFlags.contains(.shift) || abs(degrees - nearest) < Self.hold { degrees = nearest }
                    setRotation(degrees)
                case .size(let handle, let from, let half):
                    // The pointer's way along the shape's own sides.
                    let dx = value.translation.width, dy = value.translation.height
                    let cosine = CGFloat(cos(-angle)), sine = CGFloat(sin(-angle))
                    let along = CGSize(width: dx * cosine - dy * sine, height: dx * sine + dy * cosine)
                    var x = handle.x == 0 ? 1 : (half.width + CGFloat(handle.x) * along.width) / max(half.width, 1)
                    var y = handle.y == 0 ? 1 : (half.height + CGFloat(handle.y) * along.height) / max(half.height, 1)
                    if NSEvent.modifierFlags.contains(.shift) || (handle.x != 0 && handle.y != 0 && figure.kind == .disc) {
                        let both = handle.x == 0 ? y : handle.y == 0 ? x : max(x, y)
                        x = both
                        y = both
                    }
                    resize(to: ElementScale(x: Double(max(x, 0.05)) * from.x, y: Double(max(y, 0.05)) * from.y))
                case nil:
                    break
                }
            }
            .onEnded { _ in
                grip = nil
                heldZoom = nil
            }
    }

    private func pointer(centre: CGPoint, half: CGSize, angle: Double) -> PointerStyle? {
        if case .turn = grip { return .grabActive }
        if case .size(let handle, _, _) = grip { return .frameResize(position: handle.position) }
        guard let hover else { return nil }
        switch grip(at: hover, centre: centre, half: half, angle: angle) {
        case .turn: return .grabIdle
        case .size(let handle, _, _): return .frameResize(position: handle.position)
        case nil: return nil
        }
    }

    // MARK: Beside it

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Turn and Size").font(.subheadline.weight(.semibold))
                Text("Turn it by the knob over it; its handles size it from its middle (with Shift, in proportion).")
                    .font(.caption)
                    .foregroundStyle(SettingsPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Text("Turn").font(.callout)
                Slider(value: Binding(get: { figure.rotation }, set: { new in
                    let degrees = new.rounded()
                    if degrees != figure.rotation { setRotation(degrees) }
                }), in: -180...180) { Text("Turn") }
                .labelsHidden()
                .tint(Color.islandAccent)
                ReservedWidthText("\(Int(figure.rotation.rounded()))°", fitting: ["-180°"])
                    .foregroundStyle(SettingsPalette.secondary)
                    .monospacedDigit()
            }
            HStack(spacing: 8) {
                Button {
                    withAnimation(.spring(duration: 0.35, bounce: 0.12)) { setRotation(figure.rotation - 90) }
                } label: {
                    Label("90°", systemImage: "rotate.left").frame(maxWidth: .infinity)
                }
                .help("A quarter turn to the left")
                Button {
                    withAnimation(.spring(duration: 0.35, bounce: 0.12)) { setRotation(figure.rotation + 90) }
                } label: {
                    Label("90°", systemImage: "rotate.right").frame(maxWidth: .infinity)
                }
                .help("A quarter turn to the right")
            }
            .buttonBorderShape(.capsule)
            Button {
                withAnimation(.spring(duration: 0.35, bounce: 0.12)) { setRotation(0) }
            } label: {
                Label("Straighten", systemImage: "arrow.uturn.backward").frame(maxWidth: .infinity)
            }
            .buttonBorderShape(.capsule)
            .disabled(figure.rotation == 0)
            .help("Not turned at all")
        }
        .frame(maxHeight: .infinity, alignment: .center)
    }

    // MARK: Changes

    private func setRotation(_ degrees: Double) {
        let id = figure.id
        model.editedWidgets.update(widget.id) { widget in
            guard let index = widget.figures.firstIndex(where: { $0.id == id }) else { return }
            widget.figures[index].rotation = WidgetFigure.normalized(degrees)
        }
    }

    /// At `scale`, its middle where it was: the scale grows it from its corner, the move makes up
    /// the difference.
    private func resize(to scale: ElementScale) {
        let id = figure.id, base = figure.kind.size
        let range = ElementScale.range
        let new = ElementScale(x: min(max(scale.x, range.lowerBound), range.upperBound),
                               y: min(max(scale.y, range.lowerBound), range.upperBound))
        let old = widget.scale(of: id)
        guard new != old else { return }
        var offset = widget.offset(of: id)
        offset.x += Double(base.width) * (old.x - new.x) / 2
        offset.y += Double(base.height) * (old.y - new.y) / 2
        model.editedWidgets.update(widget.id) { widget in
            widget.scales[id] = new == .one ? nil : new
            widget.setOffset(offset, of: id)
        }
    }
}
