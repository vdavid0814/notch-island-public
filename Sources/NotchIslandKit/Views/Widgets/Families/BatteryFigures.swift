import SwiftUI

// The battery's figures, a widget each (`BatterySpecs`): the time left, the health, the cycles, the
// power flowing, the temperature and the charger — and the day's chart. Each leases the battery's
// details only while it is shown (`BatteryCenter`); a picture in Settings shows sample values and
// reads nothing.

/// What each figure says.
enum BatteryReadings {
    /// A battery a year old on its charger, for the pictures in Settings.
    static let sampleState = PowerState(hasBattery: true, level: 76, isCharging: true, isPluggedIn: true, isCharged: false,
                                        minutesRemaining: 72, isLowPowerMode: false)
    static let sampleDetails = BatteryDetails.demo(power: sampleState)

    static func reading(_ kind: IslandWidgetKind, state: PowerState, details: BatteryDetails?, format: WidgetFormat) -> WidgetReading {
        switch kind {
        case .batteryTime:
            if state.isCharging {
                let minutes = details?.minutesToFull ?? state.minutesRemaining
                return WidgetReading(minutes.map { format.duration(minutes: $0) } ?? "—", caption: String(localized: "Until Full"),
                                     symbol: "bolt.fill", widest: format.duration(minutes: 23 * 60 + 58))
            }
            if state.isPluggedIn {
                return WidgetReading(state.isCharged ? String(localized: "Charged") : String(localized: "On Hold"),
                                     caption: String(localized: "Battery"), symbol: "powerplug.fill")
            }
            let minutes = state.minutesRemaining ?? details?.minutesToEmpty
            return WidgetReading(minutes.map { format.duration(minutes: $0) } ?? "—", caption: String(localized: "Remaining"),
                                 symbol: "hourglass", tint: state.level <= 10 ? .red : nil, widest: format.duration(minutes: 23 * 60 + 58))
        case .batteryHealth:
            let isFine = details?.condition == .normal || details == nil
            return WidgetReading(details?.maximumCapacityPercent.map { format.percent(Double($0) / 100) } ?? "—",
                                 caption: isFine ? String(localized: "Maximum Capacity") : String(localized: "Service Recommended"),
                                 symbol: isFine ? "heart.fill" : "exclamationmark.triangle.fill", tint: isFine ? nil : .orange,
                                 widest: format.percent(1))
        case .batteryCycles:
            return WidgetReading(details?.cycleCount.map { $0.formatted(.number.grouping(.never)) } ?? "—",
                                 caption: details?.designCycleCount.map { String(localized: "of \($0) Cycles") } ?? String(localized: "Cycles"),
                                 symbol: "arrow.triangle.2.circlepath", widest: "8888")
        case .batteryPower:
            let watts = Measurement<UnitPower>.FormatStyle.measurement(width: .narrow, usage: .asProvided,
                                                                       numberFormatStyle: .number.precision(.fractionLength(1)))
            func text(_ value: Double) -> String { Measurement(value: value, unit: UnitPower.watts).formatted(watts.locale(format.locale)) }
            if let charge = details?.chargeWatts, state.isCharging {
                return WidgetReading("+" + text(charge), caption: String(localized: "Charging"), symbol: "bolt.fill", tint: .green,
                                     widest: "+" + text(188.8))
            }
            if let draw = details?.systemDrawWatts {
                return WidgetReading((state.isPluggedIn ? "" : "−") + text(draw),
                                     caption: state.isPluggedIn ? String(localized: "From the Charger") : String(localized: "From the Battery"),
                                     symbol: "bolt.fill", widest: "−" + text(188.8))
            }
            return WidgetReading("—", caption: String(localized: "Power"), symbol: "bolt.fill", widest: "−" + text(88.8))
        case .batteryTemperature:
            let celsius = details?.temperature
            return WidgetReading(celsius.map { format.temperature(celsius: $0) } ?? "—", caption: String(localized: "Battery"),
                                 symbol: (celsius ?? 0) >= 40 ? "thermometer.high" : "thermometer.medium",
                                 tint: (celsius ?? 0) >= 45 ? .red : (celsius ?? 0) >= 40 ? .orange : nil,
                                 widest: format.temperature(celsius: 188))
        case .charger:
            guard state.isPluggedIn else {
                return WidgetReading("—", caption: String(localized: "Not Connected"), symbol: "powerplug", widest: "188 W")
            }
            let watts = details?.adapterWatts.map {
                Measurement(value: Double($0), unit: UnitPower.watts)
                    .formatted(.measurement(width: .narrow, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0)))
                        .locale(format.locale))
            }
            return WidgetReading(watts ?? "—", caption: state.isCharging ? String(localized: "Charging") : String(localized: "Not Charging"),
                                 symbol: "powerplug.fill", tint: state.isCharging ? .green : nil, widest: "188 W")
        default:
            return WidgetReading("—", caption: kind.title, symbol: kind.systemImage)
        }
    }
}

/// Reads the battery for a figure: the live state and the details, leased while shown; samples in
/// a picture. The Power figure reads again every five seconds while it is shown.
private struct BatteryFigureSource<Content: View>: View {
    let kind: IslandWidgetKind
    @ViewBuilder let content: (WidgetReading) -> Content

    @Environment(AppModel.self) private var model
    @Environment(\.isWidgetPreview) private var isPicture
    @Environment(\.widgetReadsLive) private var readsLive
    /// Samples in a picture that reads nothing.
    private var isPreview: Bool { isPicture && !readsLive }
    @Environment(\.widgetStyle) private var style
    @Environment(\.locale) private var locale

    var body: some View {
        let battery = model.battery
        let format = WidgetFormat(style.format, locale: locale)
        let lease: BatteryCenter.Lease = kind == .batteryPower ? .power : .details
        let reading = isPreview
            ? BatteryReadings.reading(kind, state: BatteryReadings.sampleState, details: BatteryReadings.sampleDetails, format: format)
            : BatteryReadings.reading(kind, state: model.power.state, details: battery.details, format: format)
        content(reading)
            .whileShown { if !isPreview { battery.acquire(lease) } } stop: { if !isPreview { battery.release(lease) } }
    }
}

struct BatteryFigureWidget: View {
    let widget: IslandWidget
    let size: CGSize

    var body: some View {
        BatteryFigureSource(kind: widget.kind) { ReadingWidget(widget: widget, size: size, reading: $0) }
    }
}

struct BatteryFigureElement: View {
    let widget: IslandWidget
    let id: ElementID

    var body: some View {
        if widget.kind == .batteryChart {
            BatteryChartSource { ReadingElement(id: id, reading: $0) }
        } else {
            BatteryFigureSource(kind: widget.kind) { ReadingElement(id: id, reading: $0) }
        }
    }
}

// MARK: - Chart

/// The chart widget's reading beside its chart: the level now, under the range's name.
private struct BatteryChartSource<Content: View>: View {
    @ViewBuilder let content: (WidgetReading) -> Content

    @Environment(AppModel.self) private var model
    @Environment(\.isWidgetPreview) private var isPicture
    @Environment(\.widgetReadsLive) private var readsLive
    /// Samples in a picture that reads nothing.
    private var isPreview: Bool { isPicture && !readsLive }
    @Environment(\.widgetStyle) private var style
    @Environment(\.locale) private var locale

    var body: some View {
        let state = isPreview ? BatteryReadings.sampleState : model.power.state
        let format = WidgetFormat(style.format, locale: locale)
        content(WidgetReading(format.percent(Double(state.level) / 100), caption: model.preferences.battery.range.title,
                              symbol: state.isCharging ? "bolt.fill" : "battery.75percent", widest: format.percent(1)))
    }
}

/// The day's charge, as the battery page draws it (the same shapes, built off the main thread and
/// kept by `BatteryCenter`): redrawn for a new reading and at a bucket's end, never between.
struct BatteryChartElement: View {
    let widget: IslandWidget
    /// The chart's own room.
    let size: CGSize

    @Environment(AppModel.self) private var model
    @Environment(\.isWidgetPreview) private var isPicture
    @Environment(\.widgetReadsLive) private var readsLive
    /// Samples in a picture that reads nothing.
    private var isPreview: Bool { isPicture && !readsLive }
    @Environment(\.widgetArtworkColor) private var artwork

    var body: some View {
        let battery = model.battery
        var settings = model.preferences.battery
        // A widget has no room for the page's captions: the shapes alone, and the hours where it is tall.
        let _ = settings.showsCaptions = false
        let showsHours = size.height >= 60
        let plot = CGSize(width: max(size.width, 0), height: max(size.height - (showsHours ? BatteryChartPlot.hoursHeight : 0), 0))
        let bucket = settings.range.bucketSeconds
        let start = Date(timeIntervalSinceReferenceDate: (Date().timeIntervalSinceReferenceDate / bucket).rounded(.down) * bucket)
        PanelTimelineView(.periodic(from: start, by: bucket)) { _ in
            BatteryChartPlot(geometry: battery.chartGeometry(range: settings.range, style: settings.style, size: plot),
                             settings: settings, colors: BatteryChartColors(settings, artwork: artwork), size: plot,
                             showsHours: showsHours)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .whileShown { if !isPreview { battery.acquire(.history) } } stop: { if !isPreview { battery.release(.history) } }
        .accessibilityLabel("Battery chart")
    }
}

/// The chart filling the widget, the level and the range in a line over it where there is room.
struct BatteryChartWidget: View {
    let widget: IslandWidget
    let size: CGSize

    @Environment(\.widgetFrameProbe) private var probe
    @Environment(\.widgetStyle) private var style

    var body: some View {
        let showsHeader = size.height >= 70 && (widget.shows(.value) || widget.shows(.label))
        let headerSize = style.textPoints(.value, auto: WidgetType.fitted(12, fit: 14, widget.size(of: .value), floor: 9), fit: 14)
        let captionSize = style.textPoints(.label, auto: WidgetType.fitted(11, fit: 13, widget.size(of: .label), floor: 8), fit: 13)
        let headerHeight = showsHeader ? (max(headerSize, captionSize) * WidgetType.lineHeight).rounded(.up) + 3 : 0
        VStack(alignment: .leading, spacing: 3) {
            if showsHeader {
                BatteryChartSource { reading in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        if widget.shows(.value) {
                            Text(reading.value)
                                .widgetTextElement(.value, ReadingWidget.valueType.at(headerSize), fit: 14, in: style, probe: probe)
                        }
                        if widget.shows(.label) {
                            Text(style.element(.label)?.text.labelOverride ?? reading.caption)
                                .widgetTextElement(.label, ReadingWidget.captionType.at(captionSize), fit: 13, in: style, probe: probe)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .lineLimit(1)
                }
                .frame(height: headerHeight - 3)
            }
            if widget.shows(.chart) {
                BatteryChartElement(widget: widget, size: CGSize(width: size.width - 4, height: max(size.height - headerHeight, 0)))
                    .editorElement(.chart, in: probe)
            }
        }
        .padding(.horizontal, 2)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }
}
