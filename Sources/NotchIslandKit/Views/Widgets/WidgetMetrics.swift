import SwiftUI

nonisolated enum WidgetMetrics {
    /// Inside a widget's plate.
    static let padding: CGFloat = 6
    /// Concentric with the round buttons and icons in a widget's corners (about 28 points, inside
    /// its 6-point padding: 6 + 14).
    static let cornerRadius: CGFloat = 20
    /// Below this inner height a widget draws a single row, with small controls.
    static let singleRowHeight: CGFloat = 44

    /// Inside the widget: tighter without a plate (nothing to keep off the edge), and for a control
    /// (Wi-Fi and its kin), whose button should fill a one-cell widget.
    static func padding(for widget: IslandWidget) -> CGFloat {
        if widget.background == .none { return 2 }
        return widget.kind.control != nil ? 4 : padding
    }

    /// The glass buttons' size in a row this tall (the timer's, the stopwatch's, the shelf's): as
    /// large as the row comfortably holds, not the island's smallest.
    static func buttonSize(rowHeight: CGFloat) -> ControlSize {
        switch rowHeight {
        case 48...: .extraLarge
        case 34...: .large
        case 24...: .regular
        default: .small
        }
    }

    /// One cell wide and tall: drawn as a circle.
    static func isRound(_ widget: IslandWidget) -> Bool { widget.frame.width == 1 && widget.frame.height == 1 }

    /// A type size that grows with the room, within limits: a label never overflows a small widget
    /// and never looks lost in a large one.
    static func points(_ room: CGFloat, ratio: CGFloat, min lower: CGFloat, max upper: CGFloat) -> CGFloat {
        min(max(room * ratio, lower), upper).rounded()
    }
}
