import SwiftUI

/// Under the stage in Size mode: the panel's board by its cells (`PanelSettings`, `BoardSizing`).
/// Its cells' size — the same room divided into more, smaller cells or fewer, larger ones — and the
/// gap between them; how many columns and rows (as the handles on the stage set them, one at a
/// time). Under them, Reset Size and the island's ready-made sizes, which open over all of it and
/// make everything larger or smaller together. Nothing here changes a widget's shape: each keeps
/// its cells.
struct SizeInspector: View {
    @Environment(AppModel.self) private var model
    /// The board's room when the Cell slider was taken: the cells divide that room.
    @State private var cellRoom: CGSize?
    /// The panel when the Gap slider was taken: its range stays as it was while it moves.
    @State private var gapBase: PanelSettings?

    private static let settle: Animation = .spring(duration: 0.3, bounce: 0.1)

    var body: some View {
        let studio = model.studio
        let panel = studio.draft?.panel ?? model.preferences.panel
        let layout = model.layout.replacing(panel: panel.layout)
        let island = layout.size(for: .expanded(.home))
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                StudioCard("Cells", subtitle: "\(Int(panel.cell)) pt square, \(Int(panel.gap)) pt apart") {
                    VStack(spacing: 8) {
                        SliderRow(title: "Size", value: "\(Int(panel.cell)) pt",
                                  widest: "\(Int(PanelSettings.cellRange.upperBound)) pt") {
                            Slider(value: Binding(get: { panel.cell }, set: { new in
                                let room = cellRoom ?? BoardSizing.board(model.layout)
                                draft(BoardSizing.dividing(room, into: new.rounded(), from: panel, layout: model.layout))
                            }), in: PanelSettings.cellRange) { editing in
                                cellRoom = editing ? BoardSizing.board(model.layout) : nil
                                if !editing { commit() }
                            } label: { Text("Cell size") }
                        }
                        .help("Smaller cells fit more widgets in the same room; larger ones, fewer and larger")
                        let gaps = BoardSizing.gapRange(gapBase ?? panel)
                        SliderRow(title: "Gap", value: "\(Int(panel.gap)) pt",
                                  widest: "\(Int(PanelSettings.gapRange.upperBound)) pt") {
                            Slider(value: Binding(get: { min(max(panel.gap, gaps.lowerBound), gaps.upperBound) }, set: { new in
                                draft(BoardSizing.withGap(new, gapBase ?? panel))
                            }), in: gaps) { editing in
                                gapBase = editing ? panel : nil
                                if !editing { commit() }
                            } label: { Text("Gap") }
                        }
                        .help("The space between the widgets: the panel keeps its size, the widgets get a little smaller or larger")
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                }
                .frame(maxWidth: .infinity)
                StudioCard("Panel", subtitle: "\(Int(island.width)) × \(Int(island.height)) pt  ·  \(panel.columns) × \(panel.rows) cells") {
                    VStack(spacing: 8) {
                        countRow("Width", value: panel.columns, range: layout.columnRange, unit: "columns") { count in
                            var next = panel
                            next.columns = count
                            return next
                        }
                        countRow("Height", value: panel.rows, range: layout.rowRange, unit: "rows") { count in
                            var next = panel
                            next.rows = count
                            return next
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                }
                .frame(maxWidth: .infinity)
            }
            // The two cards as tall as each other.
            .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                // Back to exactly what Size mode found: the cells, the ready-made size, every
                // widget where it was.
                Button {
                    guard let entry = studio.sizeEntry else { return }
                    cellRoom = nil
                    gapBase = nil
                    withAnimation(Self.settle) {
                        studio.draft = nil
                        model.restoreSize(entry)
                    }
                } label: {
                    Label("Reset Size", systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity)
                }
                .disabled(studio.sizeEntry.map { $0 == model.sizeSnapshot() && studio.draft == nil } ?? true)
                .help("Everything back as it was when Size was opened")
                Button {
                    studio.toggleReadyMade()
                } label: {
                    HStack(spacing: 6) {
                        Text("Ready-made Size")
                        Spacer(minLength: 8)
                        Text(model.preferences.scale.title).foregroundStyle(SettingsPalette.secondary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(SettingsPalette.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .help("The whole panel larger or smaller: its cells, the gap and every widget together")
                // The ready-made sizes unfold out of it (`ReadyMadeBox`).
                .anchorPreference(key: ReadyMadeAnchors.self, value: .bounds) { [.button: $0] }
            }
            .controlSize(.large)
            .buttonBorderShape(.capsule)
        }
        // Where the ready-made sizes open: over the cards and the buttons, down to the window's
        // bottom (`WidgetsSettingsPage`).
        .transformAnchorPreference(key: ReadyMadeAnchors.self, value: .bounds) { $0[.area] = $1 }
    }

    /// Columns or rows, one at a time: added or taken away at both sides (columns) or the bottom.
    private func countRow(_ title: String, value: Int, range: ClosedRange<Int>, unit: String,
                          with: @escaping (Int) -> PanelSettings) -> some View {
        SliderRow(title: title, value: "\(value) \(unit)", widest: "\(range.upperBound) \(unit)") {
            Slider(value: Binding(get: { Double(min(max(value, range.lowerBound), range.upperBound)) }, set: { new in
                draft(with(Int(new.rounded())))
            }), in: Double(range.lowerBound)...Double(max(range.upperBound, range.lowerBound + 1)), step: 1) { editing in
                if !editing { commit() }
            } label: { Text(title) }
        }
    }

    /// The stage follows the slider; nothing is stored until it is let go.
    private func draft(_ panel: PanelSettings) {
        guard model.studio.draft?.panel != panel else { return }
        SnapTick.perform()
        model.studio.draft = StudioDraft(panel: panel)
    }

    private func commit() {
        guard let draft = model.studio.draft else { return }
        withAnimation(Self.settle) {
            model.setPanel(draft.panel, leadingColumns: draft.leadingColumns)
            model.studio.draft = nil
        }
    }
}

/// Where Size mode's ready-made sizes come from and open to, for the page to lay them out over
/// its scroll view (`ReadyMadePanel`).
struct ReadyMadeAnchors: PreferenceKey {
    enum Part { case button, area }
    static let defaultValue: [Part: Anchor<CGRect>] = [:]
    static func reduce(value: inout [Part: Anchor<CGRect>], nextValue: () -> [Part: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

/// The island's ready-made sizes (the pictures of General ▸ Size when open) on the Size mode's
/// controls: opened and closed exactly as Customize's Open Widgets (`WidgetVersionsMenu`) — the box
/// on Settings' ground grows out of the Ready-made button to cover the cards and the buttons, its
/// corners from the capsule's to the list's, and what is on it comes up out of a blur once it is
/// under way. The button being at the bottom right, the box grows up and to the left. A click
/// beside it closes it.
struct ReadyMadeBox: View {
    /// The button, and the room it opens over, in the space it is laid out in.
    let button: CGRect
    let area: CGRect

    @Environment(AppModel.self) private var model

    var body: some View {
        let studio = model.studio
        let isOpen = studio.showsReadyMade
        let rect = isOpen ? area : button
        let radius = isOpen ? WidgetVersionsMenu.radius : button.height / 2
        ZStack(alignment: .topLeading) {
            // A click anywhere but on it closes it (and does nothing else).
            if isOpen {
                Color.clear
                    .contentShape(Rectangle().subtracting(Rectangle().path(in: area)))
                    .onTapGesture { studio.toggleReadyMade() }
            }
            ReadyMadePanel(close: { studio.toggleReadyMade() })
                .frame(width: area.width, height: area.height)
                // Comes up out of a blur and a little from below as the box opens around it.
                .opacity(studio.readyMadeContentIn ? 1 : 0)
                .blur(radius: studio.readyMadeContentIn ? 0 : 6)
                .offset(y: studio.readyMadeContentIn ? 0 : 10)
                .frame(width: rect.width, height: rect.height, alignment: .bottomTrailing)
                .background { SettingsBackdrop() }
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                }
                .shadow(color: .black.opacity(isOpen ? 0.5 : 0), radius: 18, y: 8)
                .opacity(isOpen ? 1 : 0)
                .allowsHitTesting(isOpen)
                .offset(x: rect.minX, y: rect.minY)
        }
        // Closed from elsewhere: what is on it goes with it.
        .onChange(of: isOpen) { _, open in
            if !open, studio.readyMadeContentIn { withAnimation(.easeIn(duration: 0.12)) { studio.readyMadeContentIn = false } }
        }
    }
}

/// What the ready-made sizes' box holds: its title, Done, and the sizes. Picked, a size is set at
/// once (the stage follows); Done or Esc closes them.
struct ReadyMadePanel: View {
    let close: () -> Void

    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Ready-made Size").font(.headline)
                Spacer(minLength: 12)
                Button("Done", action: close)
                    .keyboardShortcut(.cancelAction)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
            }
            PictureChoice(options: IslandScale.allCases, selection: Binding(get: { model.preferences.scale }, set: { scale in
                model.preferences.scale = scale
                // The same cells at another scale: as many as still fit.
                model.setPanel(BoardSizing.fitted(model.preferences.panel, layout: model.layout))
            }), title: \.title) { scale in
                IslandSizePicture(scale: scale)
            }
            // In the middle of the room under the title.
            .frame(maxHeight: .infinity)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// One slider on one line: its name, the slider, and its value in a width that does not change.
private struct SliderRow<Control: View>: View {
    let title: String
    let value: String
    let widest: String
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .foregroundStyle(SettingsPalette.secondary)
                .frame(width: 52, alignment: .leading)
            control
                .labelsHidden()
                .tint(Color.islandAccent)
            ReservedWidthText(value, fitting: [widest])
                .font(.callout.monospacedDigit())
                .foregroundStyle(SettingsPalette.secondary)
        }
    }
}

/// The widgets a smaller grid (or a board saved on a larger one) left no room for: put back where
/// there is room again, or removed.
struct ParkedTray: View {
    @Environment(AppModel.self) private var model
    @State private var refused: WidgetID?

    var body: some View {
        let parked = model.editedWidgets.board.parked
        if !parked.isEmpty {
            StudioCard("Didn't Fit (\(parked.count))", subtitle: "Set aside, with their looks kept. Make room on the island, then put them back.") {
                VStack(spacing: 0) {
                    ForEach(Array(parked.enumerated()), id: \.element.id) { index, widget in
                        if index > 0 { Divider().opacity(0.5) }
                        HStack(spacing: 10) {
                            WidgetIcon(kind: widget.kind, side: 26)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(widget.kind.title)
                                if refused == widget.id {
                                    Text("No room for it yet").font(.caption).foregroundStyle(.orange)
                                }
                            }
                            Spacer(minLength: 8)
                            Button("Put Back") {
                                var restored = false
                                withAnimation(.spring(duration: 0.35, bounce: 0.2)) { restored = model.editedWidgets.restore(widget.id) }
                                if restored {
                                    refused = nil
                                } else {
                                    NSSound.beep()
                                    refused = widget.id
                                }
                            }
                            Button("Remove", role: .destructive) {
                                withAnimation(.spring(duration: 0.3)) { model.editedWidgets.remove(widget.id) }
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
            .transition(.opacity)
        }
    }
}
