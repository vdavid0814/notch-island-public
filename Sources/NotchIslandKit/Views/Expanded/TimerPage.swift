import SwiftUI

/// The timer on its own page: the timer widget over the whole page, with every control.
struct TimerPage: View {
    var body: some View {
        GeometryReader { proxy in
            TimerWidget(
                widget: IslandWidget(
                    kind: .timer,
                    frame: GridRect(column: 0, row: 0, width: WidgetBoard.columns, height: WidgetBoard.rows),
                    options: Set(IslandWidgetKind.timer.options)
                ),
                size: proxy.size
            )
        }
    }
}
