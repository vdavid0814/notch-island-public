import SwiftUI

/// The time and the calendar (`TimeSpecs`): each kind to its view, a kind not built yet to its placeholder.
struct TimeFamily: View {
    let widget: IslandWidget
    let size: CGSize

    var body: some View {
        switch widget.kind {
        case .dateTime: DateTimeWidget(widget: widget, size: size)
        default: WidgetPlaceholder(kind: widget.kind, size: size)
        }
    }
}

/// The time, large, with today's date under it (or beside it when the widget is one row wide
/// enough). Re-rendered once a minute, on the minute.
struct DateTimeWidget: View {
    let widget: IslandWidget
    let size: CGSize

    @Environment(\.widgetFrameProbe) private var probe
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

    @ViewBuilder private func content(_ date: Date) -> some View {
        let showsTime = widget.shows(.readout), showsDate = widget.shows(.dateLine)
        let tall = size.height >= 56
        // Never wider than the widget, nor taller than its share of it; below that cap S, M
        // and L stay apart (`WidgetType.fitted`).
        let dateSize = WidgetType.fitted(WidgetType.points(size.height, ratio: tall ? 0.18 : 0.42, min: 9, max: 17),
                                         fit: WidgetType.size(fittingLines: 1, in: tall ? size.height * 0.34 : size.height),
                                         widget.size(of: .dateLine), floor: 8)
        let timeText = date.formatted(.dateTime.hour().minute())
        let timeSize = WidgetType.fitted(
            WidgetType.points(tall ? size.height * 0.62 : size.height, ratio: 0.8, min: 13, max: 48),
            fit: min(WidgetType.size(fitting: timeText, in: size.width - 8, weight: .semibold, rounded: true, monospacedDigits: true),
                     WidgetType.size(fittingLines: 1, in: tall && showsDate ? size.height - dateSize * WidgetType.lineHeight : size.height) * 1.08),
            widget.size(of: .readout), floor: 11)
        let time = Text(date, format: .dateTime.hour().minute())
            .font(.system(size: timeSize, weight: .semibold, design: .rounded).monospacedDigit())
        // The longest date that fits: "Thursday, 24 September", "Thu, 24 Sep", "24".
        let dateLine = ViewThatFits(in: .horizontal) {
            Text(date, format: .dateTime.weekday(.wide).day().month(.wide)).fixedSize()
            Text(date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated)).fixedSize()
            Text(date, format: .dateTime.weekday(.abbreviated).day()).fixedSize()
            Text(date, format: .dateTime.day()).fixedSize()
        }
        .font(.system(size: dateSize, weight: .medium))
        .foregroundStyle(.secondary)
        Group {
            if tall {
                VStack(alignment: .leading, spacing: 0) {
                    if showsDate { dateLine.editorElement(.dateLine, in: probe) }
                    if showsTime { time.lineLimit(1).minimumScaleFactor(0.6).editorElement(.readout, in: probe) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if showsTime { time.lineLimit(1).fixedSize().editorElement(.readout, in: probe) }
                        if showsDate { dateLine.editorElement(.dateLine, in: probe) }
                    }
                    if showsTime {
                        time.lineLimit(1).minimumScaleFactor(0.6).editorElement(.readout, in: probe)
                    } else {
                        dateLine.editorElement(.dateLine, in: probe)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 4)
    }
}
