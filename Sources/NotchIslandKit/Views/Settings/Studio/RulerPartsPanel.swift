import SwiftUI

/// Customize's band under the editor, while a ruler (the timer's) is picked: the ruler drawn large
/// with the unit's name beside its marker ("min", "sec", "hr"). A click picks the name (its type and
/// colour are then set in the inspector), a drag moves it; beside it whether it is shown, its box's
/// width and height (the letters shrink to fit it), its type's size, and putting it back where the
/// ruler puts it. None of it moves the parts around the ruler.
struct RulerPartsPanel: View {
    let widget: IslandWidget
    let editing: ElementEditing
    let id: ElementID

    @Environment(AppModel.self) private var model
    @Environment(\.displayScale) private var displayScale
    /// Where the name is drawn, in the panel's points.
    @State private var unitFrame: CGRect = .zero
    /// The name's offset when a drag on it began.
    @State private var dragStart: ElementOffset?
    @State private var isHovering = false
    /// How large the ruler is drawn here (for its sizes in points beside it).
    @State private var zoom: CGFloat = 1

    static let controlsWidth: CGFloat = 180

    var body: some View {
        HStack(spacing: 14) {
            canvas
            controls
                .frame(width: Self.controlsWidth)
        }
        .padding(16)
    }

    /// The ruler as the widget draws it (its size in the editor), and its marker's size there.
    private var room: (size: CGSize, marker: CGFloat, labels: Bool) {
        let size = editing.boxes[id]?.size ?? CGSize(width: 200, height: 36)
        return (CGSize(width: max(size.width, 60), height: max(size.height, 18)), size.height < 30 ? 6 : 9, size.height >= 50)
    }

    private var units: TimerDraftUnits { TimerWidget.units(widget) }

    // MARK: The ruler, large

    private var canvas: some View {
        GeometryReader { proxy in
            let room = room
            let zoom = max(1, min((proxy.size.width - 24) / room.size.width, (proxy.size.height - 24) / room.size.height, 6))
            let look = widget.rulerLook(of: id)
            ZStack {
                TimerRulerPart(look: look, units: units, compact: room.marker < 9, showsLabels: room.labels, isPicture: true,
                               unitName: TimerWidget.unitName(widget, reportsFrame: true))
                    .frame(width: room.size.width, height: room.size.height)
                    .environment(\.isWidgetPreview, true)
                    .environment(\.displayScale, displayScale * zoom)
                    .allowsHitTesting(false)
                    .scaleEffect(zoom)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                if widget.shows(.rulerUnit), unitFrame != .zero {
                    Rectangle()
                        .strokeBorder(Color.white.opacity(editing.picksRulerUnit ? 0.85 : 0.25),
                                      style: StrokeStyle(lineWidth: 1, dash: editing.picksRulerUnit ? [] : [3, 3]))
                        .frame(width: unitFrame.width + 4, height: unitFrame.height + 4)
                        .position(x: unitFrame.midX, y: unitFrame.midY)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .gesture(press(zoom: zoom))
            .onContinuousHover { phase in
                if case .active(let point) = phase { isHovering = hits(point) } else { isHovering = false }
            }
            .pointerStyle(dragStart != nil ? .grabActive : isHovering ? .grabIdle : nil)
            .coordinateSpace(.named(RulerUnitFrameKey.space))
            .onPreferenceChange(RulerUnitFrameKey.self) { unitFrame = $0 }
            .onChange(of: zoom, initial: true) { _, zoom in self.zoom = zoom }
        }
        .background(Color.white.opacity(0.03), in: .rect(cornerRadius: 12, style: .continuous))
        .clipShape(.rect(cornerRadius: 12, style: .continuous))
        .accessibilityHidden(true)
    }

    /// On the name, or a few points off it.
    private func hits(_ point: CGPoint) -> Bool {
        widget.shows(.rulerUnit) && unitFrame != .zero && unitFrame.insetBy(dx: -6, dy: -6).contains(point)
    }

    /// A press on the name picks it and a drag moves it (in the ruler's points); a press elsewhere
    /// picks nothing.
    private func press(zoom: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragStart == nil {
                    guard hits(value.startLocation) else { return }
                    pick(true)
                    dragStart = widget.rulerLook(of: id).unitOffset
                }
                guard let start = dragStart, hypot(value.translation.width, value.translation.height) >= 2 else { return }
                updateLook {
                    $0.unitOffset = ElementOffset(x: (start.x + value.translation.width / zoom).rounded(),
                                                  y: (start.y + value.translation.height / zoom).rounded())
                }
            }
            .onEnded { value in
                if dragStart == nil, !hits(value.startLocation) { pick(false) }
                dragStart = nil
            }
    }

    private func pick(_ picked: Bool) {
        withAnimation(.spring(duration: 0.25)) { editing.picksRulerUnit = picked }
    }

    // MARK: Beside it

    private var controls: some View {
        let style = widget.textStyle(of: .rulerUnit)
        let shows = widget.shows(.rulerUnit)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Unit name").font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Toggle("Unit name", isOn: Binding(get: { shows }, set: { on in
                    model.editedWidgets.update(widget.id) { widget in
                        if on { widget.options.insert(.rulerUnit) } else { widget.options.remove(.rulerUnit) }
                    }
                    if !on { pick(false) }
                }))
                .toggleStyle(.switch)
                .tint(Color.islandControlAccent)
                .labelsHidden()
                .controlSize(.small)
            }
            if shows {
                // As drawn: its box where it has one, its letters' own room where not.
                let width = style.box.map { CGFloat($0.width) } ?? (unitFrame.width / zoom).rounded()
                let height = style.box.map { CGFloat($0.height) } ?? (unitFrame.height / zoom).rounded()
                FramePair(title: "Box", first: ("W", unitFrame == .zero ? nil : width, { setBox(width: $0, height: height) }),
                          second: ("H", unitFrame == .zero ? nil : height, { setBox(width: width, height: $0) }), fieldWidth: 30)
                let size = style.size ?? Double(RulerUnitName.points(markerSize: room.marker))
                HStack(spacing: 8) {
                    Text("Size").font(.callout)
                    Slider(value: Binding(get: { size }, set: { new in
                        let points = new.rounded()
                        if points != size { updateText { $0.size = points } }
                    }), in: TextStyle.sizes) { Text("Size") }
                    .labelsHidden()
                    .tint(Color.islandAccent)
                    ReservedWidthText("\(Int(size)) pt", fitting: ["48 pt"])
                        .foregroundStyle(SettingsPalette.secondary)
                        .monospacedDigit()
                }
                Button {
                    withAnimation(.spring(duration: 0.4, bounce: 0.18)) {
                        updateLook { $0.unitOffset = .zero }
                        updateText { style in
                            style.size = nil
                            style.box = nil
                        }
                    }
                } label: {
                    Label("Put Back", systemImage: "arrow.uturn.backward").frame(maxWidth: .infinity)
                }
                .buttonBorderShape(.capsule)
                .help("Beside the marker, at its own size, in no box of its own")
                Text("Click it to set its type and colour; drag it to move it.")
                    .font(.caption)
                    .foregroundStyle(SettingsPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("The unit beside the marker: min, or hr and sec where the timer sets them too.")
                    .font(.caption)
                    .foregroundStyle(SettingsPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxHeight: .infinity, alignment: .center)
    }

    /// The name set in a box this large: its letters shrink to fit it.
    private func setBox(width: CGFloat, height: CGFloat) {
        guard width > 0, height > 0 else { return }
        updateText { $0.box = TextStyle.BoxSize(width: Double(width), height: Double(height)) }
    }

    private func updateLook(_ change: (inout RulerLook) -> Void) {
        model.editedWidgets.update(widget.id) { widget in
            var look = widget.rulerLook(of: id)
            change(&look)
            look.sanitize()
            widget.setRulerLook(look, of: id)
        }
    }

    private func updateText(_ change: (inout TextStyle) -> Void) {
        model.editedWidgets.update(widget.id) { widget in
            var style = widget.textStyle(of: .rulerUnit)
            change(&style)
            style.sanitize()
            widget.setTextStyle(style, of: .rulerUnit)
        }
    }
}
