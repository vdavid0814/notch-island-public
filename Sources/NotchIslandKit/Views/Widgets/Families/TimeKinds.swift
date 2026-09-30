import SwiftUI

// The time's other widgets (`TimeSpecs`): a world clock, an analog clock, the month, the coming
// events and a countdown. Each redraws on the minute (the analog clock's seconds hand, where the
// style shows it, on the second; the month and the countdown at midnight), and stands still while
// the panel is hidden (`PanelTimelineView`).

/// What the world clock and the countdown read at a moment.
enum TimeReadings {
    /// The city a time zone is named after ("Europe/Budapest" → "Budapest").
    nonisolated static func city(_ zone: TimeZone) -> String {
        zone.identifier.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? zone.identifier
    }

    static func worldClock(_ config: WidgetConfig, at date: Date, format: WidgetFormat, home: TimeZone) -> WidgetReading {
        let zone = config.timeZone.flatMap(TimeZone.init(identifier:)) ?? TimeZone(identifier: "America/Los_Angeles") ?? home
        var there = format
        there.timeZone = zone
        var calendar = Calendar.current
        calendar.timeZone = home
        let here = calendar.dateComponents([.year, .month, .day], from: date)
        calendar.timeZone = zone
        let away = calendar.dateComponents([.year, .month, .day], from: date)
        let days = Calendar.current.dateComponents([.day], from: here, to: away).day ?? 0
        let name = config.label ?? (config.timeZone == nil ? "Cupertino" : city(zone))
        let caption = days == 0 ? name : days > 0 ? String(localized: "\(name) · Tomorrow") : String(localized: "\(name) · Yesterday")
        return WidgetReading(there.time(date), caption: caption, symbol: "globe", widest: there.time(Date(timeIntervalSince1970: 1_790_290_680)))
    }

    static func countdown(_ config: WidgetConfig, at date: Date, locale: Locale) -> WidgetReading {
        let name = config.label ?? String(localized: "Countdown")
        guard let target = config.date else {
            return WidgetReading("—", caption: String(localized: "Set a date"), symbol: "hourglass.bottomhalf.filled")
        }
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: target)).day ?? 0
        let value: String = switch days {
        case 0: String(localized: "Today")
        case 1...: Measurement(value: Double(days), unit: UnitDuration.days).formatted(.measurement(width: .wide, usage: .asProvided,
                                                                                                    numberFormatStyle: .number.precision(.fractionLength(0))).locale(locale))
        default: String(localized: "\(-days) days ago")
        }
        return WidgetReading(value, caption: name, symbol: days == 0 ? "party.popper.fill" : "hourglass.bottomhalf.filled",
                             tint: days == 0 ? .orange : nil)
    }

    /// The start of tomorrow: what a widget that changes once a day waits for.
    static func startOfDay(_ date: Date = Date()) -> Date { Calendar.current.startOfDay(for: date) }
}

private extension UnitDuration {
    static let days = UnitDuration(symbol: "d", converter: UnitConverterLinear(coefficient: 86400))
}

/// Feeds a world clock or a countdown its reading, at the moment it is drawn.
struct TimeReadingSource<Content: View>: View {
    let widget: IslandWidget
    @ViewBuilder let content: (WidgetReading) -> Content

    @Environment(\.widgetStyle) private var style
    @Environment(\.widgetDate) private var fixedDate
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone

    var body: some View {
        if let fixedDate {
            content(reading(fixedDate))
        } else if widget.kind == .countdown {
            PanelTimelineView(.periodic(from: TimeReadings.startOfDay(), by: 86400)) { content(reading($0.date)) }
        } else {
            PanelTimelineView(.everyMinute) { content(reading($0.date)) }
        }
    }

    private func reading(_ date: Date) -> WidgetReading {
        widget.kind == .countdown
            ? TimeReadings.countdown(widget.config, at: date, locale: locale)
            : TimeReadings.worldClock(widget.config, at: date, format: WidgetFormat(style.format, locale: locale, timeZone: timeZone), home: timeZone)
    }
}

// MARK: - Analog clock

/// A clock face: twelve ticks, the hour and minute hands, and the seconds hand where the style
/// shows seconds. Shapes only; drawn once a minute (once a second with the seconds hand).
struct AnalogClockWidget: View {
    let widget: IslandWidget
    let size: CGSize

    @Environment(\.widgetFrameProbe) private var probe
    @Environment(\.widgetStyle) private var style
    @Environment(\.widgetDate) private var fixedDate
    @Environment(\.timeZone) private var timeZone

    var body: some View {
        let showsSeconds = style.format.showsSeconds == true
        let diameter = max(min(size.width, size.height), 8)
        let zone = widget.config.timeZone.flatMap(TimeZone.init(identifier:)) ?? timeZone
        Group {
            if let fixedDate {
                ClockFace(date: fixedDate, zone: zone, showsSeconds: showsSeconds, diameter: diameter)
            } else if showsSeconds {
                PanelTimelineView(.everySecond) { ClockFace(date: $0.date, zone: zone, showsSeconds: true, diameter: diameter) }
            } else {
                PanelTimelineView(.everyMinute) { ClockFace(date: $0.date, zone: zone, showsSeconds: false, diameter: diameter) }
            }
        }
        .frame(width: diameter, height: diameter)
        .editorElement(.face, in: probe)
        .frame(width: size.width, height: size.height)
        .accessibilityLabel("Clock")
    }
}

private struct ClockFace: View {
    let date: Date
    let zone: TimeZone
    let showsSeconds: Bool
    let diameter: CGFloat

    @Environment(\.widgetStyle) private var style
    @Environment(\.widgetArtworkColor) private var artwork

    var body: some View {
        var calendar = Calendar(identifier: .gregorian)
        let _ = calendar.timeZone = zone
        let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
        let seconds = Double(parts.second ?? 0), minutes = Double(parts.minute ?? 0) + (showsSeconds ? seconds / 60 : 0)
        let hours = Double((parts.hour ?? 0) % 12) + minutes / 60
        let line = ResolvedLine(style.element(.face))
        let hand = line.fillColor(value: 0, artwork: artwork) ?? .white
        let stroke = line.thickness ?? max(diameter * 0.045, 1.5)
        ZStack {
            Circle().fill(.white.opacity(0.06))
            ClockTicks()
                .stroke(line.trackStyle(.white.opacity(0.45), artwork: artwork), style: StrokeStyle(lineWidth: max(diameter * 0.02, 1), lineCap: .round))
            ClockHand(length: 0.5)
                .stroke(hand, style: StrokeStyle(lineWidth: stroke * 1.25, lineCap: .round))
                .rotationEffect(.degrees(hours * 30))
            ClockHand(length: 0.78)
                .stroke(hand, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                .rotationEffect(.degrees(minutes * 6))
            if showsSeconds {
                ClockHand(length: 0.84)
                    .stroke(Color.orange, style: StrokeStyle(lineWidth: max(stroke * 0.45, 1), lineCap: .round))
                    .rotationEffect(.degrees(seconds * 6))
            }
            Circle().fill(showsSeconds ? Color.orange : hand).frame(width: stroke * 2, height: stroke * 2)
        }
        .frame(width: diameter, height: diameter)
    }
}

/// From the centre towards twelve, `length` of the radius.
private nonisolated struct ClockHand: Shape {
    let length: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.midY - rect.height / 2 * length))
        return path
    }
}

private nonisolated struct ClockTicks: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = min(rect.width, rect.height) / 2
        for tick in 0..<12 {
            let angle = Double(tick) * .pi / 6
            let inner = radius * (tick % 3 == 0 ? 0.8 : 0.88), outer = radius * 0.94
            path.move(to: CGPoint(x: rect.midX + sin(angle) * inner, y: rect.midY - cos(angle) * inner))
            path.addLine(to: CGPoint(x: rect.midX + sin(angle) * outer, y: rect.midY - cos(angle) * outer))
        }
        return path
    }
}

// MARK: - Month

/// The days of a month in weeks, as a calendar page lays them out.
nonisolated struct MonthGrid: Equatable, Sendable {
    /// The weekdays' narrow names, from the calendar's first weekday.
    var weekdays: [String]
    /// Each week's days; nil before the month's first day and after its last.
    var weeks: [[Int?]]
    var today: Int?
    var title: String

    init(date: Date, calendar: Calendar, locale: Locale) {
        var calendar = calendar
        calendar.locale = locale
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        weekdays = (0..<7).map { symbols[(first + $0) % 7] }
        let start = calendar.dateInterval(of: .month, for: date)?.start ?? date
        let count = calendar.range(of: .day, in: .month, for: date)?.count ?? 30
        let offset = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
        var cells: [Int?] = Array(repeating: nil, count: offset) + (1...count).map(Optional.init)
        while cells.count % 7 != 0 { cells.append(nil) }
        weeks = stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
        today = calendar.component(.day, from: date)
        title = start.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).month(.wide).year())
    }
}

/// This month at a glance: its name over its days, today on a disc. Drawn anew at midnight.
struct MonthCalendarWidget: View {
    let widget: IslandWidget
    let size: CGSize

    @Environment(\.widgetFrameProbe) private var probe
    @Environment(\.widgetStyle) private var style
    @Environment(\.widgetDate) private var fixedDate
    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendar

    static let titleType = TypeSpec(points: 12, weight: .semibold)

    var body: some View {
        if let fixedDate {
            content(fixedDate)
        } else {
            PanelTimelineView(.periodic(from: TimeReadings.startOfDay(), by: 86400)) { content($0.date) }
        }
    }

    @ViewBuilder private func content(_ date: Date) -> some View {
        let grid = MonthGrid(date: date, calendar: calendar, locale: locale)
        let showsTitle = widget.shows(.label) && size.height >= 70
        let titleFit = min(14, WidgetType.size(fitting: grid.title, in: size.width - 8, weight: .semibold))
        let titleSize = style.textPoints(.label, auto: WidgetType.fitted(12, fit: titleFit, widget.size(of: .label), floor: 8), fit: titleFit)
        let titleHeight = showsTitle ? (titleSize * WidgetType.lineHeight).rounded(.up) + 3 : 0
        VStack(alignment: .leading, spacing: 3) {
            if showsTitle {
                Text(style.element(.label)?.text.labelOverride ?? grid.title)
                    .widgetTextElement(.label, Self.titleType.at(titleSize), fit: titleFit, in: style, probe: probe)
                    .lineLimit(1)
                    .padding(.leading, 4)
                    // Exactly its share: the days under it end on the widget's edge, not past it.
                    .frame(height: titleHeight - 3)
            }
            MonthGridView(grid: grid, size: CGSize(width: size.width, height: max(size.height - titleHeight, 0)))
                .editorElement(.monthGrid, in: probe)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(grid.title))
    }
}

struct MonthGridView: View {
    let grid: MonthGrid
    let size: CGSize

    @Environment(\.widgetStyle) private var style
    @Environment(\.widgetArtworkColor) private var artwork
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let rows = CGFloat(grid.weeks.count + 1)
        // Whole pixels a cell, the days centred in what is left: a room a hair wider or taller (a
        // custom layout's rectangle is stored as fractions) draws the very same days.
        let cell = CGSize(width: (size.width / 7 * displayScale).rounded(.down) / displayScale,
                          height: (size.height / rows * displayScale).rounded(.down) / displayScale)
        let points = max(min(cell.height * 0.62, cell.width * 0.5, 13), 5)
        let accent = ResolvedLine(style.element(.monthGrid)).fillColor(value: 1, artwork: artwork) ?? .red
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(grid.weekdays.enumerated()), id: \.offset) { _, name in
                    Text(name)
                        .font(.system(size: points * 0.82, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: cell.width, height: cell.height)
                }
            }
            ForEach(Array(grid.weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 0) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        ZStack {
                            if let day {
                                if day == grid.today {
                                    Circle().fill(accent).frame(width: min(cell.width, cell.height) - 1, height: min(cell.width, cell.height) - 1)
                                }
                                Text("\(day)")
                                    .font(.system(size: points, weight: day == grid.today ? .bold : .medium).monospacedDigit())
                                    .foregroundStyle(day == grid.today ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                            }
                        }
                        .frame(width: cell.width, height: cell.height)
                    }
                }
            }
        }
        .lineLimit(1)
        .frame(width: size.width, height: size.height)
    }
}

// MARK: - Up next

/// The coming events from Calendar: each its time and title beside its calendar's colour. Read
/// only while shown, and only once the user allowed it from the widget's own button — a picture
/// (the gallery, the editor) shows samples and asks for nothing.
struct UpNextWidget: View {
    let widget: IslandWidget
    let size: CGSize

    @Environment(AppModel.self) private var model
    @Environment(\.isWidgetPreview) private var isPreview
    @Environment(\.widgetFrameProbe) private var probe
    @Environment(\.widgetStyle) private var style
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone
    @Environment(\.widgetDate) private var fixedDate

    var body: some View {
        let service = model.calendar
        Group {
            if isPreview {
                list(CalendarService.samples(now: fixedDate ?? Date()))
            } else if service.access == .granted {
                PanelTimelineView(.everyMinute) { _ in
                    list(service.upcoming(calendars: widget.config.calendarIDs, count: WidgetConfig.countRange.upperBound))
                }
            } else {
                // Asked only here, by a button the user presses.
                Button {
                    service.requestAccess()
                } label: {
                    Label(service.access == .denied ? "Allow in System Settings" : "Show My Events", systemImage: "calendar")
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .islandButton(.capsule)
                .help("Up Next reads your coming events from Calendar, on this Mac only")
                .frame(width: size.width, height: size.height)
            }
        }
        .editorElement(.eventList, in: probe)
        .whileShown { if !isPreview { service.acquire() } } stop: { if !isPreview { service.release() } }
    }

    @ViewBuilder private func list(_ events: [CalendarEvent]) -> some View {
        let wanted = widget.config.count ?? 2
        let rowHeight: CGFloat = size.height < 56 ? size.height : max(min(size.height / CGFloat(wanted), 34), 22)
        let rows = max(min(wanted, Int(size.height / rowHeight)), 1)
        let shown = Array(events.prefix(rows))
        let format = WidgetFormat(style.format, locale: locale, timeZone: timeZone)
        if shown.isEmpty {
            Label("Nothing coming up", systemImage: "calendar")
                .font(.system(size: min(12, WidgetType.size(fittingLines: 1, in: size.height)), weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: size.width, height: size.height)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(shown) { event in
                    UpNextRow(event: event, time: Self.time(event, format: format, now: fixedDate ?? Date()), height: rowHeight, width: size.width)
                }
            }
            .frame(width: size.width, height: size.height, alignment: .leading)
        }
    }

    /// "Now", "14:30", "Tomorrow", or the weekday for one further away.
    static func time(_ event: CalendarEvent, format: WidgetFormat, now: Date) -> String {
        var calendar = Calendar.current
        calendar.timeZone = format.timeZone
        if event.start <= now { return event.isAllDay ? String(localized: "Today") : String(localized: "Now") }
        if calendar.isDate(event.start, inSameDayAs: now) { return event.isAllDay ? String(localized: "Today") : format.time(event.start) }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(event.start, inSameDayAs: tomorrow) {
            return String(localized: "Tomorrow")
        }
        return event.start.formatted(Date.FormatStyle(locale: format.locale, timeZone: format.timeZone).weekday(.abbreviated))
    }
}

private struct UpNextRow: View {
    let event: CalendarEvent
    let time: String
    let height: CGFloat
    let width: CGFloat

    var body: some View {
        let points = max(min(height * 0.42, 13), 8)
        HStack(spacing: 6) {
            Capsule()
                .fill(Color(red: event.red, green: event.green, blue: event.blue))
                .frame(width: 3, height: max(height - 8, 6))
            Text(time)
                .font(.system(size: points, weight: .semibold, design: .rounded).monospacedDigit())
                .fixedSize()
            Text(event.title)
                .font(.system(size: points, weight: .medium))
                .foregroundStyle(.secondary)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .lineLimit(1)
        .padding(.horizontal, 4)
        .frame(width: width, height: height, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
