import SwiftUI

/// The time and today's date: one row (the time, the date beside it while it fits) or, two rows
/// tall, the date over a large time. Ticks once a minute, on the minute, only while shown. Both
/// can be moved and restyled in Customize (`WidgetLabel`).
struct DateTimeWidget: View {
    let widget: IslandWidget
    let size: CGSize

    @Environment(\.widgetDate) private var fixedDate

    var body: some View {
        Group {
            if let fixedDate {
                content(fixedDate)
            } else {
                PanelTimelineView(.everyMinute) { content($0.date) }
            }
        }
        .accessibilityElement(children: .combine)
    }

    static func isTall(_ inner: CGSize) -> Bool { inner.height >= 56 }

    /// The time's size: never wider than the widget ("09:41" is about 2.9 of its size wide).
    static func timePoints(inner: CGSize) -> CGFloat {
        min(WidgetMetrics.points(isTall(inner) ? inner.height * 0.62 : inner.height, ratio: 0.8, min: 13, max: 48),
            (inner.width - 8) / 2.9)
    }

    static func datePoints(inner: CGSize) -> CGFloat {
        WidgetMetrics.points(inner.height, ratio: isTall(inner) ? 0.18 : 0.42, min: 9, max: 17)
    }

    static func timeText(_ date: Date) -> String { date.formatted(.dateTime.hour().minute()) }

    /// The date as a restyled label sets it (on its own, the widget picks the longest wording that fits).
    static func dateText(_ date: Date) -> String { date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) }

    @ViewBuilder private func content(_ date: Date) -> some View {
        let tall = Self.isTall(size)
        let timePoints = Self.timePoints(inner: size), datePoints = Self.datePoints(inner: size)
        // The time in rounded figures unless Customize sets another typeface.
        let shown = widget.withOwnDesign(.rounded, for: .readout)
        let time = WidgetLabel(id: .readout, text: Self.timeText(date), widget: shown, size: timePoints, weight: .semibold,
                               isSecondary: false) {
            Text(date, format: .dateTime.hour().minute())
                .font(.system(size: timePoints, weight: .semibold, design: .rounded).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .movableElement(.readout, of: widget)
        // The longest wording that fits: "Thursday, 24 September", "Thu, 24 Sep", "Thu 24", "24".
        let dateLine = WidgetLabel(id: .dateLine, text: Self.dateText(date), widget: widget, size: datePoints, weight: .medium,
                                   isSecondary: true) {
            ViewThatFits(in: .horizontal) {
                Text(date, format: .dateTime.weekday(.wide).day().month(.wide)).fixedSize()
                Text(date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated)).fixedSize()
                Text(date, format: .dateTime.weekday(.abbreviated).day()).fixedSize()
                Text(date, format: .dateTime.day()).fixedSize()
            }
            .font(.system(size: datePoints, weight: .medium))
            .foregroundStyle(.secondary)
        }
        .movableElement(.dateLine, of: widget)
        let showsTime = widget.shows(.readout), showsDate = widget.shows(.dateLine)
        Group {
            if tall {
                VStack(alignment: .leading, spacing: 0) {
                    if showsDate { dateLine }
                    if showsTime { time }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            } else {
                // The date beside the time only while it fits there.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if showsTime { time.fixedSize() }
                        if showsDate { dateLine }
                    }
                    if showsTime { time } else { dateLine }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 4)
    }
}
