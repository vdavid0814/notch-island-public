import SwiftUI

/// The calendar, the base of a grid of days: this month's name over its days in weeks, today on a
/// red disc. Drawn anew at midnight, never between.
///
/// The days are moved and sized in Customize as a part of their own (their look comes later), the
/// month's name as a text (`WidgetLabel`).
struct MonthCalendarWidget: View {
    let widget: IslandWidget
    let size: CGSize

    @Environment(\.widgetDate) private var fixedDate
    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendar
    @Environment(\.timeZone) private var timeZone

    static func titlePoints(inner: CGSize) -> CGFloat {
        WidgetMetrics.points(inner.height, ratio: 0.1, min: 10, max: 14)
    }

    /// The month's name from a widget this tall (over the days; alone, at any height).
    static func hasTitleRoom(inner: CGSize) -> Bool { inner.height >= 70 }

    static func showsTitle(_ widget: IslandWidget, inner: CGSize) -> Bool {
        widget.shows(.label) && (hasTitleRoom(inner: inner) || !widget.shows(.monthGrid))
    }

    /// The days' own size in a widget whose inside is `inner` (six weeks under the weekdays).
    static func dayPoints(_ widget: IslandWidget, inner: CGSize) -> CGFloat {
        let title = showsTitle(widget, inner: inner) ? (titlePoints(inner: inner) * 1.3).rounded(.up) + 3 : 0
        let rows: CGFloat = widget.shows(.monthWeekdays) ? 7 : 6
        return MonthGridView.dayPoints(cell: CGSize(width: inner.width / 7, height: max(inner.height - title, 0) / rows))
    }

    var body: some View {
        Group {
            if let fixedDate {
                content(fixedDate)
            } else {
                var calendar = calendar
                let _ = calendar.timeZone = timeZone
                PanelTimelineView(.periodic(from: calendar.startOfDay(for: .now), by: 86400)) { content($0.date) }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    @ViewBuilder private func content(_ date: Date) -> some View {
        var calendar = calendar
        let _ = calendar.timeZone = timeZone
        let grid = MonthGrid(date: date, calendar: calendar, locale: locale)
        let showsTitle = Self.showsTitle(widget, inner: size)
        let points = Self.titlePoints(inner: size)
        let titleHeight = showsTitle ? (points * 1.3).rounded(.up) + 3 : 0
        VStack(alignment: .leading, spacing: 3) {
            if showsTitle {
                WidgetLabel(id: .label, text: grid.title, widget: widget, size: points, weight: .semibold, isSecondary: false) {
                    Text(grid.title)
                        .font(.system(size: points, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .padding(.leading, 4)
                .frame(height: titleHeight - 3)
                .movableElement(.label, of: widget)
            }
            if widget.shows(.monthGrid) {
                MonthGridView(grid: grid, size: CGSize(width: size.width, height: max(size.height - titleHeight, 0)),
                              look: widget.dayGridLook(of: .monthGrid), dayStyle: widget.textStyle(of: .monthDays),
                              showsWeekdays: widget.shows(.monthWeekdays))
                    .movableElement(.monthGrid, of: widget)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(grid.title))
    }
}

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

/// The weekdays' letters over the weeks, today's number on a disc — as the grid's look sets them
/// (`DayGridLook`): a background behind each day and one behind the whole grid; the numbers in
/// their own type, size and colour (`ElementID.monthDays`), the weekdays in the same typeface.
struct MonthGridView: View {
    let grid: MonthGrid
    let size: CGSize
    var look: DayGridLook = .plain
    var dayStyle: TextStyle = .plain
    var showsWeekdays = true

    @Environment(\.displayScale) private var displayScale
    @Environment(\.widgetLayerPass) private var layerPass
    @Environment(AppModel.self) private var model

    static let accent = Color.red

    /// The days' own size in a cell this large.
    static func dayPoints(cell: CGSize) -> CGFloat { max(min(cell.height * 0.62, cell.width * 0.5, 13), 5) }

    var body: some View {
        let rows = CGFloat(grid.weeks.count + (showsWeekdays ? 1 : 0))
        // Whole pixels a cell, so a hair more room draws the very same days.
        let cell = CGSize(width: (size.width / 7 * displayScale).rounded(.down) / displayScale,
                          height: (size.height / rows * displayScale).rounded(.down) / displayScale)
        let points = dayStyle.size.map { CGFloat($0) } ?? Self.dayPoints(cell: cell)
        let side = max(min(cell.width, cell.height) - 1, 1)
        VStack(spacing: 0) {
            if showsWeekdays {
                HStack(spacing: 0) {
                    ForEach(Array(grid.weekdays.enumerated()), id: \.offset) { _, name in
                        weekday(name, points: points * 0.82)
                            .frame(width: cell.width, height: cell.height)
                    }
                }
            }
            ForEach(Array(grid.weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 0) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        ZStack {
                            if let day {
                                if look.day.isShown, drawsSurface(look.day) {
                                    LookSurface(material: look.day.material, fill: look.day.fill, fillColor: look.day.fillColor,
                                                shape: RoundedRectangle(cornerRadius: look.day.corners.radius(height: side), style: .continuous))
                                        .frame(width: side, height: side)
                                }
                                Group {
                                    if day == grid.today {
                                        // In the days' own shape where they have one: its corners
                                        // no longer showed round the disc.
                                        RoundedRectangle(cornerRadius: look.day.isShown ? look.day.corners.radius(height: side) : side / 2,
                                                         style: .continuous)
                                            .fill(Self.accent)
                                            .frame(width: side, height: side)
                                    }
                                    number(day, points: points)
                                }
                                .opacity(layerPass == .underlay ? 0 : 1)
                            }
                        }
                        .frame(width: cell.width, height: cell.height)
                    }
                }
            }
        }
        .lineLimit(1)
        .frame(width: size.width, height: size.height)
        .background {
            if look.grid.isShown, drawsSurface(look.grid) {
                LookSurface(material: look.grid.material, fill: look.grid.fill, fillColor: look.grid.fillColor,
                            shape: RoundedRectangle(cornerRadius: look.grid.corners.radius(height: cell.height * 1.2), style: .continuous))
            }
        }
    }

    /// Zoomed in Customize, glass is drawn under the picture of the rest (`SharpZoom`).
    private func drawsSurface(_ surface: SurfaceLook) -> Bool {
        layerPass == .all || (layerPass == .underlay) == surface.isGlass
    }

    @ViewBuilder private func weekday(_ name: String, points: CGFloat) -> some View {
        if dayStyle == .plain {
            Text(name).font(.system(size: points, weight: .semibold)).foregroundStyle(.tertiary)
                .opacity(layerPass == .underlay ? 0 : 1)
        } else {
            var style = dayStyle
            let _ = style.size = Double(points)
            Text(name).font(Font(style.font(size: points, weight: .semibold))).foregroundStyle(.tertiary)
                .opacity(layerPass == .underlay ? 0 : 1)
        }
    }

    @ViewBuilder private func number(_ day: Int, points: CGFloat) -> some View {
        let isToday = day == grid.today
        if dayStyle == .plain {
            Text("\(day)")
                .font(.system(size: points, weight: isToday ? .bold : .medium).monospacedDigit())
                .foregroundStyle(isToday ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        } else {
            let font = dayStyle.font(size: points, weight: isToday ? .bold : .medium)
            Text("\(day)")
                .font(Font(font).monospacedDigit())
                .underline(dayStyle.isUnderlined)
                .strikethrough(dayStyle.isStruckThrough)
                .foregroundStyle(isToday ? AnyShapeStyle(.white) : color)
        }
    }

    /// The numbers' colour: the style's, white (primary) where Automatic.
    private var color: AnyShapeStyle {
        switch dayStyle.color {
        case .automatic: AnyShapeStyle(.primary)
        case .custom(let rgb): AnyShapeStyle(rgb.color)
        case .artwork: AnyShapeStyle(model.media.artworkColor.map { Color($0) } ?? .islandAccent)
        }
    }
}
