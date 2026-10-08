import SwiftUI

/// Daily Usage, the base of bars a day: the iPhone's Battery Usage on the island — the last eight
/// days' use as bars, one picked (today until a click picks another; a click on it again goes back
/// to today), with the title, the picked day's percentage and its name over them. Blue, orange
/// where the day used more than usual. It reads the battery's history, leased while shown; a picture
/// shows a sample week and reads nothing.
///
/// The bars are moved and sized in Customize as a part of their own (their look comes later), the
/// title, the percentage and the day as texts (`WidgetLabel`).
struct DailyUsageWidget: View {
    let widget: IslandWidget
    let size: CGSize

    @Environment(AppModel.self) private var model
    @Environment(\.isWidgetPreview) private var isPreview
    @Environment(\.widgetRenderMode) private var renderMode
    @Environment(\.widgetDate) private var fixedDate
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone

    static var title: String { String(localized: "Daily Usage") }

    static func titlePoints(inner: CGSize) -> CGFloat { WidgetMetrics.points(inner.height, ratio: 0.12, min: 10, max: 13) }
    static func valuePoints(inner: CGSize) -> CGFloat { WidgetMetrics.points(inner.height, ratio: 0.16, min: 12, max: 18) }
    static func dayPoints(inner: CGSize) -> CGFloat { WidgetMetrics.points(inner.height, ratio: 0.1, min: 9, max: 11) }

    /// The header's height: the percentage's line.
    static func headerHeight(_ widget: IslandWidget, inner: CGSize) -> CGFloat {
        guard widget.shows(.label) || widget.shows(.value) || widget.shows(.usageDay) else { return 0 }
        return (valuePoints(inner: inner) * 1.25).rounded(.up)
    }

    /// A week as the pictures show it, ending on `now`'s day.
    static func sampleDays(now: Date, calendar: Calendar) -> [BatteryUsageDay] {
        let today = calendar.startOfDay(for: now)
        let used: [Double] = [62, 68, 58, 55, 60, 94, 66, 70]
        return used.enumerated().compactMap { index, value in
            calendar.date(byAdding: .day, value: index - (used.count - 1), to: today).map {
                BatteryUsageDay(day: $0, used: value, screenActive: 4 * 3600 + 240, screenIdle: 16 * 3600 + 960, hasData: true)
            }
        }
    }

    /// "Today", or the day's short name and date.
    static func dayText(_ day: Date, today: Date, locale: Locale, calendar: Calendar) -> String {
        day == today ? String(localized: "Today")
            : day.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).weekday(.abbreviated).month().day())
    }

    var body: some View {
        let battery = model.battery
        var calendar = Calendar(identifier: .gregorian)
        let _ = calendar.timeZone = timeZone
        let _ = calendar.locale = locale
        let today = calendar.startOfDay(for: fixedDate ?? .now)
        let days = isPreview ? Self.sampleDays(now: fixedDate ?? .now, calendar: calendar) : battery.usageDays()
        let pickedDay = isPreview ? nil : battery.pickedDay()
        let picked = days.first { $0.day == pickedDay } ?? days.last
        let comparison = picked.flatMap { BatteryUsage.comparison($0, among: days, today: today) }
        let accent = comparison == .more ? Color.orange : Color.blue
        let header = Self.headerHeight(widget, inner: size)
        VStack(alignment: .leading, spacing: header > 0 ? 4 : 0) {
            if header > 0 {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    if widget.shows(.label) { title }
                    Spacer(minLength: 4)
                    if let picked {
                        if widget.shows(.value) { value(picked, accent: accent) }
                        if widget.shows(.usageDay) { dayLabel(picked.day, today: today, calendar: calendar) }
                    }
                }
                .frame(height: header)
            }
            DailyUsageBars(days: days, picked: picked?.day, accent: accent, calendar: calendar, locale: locale,
                           look: widget.chartLook(of: .chart)) { day in
                // Live only: in a picture nothing is picked.
                guard !isPreview, renderMode == .live else { return }
                battery.selectedDay = day == today || day == battery.selectedDay ? nil : day
            }
            .frame(width: size.width, height: max(size.height - header - (header > 0 ? 4 : 0), 0))
            .movableElement(.chart, of: widget)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .whileShown { if !isPreview { battery.acquire(.history) } } stop: { if !isPreview { battery.release(.history) } }
    }

    private var title: some View {
        let points = Self.titlePoints(inner: size)
        return WidgetLabel(id: .label, text: Self.title, widget: widget, size: points, weight: .semibold, isSecondary: true) {
            Text(Self.title)
                .font(.system(size: points, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .movableElement(.label, of: widget)
    }

    private func value(_ day: BatteryUsageDay, accent: Color) -> some View {
        let points = Self.valuePoints(inner: size)
        let text = IslandFormat.percent(day.used / 100)
        return WidgetLabel(id: .value, text: text, widget: widget.withOwnDesign(.rounded, for: .value), size: points, weight: .semibold,
                           isSecondary: false) {
            Text(text)
                .font(.system(size: points, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(accent)
                .lineLimit(1)
        }
        .fixedSize()
        .movableElement(.value, of: widget)
    }

    private func dayLabel(_ day: Date, today: Date, calendar: Calendar) -> some View {
        let points = Self.dayPoints(inner: size)
        let text = Self.dayText(day, today: today, locale: locale, calendar: calendar)
        return WidgetLabel(id: .usageDay, text: text, widget: widget, size: points, weight: .medium, isSecondary: true) {
            Text(text)
                .font(.system(size: points, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .fixedSize()
        .movableElement(.usageDay, of: widget)
    }
}

/// One bar a day out of 100 % (a day of more than one charge reaches the top), the picked one in
/// colour, the day's letter under each and the percentages beside; a click on a column picks it.
struct DailyUsageBars: View {
    let days: [BatteryUsageDay]
    let picked: Date?
    let accent: Color
    let calendar: Calendar
    let locale: Locale
    /// As Customize set it (as the battery chart's): the bars' corners, their colours by how much a
    /// day used (`lightUse`, `heavyUse`), and the percentages beside them.
    var look: ChartLook = .plain
    let pick: (Date) -> Void

    @Environment(AppModel.self) private var model

    /// A day that used less than this is light, from `heavyUse` on heavy (percent of the battery).
    static let lightUse = Double(PowerState.lowLevel)
    static let heavyUse = Double(ChartLook.mediumLevel)

    /// A day's bar: the look's colour for how much it used, else grey; the picked day in its accent
    /// where the look leaves its colour automatic, at full strength where it sets one (the others
    /// a little fainter).
    private func fill(_ day: BatteryUsageDay, picked: Bool) -> AnyShapeStyle {
        let set: TextStyle.TextColor = day.used < Self.lightUse ? look.lowColor : day.used < Self.heavyUse ? look.mediumColor : look.highColor
        switch set {
        case .automatic: return picked ? AnyShapeStyle(accent) : AnyShapeStyle(Color(white: 0.62))
        case .custom(let rgb): return AnyShapeStyle(rgb.color.opacity(picked ? 1 : 0.6))
        case .artwork: return AnyShapeStyle((model.media.artworkColor.map { Color($0) } ?? .islandAccent).opacity(picked ? 1 : 0.6))
        }
    }

    var body: some View {
        let top = 100.0
        let percentages = look.percentages.map(Double.init)
        // Sized by the room it is given alone: nothing in it may push the widget taller.
        GeometryReader { proxy in
            let labels: CGFloat = proxy.size.height >= 40 ? 12 : 10
            let percentWidth: CGFloat = percentages.isEmpty ? 0 : 24
            let plot = max(proxy.size.height - labels, 1)
            let width = max(proxy.size.width - percentWidth - 2, 1)
            let slot = width / CGFloat(max(days.count, 1))
            let letter = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).weekday(.narrow)
            ZStack(alignment: .topLeading) {
                ForEach(percentages, id: \.self) { value in
                    let y = plot * (1 - CGFloat(value / top))
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: width, y: y))
                    }
                    .stroke(.white.opacity(0.16), style: StrokeStyle(lineWidth: 0.5, dash: [1.5, 2.5]))
                    Text(verbatim: IslandFormat.percent(value / 100))
                        .font(.system(size: min(8, max(plot / 5, 6))).monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .fixedSize()
                        .frame(width: percentWidth, alignment: .trailing)
                        // Beside its line, kept inside the plot at the top and the bottom.
                        .position(x: proxy.size.width - percentWidth / 2, y: min(max(y, 5), plot - 4))
                }
                ForEach(Array(days.enumerated()), id: \.element.day) { index, day in
                    let isPicked = day.day == picked
                    let height = max(plot * CGFloat(min(day.used / top, 1)), day.hasData ? 2 : 0)
                    let barWidth = max(slot * 0.62, 2)
                    UnevenRoundedRectangle(topLeadingRadius: look.corners.radius(width: barWidth),
                                           topTrailingRadius: look.corners.radius(width: barWidth), style: .continuous)
                        .fill(fill(day, picked: isPicked))
                        .frame(width: barWidth, height: height)
                        .offset(x: slot * CGFloat(index) + (slot - barWidth) / 2, y: plot - height)
                    Text(day.day.formatted(letter))
                        .font(.system(size: labels - 3, weight: isPicked ? .semibold : .regular))
                        .foregroundStyle(isPicked ? AnyShapeStyle(accent) : AnyShapeStyle(.tertiary))
                        .frame(width: slot)
                        .offset(x: slot * CGFloat(index), y: plot + 2)
                    // The whole column picks the day.
                    Color.clear
                        .contentShape(.rect)
                        .frame(width: slot, height: proxy.size.height)
                        .offset(x: slot * CGFloat(index))
                        .onTapGesture { pick(day.day) }
                        .accessibilityElement()
                        .accessibilityLabel(Text("\(day.day.formatted(.dateTime.weekday(.wide))): \(IslandFormat.percent(day.used / 100))"))
                        .accessibilityAddTraits(.isButton)
                }
            }
        }
    }
}
