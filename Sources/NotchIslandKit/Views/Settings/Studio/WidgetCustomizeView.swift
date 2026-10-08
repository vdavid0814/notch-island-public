import Observation
import SwiftUI

/// Whether Customize is shown, for its own growing out of the notch and back (`SettingsSurfaceView`
/// sets it; the view animates it).
@Observable final class CustomizePresentation {
    var isShown = false
}

/// One widget's Customize, over all of Settings' area, on Settings' own ground (black at the notch
/// easing into grey): black boxes laid out like Settings' sidebar — the panel with everything the
/// widget can be set to on the left, as wide a panel on the right, a band as tall along the bottom
/// and a lower one along the top — and between them a black editor on graph paper with the widget
/// as large as the room allows. Every box keeps the sidebar's insets and corners (the outer lower
/// ones concentric with the island's). It comes in in steps — the panels from their sides, then
/// the editor and the widget growing into place — and goes out the other way.
struct WidgetCustomizeView: View {
    let id: WidgetID
    let placement: SettingsPlacement
    let presentation: CustomizePresentation
    let close: () -> Void

    @Environment(AppModel.self) private var model
    @State private var panelsIn = false
    @State private var editorIn = false
    @State private var editing = ElementEditing()
    @State private var versions = WidgetVersionStore()

    /// The side panels' width (the band along the bottom is as tall): room for the colour mixer,
    /// a tenth under the sidebar's 340 of before.
    static let panelWidth: CGFloat = 306
    /// The band along the top, about 60 % lower than the others.
    static let topBandRatio: CGFloat = 0.4
    /// Settings' own corners, as on the sidebar.
    static let radius: CGFloat = 16
    /// Around the widget inside the editor.
    static let editorMargin: CGFloat = 40
    /// From the start of going out until it can be taken away.
    static let outDuration: TimeInterval = 0.4

    var body: some View {
        GeometryReader { proxy in
            let gap = placement.gap
            // The band along the bottom as thick as the side panels, but never more than a third of
            // the height; the one along the top 40 % of it.
            let bottom = min(Self.panelWidth, (proxy.size.height - 4 - gap) / 3).rounded()
            let top = (bottom * Self.topBandRatio).rounded()
            // The middle what the panels and their gaps leave: nothing in it can widen it and push
            // a panel past Settings' edge, and every gap stays the same.
            let middle = max(0, proxy.size.width - 2 * placement.leading - 2 * Self.panelWidth - 2 * gap)
            if let widget = model.editedWidgets.board.widget(id) {
                HStack(spacing: gap) {
                    CustomizePanel(widget: widget, addFigure: addFigure)
                        .frame(width: Self.panelWidth)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .background(BlackBox(shape: side(leading: true)))
                        .offset(x: panelsIn ? 0 : -40)
                        .opacity(panelsIn ? 1 : 0)
                    VStack(spacing: gap) {
                        CustomizeTopBar(widget: widget, editing: editing, versions: versions, close: close)
                            .frame(height: top)
                            .background(BlackBox(shape: box))
                            .offset(y: panelsIn ? 0 : -24)
                            .opacity(panelsIn ? 1 : 0)
                            // Its Open Widget grows into a list down over the editor.
                            .zIndex(1)
                        // Before and after: the widget as Customize found it, looked at, not edited.
                        editor(editing.showsOriginal ? (editing.original ?? widget) : widget)
                            .allowsHitTesting(!editing.showsOriginal)
                            .overlay(alignment: .topLeading) {
                                if editing.showsOriginal {
                                    Label("Before", systemImage: "clock.arrow.circlepath")
                                        .font(.callout.weight(.semibold))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color.accentColor, in: .capsule)
                                        .padding(14)
                                        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .topLeading)))
                                }
                            }
                            .scaleEffect(editorIn ? 1 : 0.94)
                            .opacity(editorIn ? 1 : 0)
                        // A picked line's parts, or a picked button's symbol, placed and sized.
                        Group {
                            if let picked = editing.selected, widget.kind.spec.progressBars.contains(picked) {
                                ProgressPartsPanel(widget: widget, editing: editing, id: picked)
                            } else if let picked = editing.selected, widget.kind.spec.rulers.contains(picked) {
                                RulerPartsPanel(widget: widget, editing: editing, id: picked)
                            } else if let picked = editing.selected, let figure = widget.figure(picked) {
                                FigurePanel(widget: widget, figure: figure)
                            } else {
                                ButtonSymbolPanel(widget: widget, editing: editing)
                            }
                        }
                            .frame(height: bottom)
                            .background(BlackBox(shape: box))
                            .offset(y: panelsIn ? 0 : 24)
                            .opacity(panelsIn ? 1 : 0)
                    }
                    .frame(width: middle)
                    // Its pictures where their fit puts them, as the editor draws them.
                    ElementInspector(widget: IslandWidgetView.resolved(widget, size: natural(of: widget)), editing: editing)
                        .frame(width: Self.panelWidth)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .background(BlackBox(shape: side(leading: false)))
                        .offset(x: panelsIn ? 0 : 40)
                        .opacity(panelsIn ? 1 : 0)
                }
                .padding(.horizontal, placement.leading)
                .padding(.bottom, gap)
                .padding(.top, 4)
            }
        }
        // The saved versions open: a click anywhere but on them closes them (and does nothing else).
        .overlay {
            if editing.showsVersions {
                Color.clear
                    .contentShape(Rectangle().subtracting(Rectangle().path(in: editing.versionsFrame)))
                    .onTapGesture {
                        withAnimation(.spring(duration: 0.38, bounce: 0.08)) { editing.showsVersions = false }
                    }
            }
        }
        .coordinateSpace(.named(ElementEditing.space))
        .onChange(of: model.editedWidgets.board.widget(id)) { old, new in
            if let old, let new, old.id == new.id { editing.record(old, new) }
            // A change shows the widget as it is now.
            if editing.showsOriginal { editing.showsOriginal = false }
        }
        // Another part picked: none of a line's parts.
        .onChange(of: editing.selected) {
            editing.progressPart = nil
            editing.picksRulerUnit = false
            editing.linePreview = nil
        }
        // Another widget: its own history, nothing picked, the versions closed, its before.
        .onChange(of: id) {
            editing = ElementEditing()
            anchor()
            editing.original = model.editedWidgets.board.widget(id)
        }
        .onAppear {
            anchor()
            if editing.original == nil { editing.original = model.editedWidgets.board.widget(id) }
        }
        .onAppear { animate(presentation.isShown) }
        .onChange(of: presentation.isShown) { _, shown in
            animate(shown)
            // Opened again: before is now.
            if shown {
                anchor()
                editing.original = model.editedWidgets.board.widget(id)
                editing.showsOriginal = false
            }
        }
    }

    /// A side panel: the sidebar's shape, its outer lower corner concentric with the island's.
    private func side(leading: Bool) -> UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: Self.radius,
                               bottomLeadingRadius: leading ? placement.outerRadius : Self.radius,
                               bottomTrailingRadius: leading ? Self.radius : placement.outerRadius,
                               topTrailingRadius: Self.radius, style: .continuous)
    }

    private var box: UnevenRoundedRectangle {
        UnevenRoundedRectangle(cornerRadii: .uniform(Self.radius), style: .continuous)
    }

    /// In: the panels, then the editor. Out: all together, quicker.
    private func animate(_ shown: Bool) {
        withAnimation(shown ? .spring(duration: 0.5, bounce: 0.14) : .easeIn(duration: 0.22)) { panelsIn = shown }
        withAnimation(shown ? .spring(duration: 0.6, bounce: 0.16).delay(0.08) : .easeIn(duration: 0.22)) { editorIn = shown }
    }

    /// Customize places the widget's parts at the size it is now: placed at another, they are
    /// taken along to this one (as the widget is drawn here, `IslandWidgetView.adapted`) and it is
    /// their size from now on. Not a change to undo.
    private func anchor() {
        guard let widget = model.editedWidgets.board.widget(id), widget.designSize != widget.frame.size else { return }
        var anchored = IslandWidgetView.adapted(widget, size: natural(of: widget))
        anchored.designSize = widget.frame.size
        editing.skipRecording(anchored)
        model.editedWidgets.update(id) { $0 = anchored }
    }

    /// A new shape in the middle of the widget, picked in the editor to be moved and sized.
    private func addFigure(_ kind: WidgetFigure.Kind) {
        let figure = WidgetFigure.new(kind)
        withAnimation(.spring(duration: 0.35, bounce: 0.14)) {
            model.editedWidgets.update(id) { widget in
                guard widget.figures.count < WidgetFigure.limit else { return }
                widget.figures.append(figure)
            }
        }
        if model.editedWidgets.board.widget(id)?.figure(figure.id) != nil { editing.selected = figure.id }
    }

    /// The widget's own size on the board.
    private func natural(of widget: IslandWidget) -> CGSize {
        WidgetBoardGeometry(size: WidgetsSettingsPage.boardSize(model.layout), grid: model.editedWidgets.board.grid)
            .frame(for: widget.frame).size
    }

    /// The widget on graph paper, as large as the editor allows (within its margin), its parts
    /// moved there (`WidgetElementEditor`).
    private func editor(_ widget: IslandWidget) -> some View {
        GeometryReader { proxy in
            let geometry = WidgetBoardGeometry(size: WidgetsSettingsPage.boardSize(model.layout), grid: model.editedWidgets.board.grid)
            let natural = geometry.frame(for: widget.frame).size
            let room = CGSize(width: max(proxy.size.width - 2 * Self.editorMargin, 40),
                              height: max(proxy.size.height - 2 * Self.editorMargin, 40))
            let scale = min(room.width / natural.width, room.height / natural.height, 4)
            WidgetElementEditor(widget: IslandWidgetView.resolved(widget, size: natural), natural: natural, scale: scale,
                                isIn: editorIn, editing: editing)
        }
        .background { GraphPaper() }
        .background(BlackBox(shape: box))
        .clipShape(box)
    }
}

/// A black box in Settings' corners, with a hairline edge.
private struct BlackBox: View {
    let shape: UnevenRoundedRectangle

    var body: some View {
        shape.fill(.black).overlay { shape.strokeBorder(.white.opacity(0.08)) }
    }
}

/// Graph paper: a faint line every 16 points, a stronger one every 64. Drawn once; nothing moves.
private struct GraphPaper: View {
    var body: some View {
        Canvas { context, size in
            for (step, opacity) in [(CGFloat(16), 0.05), (64, 0.1)] {
                var path = Path()
                var x = step
                while x < size.width {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                    x += step
                }
                var y = step
                while y < size.height {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    y += step
                }
                context.stroke(path, with: .color(.white.opacity(opacity)), lineWidth: 1)
            }
        }
    }
}

/// Everything a widget can be set to, compact: its name, its background (and the colour and strength
/// under it), and a switch for each of its elements.
private struct CustomizePanel: View {
    let widget: IslandWidget
    let addFigure: (WidgetFigure.Kind) -> Void

    @Environment(AppModel.self) private var model
    @State private var isMixing = false

    var body: some View {
        let kind = widget.kind
        ScrollView {
            VStack(alignment: .leading, spacing: StudioDivider.spacing) {
                HStack(spacing: 10) {
                    WidgetIcon(kind: kind, side: 32)
                    Text(kind.title).font(.headline)
                    Text("\(widget.frame.width) × \(widget.frame.height)")
                        .font(.callout)
                        .foregroundStyle(SettingsPalette.secondary)
                        .monospacedDigit()
                    Spacer(minLength: 8)
                }
                StudioDivider()
                VStack(alignment: .leading, spacing: 10) {
                    Text("Background").font(.subheadline.weight(.semibold))
                    Picker("Background", selection: Binding(get: { widget.background }, set: { background in
                        withAnimation(.spring(duration: 0.4, bounce: 0.18)) { update { $0.background = background } }
                    })) {
                        ForEach(WidgetBackground.allCases) { Text($0.title).tag($0) }
                    }
                    .choiceBar(width: CustomizeView.innerWidth)
                    .labelsHidden()
                    .fixedSize()
                    if widget.background != .none {
                        BackgroundSettings(widget: widget, stacked: true, isMixing: $isMixing) { change in update(change) }
                            .transition(.opacity)
                    }
                }
                .animation(.spring(duration: 0.35, bounce: 0.12), value: widget.background)
                .animation(.spring(duration: 0.35, bounce: 0.12), value: isMixing)
                let switchable = kind.spec.elements.filter { !$0.isRequired }
                let size = WidgetBoardGeometry(size: WidgetsSettingsPage.boardSize(model.layout), grid: model.editedWidgets.board.grid)
                    .frame(for: widget.frame).size
                if !switchable.isEmpty {
                    StudioDivider()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Elements").font(.subheadline.weight(.semibold))
                            .padding(.bottom, 4)
                        ForEach(switchable, id: \.id) { element in
                            // No room at this size: off, and kept so (it comes back where there is).
                            let hasRoom = IslandWidgetView.hasRoom(for: element.id, in: widget, size: size)
                            HStack(spacing: 10) {
                                Image(systemName: element.symbol)
                                    .foregroundStyle(SettingsPalette.secondary)
                                    .frame(width: 22)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(element.title)
                                    if !hasRoom {
                                        Text("No room at this size")
                                            .font(.caption)
                                            .foregroundStyle(SettingsPalette.secondary)
                                    }
                                }
                                Spacer(minLength: 8)
                                Toggle(element.title, isOn: Binding(get: { hasRoom && widget.shows(element.id) }, set: { on in
                                    withAnimation(Motion.content) { model.editedWidgets.setOption(element.id, on, for: widget.id) }
                                }))
                                .toggleStyle(.switch)
                                .tint(Color.islandControlAccent)
                                .labelsHidden()
                                .controlSize(.small)
                                .disabled(!hasRoom)
                            }
                            .padding(.vertical, 3)
                            .help(hasRoom ? "" : "Make the widget larger to show it")
                        }
                    }
                }
                if !kind.spec.settings.isEmpty {
                    StudioDivider()
                    WidgetSettingsSection(widget: widget)
                }
                StudioDivider()
                figures
            }
            // Exactly the panel's inside: nothing in it (the mixer) can widen it.
            .frame(width: CustomizeView.innerWidth, alignment: .leading)
            .padding(16)
        }
        .scrollIndicators(.never)
    }

    private func update(_ change: (inout IslandWidget) -> Void) {
        model.editedWidgets.update(widget.id, change)
    }

    /// Shapes to add: each comes in the middle of the widget, to be moved and sized in the editor.
    private var figures: some View {
        let isFull = widget.figures.count >= WidgetFigure.limit
        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Shapes").font(.subheadline.weight(.semibold))
                Text(isFull ? "A widget holds \(WidgetFigure.limit) shapes at most." : "Add one, then move and size it in the editor.")
                    .font(.caption)
                    .foregroundStyle(SettingsPalette.secondary)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(WidgetFigure.Kind.allCases) { kind in
                    Button {
                        addFigure(kind)
                    } label: {
                        Image(systemName: kind.symbol)
                            .font(.system(size: 15, weight: .medium))
                            .frame(maxWidth: .infinity, minHeight: 26)
                    }
                    .buttonBorderShape(.capsule)
                    .help(Text("Add a \(kind.title.lowercased())"))
                    .accessibilityLabel(Text("Add \(kind.title)"))
                }
            }
            .disabled(isFull)
        }
    }
}

private enum CustomizeView {
    /// The panel's inside: the background's bar is made exactly as wide.
    static let innerWidth = WidgetCustomizeView.panelWidth - 32
}
