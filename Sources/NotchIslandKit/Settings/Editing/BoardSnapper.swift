import CoreGraphics

/// The board's snapping: whole cells, kept inside the board, a resize within the kind's limits.
struct BoardSnapper {
    let geometry: WidgetBoardGeometry

    /// A widget of `size` dragged to `frame`: the nearest whole-cell place.
    func move(_ frame: CGRect, size: GridSize) -> GridRect {
        geometry.snappedMove(origin: frame.origin, size: size)
    }

    /// A widget at `rect` whose corner `handle` was dragged until it spans `frame`.
    func resize(_ frame: CGRect, from rect: GridRect, kind: IslandWidgetKind, handle: ResizeHandle) -> GridRect {
        geometry.snappedResize(frame: frame, from: rect, kind: kind, movesLeading: handle.movesLeading, movesTop: handle.movesTop)
    }
}
