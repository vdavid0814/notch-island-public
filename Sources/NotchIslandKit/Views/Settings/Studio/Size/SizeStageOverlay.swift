import AppKit
import SwiftUI

/// Over the stage's island in Size mode: a handle on each side (the width, kept centred on the
/// notch) and on the lower edge (the board's height). While one is dragged, an outline follows the
/// pointer exactly and the island itself steps from size to size (`StudioDraft`); the preference is
/// written once, when the drag ends.
struct SizeStageOverlay: View {
    /// The island as drawn now (the draft's size while dragging), in the overlay's space: centred
    /// on its width, hanging from its top.
    let island: CGSize
    /// The overlay's own size (the most the island is dragged to at once: `StudioStage.sizeRoom`).
    let room: CGSize
    /// The island's layout without the draft.
    let base: IslandLayout

    @Environment(AppModel.self) private var model
    @State private var drag: Drag?
    @GestureState private var isDragging = false

    private struct Drag: Equatable {
        let handle: ResizeHandle
        /// The island's size when the drag began.
        let start: CGSize
        /// The size under the pointer.
        var live: CGSize
    }

    private static let space = "sizeStage"

    var body: some View {
        let frame = CGRect(x: (room.width - island.width) / 2, y: 0, width: island.width, height: island.height)
        let grid = model.editedWidgets.board.grid
        ZStack(alignment: .topLeading) {
            if let drag {
                let live = CGRect(x: (room.width - drag.live.width) / 2, y: 0, width: drag.live.width, height: drag.live.height)
                UnevenRoundedRectangle(bottomLeadingRadius: 24, bottomTrailingRadius: 24, style: .continuous)
                    .strokeBorder(Color.islandAccent.opacity(0.9), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .frame(width: live.width, height: live.height)
                    .offset(x: live.minX, y: live.minY)
                    .allowsHitTesting(false)
            }
            ForEach([ResizeHandle.leading, .trailing, .bottom], id: \.self) { handle in
                let at = drag.map { drag in
                    handle.position(on: CGRect(x: (room.width - drag.live.width) / 2, y: 0, width: drag.live.width, height: drag.live.height))
                } ?? handle.position(on: frame)
                EdgeHandle(isVertical: handle != .bottom)
                    .position(at)
                    .gesture(gesture(handle))
                    .help(handle == .bottom ? "Drag to make the board taller or shorter" : "Drag to make the panel wider or narrower")
            }
            // What it is now, under the island.
            SizeBadge(text: "\(Int(island.width)) × \(Int(island.height)) pt  ·  \(grid.columns) × \(grid.rows) cells", tint: Color.islandAccent)
                .position(x: room.width / 2, y: min((drag?.live.height ?? island.height) + 22, room.height - 10))
                .allowsHitTesting(false)
        }
        .frame(width: room.width, height: room.height, alignment: .topLeading)
        .coordinateSpace(.named(Self.space))
        .finishingCancelledDrag(isDragging, finish: finish)
    }

    private func gesture(_ handle: ResizeHandle) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.space))
            .tracking($isDragging)
            .onChanged { value in
                var current = drag ?? Drag(handle: handle, start: island, live: island)
                let limit = base.maximumExpandedSize
                let smallest = base.replacing(panel: PanelLayout(widthFactor: PanelSettings.widthRange.lowerBound,
                                                                 boardHeightFactor: PanelSettings.boardHeightRange.lowerBound))
                    .size(for: .expanded(.home))
                let largest = base.replacing(panel: PanelLayout(widthFactor: PanelSettings.widthRange.upperBound,
                                                                boardHeightFactor: PanelSettings.boardHeightRange.upperBound))
                    .size(for: .expanded(.home))
                switch handle {
                case .leading, .trailing:
                    // Centred on the notch: both sides move.
                    let delta = value.translation.width * (handle == .trailing ? 2 : -2)
                    current.live.width = min(max(current.start.width + delta, smallest.width), min(largest.width, limit.width, room.width))
                default:
                    current.live.height = min(max(current.start.height + value.translation.height, smallest.height),
                                             min(largest.height, limit.height, room.height - 34))
                }
                drag = current
                var panel = base.panel(forExpandedSize: current.live)
                panel.keepsSize = model.preferences.panel.keepsSize
                if model.studio.draft?.panel != panel {
                    SnapTick.perform()
                    withAnimation(.spring(duration: 0.2, bounce: 0.08)) { model.studio.draft = StudioDraft(panel: panel) }
                }
            }
            .onEnded { _ in finish() }
    }

    private func finish() {
        guard drag != nil else { return }
        drag = nil
        guard let draft = model.studio.draft else { return }
        withAnimation(.spring(duration: 0.25, bounce: 0.1)) {
            model.preferences.panel = draft.panel
            model.studio.draft = nil
        }
    }
}

/// A grip on an edge: a short white bar.
private struct EdgeHandle: View {
    let isVertical: Bool

    var body: some View {
        Capsule()
            .fill(.white)
            .overlay(Capsule().strokeBorder(Color.islandAccent, lineWidth: 2))
            .frame(width: isVertical ? 8 : 44, height: isVertical ? 44 : 8)
            .shadow(color: .black.opacity(0.45), radius: 3)
            .frame(width: isVertical ? 28 : 64, height: isVertical ? 64 : 28)
            .contentShape(.rect)
            .onHover { inside in
                if inside { (isVertical ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push() } else { NSCursor.pop() }
            }
    }
}
