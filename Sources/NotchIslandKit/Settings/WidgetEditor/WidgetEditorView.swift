import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Customize Island as a window (only without a notch screen, where Settings cannot grow out of
/// the notch): the same widget studio as Settings ▸ Widgets.
struct WidgetEditorView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        WidgetsSettingsPage()
            .background(SettingsPalette.window)
            .environment(\.colorScheme, .dark)
    }
}

// MARK: - Board editing

struct BoardEditor: View {
    @Binding var selection: WidgetID?
    /// Widgets picked together with ⌘-click, edited as one (two or more; empty otherwise).
    var group: Binding<Set<WidgetID>> = .constant([])
    /// A widget was clicked (not dragged): Settings opens its editor.
    var onEdit: ((WidgetID) -> Void)?
    /// Every cell drawn, the widgets faint over them (Settings ▸ Widgets ▸ Size).
    var showsGrid = false

    @Environment(AppModel.self) private var model
    /// A drag in progress: where the widget is under the pointer, and the cells it will land on.
    @State private var interaction: DragSession<WidgetID, GridRect>?
    /// A widget dragged in from the gallery: where it would land, and whether it fits there as it is.
    @State private var dropCandidate: (rect: GridRect, isExact: Bool)?
    /// True for as long as a move or resize drag is really in progress (`tracking`).
    @GestureState private var isDragging = false
    @FocusState private var isFocused: Bool

    private static let settle: Animation = .spring(duration: 0.32, bounce: 0.18)

    var body: some View {
        GeometryReader { proxy in
            // While the panel is being sized (`StudioDraft`): the board on the draft's grid, each
            // widget on its cells — never the old grid stretched to the new size.
            let board = model.studio.draft.map { $0.board(model.editedWidgets.board) } ?? model.editedWidgets.board
            let geometry = WidgetBoardGeometry(size: proxy.size, grid: board.grid)
            ZStack(alignment: .topLeading) {
                GridLayer(geometry: geometry, isEmphasized: interaction != nil || showsGrid,
                          occupied: showsGrid ? [] : board.widgets.filter { $0.id != interaction?.id }.map(\.frame))
                    .contentShape(.rect)
                    .onTapGesture {
                        selection = nil
                        group.wrappedValue = []
                    }

                if let interaction {
                    Guides(geometry: geometry, candidate: interaction.candidate)
                }
                // A move shows where the widget will land; a resize shows it there already.
                if let interaction, interaction.handle == nil {
                    Ghost(frame: geometry.frame(for: interaction.candidate), rect: interaction.candidate,
                          isValid: interaction.isValid)
                        // Over the resting widgets (its badge must stay readable), under the one
                        // being dragged.
                        .zIndex(1.5)
                }

                ForEach(board.widgets) { widget in
                    widgetView(widget, geometry: geometry)
                        .opacity(showsGrid ? 0.55 : 1)
                }
                if let dropCandidate {
                    Ghost(frame: geometry.frame(for: dropCandidate.rect), rect: dropCandidate.rect, isValid: true)
                        .zIndex(3)
                }
            }
            .coordinateSpace(.named(BoardSpace.name))
            .onDrop(of: [.plainText], delegate: GalleryDrop(model: model, geometry: geometry, candidate: $dropCandidate) { id in
                group.wrappedValue = []
                selection = id
            })
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
            nudge(press.key) ? .handled : .ignored
        }
        .onDeleteCommand {
            let doomed = group.wrappedValue.isEmpty ? Set([selection].compactMap { $0 }) : group.wrappedValue
            guard !doomed.isEmpty else { return }
            withAnimation(Self.settle) { doomed.forEach { model.editedWidgets.remove($0) } }
            selection = nil
            group.wrappedValue = []
        }
        .onChange(of: selection) { _, new in if new != nil { isFocused = true } }
        .finishingCancelledDrag(isDragging, finish: finish)
    }

    @ViewBuilder private func widgetView(_ widget: IslandWidget, geometry: WidgetBoardGeometry) -> some View {
        let active = interaction?.id == widget.id ? interaction : nil
        let resting = geometry.frame(for: widget.frame)
        let isResizing = active?.handle != nil
        let isMoving = active != nil && !isResizing
        // Moving: the widget follows the pointer (its size, so its layout, stays). Resizing: its
        // content steps from cell to cell — laid out once per cell with a short spring, not at
        // every pointer event, which made a corner drag stutter — while an outline and the handles
        // follow the pointer exactly.
        let pointerFrame = active?.live ?? resting
        let contentFrame = if let active, isResizing { geometry.frame(for: active.candidate) } else { pointerFrame }
        let isGrouped = group.wrappedValue.contains(widget.id)
        let isSelected = selection == widget.id || isGrouped
        let showsHandles = selection == widget.id && group.wrappedValue.count < 2

        ZStack(alignment: .topLeading) {
            ZoomedWidgetView(widget: widget, size: contentFrame.size)
                // A picture: no live glass, nothing ticking.
                .environment(\.widgetRenderMode, .canvas)
                .allowsHitTesting(false)
                .overlay {
                    RoundedRectangle(cornerRadius: min(WidgetMetrics.cornerRadius, contentFrame.height / 2), style: .continuous)
                        .strokeBorder(isSelected ? Color.islandAccent : .white.opacity(0.14), lineWidth: isSelected ? 2 : 1)
                }
                .contentShape(.rect(cornerRadius: WidgetMetrics.cornerRadius))
                .scaleEffect(isMoving ? 1.03 : 1)
                .shadow(color: .black.opacity(isMoving ? 0.45 : 0), radius: 14, y: 6)
                .onTapGesture {
                    if NSEvent.modifierFlags.contains(.command) {
                        toggleInGroup(widget.id)
                    } else {
                        group.wrappedValue = []
                        selection = widget.id
                        onEdit?(widget.id)
                    }
                }
                .gesture(moveGesture(widget, geometry: geometry))
                .frame(width: contentFrame.width, height: contentFrame.height)
                .offset(x: contentFrame.minX, y: contentFrame.minY)
                .animation(isResizing ? .spring(duration: 0.2, bounce: 0.08) : nil, value: contentFrame)

            if let active, isResizing {
                ResizeOutline(frame: pointerFrame, cornerRadius: min(WidgetMetrics.cornerRadius, pointerFrame.height / 2),
                              badge: "\(active.candidate.width) × \(active.candidate.height)",
                              badgeAtBottom: active.candidate.row == 0, isValid: active.isValid)
            }

            if showsHandles, !isMoving {
                ZStack(alignment: .topLeading) {
                    ForEach(ResizeHandle.corners, id: \.self) { handle in
                        HandleDot()
                            .position(handle.position(on: pointerFrame))
                            .gesture(resizeGesture(widget, handle: handle, geometry: geometry))
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            }
        }
        .zIndex(active != nil ? 2 : (isSelected ? 1 : 0))
    }

    // MARK: Gestures

    private func moveGesture(_ widget: IslandWidget, geometry: WidgetBoardGeometry) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(BoardSpace.name))
            .tracking($isDragging)
            .onChanged { value in
                var current = interaction ?? begin(widget, handle: nil, geometry: geometry)
                current.live = current.start.offsetBy(dx: value.translation.width, dy: value.translation.height)
                update(&current, candidate: BoardSnapper(geometry: geometry).move(current.live, size: widget.frame.size),
                       kind: widget.kind)
                interaction = current
            }
            .onEnded { _ in finish() }
    }

    private func resizeGesture(_ widget: IslandWidget, handle: ResizeHandle, geometry: WidgetBoardGeometry) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(BoardSpace.name))
            .tracking($isDragging)
            .onChanged { value in
                var current = interaction ?? begin(widget, handle: handle, geometry: geometry)
                current.live = handle.resized(current.start, by: value.translation, minimum: CGSize(width: 24, height: 20))
                update(&current, candidate: BoardSnapper(geometry: geometry).resize(current.live, from: widget.frame,
                                                                                    kind: widget.kind, handle: handle),
                       kind: widget.kind)
                interaction = current
            }
            .onEnded { _ in finish() }
    }

    /// ⌘-click: adds the widget to the group (with the one already selected), or takes it out.
    private func toggleInGroup(_ id: WidgetID) {
        var picked = group.wrappedValue
        if picked.isEmpty, let selection { picked.insert(selection) }
        if picked.contains(id) { picked.remove(id) } else { picked.insert(id) }
        withAnimation(.spring(duration: 0.3)) {
            group.wrappedValue = picked.count >= 2 ? picked : []
            selection = picked.count == 1 ? picked.first : (picked.contains(id) ? id : picked.first)
        }
    }

    private func begin(_ widget: IslandWidget, handle: ResizeHandle?, geometry: WidgetBoardGeometry) -> DragSession<WidgetID, GridRect> {
        // Dragging one widget of a group moves that widget only; the group stays picked.
        if !group.wrappedValue.contains(widget.id) { group.wrappedValue = [] }
        selection = widget.id
        let frame = geometry.frame(for: widget.frame)
        return DragSession(id: widget.id, handle: handle, start: frame, candidate: widget.frame)
    }

    private func update(_ interaction: inout DragSession<WidgetID, GridRect>, candidate: GridRect, kind: IslandWidgetKind) {
        interaction.land(on: candidate, isValid: model.editedWidgets.board.isFree(candidate, for: kind, excluding: interaction.id))
    }

    private func finish() {
        guard let current = interaction else { return }
        withAnimation(Self.settle) {
            if current.isValid { model.editedWidgets.setFrame(current.candidate, for: current.id) }
            interaction = nil
        }
    }

    /// Arrow keys move the selected widget one cell, when there is room.
    private func nudge(_ key: KeyEquivalent) -> Bool {
        guard let selection, let widget = model.editedWidgets.board.widget(selection) else { return false }
        var rect = widget.frame
        switch key {
        case .leftArrow: rect.column -= 1
        case .rightArrow: rect.column += 1
        case .upArrow: rect.row -= 1
        case .downArrow: rect.row += 1
        default: return false
        }
        var moved = false
        withAnimation(Self.settle) { moved = model.editedWidgets.setFrame(rect, for: selection) }
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
            ForEach(0..<geometry.grid.rows, id: \.self) { row in
                ForEach(0..<geometry.grid.columns, id: \.self) { column in
                    let cell = GridRect(column: column, row: row, width: 1, height: 1)
                    let frame = geometry.frame(for: cell)
                    // Each cell a round dot: the room shown, not a tile to be filled.
                    Circle()
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
        let tint = isValid ? Color.islandAccent : .red
        RoundedRectangle(cornerRadius: min(WidgetMetrics.cornerRadius, frame.height / 2), style: .continuous)
            .fill(tint.opacity(0.16))
            .strokeBorder(tint.opacity(0.9), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            // The size badge sits on the edge away from the island's header: under the top row it
            // was covered by the header (and its tooltips).
            .sizeBadge("\(rect.width) × \(rect.height)", tint: tint, atBottom: rect.row == 0)
            .frame(width: frame.width, height: frame.height)
            .offset(x: frame.minX, y: frame.minY)
            .animation(.spring(duration: 0.18, bounce: 0), value: frame)
            .allowsHitTesting(false)
    }
}

/// The centre line, when the landing place is centred on the notch.
private struct Guides: View {
    let geometry: WidgetBoardGeometry
    let candidate: GridRect

    var body: some View {
        let size = geometry.size
        ZStack(alignment: .topLeading) {
            // Only the notch's centre line; the edge-alignment lines were taken out (the user found
            // them noisy — the grid and the ghost already show where it lands).
            if candidate.isHorizontallyCentred(in: geometry.grid) {
                GuideLine(axis: .vertical, position: size.width / 2, length: size.height)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
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
                Group {
                    Image(systemName: kind.systemImage)
                        .font(.system(size: side * 0.46, weight: .semibold))
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
            }
            .frame(width: side, height: side)
            .accessibilityHidden(true)
    }
}

extension IslandWidgetKind {
    /// The app icon's gradient (`WidgetKindSpec.iconColors`).
    var iconColors: [Color] { spec.iconColors.map(\.color) }
}

/// A widget dragged from Settings' gallery onto the stage's board: while it is over the board, the
/// place it would take (its default size, centred under the pointer, snapped to the cells — or the
/// free place nearest that); let go, it is added there and picked, looking as the board's other
/// widgets do (`WidgetBoard.add(_:near:)`).
struct GalleryDrop: DropDelegate {
    let model: AppModel
    let geometry: WidgetBoardGeometry
    @Binding var candidate: (rect: GridRect, isExact: Bool)?
    let added: (WidgetID) -> Void

    static let prefix = "notchisland-widget:"

    static func payload(_ kind: IslandWidgetKind) -> String { prefix + kind.rawValue }

    private var kind: IslandWidgetKind? { model.studio.draggedKind }

    func validateDrop(info: DropInfo) -> Bool { kind != nil && info.hasItemsConforming(to: [.plainText]) }

    func dropEntered(info: DropInfo) { update(info) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        update(info)
        return DropProposal(operation: .copy)
    }

    func dropExited(info: DropInfo) { candidate = nil }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            candidate = nil
            model.studio.draggedKind = nil
        }
        guard let kind, let anchor = anchor(for: kind, at: info.location) else { return false }
        var id: WidgetID?
        withAnimation(.spring(duration: 0.35, bounce: 0.2)) { id = model.editedWidgets.add(kind, near: anchor) }
        guard let id else {
            NSSound.beep()
            return false
        }
        added(id)
        return true
    }

    private func update(_ info: DropInfo) {
        guard let kind, let anchor = anchor(for: kind, at: info.location) else { return candidate = nil }
        let board = model.editedWidgets.board
        if board.isFree(anchor, for: kind) {
            candidate = (anchor, true)
        } else if let near = board.placement(for: kind, size: anchor.size, near: anchor) {
            candidate = (near, false)
        } else {
            candidate = nil
        }
    }

    /// Its default size with its middle under the pointer, on whole cells inside the board.
    private func anchor(for kind: IslandWidgetKind, at point: CGPoint) -> GridRect? {
        let grid = model.editedWidgets.board.grid
        let size = grid.defaultSize(for: kind)
        guard size.width <= grid.columns, size.height <= grid.rows else { return nil }
        let frame = geometry.frame(for: GridRect(column: 0, row: 0, width: size.width, height: size.height))
        return geometry.snappedMove(origin: CGPoint(x: point.x - frame.width / 2, y: point.y - frame.height / 2), size: size)
    }
}
