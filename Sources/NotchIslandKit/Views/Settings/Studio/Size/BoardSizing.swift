import CoreGraphics
import Foundation

/// The open panel's board by its cells (Settings ▸ Widgets ▸ Size, `PanelSettings`): so many square
/// cells, each with the gap after it — the pitch — and the panel exactly as large as they make it.
///
/// - Columns and rows are added or taken away one at a time (a side's handle, the Width and Height
///   sliders): the cells keep their size, the panel grows or shrinks by one pitch, and each widget
///   keeps its cells — nothing on the board changes shape.
/// - Smaller or larger cells (the Cell slider) divide the same room again: as many columns and
///   rows as fit where the board was, so more, smaller widgets fit, or fewer, larger ones. Each
///   widget keeps its cells, so it is drawn smaller or larger as a whole (`ZoomedWidgetView`).
/// - The gap keeps the pitch, so the panel stays as it is: a wider gap leaves the cells, and the
///   widgets on them, a little smaller.
nonisolated enum BoardSizing {
    /// The widgets' board in the open island as it is drawn: the page's area (inside the sides'
    /// insets, between the header and the bottom inset) less the gap's own inset.
    static func board(_ layout: IslandLayout) -> CGSize {
        let island = layout.size(for: .expanded(.home))
        let inset = 2 * layout.boardInset
        return CGSize(width: island.width - 2 * IslandLayout.boardSideInset - inset,
                      height: island.height - layout.notch.height - IslandLayout.boardTopInset - IslandLayout.boardBottomInset - inset)
    }

    /// `panel` with as many columns and rows as the screen and the header let it have.
    static func fitted(_ panel: PanelSettings, layout: IslandLayout) -> PanelSettings {
        let sized = layout.replacing(panel: panel.layout)
        var next = panel
        next.columns = sized.columnRange.clamp(panel.columns)
        next.rows = sized.rowRange.clamp(panel.rows)
        return next
    }

    /// Cells of `cell` points in the room a board of `board` takes: as many columns and rows of
    /// them as fit there.
    static func dividing(_ board: CGSize, into cell: Double, from panel: PanelSettings, layout: IslandLayout) -> PanelSettings {
        var next = panel
        next.cell = PanelSettings.cellRange.clamp(cell.rounded())
        let pitch = layout.replacing(panel: next.layout).pitch, gap = CGFloat(panel.gap)
        next.columns = Int(((board.width + gap) / pitch).rounded())
        next.rows = Int(((board.height + gap) / pitch).rounded())
        return fitted(next, layout: layout)
    }

    /// Another gap: the pitch kept (the cells take up the difference), so the panel is as it was.
    static func withGap(_ gap: Double, _ panel: PanelSettings) -> PanelSettings {
        let pitch = panel.cell + panel.gap
        let gap = gapRange(panel).clamp(gap.rounded())
        return PanelSettings(cell: pitch - gap, gap: gap, columns: panel.columns, rows: panel.rows)
    }

    /// The gaps the panel's pitch leaves room for: its cells no smaller than the smallest.
    static func gapRange(_ panel: PanelSettings) -> ClosedRange<Double> {
        let pitch = panel.cell + panel.gap
        let most = min(PanelSettings.gapRange.upperBound, pitch - PanelSettings.cellRange.lowerBound)
        return PanelSettings.gapRange.lowerBound...max(PanelSettings.gapRange.lowerBound, most)
    }

    /// The columns and rows of a board dragged to `size` (island points) with `panel`'s cells: the
    /// nearest whole number of each.
    static func counts(forIsland size: CGSize, panel: PanelSettings, layout: IslandLayout) -> (columns: Int, rows: Int) {
        let pitch = layout.replacing(panel: panel.layout).pitch
        let width = size.width - 2 * IslandLayout.boardSideInset + IslandLayout.referenceGap
        let height = size.height - layout.notch.height - IslandLayout.boardTopInset - IslandLayout.boardBottomInset + IslandLayout.referenceGap
        return (Int((width / pitch).rounded()), Int((height / pitch).rounded()))
    }
}
