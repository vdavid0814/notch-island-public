import SwiftUI

/// The time and the calendar (`TimeSpecs`): each kind to its view, a kind not built yet to its placeholder.
struct TimeFamily: View, WidgetFamilyElements {
    let widget: IslandWidget
    let size: CGSize

    var body: some View {
        switch widget.kind {
        case .dateTime: DateTimeWidget(widget: widget, size: size)
        case .worldClock, .countdown: TimeReadingSource(widget: widget) { ReadingWidget(widget: widget, size: size, reading: $0) }
        case .analogClock: AnalogClockWidget(widget: widget, size: size)
        case .monthCalendar: MonthCalendarWidget(widget: widget, size: size)
        case .upNext: UpNextWidget(widget: widget, size: size)
        default: WidgetPlaceholder(kind: widget.kind, size: size)
        }
    }

    func demands(_ input: PlanInput) -> [ElementDemand] {
        switch widget.kind {
        case .worldClock, .countdown: ReadingWidget.demands(input)
        case .monthCalendar: input.demands(types: [.label: MonthCalendarWidget.titleType.at(12)])
        default: input.demands(types: [.readout: DateTimeWidget.timeType.at(32), .dateLine: DateTimeWidget.dateType.at(13)])
        }
    }

    func element(_ id: ElementID) -> TimeElement { TimeElement(widget: widget, id: id) }
}

/// One element of a time widget on its own (a custom layout), at the size the layout plans.
struct TimeElement: View {
    let widget: IslandWidget
    let id: ElementID

    @Environment(\.widgetPlan) private var plan
    @Environment(\.widgetStyle) private var style
    @Environment(\.widgetDate) private var fixedDate
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone

    @Environment(\.calendar) private var calendar

    var body: some View {
        Group {
            switch widget.kind {
            case .worldClock, .countdown:
                TimeReadingSource(widget: widget) { ReadingElement(id: id, reading: $0) }
            case .monthCalendar:
                month
            default:
                if let fixedDate {
                    content(fixedDate)
                } else if style.format.showsSeconds == true {
                    PanelTimelineView(.everySecond) { content($0.date) }
                } else {
                    PanelTimelineView(.everyMinute) { content($0.date) }
                }
            }
        }
    }

    /// The month's name or its days, on their own rectangles.
    @ViewBuilder private var month: some View {
        let planned = plan?.elements[id]
        let room = planned?.size ?? CGSize(width: 120, height: 80)
        let grid = MonthGrid(date: fixedDate ?? Date(), calendar: calendar, locale: locale)
        if id == .monthGrid {
            MonthGridView(grid: grid, size: room)
        } else if id == .label {
            Text(style.element(.label)?.text.labelOverride ?? grid.title)
                .widgetText(.label, MonthCalendarWidget.titleType.at(planned?.points ?? 12), in: style)
                .lineLimit(1)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: style.element(.label)?.text.alignment?.frameAlignment ?? .leading)
        }
    }

    @ViewBuilder private func content(_ date: Date) -> some View {
        let planned = plan?.elements[id]
        let format = WidgetFormat(style.format, locale: locale, timeZone: timeZone)
        let alignment = style.element(id)?.text.alignment?.frameAlignment ?? .leading
        switch (widget.kind, id) {
        case (.dateTime, .readout):
            Text(date, format: format.time)
                .widgetText(.readout, DateTimeWidget.timeType.at(planned?.points ?? 24), in: style)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
        case (.dateTime, .dateLine):
            Group {
                if let text = format.date(date) {
                    Text(text)
                } else {
                    // The longest wording that fits its rectangle, as the stacks choose.
                    ViewThatFits(in: .horizontal) {
                        Text(date, format: .dateTime.weekday(.wide).day().month(.wide)).fixedSize()
                        Text(date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated)).fixedSize()
                        Text(date, format: .dateTime.weekday(.abbreviated).day()).fixedSize()
                        Text(date, format: .dateTime.day())
                    }
                }
            }
            .widgetText(.dateLine, DateTimeWidget.dateType.at(planned?.points ?? 12), in: style)
            .foregroundStyle(.secondary)
            .lineLimit(style.element(.dateLine)?.text.lineLimit ?? 1)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
        default:
            EmptyView()
        }
    }
}

/// The time, large, with today's date under it (or beside it when the widget is one row wide
/// enough). Re-rendered once a minute, on the minute.
struct DateTimeWidget: View {
    let widget: IslandWidget
    let size: CGSize

    @Environment(\.widgetFrameProbe) private var probe
    @Environment(\.widgetStyle) private var style
    @Environment(\.widgetDate) private var fixedDate
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone

    /// The time's type (rounded semibold, digits of one width) and the date's (medium).
    static let timeType = TypeSpec(points: 32, design: .rounded, weight: .semibold, monospacedDigits: true)
    static let dateType = TypeSpec(points: 13, weight: .medium)

    var body: some View {
        Group {
            if let fixedDate {
                content(fixedDate)
            } else if style.format.showsSeconds == true {
                // Once a second only when the style shows seconds; else once a minute, on the minute.
                PanelTimelineView(.everySecond) { content($0.date) }
            } else {
                PanelTimelineView(.everyMinute) { content($0.date) }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The time's room and size: its width, and its share of the height under the date.
    private func timeSizes(_ timeText: String, tall: Bool, showsDate: Bool, dateSize: CGFloat) -> (fit: CGFloat, points: CGFloat) {
        let fit = min(WidgetType.size(fitting: timeText, in: size.width - 8, weight: .semibold, rounded: true, monospacedDigits: true),
                      WidgetType.size(fittingLines: 1, in: tall && showsDate ? size.height - dateSize * WidgetType.lineHeight : size.height) * 1.08)
        return (fit, style.textPoints(.readout, auto: WidgetType.fitted(
            WidgetType.points(tall ? size.height * 0.62 : size.height, ratio: 0.8, min: 13, max: 48),
            fit: fit, widget.size(of: .readout), floor: 11), fit: fit))
    }

    @ViewBuilder private func content(_ date: Date) -> some View {
        let showsTime = widget.shows(.readout), showsDate = widget.shows(.dateLine)
        let tall = size.height >= 56
        // Never wider than the widget, nor taller than its share of it; below that cap S, M
        // and L stay apart (`WidgetType.fitted`).
        let format = WidgetFormat(style.format, locale: locale, timeZone: timeZone)
        // Measured as `Text` draws it: in the view's locale and time zone, in the style's format.
        let timeText = format.time(date)
        let lineFit = WidgetType.size(fittingLines: 1, in: tall ? size.height * 0.34 : size.height)
        // On one row the date shares the width with the time, and is drawn only while its longest
        // wording fits beside it (the time's size does not depend on the date's there).
        let longestDate = format.date(date)
            ?? date.formatted(Date.FormatStyle(locale: locale, timeZone: timeZone).weekday(.wide).day().month(.wide))
        let timeWidth = WidgetTypography.width(timeText, style.drawnType(.readout, Self.timeType.at(
            timeSizes(timeText, tall: tall, showsDate: showsDate, dateSize: 0).points)), scale: 2)
        let beside = CGSize(width: size.width - 8 - 8 - timeWidth, height: size.height)
        let dateFit = tall || !showsTime ? lineFit
            : min(lineFit, TextFit.maxPoints(samples: [longestDate], spec: style.drawnType(.dateLine, Self.dateType), room: beside,
                                             scale: 2) ?? 0)
        let dateSize = style.textPoints(.dateLine, auto: WidgetType.fitted(WidgetType.points(size.height, ratio: tall ? 0.18 : 0.42, min: 9, max: 17),
                                                                           fit: lineFit, widget.size(of: .dateLine), floor: 8),
                                        fit: dateFit)
        let (timeFit, timeSize) = timeSizes(timeText, tall: tall, showsDate: showsDate, dateSize: dateSize)
        let timeType = Self.timeType.at(timeSize)
        let time = Text(date, format: format.time).widgetText(.readout, timeType, in: style)
        let dateType = Self.dateType.at(dateSize)
        // The longest date that fits: "Thursday, 24 September", "Thu, 24 Sep", "24" — or the
        // style's own template.
        let dateLine = Group {
            if let text = format.date(date) {
                Text(text).fixedSize()
            } else {
                ViewThatFits(in: .horizontal) {
                    Text(date, format: .dateTime.weekday(.wide).day().month(.wide)).fixedSize()
                    Text(date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated)).fixedSize()
                    Text(date, format: .dateTime.weekday(.abbreviated).day()).fixedSize()
                    Text(date, format: .dateTime.day()).fixedSize()
                }
            }
        }
        .widgetText(.dateLine, dateType, in: style)
        .foregroundStyle(.secondary)
        let timeDrawn = WidgetFrameProbe.Drawn.text(style.drawnType(.readout, timeType), lines: 1, fit: timeFit)
        let dateDrawn = WidgetFrameProbe.Drawn.text(style.drawnType(.dateLine, dateType), lines: 1, fit: dateFit)
        Group {
            if tall {
                VStack(alignment: .leading, spacing: 0) {
                    if showsDate { dateLine.editorElement(.dateLine, in: probe, drawn: dateDrawn) }
                    if showsTime { time.lineLimit(1).minimumScaleFactor(0.6).editorElement(.readout, in: probe, drawn: timeDrawn) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if showsTime { time.lineLimit(1).fixedSize().editorElement(.readout, in: probe, drawn: timeDrawn) }
                        if showsDate { dateLine.editorElement(.dateLine, in: probe, drawn: dateDrawn) }
                    }
                    if showsTime {
                        time.lineLimit(1).minimumScaleFactor(0.6).editorElement(.readout, in: probe, drawn: timeDrawn)
                    } else {
                        dateLine.editorElement(.dateLine, in: probe, drawn: dateDrawn)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 4)
    }
}

extension TimelineSchedule where Self == PeriodicTimelineSchedule {
    /// Once a second, on the second.
    static var everySecond: PeriodicTimelineSchedule {
        .periodic(from: Date(timeIntervalSinceReferenceDate: Date().timeIntervalSinceReferenceDate.rounded(.down)), by: 1)
    }
}
