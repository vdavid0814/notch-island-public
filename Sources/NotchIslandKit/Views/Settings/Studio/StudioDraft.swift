import CoreGraphics
import Foundation

/// The panel while it is being sized in Settings ▸ Widgets ▸ Size (session only): the stage draws
/// it, and it is stored (`AppModel.setPanel`) once the drag or the slider is let go — a column
/// taken away for a moment sets nothing aside.
nonisolated struct StudioDraft: Equatable, Sendable {
    var panel: PanelSettings
    /// Of the columns added (taken away, if negative), how many at the leading side: the side whose
    /// handle is dragged. nil: half at each side.
    var leadingColumns: Int?

    /// `board` as the draft has it: on its grid, each widget on its cells.
    func board(_ board: WidgetBoard) -> WidgetBoard {
        var board = board
        board.setGridKeepingCells(panel.grid, leadingColumns: leadingColumns)
        return board
    }
}

/// Everything Size mode changes, as it was when Size mode was entered: Reset Size puts all of it
/// back — the panel's cells, the ready-made size and every page's board, each widget where it was
/// (a column taken away and given back moves or parks nothing then).
struct SizeSnapshot: Equatable {
    var panel: PanelSettings
    var scale: IslandScale
    var boards: [ExpandedPage: WidgetBoard]
}
