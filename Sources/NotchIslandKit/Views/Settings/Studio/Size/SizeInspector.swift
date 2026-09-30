import SwiftUI

/// Under the stage in Size mode: the open panel's size, and its board's cells — how many, how
/// large, and the gap between them (`BoardSizing`). Cells added keep their size and the panel
/// grows with them, unless its size is kept: then the cells get smaller instead.
struct SizeInspector: View {
    @Environment(AppModel.self) private var model
    @State private var blockedNote: String?

    private static let settle: Animation = .spring(duration: 0.3, bounce: 0.1)

    var body: some View {
        let studio = model.studio
        let panel = studio.draft?.panel ?? model.preferences.panel
        let layout = model.layout.replacing(panel: panel.layout)
        let island = layout.size(for: .expanded(.home))
        let grid = model.editedWidgets.board.grid
        let board = BoardSizing.board(layout)
        let cell = BoardSizing.cell(grid, board: board)
        let ranges = BoardSizing.factorRanges(model.layout)
        // Compact, the most used first: the stage above stays in sight while they change it.
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Size").font(.title3.weight(.semibold))
                    Text("Add cells, or drag the island's edges above. Each widget keeps its cells, so more cells are more room.")
                        .font(.callout)
                        .foregroundStyle(SettingsPalette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Button("Reset Size and Cells") {
                    withAnimation(Self.settle) {
                        studio.draft = nil
                        model.preferences.panel = PanelSettings()
                        model.editedWidgets.setGrid(.standard)
                    }
                    blockedNote = nil
                }
                .disabled(model.preferences.panel == PanelSettings() && grid == .standard)
            }
            countsBar(grid, panel: panel, cell: cell)
            if let blockedNote {
                Label(blockedNote, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(SettingsPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
            HStack(alignment: .top, spacing: 12) {
                StudioCard("Cells", subtitle: "\(Int(cell.width.rounded())) × \(Int(cell.height.rounded())) pt each, \(Int(grid.gap)) pt apart") {
                    VStack(spacing: 8) {
                        // A cell's size is the panel's share while the panel keeps its size.
                        cellRow("Width", value: cell.width, disabled: panel.keepsSize) { width in
                            CGSize(width: width, height: cell.height)
                        }
                        cellRow("Height", value: cell.height, disabled: panel.keepsSize) { height in
                            CGSize(width: cell.width, height: height)
                        }
                        SliderRow(title: "Gap", value: "\(Int(grid.gap)) pt", widest: "\(Int(BoardSizing.maximumCell)) pt") {
                            Slider(value: Binding(get: { Double(grid.gap) }, set: { new in
                                let gap = CGFloat(new.rounded())
                                guard gap != grid.gap else { return }
                                apply(BoardSizing.setGap(gap, panel: model.preferences.panel, grid: grid, layout: model.layout), animated: false)
                            }), in: Double(BoardGrid.gapRange.lowerBound)...Double(BoardGrid.gapRange.upperBound)) {
                                Text("Gap")
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                StudioCard("Panel", subtitle: "\(Int(island.width)) × \(Int(island.height)) pt") {
                    VStack(spacing: 8) {
                        factorRow("Width", value: panel.widthFactor, range: ranges.width) { panel, value in
                            var next = panel
                            next.widthFactor = value
                            return next
                        }
                        factorRow("Height", value: panel.boardHeightFactor, range: ranges.height) { panel, value in
                            var next = panel
                            next.boardHeightFactor = value
                            return next
                        }
                        HStack {
                            Text("Size when open").foregroundStyle(SettingsPalette.secondary)
                            Spacer(minLength: 8)
                            Picker("Size when open", selection: Binding(get: { model.preferences.scale }, set: { scale in
                                withAnimation(Self.settle) { model.preferences.scale = scale }
                            })) {
                                ForEach(IslandScale.allCases) { Text($0.title).tag($0) }
                            }
                            .labelsHidden()
                            .fixedSize()
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: Counts

    /// What is changed most, on one row: the columns, the rows, and whether the panel keeps its
    /// size as they change. Under each other where the row is too narrow.
    private func countsBar(_ grid: BoardGrid, panel: PanelSettings, cell: CGSize) -> some View {
        let columns = countControl("Columns", value: grid.columns, note: "One more at each side") { delta in
            setCounts(columns: grid.columns + 2 * delta, rows: grid.rows)
        }
        let rows = countControl("Rows", value: grid.rows, note: "At the bottom") { delta in
            setCounts(columns: grid.columns, rows: grid.rows + delta)
        }
        let keeps = HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Keep Panel Size").font(.subheadline.weight(.medium))
                Text(panel.keepsSize ? "New cells make all of them smaller" : "The panel grows with new cells")
                    .font(.caption)
                    .foregroundStyle(SettingsPalette.secondary)
            }
            Toggle("Keep Panel Size", isOn: Binding(get: { model.preferences.panel.keepsSize }, set: { on in
                model.preferences.panel.keepsSize = on
                blockedNote = nil
            }))
            .labelsHidden()
            .toggleStyle(.islandSwitch)
        }
        .help("On: the panel stays as it is, and every cell and the gap get smaller so new cells fit. Off: cells keep their size and the panel grows with them.")
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                columns
                Divider().frame(height: 30).padding(.horizontal, 18)
                rows
                Spacer(minLength: 18)
                keeps
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 0) {
                    columns
                    Divider().frame(height: 30).padding(.horizontal, 18)
                    rows
                }
                keeps
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SettingsPalette.card, in: .rect(cornerRadius: SettingsForm.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SettingsForm.cardRadius, style: .continuous).strokeBorder(SettingsPalette.cardStroke)
        }
    }

    private func countControl(_ title: String, value: Int, note: String, change: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.medium))
                Text(note).font(.caption).foregroundStyle(SettingsPalette.secondary)
            }
            Text("\(value)")
                .font(.title2.weight(.semibold).monospacedDigit())
                .frame(minWidth: 30, alignment: .trailing)
                .contentTransition(.numericText(value: Double(value)))
            // Every step is tried: one that cannot be taken says why.
            Stepper(title, onIncrement: { change(1) }, onDecrement: { change(-1) })
                .labelsHidden()
        }
        .fixedSize()
    }

    // MARK: Panel

    /// A proportion of the panel: the draft follows the slider, the preference is written on release.
    private func factorRow(_ title: String, value: Double, range: ClosedRange<Double>,
                           with: @escaping (PanelSettings, Double) -> PanelSettings) -> some View {
        let studio = model.studio
        return SliderRow(title: title, value: value.formatted(.percent.precision(.fractionLength(0))),
                         widest: range.upperBound.formatted(.percent.precision(.fractionLength(0)))) {
            Slider(value: Binding(get: { min(max(value, range.lowerBound), range.upperBound) }, set: { new in
                let snapped = (new / 0.01).rounded() * 0.01
                let next = with(studio.draft?.panel ?? model.preferences.panel, snapped)
                if studio.draft?.panel != next { studio.draft = StudioDraft(panel: next) }
            }), in: range) { editing in
                if !editing { commitDraft() }
            } label: {
                Text(title)
            }
        }
    }

    private func commitDraft() {
        guard let draft = model.studio.draft else { return }
        model.preferences.panel = draft.panel
        model.studio.draft = nil
    }

    // MARK: Cells

    /// A cell's width or height: the panel follows it while the slider moves (a draft), and is
    /// written on release.
    private func cellRow(_ title: String, value: CGFloat, disabled: Bool, size: @escaping (CGFloat) -> CGSize) -> some View {
        let studio = model.studio
        let range = Double(BoardSizing.minimumCell)...Double(BoardSizing.maximumCell)
        return SliderRow(title: title, value: "\(Int(value.rounded())) pt", widest: "\(Int(BoardSizing.maximumCell)) pt") {
            Slider(value: Binding(get: { min(max(Double(value), range.lowerBound), range.upperBound) }, set: { new in
                let grid = model.editedWidgets.board.grid
                let from = studio.draft?.panel ?? model.preferences.panel
                guard case .changed(let change) = BoardSizing.setCell(size(CGFloat(new.rounded())), panel: from, grid: grid,
                                                                       layout: model.layout),
                      studio.draft?.panel != change.panel else { return }
                studio.draft = StudioDraft(panel: change.panel)
            }), in: range) { editing in
                if !editing { commitDraft() }
            } label: {
                Text(title)
            }
            .disabled(disabled)
        }
        .help(disabled ? "The panel keeps its size: its cells are its share. Turn off Keep Panel Size to set them." : "")
    }

    /// More or fewer columns or rows. Refused with its reason; taken with a note when a widget
    /// finds no room on the new grid (it is set aside, not lost).
    private func setCounts(columns: Int, rows: Int) {
        let grid = model.editedWidgets.board.grid
        let outcome = BoardSizing.setCounts(columns: columns, rows: rows, panel: model.preferences.panel, grid: grid, layout: model.layout)
        apply(outcome, animated: true)
    }

    private func apply(_ outcome: BoardSizing.Outcome, animated: Bool) {
        switch outcome {
        case .refused(let reason):
            NSSound.beep()
            withAnimation(.easeOut(duration: 0.15)) { blockedNote = reason }
        case .changed(let change):
            let board = model.editedWidgets.board
            let countsChange = change.grid.columns != board.grid.columns || change.grid.rows != board.grid.rows
            let aside = countsChange ? StudioGrid.setAside(by: change.grid, on: board, keepingCells: true) : []
            withAnimation(animated ? Self.settle : nil) {
                model.studio.draft = nil
                if model.preferences.panel != change.panel { model.preferences.panel = change.panel }
                if countsChange { model.editedWidgets.setGridKeepingCells(change.grid) } else { model.editedWidgets.setGrid(change.grid) }
                blockedNote = aside.isEmpty ? nil
                    : String(localized: "\(aside.formatted(.list(type: .and))) found no room on this grid: under Didn't Fit below.")
            }
        }
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
