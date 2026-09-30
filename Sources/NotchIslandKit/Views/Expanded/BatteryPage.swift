import SwiftUI

/// The battery on its own page: the level, what it is doing and the battery's health on the left,
/// the day's charge as the iPhone draws it on the right.
///
/// The details and the history are leased while the page is shown (`BatteryCenter`); the chart's
/// shapes are built off the main thread and only filled and stroked here, so it redraws only for a
/// new reading and at a bucket's end.
struct BatteryPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let battery = model.battery
        GeometryReader { proxy in
            HStack(alignment: .top, spacing: Metrics.Expanded.columnSpacing) {
                BatterySummary(height: proxy.size.height)
                    .frame(width: Self.summaryWidth(page: proxy.size.width))
                BatteryChartView()
            }
        }
        .whileShown {
            battery.acquire(.details)
            battery.acquire(.history)
        } stop: {
            battery.release(.details)
            battery.release(.history)
        }
    }

    /// The left column's width on a page `width` wide; the chart takes the rest.
    static func summaryWidth(page width: CGFloat) -> CGFloat {
        min(max(width * 0.3, 140), 200)
    }
}

/// The big percentage, the state line, and maximum capacity, cycles and the adapter under them.
private struct BatterySummary: View {
    let height: CGFloat

    @Environment(AppModel.self) private var model

    var body: some View {
        let state = model.power.state
        let details = model.battery.details
        VStack(alignment: .leading, spacing: Metrics.Spacing.xxSmall) {
            Text(IslandFormat.percent(Double(state.level) / 100))
                .font(.system(size: WidgetType.points(height, ratio: 0.3, min: 24, max: Metrics.Expanded.bigTimeFontSize),
                              weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(state.tint.style)
                .contentTransition(.opacity)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            // One line, whole: where "Charging — 1 h 12 min to full" is too wide (the smaller island
            // sizes), only "1 h 12 min to full" is said, which tells the charging too.
            ViewThatFits(in: .horizontal) {
                Text(BatteryPageText.state(state, details: details))
                Text(BatteryPageText.state(state, details: details, short: true))
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .layoutPriority(1)
            Spacer(minLength: Metrics.Spacing.small)
            Grid(alignment: .leading, horizontalSpacing: Metrics.Spacing.medium, verticalSpacing: Metrics.Spacing.xxSmall) {
                ForEach(BatteryPageText.facts(details), id: \.label) { fact in
                    GridRow {
                        Text(fact.label).foregroundStyle(.secondary)
                        Text(fact.value).monospacedDigit()
                    }
                }
            }
            .font(.caption)
            .lineLimit(1)
            // The state and the facts keep their lines; the percentage gives way (Extra Small).
            .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // The level only: the minutes left change about once a minute and are simply swapped.
        .animation(Motion.content, value: state.level)
    }
}

/// The chart, "Last charged to …" over it, the percentages beside it and the hours under it.
private struct BatteryChartView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var preferences = model.preferences
        let settings = preferences.battery
        let range = settings.range
        VStack(alignment: .leading, spacing: Metrics.Spacing.xSmall) {
            if settings.showsCaptions {
                let lastCharged = Text(model.battery.lastCharge.map(BatteryPageText.lastCharged) ?? "")
                // The charge's time before the range's name, which the hours under the chart tell too.
                ViewThatFits(in: .horizontal) {
                    HStack {
                        lastCharged
                        Spacer(minLength: Metrics.Spacing.medium)
                        Text(range.title)
                    }
                    lastCharged
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            // Redrawn at each bucket's end, when the window moves on; nothing between.
            let bucket = range.bucketSeconds
            let start = Date(timeIntervalSinceReferenceDate: (Date().timeIntervalSinceReferenceDate / bucket).rounded(.down) * bucket)
            PanelTimelineView(.periodic(from: start, by: bucket)) { _ in
                GeometryReader { proxy in
                    let plot = CGSize(width: max(proxy.size.width - (settings.showsCaptions ? Self.percentWidth : 0), 0),
                                      height: max(proxy.size.height - Self.hoursHeight, 0))
                    BatteryChartPlot(geometry: model.battery.chartGeometry(range: range, style: settings.style, size: plot),
                                     settings: settings, colors: colors(settings), size: plot)
                }
            }
        }
        .contextMenu {
            Picker("Style", selection: $preferences.battery.style) {
                ForEach(BatteryChartStyle.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Picker("Range", selection: $preferences.battery.range) {
                ForEach(BatteryChartRange.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Divider()
            Button("Battery Page Settings…", systemImage: "gearshape") { model.perform(.showSettingsPane(.activities)) }
        }
    }

    static let percentWidth: CGFloat = 30
    static let hoursHeight: CGFloat = 14

    private func colors(_ settings: BatteryDisplaySettings) -> BatteryChartColors {
        BatteryChartColors(normal: resolve(settings.normalColor, .white),
                           charging: resolve(settings.chargingColor, .green),
                           low: resolve(settings.lowColor, .red))
    }

    /// A chart colour: automatic is the slot's own; the accent is the theme's, as nowhere else on
    /// the page has one.
    private func resolve(_ color: StyleColor, _ automatic: Color) -> AnyShapeStyle {
        switch color {
        case .automatic: AnyShapeStyle(automatic)
        case .accent, .theme: AnyShapeStyle(Color.islandAccent)
        case .artwork: AnyShapeStyle(model.media.artworkColor.map { Color($0) } ?? automatic)
        case .semantic(let semantic):
            switch semantic {
            case .primary: AnyShapeStyle(.primary)
            case .secondary: AnyShapeStyle(.secondary)
            case .tertiary: AnyShapeStyle(.tertiary)
            case .positive: AnyShapeStyle(Color.green)
            case .warning: AnyShapeStyle(Color.orange)
            case .critical: AnyShapeStyle(Color.red)
            }
        case .named(let tint): AnyShapeStyle(tint.color ?? automatic)
        case .rgb(let rgb, let alpha): AnyShapeStyle(rgb.color.opacity(alpha))
        case .valueScale(let scale):
            // Over the chart's height: a charge red at the bottom, green at the top.
            AnyShapeStyle(LinearGradient(colors: scale == .rising ? [.green, .red] : [.red, .green],
                                         startPoint: .top, endPoint: .bottom))
        }
    }
}

private struct BatteryChartColors {
    var normal: AnyShapeStyle
    var charging: AnyShapeStyle
    var low: AnyShapeStyle
}

/// The shapes, the percentages and the hours, at `size` (the plot's own).
private struct BatteryChartPlot: View {
    let geometry: BatteryChartGeometry?
    let settings: BatteryDisplaySettings
    let colors: BatteryChartColors
    let size: CGSize

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                ZStack(alignment: .topLeading) {
                    if let geometry { shapes(geometry) }
                }
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                if settings.showsCaptions {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(verbatim: IslandFormat.percent(1))
                        Spacer(minLength: 0)
                        Text(verbatim: IslandFormat.percent(0.5))
                        Spacer(minLength: 0)
                        Text(verbatim: IslandFormat.percent(0))
                    }
                    .frame(width: BatteryChartView.percentWidth, height: size.height, alignment: .trailing)
                }
            }
            ZStack(alignment: .topLeading) {
                // Each hour just after its line, as the iPhone has them; one too near the end is left out.
                ForEach(geometry?.ticks ?? [], id: \.x) { tick in
                    if tick.x <= size.width - 16 {
                        Text(BatteryPageText.hour(tick.date))
                            .offset(x: tick.x + 2)
                    }
                }
            }
            .frame(width: size.width, height: BatteryChartView.hoursHeight, alignment: .bottomLeading)
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.tertiary)
    }

    @ViewBuilder private func shapes(_ geometry: BatteryChartGeometry) -> some View {
        if settings.shadesDisplayOff {
            ChartShape(path: geometry.displayOff).fill(.white.opacity(0.06))
        }
        ChartShape(path: geometry.axis).stroke(.white.opacity(0.18), style: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
        if settings.showsGaps {
            ChartShape(path: geometry.gaps).stroke(.white.opacity(0.2), lineWidth: 1)
        }
        switch geometry.style {
        case .bars, .area:
            let opacity = geometry.style == .area ? 0.55 : 1
            ChartShape(path: geometry.level).fill(colors.normal).opacity(opacity)
            ChartShape(path: geometry.charging).fill(colors.charging).opacity(opacity)
            ChartShape(path: geometry.low).fill(colors.low).opacity(opacity)
        case .line:
            let line = StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            ChartShape(path: geometry.level).stroke(colors.normal, style: line)
            ChartShape(path: geometry.charging).stroke(colors.charging, style: line)
            ChartShape(path: geometry.low).stroke(colors.low, style: line)
        }
    }
}

/// A prebuilt path as a shape: equal paths are not drawn again.
nonisolated private struct ChartShape: Shape, Equatable {
    let path: Path

    func path(in rect: CGRect) -> Path { path }
}

/// What the battery page says, kept out of the views so it can be tested.
nonisolated enum BatteryPageText {
    nonisolated struct Fact: Equatable {
        var label: String
        var value: String
    }

    /// "Charging — 1 h 12 min to full", "5 h 40 min left", "Fully charged", "On power adapter";
    /// `short`, charging is only "1 h 12 min to full".
    static func state(_ state: PowerState, details: BatteryDetails?, short: Bool = false) -> String {
        if state.isCharging {
            guard let minutes = state.minutesRemaining ?? details?.minutesToFull else { return String(localized: "Charging") }
            if short { return String(localized: "\(duration(minutes)) to full") }
            return String(localized: "Charging — \(duration(minutes)) to full")
        }
        if state.isPluggedIn {
            return state.isCharged ? String(localized: "Fully charged") : String(localized: "On power adapter")
        }
        guard let minutes = state.minutesRemaining ?? details?.minutesToEmpty else { return String(localized: "On battery") }
        return String(localized: "\(duration(minutes)) left")
    }

    /// "1 h 12 min", "45 min", "5 h".
    static func duration(_ minutes: Int) -> String {
        let hours = max(minutes, 0) / 60, rest = max(minutes, 0) % 60
        if hours == 0 { return String(localized: "\(rest) min") }
        if rest == 0 { return String(localized: "\(hours) h") }
        return String(localized: "\(hours) h \(rest) min")
    }

    /// Maximum capacity and cycles, "—" until read; the adapter while one is connected.
    static func facts(_ details: BatteryDetails?) -> [Fact] {
        var facts = [
            Fact(label: String(localized: "Maximum Capacity"),
                 value: details?.maximumCapacityPercent.map { IslandFormat.percent(Double($0) / 100) } ?? "—"),
            Fact(label: String(localized: "Cycle Count"), value: details?.cycleCount.map { "\($0)" } ?? "—"),
        ]
        if let watts = details?.adapterWatts {
            facts.append(Fact(label: String(localized: "Power Adapter"), value: String(localized: "\(watts) W")))
        }
        return facts
    }

    /// "Last charged to 80% at 10:40", "… yesterday at 18:30", "… on Mon at 09:15".
    static func lastCharged(_ charge: BatteryLastCharge) -> String {
        let calendar = Calendar.autoupdatingCurrent
        let percent = IslandFormat.percent(Double(charge.level) / 100)
        let time = charge.date.formatted(date: .omitted, time: .shortened)
        if calendar.isDateInToday(charge.date) { return String(localized: "Last charged to \(percent) at \(time)") }
        if calendar.isDateInYesterday(charge.date) { return String(localized: "Last charged to \(percent) yesterday at \(time)") }
        let day = charge.date.formatted(.dateTime.weekday(.abbreviated))
        return String(localized: "Last charged to \(percent) on \(day) at \(time)")
    }

    /// An axis hour: "00", "06", "12", "18".
    static func hour(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)))
    }
}
