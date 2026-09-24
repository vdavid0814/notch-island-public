import AppKit
import SwiftUI

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

struct BoardEditor: View {
    @Binding var selection: IslandWidgetKind?
    let thumbnails: ThumbnailCache
    /// Widgets picked together with ⌘-click, edited as one (two or more; empty otherwise).
    var group: Binding<Set<IslandWidgetKind>> = .constant([])
    /// A widget was clicked (not dragged): Settings opens its editor.
    var onEdit: ((IslandWidgetKind) -> Void)?

    @Environment(AppModel.self) private var model
    @State private var interaction: Interaction?
    /// True for as long as a move or resize drag is really in progress. Unlike `onEnded`, a
    /// `GestureState` also resets when the drag is cancelled (released outside the panel, the
    /// panel losing the pointer): the drag is then finished instead of the widget staying stuck
    /// half-way.
    @GestureState private var isDragging = false
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
            let doomed = group.wrappedValue.isEmpty ? Set([selection].compactMap { $0 }) : group.wrappedValue
            guard !doomed.isEmpty else { return }
            withAnimation(Self.settle) { doomed.forEach { model.widgets.remove($0) } }
            selection = nil
            group.wrappedValue = []
        }
        .onChange(of: selection) { _, new in if new != nil { isFocused = true } }
        .onChange(of: isDragging) { _, dragging in
            if !dragging, interaction != nil { finish() }
        }
    }

    @ViewBuilder private func widgetView(_ widget: IslandWidget, geometry: WidgetBoardGeometry) -> some View {
        let active = interaction?.kind == widget.kind ? interaction : nil
        let resting = geometry.frame(for: widget.frame)
        let isResizing = active?.handle != nil
        let isMoving = active != nil && !isResizing
        // Moving: the widget follows the pointer (its size, so its layout, stays). Resizing: its
        // content steps from cell to cell — laid out once per cell with a short spring, not at
        // every pointer event, which made a corner drag stutter — while an outline and the handles
        // follow the pointer exactly.
        let pointerFrame = active?.live ?? resting
        let contentFrame = if let active, isResizing { geometry.frame(for: active.candidate) } else { pointerFrame }
        let isGrouped = group.wrappedValue.contains(widget.kind)
        let isSelected = selection == widget.kind || isGrouped
        let showsHandles = selection == widget.kind && group.wrappedValue.count < 2

        ZStack(alignment: .topLeading) {
            IslandWidgetView(widget: widget, size: contentFrame.size, thumbnails: thumbnails)
                .allowsHitTesting(false)
                .overlay {
                    RoundedRectangle(cornerRadius: min(WidgetMetrics.cornerRadius, contentFrame.height / 2), style: .continuous)
                        .strokeBorder(isSelected ? Color.accentColor : .white.opacity(0.14), lineWidth: isSelected ? 2 : 1)
                }
                .contentShape(.rect(cornerRadius: WidgetMetrics.cornerRadius))
                .scaleEffect(isMoving ? 1.03 : 1)
                .shadow(color: .black.opacity(isMoving ? 0.45 : 0), radius: 14, y: 6)
                .onTapGesture {
                    if NSEvent.modifierFlags.contains(.command) {
                        toggleInGroup(widget.kind)
                    } else {
                        group.wrappedValue = []
                        selection = widget.kind
                        onEdit?(widget.kind)
                    }
                }
                .gesture(moveGesture(widget, geometry: geometry))
                .frame(width: contentFrame.width, height: contentFrame.height)
                .offset(x: contentFrame.minX, y: contentFrame.minY)
                .animation(isResizing ? .spring(duration: 0.2, bounce: 0.08) : nil, value: contentFrame)

            if let active, isResizing {
                ResizeOutline(frame: pointerFrame, rect: active.candidate, isValid: active.isValid)
            }

            if showsHandles, !isMoving {
                ZStack(alignment: .topLeading) {
                    ForEach(Handle.allCases, id: \.self) { handle in
                        HandleDot()
                            .position(
                                x: handle.movesLeading ? pointerFrame.minX : pointerFrame.maxX,
                                y: handle.movesTop ? pointerFrame.minY : pointerFrame.maxY
                            )
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
            .updating($isDragging) { _, dragging, _ in dragging = true }
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
            .updating($isDragging) { _, dragging, _ in dragging = true }
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

    /// ⌘-click: adds the widget to the group (with the one already selected), or takes it out.
    private func toggleInGroup(_ kind: IslandWidgetKind) {
        var picked = group.wrappedValue
        if picked.isEmpty, let selection { picked.insert(selection) }
        if picked.contains(kind) { picked.remove(kind) } else { picked.insert(kind) }
        withAnimation(.spring(duration: 0.3)) {
            group.wrappedValue = picked.count >= 2 ? picked : []
            selection = picked.count == 1 ? picked.first : (picked.contains(kind) ? kind : picked.first)
        }
    }

    private func begin(_ widget: IslandWidget, handle: Handle?, geometry: WidgetBoardGeometry) -> Interaction {
        // Dragging one widget of a group moves that widget only; the group stays picked.
        if !group.wrappedValue.contains(widget.kind) { group.wrappedValue = [] }
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

/// The pointer's rectangle while a corner is dragged: a thin dashed line with the size the widget
/// will take — accent when it fits, red when it would cover another widget.
private struct ResizeOutline: View {
    let frame: CGRect
    let rect: GridRect
    let isValid: Bool

    var body: some View {
        let tint = isValid ? Color.accentColor : .red
        RoundedRectangle(cornerRadius: min(WidgetMetrics.cornerRadius, frame.height / 2), style: .continuous)
            .strokeBorder(tint.opacity(0.9), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            .overlay(alignment: rect.row == 0 ? .bottom : .top) {
                Text("\(rect.width) × \(rect.height)")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(tint, in: Capsule())
                    .foregroundStyle(.white)
                    .fixedSize()
                    .offset(y: rect.row == 0 ? 9 : -9)
            }
            .frame(width: max(frame.width, 1), height: max(frame.height, 1))
            .offset(x: frame.minX, y: frame.minY)
            .allowsHitTesting(false)
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
            // The size badge sits on the edge away from the island's header: under the top row it
            // was covered by the header (and its tooltips).
            .overlay(alignment: rect.row == 0 ? .bottom : .top) {
                Text("\(rect.width) × \(rect.height)")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(tint, in: Capsule())
                    .foregroundStyle(.white)
                    .fixedSize()
                    .offset(y: rect.row == 0 ? 9 : -9)
            }
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
            if candidate.isHorizontallyCentred {
                line(x: size.width / 2, color: .yellow)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    private func line(x: CGFloat, color: Color) -> some View {
        Rectangle().fill(color.opacity(0.85))
            .frame(width: 1, height: geometry.size.height + 16)
            .offset(x: x - 0.5, y: -8)
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

/// The widget's app icon: its symbol on a gradient squircle.
struct WidgetIcon: View {
    let kind: IslandWidgetKind
    let side: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: side * 0.26, style: .continuous)
            .fill(LinearGradient(colors: kind.iconColors, startPoint: .top, endPoint: .bottom))
            .overlay {
                Group {
                    if let control = kind.systemControl {
                        ControlGlyph(control: control, on: true, size: side * 0.46)
                    } else {
                        Image(systemName: kind.systemImage)
                            .font(.system(size: side * 0.46, weight: .semibold))
                    }
                }
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
        case .keyboardBrightness: [Color(red: 0.5, green: 0.85, blue: 0.95), Color(red: 0.2, green: 0.6, blue: 0.8)]
        case .wifi, .bluetooth, .airDrop: [Color(red: 0.3, green: 0.62, blue: 1.0), Color(red: 0.05, green: 0.4, blue: 0.95)]
        case .darkMode: [Color(red: 0.45, green: 0.45, blue: 0.55), Color(red: 0.2, green: 0.2, blue: 0.28)]
        case .nightShift: [Color(red: 1.0, green: 0.72, blue: 0.3), Color(red: 0.98, green: 0.5, blue: 0.1)]
        case .keepAwake: [Color(red: 0.7, green: 0.55, blue: 0.4), Color(red: 0.5, green: 0.35, blue: 0.22)]
        case .microphone: [Color(red: 1.0, green: 0.45, blue: 0.4), Color(red: 0.9, green: 0.2, blue: 0.2)]
        case .calculator: [Color(red: 1.0, green: 0.62, blue: 0.2), Color(red: 0.95, green: 0.42, blue: 0.05)]
        case .voiceMemos: [Color(red: 1.0, green: 0.38, blue: 0.38), Color(red: 0.85, green: 0.12, blue: 0.2)]
        case .screenshot: [Color(red: 0.62, green: 0.64, blue: 0.7), Color(red: 0.38, green: 0.4, blue: 0.47)]
        case .notes: [Color(red: 1.0, green: 0.86, blue: 0.3), Color(red: 0.98, green: 0.7, blue: 0.08)]
        case .lockScreen: [Color(red: 0.5, green: 0.52, blue: 0.6), Color(red: 0.26, green: 0.28, blue: 0.36)]
        case .focus: [Color(red: 0.55, green: 0.45, blue: 1.0), Color(red: 0.35, green: 0.22, blue: 0.85)]
        case .clock: [Color(red: 0.4, green: 0.42, blue: 0.48), Color(red: 0.14, green: 0.15, blue: 0.2)]
        case .home: [Color(red: 1.0, green: 0.66, blue: 0.2), Color(red: 1.0, green: 0.48, blue: 0.1)]
        case .dateTime: [Color(red: 1.0, green: 0.4, blue: 0.36), Color(red: 0.95, green: 0.2, blue: 0.22)]
        case .systemStats: [Color(red: 0.36, green: 0.85, blue: 0.62), Color(red: 0.1, green: 0.62, blue: 0.45)]
        }
    }
}
