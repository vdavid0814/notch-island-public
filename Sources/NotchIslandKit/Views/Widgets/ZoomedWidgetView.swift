import SwiftUI

/// A widget on a board, `size` large on its cells. Down to the size its cells have at the design's
/// cells (`WidgetZoom`) it is laid out at its size; smaller, it is laid out at that design size and
/// drawn smaller as a whole — the same widget, zoomed out, never one laid out again for less room
/// (texts at their floor, parts left out). Larger, it takes the room as it is designed to.
struct ZoomedWidgetView: View {
    let widget: IslandWidget
    let size: CGSize

    var body: some View {
        let scale = WidgetZoom.scale(span: widget.frame.size, size: size)
        if scale >= 0.999 {
            IslandWidgetView(widget: widget, size: size)
        } else {
            let laid = CGSize(width: size.width / scale, height: size.height / scale)
            IslandWidgetView(widget: widget, size: laid)
                .frame(width: laid.width, height: laid.height)
                .scaleEffect(scale)
                .frame(width: size.width, height: size.height)
        }
    }
}

/// The design's cells: every widget is made for a board of 40-pt cells 8 pt apart. Smaller cells
/// show it zoomed out (`ZoomedWidgetView`).
nonisolated enum WidgetZoom {
    static let cell: CGFloat = 40
    static let gap: CGFloat = 8

    /// A widget on `span` cells, at the design's cells.
    static func designSize(span: GridSize) -> CGSize {
        CGSize(width: CGFloat(span.width) * (cell + gap) - gap, height: CGFloat(span.height) * (cell + gap) - gap)
    }

    /// How much smaller than its design a widget of `size` on `span` cells is drawn: 1 from the
    /// design's size up, as much as it is smaller below it (the tighter of its two sides, so the
    /// design fits whole).
    static func scale(span: GridSize, size: CGSize) -> CGFloat {
        let design = designSize(span: span)
        guard design.width > 0, design.height > 0 else { return 1 }
        return min(1, size.width / design.width, size.height / design.height)
    }
}
