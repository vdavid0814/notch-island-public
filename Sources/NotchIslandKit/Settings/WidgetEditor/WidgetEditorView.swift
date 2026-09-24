import AppKit
import SwiftUI

/// Customize Island: the open island at its real size on a desktop, with the widget gallery below and
/// an inspector beside it.
///
/// Widgets move freely under the pointer, and a ghost shows the whole cells they will land on; on
/// release they settle there. Guides light up when an edge lines up with another widget's edge or
/// the widget sits on the notch's centre line, and the trackpad ticks each time the landing place
/// changes.
struct WidgetEditorView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: IslandWidgetKind?
    @State private var thumbnails = ThumbnailCache()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                EditorStage(selection: $selection, thumbnails: thumbnails)
                Divider()
                WidgetInspector(selection: $selection)
                    .frame(width: 290)
            }
            Divider()
            WidgetGallery(selection: $selection)
                .frame(height: 230)
        }
        .environment(\.islandGlassStyle, model.preferences.glassStyle)
    }
}

// MARK: - Stage

/// A desktop with the island hanging from its top edge.
private struct EditorStage: View {
    @Binding var selection: IslandWidgetKind?
    let thumbnails: ThumbnailCache

    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.13, blue: 0.30),
                    Color(red: 0.32, green: 0.14, blue: 0.40),
                    Color(red: 0.86, green: 0.42, blue: 0.32),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay(alignment: .top) {
                // The menu bar the island hangs from.
                Rectangle().fill(.black.opacity(0.35)).frame(height: model.layout.notch.height)
            }
            .clipShape(.rect(cornerRadius: 14))
            .onTapGesture { selection = nil }

            VStack(spacing: 18) {
                IslandPreview(selection: $selection, thumbnails: thumbnails)
                Text("Drag a widget to move it, drag a corner to resize it. Everything snaps to the grid, so edges line up and the island stays symmetric.")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 38)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The open island exactly as the notch shows it, with an editable board for a home page.
private struct IslandPreview: View {
    @Binding var selection: IslandWidgetKind?
    let thumbnails: ThumbnailCache

    @Environment(AppModel.self) private var model
    @Environment(\.islandGlassStyle) private var style

    var body: some View {
        let layout = model.layout
        let presentation = IslandPresentation.expanded(.home)
        let size = layout.size(for: presentation)
        let split = NotchSplit(
            layout: layout,
            presentation: presentation,
            outerInset: Metrics.Expanded.horizontalInset,
            clearance: Metrics.notchClearance
        )
        let shape = IslandShape(bottomRadius: layout.bottomRadius(for: presentation),
                                shoulderRadius: layout.shoulderRadius(for: presentation))

        VStack(spacing: 0) {
            ExpandedHeader(split: split, height: layout.notch.height)
                .allowsHitTesting(false)
                .overlay {
                    // The camera housing.
                    UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8)
                        .fill(.black)
                        .frame(width: layout.notch.width, height: layout.notch.height)
                }
            BoardEditor(selection: $selection, thumbnails: thumbnails)
                .padding(.top, Metrics.Expanded.pageTopInset)
                .padding(.bottom, Metrics.Expanded.pageBottomInset)
                .padding(.horizontal, split.contentInset)
        }
        .frame(width: size.width, height: size.height)
        .controlSize(Metrics.controlSize(forScale: layout.scale.factor))
        .environment(\.appearsActive, true)
        .islandSurfaceShade(style, solidDepth: layout.notch.height, in: shape)
        .islandGlass(in: shape)
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
    }
}

// MARK: - Board editing

private enum Handle: CaseIterable {
    case topLeading, topTrailing, bottomLeading, bottomTrailing

    var movesLeading: Bool { self == .topLeading || self == .bottomLeading }
    var movesTop: Bool { self == .topLeading || self == .topTrailing }
}

/// A drag in progress: where the widget is under the pointer, and the cells it will land on.
private struct Interaction: Equatable {
    let kind: IslandWidgetKind
    /// nil while moving.
    let handle: Handle?
    let start: CGRect
    var live: CGRect
    var candidate: GridRect
    var isValid: Bool
}

private struct BoardEditor: View {
    @Binding var selection: IslandWidgetKind?
    let thumbnails: ThumbnailCache

    @Environment(AppModel.self) private var model
    @State private var interaction: Interaction?
    @FocusState private var isFocused: Bool

    private static let settle: Animation = .spring(duration: 0.32, bounce: 0.18)

    var body: some View {
        GeometryReader { proxy in
            let geometry = WidgetBoardGeometry(size: proxy.size, gap: WidgetMetrics.gap)
            let board = model.widgets.board
            ZStack(alignment: .topLeading) {
                GridLayer(geometry: geometry, isEmphasized: interaction != nil,
                          occupied: board.widgets.filter { $0.kind != interaction?.kind }.map(\.frame))
                    .contentShape(.rect)
                    .onTapGesture { selection = nil }

                if let interaction {
                    Guides(geometry: geometry, candidate: interaction.candidate,
                           others: board.widgets.filter { $0.kind != interaction.kind }.map(\.frame))
                    Ghost(frame: geometry.frame(for: interaction.candidate), rect: interaction.candidate,
                          isValid: interaction.isValid)
                }

                ForEach(board.widgets) { widget in
                    widgetView(widget, geometry: geometry)
                }
            }
            .coordinateSpace(.named(BoardSpace.name))
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
            nudge(press.key) ? .handled : .ignored
        }
        .onDeleteCommand {
            guard let selection else { return }
            withAnimation(Self.settle) { model.widgets.remove(selection) }
            self.selection = nil
        }
        .onChange(of: selection) { _, new in if new != nil { isFocused = true } }
    }

    @ViewBuilder private func widgetView(_ widget: IslandWidget, geometry: WidgetBoardGeometry) -> some View {
        let active = interaction?.kind == widget.kind ? interaction : nil
        let frame = active?.live ?? geometry.frame(for: widget.frame)
        let isSelected = selection == widget.kind
        let isMoving = active != nil && active?.handle == nil

        IslandWidgetView(widget: widget, size: frame.size, thumbnails: thumbnails)
            .allowsHitTesting(false)
            .overlay {
                RoundedRectangle(cornerRadius: min(WidgetMetrics.cornerRadius, frame.height / 2), style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : .white.opacity(0.14), lineWidth: isSelected ? 2 : 1)
            }
            .contentShape(.rect(cornerRadius: WidgetMetrics.cornerRadius))
            .scaleEffect(isMoving ? 1.03 : 1)
            .shadow(color: .black.opacity(isMoving ? 0.45 : 0), radius: 14, y: 6)
            .onTapGesture { selection = widget.kind }
            .gesture(moveGesture(widget, geometry: geometry))
            .overlay(alignment: .topLeading) {
                if isSelected, !isMoving {
                    ZStack(alignment: .topLeading) {
                        ForEach(Handle.allCases, id: \.self) { handle in
                            HandleDot()
                                .position(
                                    x: handle.movesLeading ? 0 : frame.width,
                                    y: handle.movesTop ? 0 : frame.height
                                )
                                .gesture(resizeGesture(widget, handle: handle, geometry: geometry))
                        }
                    }
                    .frame(width: frame.width, height: frame.height)
                }
            }
            .frame(width: frame.width, height: frame.height)
            .offset(x: frame.minX, y: frame.minY)
            .zIndex(active != nil ? 2 : (isSelected ? 1 : 0))
    }

    // MARK: Gestures

    private func moveGesture(_ widget: IslandWidget, geometry: WidgetBoardGeometry) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(BoardSpace.name))
            .onChanged { value in
                var current = interaction ?? begin(widget, handle: nil, geometry: geometry)
                current.live = current.start.offsetBy(dx: value.translation.width, dy: value.translation.height)
                update(&current, candidate: geometry.snappedMove(origin: current.live.origin, size: widget.frame.size))
                interaction = current
            }
            .onEnded { _ in finish() }
    }

    private func resizeGesture(_ widget: IslandWidget, handle: Handle, geometry: WidgetBoardGeometry) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(BoardSpace.name))
            .onChanged { value in
                var current = interaction ?? begin(widget, handle: handle, geometry: geometry)
                let start = current.start
                var minX = start.minX, maxX = start.maxX, minY = start.minY, maxY = start.maxY
                if handle.movesLeading { minX = min(start.minX + value.translation.width, maxX - 24) }
                else { maxX = max(start.maxX + value.translation.width, minX + 24) }
                if handle.movesTop { minY = min(start.minY + value.translation.height, maxY - 20) }
                else { maxY = max(start.maxY + value.translation.height, minY + 20) }
                current.live = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
                update(&current, candidate: geometry.snappedResize(
                    frame: current.live, from: widget.frame, kind: widget.kind,
                    movesLeading: handle.movesLeading, movesTop: handle.movesTop
                ))
                interaction = current
            }
            .onEnded { _ in finish() }
    }

    private func begin(_ widget: IslandWidget, handle: Handle?, geometry: WidgetBoardGeometry) -> Interaction {
        selection = widget.kind
        let frame = geometry.frame(for: widget.frame)
        return Interaction(kind: widget.kind, handle: handle, start: frame, live: frame,
                           candidate: widget.frame, isValid: true)
    }

    private func update(_ interaction: inout Interaction, candidate: GridRect) {
        if candidate != interaction.candidate {
            // The "click" of snapping: one tick per new landing place.
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        interaction.candidate = candidate
        interaction.isValid = model.widgets.board.isFree(candidate, for: interaction.kind)
    }

    private func finish() {
        guard let current = interaction else { return }
        withAnimation(Self.settle) {
            if current.isValid { model.widgets.setFrame(current.candidate, for: current.kind) }
            interaction = nil
        }
    }

    /// Arrow keys move the selected widget one cell, when there is room.
    private func nudge(_ key: KeyEquivalent) -> Bool {
        guard let selection, let widget = model.widgets.board.widget(selection) else { return false }
        var rect = widget.frame
        switch key {
        case .leftArrow: rect.column -= 1
        case .rightArrow: rect.column += 1
        case .upArrow: rect.row -= 1
        case .downArrow: rect.row += 1
        default: return false
        }
        var moved = false
        withAnimation(Self.settle) { moved = model.widgets.setFrame(rect, for: selection) }
        if !moved { NSSound.beep() }
        return true
    }
}

private enum BoardSpace { static let name = "widgetBoard" }

/// The cells, faint at rest and brighter while something is being dragged.
private struct GridLayer: View {
    let geometry: WidgetBoardGeometry
    let isEmphasized: Bool
    /// Cells under widgets are not drawn: the grid shows where there is room.
    let occupied: [GridRect]

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<WidgetBoard.rows, id: \.self) { row in
                ForEach(0..<WidgetBoard.columns, id: \.self) { column in
                    let cell = GridRect(column: column, row: row, width: 1, height: 1)
                    let frame = geometry.frame(for: cell)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.white.opacity(occupied.contains { $0.intersects(cell) } ? 0 : (isEmphasized ? 0.08 : 0.04)))
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                }
            }
        }
        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        .animation(.easeOut(duration: 0.15), value: isEmphasized)
    }
}

/// Where the dragged widget will land: accent when it fits, red when it would cover another one.
private struct Ghost: View {
    let frame: CGRect
    let rect: GridRect
    let isValid: Bool

    var body: some View {
        let tint = isValid ? Color.accentColor : .red
        RoundedRectangle(cornerRadius: min(WidgetMetrics.cornerRadius, frame.height / 2), style: .continuous)
            .fill(tint.opacity(0.16))
            .strokeBorder(tint.opacity(0.9), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            .overlay(alignment: .top) {
                Text("\(rect.width) × \(rect.height)")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(tint, in: Capsule())
                    .foregroundStyle(.white)
                    .offset(y: -9)
            }
            .frame(width: frame.width, height: frame.height)
            .offset(x: frame.minX, y: frame.minY)
            .animation(.spring(duration: 0.18, bounce: 0), value: frame)
            .allowsHitTesting(false)
    }
}

/// Lines for every edge the landing place shares with another widget, and for the centre line.
private struct Guides: View {
    let geometry: WidgetBoardGeometry
    let candidate: GridRect
    let others: [GridRect]

    var body: some View {
        let target = geometry.frame(for: candidate)
        let columns = Set(others.flatMap { [$0.column, $0.maxColumn] })
        let rows = Set(others.flatMap { [$0.row, $0.maxRow] })
        let size = geometry.size
        ZStack(alignment: .topLeading) {
            if candidate.isHorizontallyCentred {
                line(x: size.width / 2, color: .yellow)
            }
            if columns.contains(candidate.column) { line(x: target.minX, color: .accentColor) }
            if columns.contains(candidate.maxColumn) { line(x: target.maxX, color: .accentColor) }
            if rows.contains(candidate.row) { line(y: target.minY, color: .accentColor) }
            if rows.contains(candidate.maxRow) { line(y: target.maxY, color: .accentColor) }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    private func line(x: CGFloat, color: Color) -> some View {
        Rectangle().fill(color.opacity(0.85))
            .frame(width: 1, height: geometry.size.height + 16)
            .offset(x: x - 0.5, y: -8)
    }

    private func line(y: CGFloat, color: Color) -> some View {
        Rectangle().fill(color.opacity(0.85))
            .frame(width: geometry.size.width + 16, height: 1)
            .offset(x: -8, y: y - 0.5)
    }
}

private struct HandleDot: View {
    var body: some View {
        Circle()
            .fill(.white)
            .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 2))
            .frame(width: 12, height: 12)
            .shadow(color: .black.opacity(0.4), radius: 2)
            .frame(width: 26, height: 26)
            .contentShape(.rect)
            .onHover { inside in
                if inside { NSCursor.crosshair.push() } else { NSCursor.pop() }
            }
    }
}

// MARK: - Inspector

private struct WidgetInspector: View {
    @Binding var selection: IslandWidgetKind?

    @Environment(AppModel.self) private var model

    var body: some View {
        if let kind = selection, let widget = model.widgets.board.widget(kind) {
            Form {
                Section {
                    HStack(spacing: 12) {
                        WidgetIcon(kind: kind, side: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(kind.title).font(.headline)
                            Text(kind.summary).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section("Size") {
                    Stepper(value: dimension(widget, \.width), in: kind.minimumSize.width...kind.maximumSize.width) {
                        LabeledContent("Width", value: "\(widget.frame.width) of \(WidgetBoard.columns)")
                    }
                    Stepper(value: dimension(widget, \.height), in: kind.minimumSize.height...kind.maximumSize.height) {
                        LabeledContent("Height", value: "\(widget.frame.height) of \(WidgetBoard.rows)")
                    }
                    Button("Center on the Notch", systemImage: "align.horizontal.center") { center(widget) }
                        .disabled(widget.frame.isHorizontallyCentred || !canCenter(widget))
                }
                if !kind.options.isEmpty {
                Section("Controls") {
                    ForEach(kind.options) { option in
                        Toggle(option.title, isOn: Binding(
                            get: { widget.shows(option) },
                            set: { on in withAnimation(Motion.content) { model.widgets.setOption(option, on, for: kind) } }
                        ))
                    }
                }
                }
                Section {
                    Button("Remove from Island", systemImage: "minus.circle", role: .destructive) {
                        withAnimation(.spring(duration: 0.3)) { model.widgets.remove(kind) }
                        selection = nil
                    }
                }
            }
            .formStyle(.grouped)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "square.grid.3x2")
                    .font(.system(size: 34))
                    .foregroundStyle(.secondary)
                Text("Select a Widget").font(.headline)
                Text("Click a widget on the island to change its size and choose which controls it shows. Arrow keys move it one cell; Delete removes it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// A stepper binding that resizes from the top-left corner, sliding left or up when the widget
    /// would leave the board; refused with a beep when it would cover another widget.
    private func dimension(_ widget: IslandWidget, _ keyPath: WritableKeyPath<GridRect, Int>) -> Binding<Int> {
        Binding(
            get: { widget.frame[keyPath: keyPath] },
            set: { value in
                var rect = widget.frame
                rect[keyPath: keyPath] = value
                rect.column = min(rect.column, WidgetBoard.columns - rect.width)
                rect.row = min(rect.row, WidgetBoard.rows - rect.height)
                var done = false
                withAnimation(.spring(duration: 0.3, bounce: 0.15)) {
                    done = model.widgets.setFrame(rect, for: widget.kind)
                }
                if !done { NSSound.beep() }
            }
        )
    }

    private func centred(_ widget: IslandWidget) -> GridRect? {
        let free = WidgetBoard.columns - widget.frame.width
        guard free % 2 == 0 else { return nil }
        var rect = widget.frame
        rect.column = free / 2
        return rect
    }

    private func canCenter(_ widget: IslandWidget) -> Bool {
        centred(widget).map { model.widgets.board.isFree($0, for: widget.kind) } ?? false
    }

    private func center(_ widget: IslandWidget) {
        guard let rect = centred(widget) else { return }
        withAnimation(.spring(duration: 0.3, bounce: 0.15)) { _ = model.widgets.setFrame(rect, for: widget.kind) }
    }
}

// MARK: - Gallery

/// Every widget as a store card: add it, or select it when it is already on the island.
private struct WidgetGallery: View {
    @Binding var selection: IslandWidgetKind?

    @Environment(AppModel.self) private var model
    @State private var notice: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Widgets").font(.title2.weight(.bold))
                Text(notice ?? "Add a widget, then drag it into place.")
                    .font(.callout)
                    .foregroundStyle(notice == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
                Spacer()
                Button("Reset to Default") {
                    withAnimation(.spring(duration: 0.35)) { model.widgets.reset() }
                    selection = nil
                }
            }
            .padding(.horizontal, 20)

            ScrollView(.horizontal) {
                HStack(spacing: 14) {
                    ForEach(IslandWidgetKind.allCases) { kind in
                        GalleryCard(
                            kind: kind,
                            isAdded: model.widgets.board.contains(kind),
                            isSelected: selection == kind,
                            add: { add(kind) },
                            select: { selection = kind }
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 4)
            }
            .scrollIndicators(.never)
        }
        .padding(.top, 16)
        .padding(.bottom, 12)
        .task(id: notice) {
            guard notice != nil else { return }
            try? await Task.sleep(for: .seconds(4))
            notice = nil
        }
    }

    private func add(_ kind: IslandWidgetKind) {
        var added = false
        withAnimation(.spring(duration: 0.35, bounce: 0.2)) { added = model.widgets.add(kind) }
        if added {
            selection = kind
        } else {
            NSSound.beep()
            notice = "No room for \(kind.title) — make a widget smaller or remove one."
        }
    }
}

private struct GalleryCard: View {
    let kind: IslandWidgetKind
    let isAdded: Bool
    let isSelected: Bool
    let add: () -> Void
    let select: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                WidgetIcon(kind: kind, side: 50)
                Spacer()
                if isAdded {
                    Button(action: select) {
                        Label("Added", systemImage: "checkmark")
                            .font(.caption.weight(.bold))
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .help("Select it on the island")
                } else {
                    Button(action: add) {
                        Text("Add").font(.caption.weight(.bold)).frame(minWidth: 34)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .help("Add \(kind.title) to the island")
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(kind.title).font(.headline)
                Text(kind.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
            }
            Text("From \(kind.minimumSize.width) × \(kind.minimumSize.height) cells")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(width: 214, alignment: .leading)
        .background(.white.opacity(isSelected ? 0.1 : 0.05), in: .rect(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : .white.opacity(0.08), lineWidth: isSelected ? 2 : 1)
        }
        .contentShape(.rect(cornerRadius: 18))
        .onTapGesture { if isAdded { select() } }
    }
}

/// The widget's app icon: its symbol on a gradient squircle.
struct WidgetIcon: View {
    let kind: IslandWidgetKind
    let side: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: side * 0.26, style: .continuous)
            .fill(LinearGradient(colors: kind.iconColors, startPoint: .top, endPoint: .bottom))
            .overlay {
                Image(systemName: kind.systemImage)
                    .font(.system(size: side * 0.46, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
            }
            .frame(width: side, height: side)
            .accessibilityHidden(true)
    }
}

extension IslandWidgetKind {
    var iconColors: [Color] {
        switch self {
        case .nowPlaying: [Color(red: 1.0, green: 0.36, blue: 0.47), Color(red: 0.93, green: 0.16, blue: 0.33)]
        case .timer: [Color(red: 1.0, green: 0.66, blue: 0.2), Color(red: 1.0, green: 0.45, blue: 0.08)]
        case .stopwatch: [Color(red: 1.0, green: 0.82, blue: 0.25), Color(red: 1.0, green: 0.6, blue: 0.1)]
        case .shelf: [Color(red: 0.35, green: 0.78, blue: 1.0), Color(red: 0.12, green: 0.48, blue: 1.0)]
        case .battery: [Color(red: 0.4, green: 0.9, blue: 0.45), Color(red: 0.16, green: 0.7, blue: 0.3)]
        case .volume: [Color(red: 0.6, green: 0.5, blue: 1.0), Color(red: 0.4, green: 0.28, blue: 0.92)]
        case .brightness: [Color(red: 1.0, green: 0.88, blue: 0.35), Color(red: 0.98, green: 0.7, blue: 0.1)]
        case .assistant: [Color(red: 0.36, green: 0.62, blue: 1.0), Color(red: 0.86, green: 0.3, blue: 0.95)]
        }
    }
}
