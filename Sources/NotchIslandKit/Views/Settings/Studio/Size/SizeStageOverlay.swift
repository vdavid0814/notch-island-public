import AppKit
import SwiftUI

/// Over the stage's island in Size mode: a handle on each side (columns, the panel kept centred on
/// the notch) and on the lower edge (rows). While one is dragged, an outline follows the pointer
/// and the island steps a whole cell at a time (`StudioDraft`) — one column or row, of the cells'
/// own size, so nothing on the board changes shape; the panel is stored once the drag ends.
struct SizeStageOverlay: View {
    /// The island as drawn now (the draft's while dragging), in the overlay's space: centred on its
    /// width, hanging from its top.
    let island: CGSize
    /// The overlay's own size.
    let room: CGSize
    /// The island's layout without the draft.
    let base: IslandLayout
    /// How much smaller the stage shows the island: a drag on the screen is this much larger on it.
    let fit: CGFloat

    @Environment(AppModel.self) private var model
    @State private var drag: Drag?
    @GestureState private var isDragging = false

    private struct Drag: Equatable {
        let handle: ResizeHandle
        /// The panel and the island's size when the drag began, and how much smaller it was shown.
        let start: PanelSettings
        let startIsland: CGSize
        let fit: CGFloat
        /// The size under the pointer.
        var live: CGSize
    }

    var body: some View {
        let frame = CGRect(x: (room.width - island.width) / 2, y: 0, width: island.width, height: island.height)
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
                EdgeHandle(isVertical: handle != .bottom)
                    .position(handle.position(on: frame))
                    .gesture(gesture(handle))
                    .help(handle == .bottom ? "Drag for more or fewer rows" : "Drag for more or fewer columns")
            }
        }
        .frame(width: room.width, height: room.height, alignment: .topLeading)
        .finishingCancelledDrag(isDragging, finish: finish)
    }

    private func gesture(_ handle: ResizeHandle) -> some Gesture {
        // On the screen, not in the stage's own (shrunk) space: that space changes as the island
        // grows, and the pointer would run away from it.
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .tracking($isDragging)
            .onChanged { value in
                var current = drag ?? Drag(handle: handle, start: model.preferences.panel, startIsland: island,
                                           fit: max(fit, 0.1), live: island)
                let dx = value.translation.width / current.fit, dy = value.translation.height / current.fit
                switch handle {
                case .leading, .trailing:
                    // Centred on the notch: both sides move.
                    current.live.width = max(current.startIsland.width + 2 * (handle == .trailing ? dx : -dx), 1)
                default:
                    current.live.height = max(current.startIsland.height + dy, base.notch.height + 1)
                }
                drag = current
                let counts = BoardSizing.counts(forIsland: current.live, panel: current.start, layout: base)
                var next = current.start
                if handle == .bottom { next.rows = counts.rows } else { next.columns = counts.columns }
                next = BoardSizing.fitted(next, layout: base)
                let draft = StudioDraft(panel: next, leadingColumns: handle == .leading ? next.columns - current.start.columns : 0)
                if model.studio.draft != draft {
                    SnapTick.perform()
                    withAnimation(.spring(duration: 0.2, bounce: 0.08)) { model.studio.draft = draft }
                }
            }
            .onEnded { _ in finish() }
    }

    private func finish() {
        guard drag != nil else { return }
        drag = nil
        guard let draft = model.studio.draft else { return }
        withAnimation(.spring(duration: 0.25, bounce: 0.1)) {
            model.setPanel(draft.panel, leadingColumns: draft.leadingColumns)
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
