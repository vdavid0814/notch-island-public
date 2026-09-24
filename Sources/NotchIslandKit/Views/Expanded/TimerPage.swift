import SwiftUI

/// The timer on its own page: the timer widget over the whole page, with every control, set in the
/// units the home page's timer widget uses (its Hours and Seconds options).
struct TimerPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let units = (model.widgets.board.widget(.timer)?.options ?? IslandWidgetKind.timer.defaultOptions)
            .intersection([.timerHours, .timerSeconds])
        GeometryReader { proxy in
            TimerWidget(
                widget: IslandWidget(
                    kind: .timer,
                    frame: GridRect(column: 0, row: 0, width: WidgetBoard.columns, height: WidgetBoard.rows),
                    options: Set<WidgetOption>([.ruler, .readout, .addMinute]).union(units)
                ),
                size: proxy.size
            )
        }
    }
}
