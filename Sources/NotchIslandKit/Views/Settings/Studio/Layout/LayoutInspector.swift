import AppKit
import SwiftUI

// The grid inside the widget, in the Customize inspector and on the canvas's bar: one element's
// frame (in points of the widget, as the canvas's size badge reads), what holds it when the widget is resized, its order; the
// commands for several picked at once; the grid's density; and what can be added.

/// One placed element: whether it lies over what it overlaps or under it, its frame in points, and
/// whether it keeps its shape as it is resized.
struct FrameInspector: View {
    let session: EditorSession
    let id: ElementID

    var body: some View {
        if let layout = session.drawnLayout, let item = layout.items.first(where: { $0.id == id }),
           let frame = session.elementFrame(id) {
            InspectorSection("Layer") {
                Picker("", selection: Binding(get: { LayoutEdit.layer(of: id, in: layout) }, set: { layer in
                    withAnimation(Motion.content) { session.editLayout { LayoutEdit.setLayer(layer, [id], in: &$0) } }
                })) {
                    ForEach(LayoutEdit.Layer.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .choiceBar()
                .fixedSize()
                Text("In Front: drawn over what it lies on. Behind: what it lies on covers it.")
                    .font(.caption)
                    .foregroundStyle(SettingsPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            InspectorSection("Frame", trailing: AnyView(Text("in points").font(.caption).foregroundStyle(SettingsPalette.secondary))) {
                HStack(spacing: 8) {
                    pointField("X", frame.minX) { value in set(frame) { $0.origin.x = value } }
                    pointField("Y", frame.minY) { value in set(frame) { $0.origin.y = value } }
                }
                HStack(spacing: 8) {
                    pointField("W", frame.width) { value in set(frame) { $0.size.width = max(value, 1) } }
                    pointField("H", frame.height) { value in set(frame) { $0.size.height = max(value, 1) } }
                }
                InspectorRow("Keep Shape", isSet: item.keepsAspect, reset: { session.editLayout { LayoutEdit.setKeepsAspect(false, [id], in: &$0) } }) {
                    Toggle("", isOn: Binding(get: { item.keepsAspect }, set: { on in
                        session.editLayout { LayoutEdit.setKeepsAspect(on, [id], in: &$0) }
                    }))
                    .labelsHidden()
                    .toggleStyle(.islandSwitch)
                    .help("On: four corner handles, and it grows and shrinks as a whole. Off: eight handles (hold ⇧ to keep its shape once).")
                }
                Text(item.keepsAspect ? "Resized from its four corners, as a whole."
                                      : "Resized by eight handles: its width and height change on their own.")
                    .font(.caption)
                    .foregroundStyle(SettingsPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The frame typed in, in the widget's points at the size on the canvas: text by the same rule
    /// as a handle dragged to it (`EditorSession.setFrame`).
    private func set(_ frame: CGRect, _ edit: (inout CGRect) -> Void) {
        var rect = frame
        edit(&rect)
        withAnimation(Motion.content) { session.setFrame(rect, of: id) }
    }

    private func pointField(_ title: String, _ value: CGFloat, set: @escaping (CGFloat) -> Void) -> some View {
        let shown = (Double(value) * 2).rounded() / 2
        return HStack(spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(SettingsPalette.secondary)
                .frame(width: 14, alignment: .leading)
            TextField(title, value: Binding(get: { shown }, set: { new in
                if abs(new - shown) >= 0.25 { set(CGFloat(new)) }
            }), format: .number.precision(.fractionLength(0...1)))
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(title == "X" ? "Left edge" : title == "Y" ? "Top edge" : title == "W" ? "Width" : "Height")
            Stepper("", value: Binding(get: { shown }, set: { set(CGFloat($0)) }), step: 1)
                .labelsHidden()
                .controlSize(.small)
        }
    }
}

/// The six alignments.
private struct AlignButtons: View {
    let perform: (LayoutEdit.Alignment) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(LayoutEdit.Alignment.allCases, id: \.self) { alignment in
                Button { withAnimation(Motion.content) { perform(alignment) } } label: {
                    Image(systemName: alignment.systemImage).frame(width: 20, height: 18)
                }
                .help(alignment.title)
                .accessibilityLabel(alignment.title)
            }
        }
        .buttonStyle(.borderless)
    }
}

private struct OrderButtons: View {
    let perform: (LayoutEdit.Order) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(LayoutEdit.Order.allCases, id: \.self) { order in
                Button { withAnimation(Motion.content) { perform(order) } } label: {
                    Image(systemName: order.systemImage).frame(width: 22, height: 18)
                }
                .help(order.title)
                .accessibilityLabel(order.title)
            }
        }
        .buttonStyle(.borderless)
    }
}

/// Several elements picked: aligned, spaced, ordered, locked and hidden together.
struct ArrangeInspector: View {
    let session: EditorSession

    var body: some View {
        let ids = session.selection
        let canArrange = session.supportsCustomLayout
        VStack(alignment: .leading, spacing: 12) {
            Text("\(ids.count) elements picked. Drag them together, or arrange them here; pick one to change its look.")
                .font(.callout)
                .foregroundStyle(SettingsPalette.secondary)
            InspectorSection("Arrange") {
                InspectorRow("Align", isSet: false, reset: {}) {
                    AlignButtons { alignment in session.editLayout { LayoutEdit.align(ids, alignment, in: &$0) } }
                }
                InspectorRow("Distribute", isSet: false, reset: {}) {
                    HStack(spacing: 2) {
                        ForEach(LayoutEdit.Distribution.allCases, id: \.self) { axis in
                            Button { withAnimation(Motion.content) { session.editLayout { LayoutEdit.distribute(ids, axis, in: &$0) } } } label: {
                                Image(systemName: axis.systemImage).frame(width: 22, height: 18)
                            }
                            .help(axis.title)
                            .accessibilityLabel(axis.title)
                        }
                    }
                    .buttonStyle(.borderless)
                    .disabled(ids.count < 3)
                }
                InspectorRow("Order", isSet: false, reset: {}) {
                    OrderButtons { order in session.editLayout { LayoutEdit.reorder(ids, order, in: &$0) } }
                }
                Button("Hide", systemImage: "eye.slash") { withAnimation(Motion.content) { session.hideSelection() } }
                    .controlSize(.small)
            }
            .disabled(!canArrange)
        }
    }
}

/// With nothing picked, in a custom layout: the editing grid, the mirror, and the way back.
struct LayoutGridInspector: View {
    let session: EditorSession

    var body: some View {
        if let layout = session.drawnLayout {
            InspectorSection("Custom Layout") {
                InspectorRow("Grid", isSet: false, reset: {}) {
                    Picker("", selection: Binding(get: { LayoutEdit.density(of: layout) }, set: { density in
                        session.editLayout { LayoutEdit.setDensity(density, in: &$0) }
                    })) {
                        ForEach(LayoutEdit.Density.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .choiceBar()
                    .controlSize(.small)
                    .fixedSize()
                    .help("How fine the grid the elements land on is. Nothing placed moves.")
                }
                // Two equal buttons across the pane.
                HStack(spacing: 8) {
                    Button {
                        withAnimation(Motion.content) { session.editLayout { LayoutEdit.flipHorizontally(&$0) } }
                    } label: {
                        Label("Flip", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                            .frame(maxWidth: .infinity)
                    }
                    .help("Flip Horizontally: mirror the layout left to right")
                    Button {
                        session.selection = Set(layout.items.map(\.id))
                    } label: {
                        Label("Pick All", systemImage: "checkmark.circle").frame(maxWidth: .infinity)
                    }
                    .keyboardShortcut("a", modifiers: .command)
                }
                .controlSize(.small)
                let tray = session.trayElements
                if !tray.isEmpty {
                    Text("Not on the widget")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(SettingsPalette.secondary)
                        .padding(.top, 4)
                    ForEach(tray, id: \.id) { element in
                        HStack(spacing: 8) {
                            Image(systemName: element.symbol).frame(width: 18)
                            Text(element.title).font(.callout).lineLimit(1)
                            Spacer(minLength: 0)
                            Button("Place") { withAnimation(Motion.content) { session.placeFromTray(element.id) } }
                                .controlSize(.small)
                        }
                    }
                }
            }
        }
    }
}

/// On the canvas, under the widget: how it is laid out (its kind's own way, or freely), what this
/// size draws, and what can be added.
struct CanvasLayoutBar: View {
    let session: EditorSession

    var body: some View {
        let state = session.layoutState
        if state != .unsupported {
            HStack(spacing: 8) {
                Picker("Layout", selection: Binding(get: { state.isCustom || state == .automaticHere }, set: { custom in
                    withAnimation(Motion.content) { session.setCustomLayout(custom) }
                })) {
                    Text("Automatic").tag(false)
                    Text("Custom").tag(true)
                }
                .choiceBar()
                .labelsHidden()
                .fixedSize()
                .help("Automatic: the widget arranges its elements. Custom: drag them where you like.")
                if let note = note(state) {
                    Menu {
                        Button("Customize This Size") { withAnimation(Motion.content) { session.customizeThisSize() } }
                            .disabled(state == .custom)
                        Button("Use Automatic Here") { withAnimation(Motion.content) { session.useAutomaticHere() } }
                            .disabled(state == .automaticHere)
                    } label: {
                        Label(note, systemImage: state == .custom ? "checkmark.circle" : "arrow.triangle.2.circlepath")
                            .labelStyle(.titleAndIcon)
                    }
                    .fixedSize()
                    .help("Each shape of the widget can have a layout of its own; a shape without one reflows the nearest.")
                }
                Menu {
                    Button("Label", systemImage: "textformat") { add(.label("Label")) }
                    Menu("Symbol") {
                        ForEach(["star.fill", "heart.fill", "bolt.fill", "circle.fill", "music.note", "clock", "flame.fill", "leaf.fill",
                                 "moon.fill", "sun.max.fill"], id: \.self) { name in
                            Button { add(.symbol(name)) } label: { Label(name, systemImage: name) }
                        }
                    }
                    Button("Divider", systemImage: "minus") { add(.divider(.horizontal)) }
                    Button("Vertical Divider", systemImage: "line.diagonal") { add(.divider(.vertical)) }
                    Menu("Shape") {
                        ForEach(DecorationShape.allCases, id: \.self) { shape in
                            Button(shape.title, systemImage: shape.systemImage) { add(.shape(shape)) }
                        }
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .fixedSize()
                .help("Add a label, a symbol, a divider or a shape of your own")
            }
            .controlSize(.small)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .glassEffect(Glass.regular.tint(Color.black.opacity(0.35)), in: .capsule)
        }
    }

    private func add(_ decoration: Decoration) {
        withAnimation(Motion.content) { session.addDecoration(decoration) }
    }

    /// What the size on the canvas draws, once the widget is laid out freely.
    private func note(_ state: LayoutState) -> String? {
        switch state {
        case .custom: String(localized: "This Size")
        case .reflowed(let source): String(localized: "From the \(source.title) one")
        case .automaticHere: String(localized: "Automatic Here")
        case .automatic, .unsupported: nil
        }
    }
}
