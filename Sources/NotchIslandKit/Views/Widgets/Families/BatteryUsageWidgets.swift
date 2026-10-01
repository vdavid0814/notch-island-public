import SwiftUI

// The iPhone's Battery Usage on the island (`BatterySpecs`): Daily Usage — the last eight days'
// use as bars, one picked (today by default; a click picks another) — and Screen Activity, the
// displays' time that day. Both read the history (`BatteryCenter.usageDays`), leased while shown;
// a picture in Settings shows a sample week and reads nothing.

/// A week as the pictures show it.
enum BatteryUsageSamples {
    static func days(now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> [BatteryUsageDay] {
        let today = calendar.startOfDay(for: now)
        let used: [Double] = [62, 68, 58, 55, 60, 94, 66, 70]
        return used.enumerated().compactMap { index, value in
            calendar.date(byAdding: .day, value: index - (used.count - 1), to: today).map {
                BatteryUsageDay(day: $0, used: value, screenActive: 4 * 3600 + 240, screenIdle: 16 * 3600 + 960, hasData: true)
            }
        }
    }
}

/// The days and the one picked, as a Battery Usage widget reads them.
private struct BatteryUsageSource<Content: View>: View {
    @ViewBuilder let content: (_ days: [BatteryUsageDay], _ picked: BatteryUsageDay?, _ pick: @escaping (Date) -> Void) -> Content

    @Environment(AppModel.self) private var model
    @Environment(\.isWidgetPreview) private var isPicture
    @Environment(\.widgetReadsLive) private var readsLive
    @Environment(\.widgetRenderMode) private var renderMode
    private var isPreview: Bool { isPicture && !readsLive }

    var body: some View {
        let battery = model.battery
        let days = isPreview ? BatteryUsageSamples.days() : battery.usageDays()
        let pickedDay = isPreview ? nil : battery.pickedDay()
        let picked = days.first { $0.day == pickedDay } ?? days.last
        content(days, picked) { day in
            // Live only: on the canvas and in pictures nothing is picked.
            guard !isPreview, renderMode == .live else { return }
            let today = Calendar.autoupdatingCurrent.startOfDay(for: Date())
            battery.selectedDay = day == today || day == battery.selectedDay ? nil : day
        }
        .whileShown { if !isPreview { battery.acquire(.history) } } stop: { if !isPreview { battery.release(.history) } }
    }
}

/// Daily Usage: what the picked day used and how that compares, and the last days' bars.
struct BatteryUsageWidget: View {
    let widget: IslandWidget
    let size: CGSize

    @Environment(\.widgetFrameProbe) private var probe
    @Environment(\.widgetStyle) private var style
    @Environment(\.widgetArtworkColor) private var artwork

    var body: some View {
        BatteryUsageSource { days, picked, pick in
            let calendar = Calendar.autoupdatingCurrent
            let today = calendar.startOfDay(for: Date())
            let comparison = picked.flatMap { BatteryUsage.comparison($0, among: days, today: today) }
            // The iPhone's: blue, orange where the day used more than usual (or the widget's Chart colour).
            let accent = ResolvedLine(style.element(.chart)).fillColor(value: 1, artwork: artwork)
                ?? (comparison == .more ? Color.orange : Color.blue)
            let showsSentence = size.height >= 130 && size.width >= 170
            // Low: the title, the percentage and the day on one line, smaller, so the bars keep their room.
            let compact = size.height < 110
            let dayName = picked.map { $0.day == today ? String(localized: "Today") : $0.day.formatted(.dateTime.weekday(.abbreviated).month().day()) }
            VStack(alignment: .leading, spacing: compact ? 2 : 4) {
                if compact {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("Daily Usage")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(comparison == .more ? AnyShapeStyle(accent) : AnyShapeStyle(.secondary))
                        Spacer(minLength: 4)
                        if let picked {
                            Text(IslandFormat.percent(picked.used / 100))
                                .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                                .foregroundStyle(accent)
                            Text(dayName ?? "")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .lineLimit(1)
                } else {
                    Text("Daily Usage")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(comparison == .more ? AnyShapeStyle(accent) : AnyShapeStyle(.secondary))
                    if showsSentence, let picked {
                        Text(BatteryUsage.sentence(comparison, day: picked.day, isToday: picked.day == today))
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(3)
                            .minimumScaleFactor(0.85)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let picked {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(IslandFormat.percent(picked.used / 100))
                                .font(.system(size: size.height >= 140 ? 22 : 17, weight: .semibold, design: .rounded).monospacedDigit())
                                .foregroundStyle(accent)
                            Text(dayName ?? "")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .lineLimit(1)
                    }
                }
                DailyUsageBars(days: days, picked: picked?.day, accent: accent, today: today, pick: pick)
                    .frame(maxHeight: .infinity)
                    .layoutPriority(-1)
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .editorElement(.chart, in: probe)
        }
    }
}

/// One bar a day, the picked one in colour, the day's letter under each and the percentages beside.
private struct DailyUsageBars: View {
    let days: [BatteryUsageDay]
    let picked: Date?
    let accent: Color
    let today: Date
    let pick: (Date) -> Void

    var body: some View {
        // Out of 100 %, as the iPhone's (a day of more than one charge reaches the top).
        let top = 100.0
        // Sized by the room it is given alone: nothing in it may push the widget taller.
        GeometryReader { whole in
        let showsPercent = whole.size.height >= 46
        let labels: CGFloat = whole.size.height >= 40 ? 12 : 10
        HStack(alignment: .top, spacing: 4) {
            GeometryReader { proxy in
                let plot = max(proxy.size.height - labels, 1)
                let slot = proxy.size.width / CGFloat(max(days.count, 1))
                ZStack(alignment: .topLeading) {
                    // 0, 50 and 100 %.
                    ForEach([0.0, 50, 100], id: \.self) { value in
                        Path { path in
                            let y = plot * (1 - CGFloat(value / top))
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                        }
                        .stroke(.white.opacity(0.16), style: StrokeStyle(lineWidth: 0.5, dash: [1.5, 2.5]))
                    }
                    ForEach(Array(days.enumerated()), id: \.element.day) { index, day in
                        let isPicked = day.day == picked
                        let height = max(plot * CGFloat(min(day.used / top, 1)), day.hasData ? 2 : 0)
                        let width = max(slot * 0.62, 2)
                        UnevenRoundedRectangle(topLeadingRadius: min(width * 0.3, 3), topTrailingRadius: min(width * 0.3, 3),
                                               style: .continuous)
                            .fill(isPicked ? AnyShapeStyle(accent) : AnyShapeStyle(Color(white: 0.62)))
                            .frame(width: width, height: height)
                            .offset(x: slot * CGFloat(index) + (slot - width) / 2, y: plot - height)
                        Text(day.day.formatted(.dateTime.weekday(.narrow)))
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
            if showsPercent {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(verbatim: IslandFormat.percent(top / 100))
                    Spacer(minLength: 0)
                    Text(verbatim: IslandFormat.percent(top / 200))
                    Spacer(minLength: 0)
                    Text(verbatim: IslandFormat.percent(0))
                }
                .font(.system(size: 8).monospacedDigit())
                .foregroundStyle(.tertiary)
                .padding(.bottom, labels - 4)
                .fixedSize(horizontal: true, vertical: false)
                .frame(height: whole.size.height)
            }
        }
        }
    }
}

/// Screen Activity: how long the displays were on and off the picked day.
struct BatteryScreenTimeWidget: View {
    let widget: IslandWidget
    let size: CGSize

    @Environment(\.widgetFrameProbe) private var probe
    @Environment(\.widgetStyle) private var style
    @Environment(\.locale) private var locale

    var body: some View {
        BatteryUsageSource { _, picked, _ in
            let format = WidgetFormat(style.format, locale: locale)
            let today = Calendar.autoupdatingCurrent.startOfDay(for: Date())
            let isPast = picked.map { $0.day != today } ?? false
            // One over the other where it is narrow and tall enough; beside each other otherwise.
            let stacked = size.width < 150 && size.height >= 90
            let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
            VStack(alignment: .leading, spacing: 2) {
                if isPast, let picked, size.height >= 70 {
                    Text(picked.day.formatted(.dateTime.weekday(.wide).month().day()))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                layout {
                    // The short words where the full ones do not fit.
                    let short = size.width < 200
                    figure(short ? String(localized: "Active") : String(localized: "Screen Active"),
                           picked.map { format.duration(minutes: Int($0.screenActive / 60)) } ?? "—")
                    figure(short ? String(localized: "Idle") : String(localized: "Screen Idle"),
                           picked.map { format.duration(minutes: Int($0.screenIdle / 60)) } ?? "—")
                }
            }
            .frame(width: size.width, height: size.height, alignment: stacked ? .topLeading : .leading)
            .editorElement(.chart, in: probe)
        }
    }

    private func figure(_ caption: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(caption)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                // As large as the height lets it, no wider than its half of the widget holds "16h 16m".
                .font(.system(size: min(max(size.height * 0.28, 11), 22, size.width * 0.085), weight: .semibold, design: .rounded)
                    .monospacedDigit())
                .minimumScaleFactor(0.6)
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
