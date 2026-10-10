import SwiftUI

// The widgets built on the readout as World Clock is (`ReadingWidget`): the battery's figures — the
// time left, the health, the cycles, the power flowing, the temperature, the charger, the last
// charge — and the Mac's uptime and free disk space. Each reads only while it is shown; a picture
// (the gallery, Customize's editor) shows samples and reads nothing.

/// What a readout shows as a picture draws it: a sample, or the world clock's time `now`.
enum Readouts {
    static func picture(_ widget: IslandWidget, now: Date = .now, locale: Locale = .current,
                        timeZone: TimeZone = .current) -> WidgetReading {
        switch widget.kind {
        case .worldClock: WorldClockWidget.reading(widget.config, at: now, locale: locale, home: timeZone)
        case .uptime: SystemReadings.uptime(SystemReadings.sampleUptime, thermal: .nominal, locale: locale)
        case .diskSpace: SystemReadings.disk(SystemReadings.sampleDisk, locale: locale)
        case .memory: SystemReadings.memory(SystemReadings.sampleMemory.used, of: SystemReadings.sampleMemory.total, locale: locale)
        case .chipTemperature: SystemReadings.chip(SystemReadings.sampleChip, name: "Apple M5", locale: locale)
        default:
            BatteryReadings.reading(widget.kind, state: BatteryReadings.sampleState, details: BatteryReadings.sampleDetails,
                                    lastCharge: BatteryReadings.sampleLastCharge(now: now, timeZone: timeZone),
                                    now: now, locale: locale, timeZone: timeZone)
        }
    }
}

// MARK: - Battery

/// What each battery figure says.
enum BatteryReadings {
    /// A battery on its charger, three quarters full, for the pictures.
    static let sampleState = PowerState(hasBattery: true, level: 76, isCharging: true, isPluggedIn: true, isCharged: false,
                                        minutesRemaining: 72, isLowPowerMode: false)

    /// A battery a year and a half old (`BatteryDetails.demo`), charging at 42 W and 31 °C warm.
    static let sampleDetails: BatteryDetails = {
        var details = BatteryDetails.demo(power: sampleState)
        details.chargeWatts = 42.6
        details.systemDrawWatts = 11.4
        details.temperature = 31
        details.minutesToFull = 72
        return details
    }()

    /// Charged to 100 % yesterday at 18:30.
    static func sampleLastCharge(now: Date, timeZone: TimeZone) -> BatteryLastCharge {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return BatteryLastCharge(level: 100, date: calendar.startOfDay(for: now).addingTimeInterval(-5.5 * 3600))
    }

    /// The details each figure reads, as long as it is shown: the Power figure again every five
    /// seconds, the last charge from the history.
    static func lease(_ kind: IslandWidgetKind) -> BatteryCenter.Lease {
        switch kind {
        case .batteryPower: .power
        case .batteryLastCharge: .history
        default: .details
        }
    }

    static func reading(_ kind: IslandWidgetKind, state: PowerState, details: BatteryDetails?, lastCharge: BatteryLastCharge?,
                        now: Date, locale: Locale, timeZone: TimeZone) -> WidgetReading {
        func duration(_ minutes: Int) -> String {
            Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .narrow).locale(locale))
        }
        func watts(_ value: Double, decimals: Int) -> String {
            Measurement(value: value, unit: UnitPower.watts)
                .formatted(.measurement(width: .narrow, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(decimals)))
                    .locale(locale))
        }
        let widestTime = duration(23 * 60 + 58)
        switch kind {
        case .batteryTime:
            if state.isCharging {
                let minutes = details?.minutesToFull ?? state.minutesRemaining
                return WidgetReading(minutes.map(duration) ?? "—", caption: String(localized: "Until Full"), symbol: "bolt.fill",
                                     widest: widestTime)
            }
            if state.isPluggedIn {
                return WidgetReading(state.isCharged ? String(localized: "Charged") : String(localized: "On Hold"),
                                     caption: String(localized: "Battery"), symbol: "powerplug.fill")
            }
            let minutes = state.minutesRemaining ?? details?.minutesToEmpty
            return WidgetReading(minutes.map(duration) ?? "—", caption: String(localized: "Remaining"), symbol: "hourglass",
                                 widest: widestTime)
        case .batteryHealth:
            let isFine = details.map { $0.condition == .normal } ?? true
            return WidgetReading(details?.maximumCapacityPercent.map { IslandFormat.percent(Double($0) / 100) } ?? "—",
                                 caption: isFine ? String(localized: "Maximum Capacity") : String(localized: "Service Recommended"),
                                 symbol: isFine ? "heart.fill" : "exclamationmark.triangle.fill", widest: IslandFormat.percent(1))
        case .batteryCycles:
            let count = { (value: Int) in value.formatted(.number.grouping(.never).locale(locale)) }
            return WidgetReading(details?.cycleCount.map(count) ?? "—",
                                 caption: details?.designCycleCount.map { String(localized: "of \(count($0)) Cycles") } ?? String(localized: "Cycles"),
                                 symbol: "arrow.triangle.2.circlepath", widest: "8888")
        case .batteryPower:
            if let charge = details?.chargeWatts, state.isCharging {
                return WidgetReading("+" + watts(charge, decimals: 1), caption: String(localized: "Charging"), symbol: "bolt.fill",
                                     widest: "+" + watts(188.8, decimals: 1))
            }
            if let draw = details?.systemDrawWatts {
                return WidgetReading((state.isPluggedIn ? "" : "−") + watts(draw, decimals: 1),
                                     caption: state.isPluggedIn ? String(localized: "From the Charger") : String(localized: "From the Battery"),
                                     symbol: "bolt.fill", widest: "−" + watts(188.8, decimals: 1))
            }
            return WidgetReading("—", caption: String(localized: "Power"), symbol: "bolt.fill", widest: "−" + watts(88.8, decimals: 1))
        case .batteryTemperature:
            let celsius = details?.temperature
            return WidgetReading(celsius.map { temperature($0, locale: locale) } ?? "—", caption: String(localized: "Battery"),
                                 symbol: (celsius ?? 0) >= 40 ? "thermometer.high" : "thermometer.medium",
                                 widest: temperature(188, locale: locale))
        case .charger:
            guard state.isPluggedIn else {
                return WidgetReading("—", caption: String(localized: "Not Connected"), symbol: "powerplug", widest: "188 W")
            }
            return WidgetReading(details?.adapterWatts.map { watts(Double($0), decimals: 0) } ?? "—",
                                 caption: state.isCharging ? String(localized: "Charging") : String(localized: "Not Charging"),
                                 symbol: "powerplug.fill", widest: watts(188, decimals: 0))
        case .batteryLastCharge:
            guard let lastCharge else {
                return WidgetReading("—", caption: String(localized: "Last Charged"), symbol: "battery.100percent.bolt",
                                     widest: IslandFormat.percent(1))
            }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            var style = Date.FormatStyle.dateTime.hour().minute()
            style.timeZone = timeZone
            style.locale = locale
            let time = lastCharge.date.formatted(style)
            let today = calendar.startOfDay(for: now)
            let day = calendar.startOfDay(for: lastCharge.date)
            let when: String
            if day == today {
                when = String(localized: "Today, \(time)")
            } else if calendar.date(byAdding: .day, value: -1, to: today) == day {
                when = String(localized: "Yesterday, \(time)")
            } else {
                var weekday = Date.FormatStyle.dateTime.weekday(.abbreviated).hour().minute()
                weekday.timeZone = timeZone
                weekday.locale = locale
                when = lastCharge.date.formatted(weekday)
            }
            return WidgetReading(IslandFormat.percent(Double(lastCharge.level) / 100), caption: String(localized: "Last Charged · \(when)"),
                                 symbol: "battery.100percent.bolt", widest: IslandFormat.percent(1))
        default:
            return WidgetReading("—", caption: kind.title, symbol: kind.systemImage)
        }
    }

    /// In the unit the locale measures in (Fahrenheit in the US).
    static func temperature(_ celsius: Double, locale: Locale) -> String {
        let unit: UnitTemperature = locale.measurementSystem == .us ? .fahrenheit : .celsius
        return Measurement(value: celsius, unit: UnitTemperature.celsius).converted(to: unit)
            .formatted(.measurement(width: .narrow, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0)))
                .locale(locale))
    }
}

/// One of the battery's figures: the live state and the details, leased only while shown
/// (`BatteryCenter`); a sample in a picture.
struct BatteryFigureWidget: View {
    let widget: IslandWidget
    let size: CGSize

    @Environment(AppModel.self) private var model
    @Environment(\.isWidgetPreview) private var isPreview
    @Environment(\.widgetDate) private var fixedDate
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone

    var body: some View {
        let battery = model.battery
        let lease = BatteryReadings.lease(widget.kind)
        let reading = isPreview
            ? Readouts.picture(widget, now: fixedDate ?? .now, locale: locale, timeZone: timeZone)
            : BatteryReadings.reading(widget.kind, state: model.power.state, details: battery.details, lastCharge: battery.lastCharge,
                                      now: .now, locale: locale, timeZone: timeZone)
        ReadingWidget(widget: widget, size: size, reading: reading)
            .whileShown { if !isPreview { battery.acquire(lease) } } stop: { if !isPreview { battery.release(lease) } }
    }
}

// MARK: - The Mac

/// What the Mac's figures say: its uptime with how warm it runs, and the startup disk's free space.
enum SystemReadings {
    /// Three days and four hours, for the pictures.
    static let sampleUptime: TimeInterval = 3 * 86400 + 4 * 3600
    static let sampleDisk: (free: Int64, total: Int64) = (212_000_000_000, 494_000_000_000)
    /// 9.6 GB of 16 GB in use.
    static let sampleMemory: (used: UInt64, total: UInt64) = (10_307_921_510, 17_179_869_184)

    /// 46 °C on average, the hottest core 51 °C.
    static let sampleChip = ChipReading(average: 46, hottest: 51)

    /// The cores' average, and the hottest under it beside the chip's name; the thermometer fuller as
    /// it warms.
    static func chip(_ reading: ChipReading?, name: String, locale: Locale) -> WidgetReading {
        guard let reading else { return WidgetReading("—", caption: name, symbol: "thermometer.medium") }
        let symbol = reading.average < 45 ? "thermometer.low" : reading.average < 75 ? "thermometer.medium" : "thermometer.high"
        return WidgetReading(BatteryReadings.temperature(reading.average, locale: locale),
                             caption: String(localized: "\(ChipSensors.shortName(name)) · Hottest \(BatteryReadings.temperature(reading.hottest, locale: locale))"),
                             symbol: symbol, widest: BatteryReadings.temperature(188, locale: locale))
    }

    /// The memory in use, in MB under a gigabyte, in GB above (as Activity Monitor writes it), of
    /// the Mac's whole.
    static func memory(_ used: UInt64?, of total: UInt64, locale: Locale) -> WidgetReading {
        let bytes = { (value: UInt64) in Int64(clamping: value).formatted(.byteCount(style: .memory).locale(locale)) }
        guard let used else { return WidgetReading("—", caption: String(localized: "Memory Used"), symbol: "memorychip") }
        return WidgetReading(bytes(used), caption: String(localized: "Used of \(bytes(total))"), symbol: "memorychip",
                             widest: bytes(88_880_000_000))
    }

    /// The startup disk's free space (what Finder calls available) and its size. Touches the disk:
    /// never on the main thread.
    nonisolated static func disk() -> (free: Int64, total: Int64)? {
        let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey,
                                                                             .volumeTotalCapacityKey])
        guard let free = values?.volumeAvailableCapacityForImportantUsage, let total = values?.volumeTotalCapacity else { return nil }
        return (free, Int64(total))
    }

    static func disk(_ space: (free: Int64, total: Int64)?, locale: Locale) -> WidgetReading {
        guard let space else { return WidgetReading("—", caption: String(localized: "Free"), symbol: "internaldrive.fill") }
        let bytes = { (value: Int64) in value.formatted(.byteCount(style: .file).locale(locale)) }
        return WidgetReading(bytes(space.free), caption: String(localized: "Free of \(bytes(space.total))"),
                             symbol: "internaldrive.fill", widest: bytes(888_800_000_000))
    }

    static func uptime(_ seconds: TimeInterval, thermal: ProcessInfo.ThermalState, locale: Locale) -> WidgetReading {
        let minutes = Int(seconds / 60)
        let allowed: Set<Duration.UnitsFormatStyle.Unit> = minutes >= 24 * 60 ? [.days, .hours] : [.hours, .minutes]
        let value = Duration.seconds(minutes * 60).formatted(.units(allowed: allowed, width: .narrow).locale(locale))
        let state = switch thermal {
        case .nominal: String(localized: "Running Cool")
        case .fair: String(localized: "Warm")
        case .serious: String(localized: "Hot")
        case .critical: String(localized: "Too Hot")
        @unknown default: String(localized: "Uptime")
        }
        let symbol = thermal == .nominal || thermal == .fair ? "clock.arrow.circlepath" : "thermometer.high"
        return WidgetReading(value, caption: state, symbol: symbol,
                             widest: Duration.seconds(88 * 86400 + 88 * 3600).formatted(.units(allowed: [.days, .hours], width: .narrow)
                                 .locale(locale)))
    }
}

/// How long the Mac has been up, redrawn on the minute while shown; a sample in a picture.
struct UptimeWidget: View {
    let widget: IslandWidget
    let size: CGSize

    @Environment(\.isWidgetPreview) private var isPreview
    @Environment(\.locale) private var locale

    var body: some View {
        if isPreview {
            ReadingWidget(widget: widget, size: size, reading: Readouts.picture(widget, locale: locale))
        } else {
            PanelTimelineView(.everyMinute) { _ in
                ReadingWidget(widget: widget, size: size,
                              reading: SystemReadings.uptime(ProcessInfo.processInfo.systemUptime,
                                                             thermal: ProcessInfo.processInfo.thermalState, locale: locale))
            }
        }
    }
}

/// The memory in use, read every two seconds while shown (`SystemStatsMonitor`, shared with the
/// System widget); a sample in a picture.
struct MemoryWidget: View {
    let widget: IslandWidget
    let size: CGSize

    @Environment(AppModel.self) private var model
    @Environment(\.isWidgetPreview) private var isPreview
    @Environment(\.locale) private var locale

    var body: some View {
        let stats = model.stats
        ReadingWidget(widget: widget, size: size,
                      reading: isPreview ? Readouts.picture(widget, locale: locale)
                          : SystemReadings.memory(stats.memoryBytes, of: stats.physicalMemory, locale: locale))
            .whileShown { if !isPreview { withoutAnimation { stats.startObserving() } } } stop: { if !isPreview { stats.stopObserving() } }
    }
}

/// The startup disk's free space, read as the widget comes on screen (the space changes slowly,
/// and nothing watches it); a sample in a picture.
struct DiskSpaceWidget: View {
    let widget: IslandWidget
    let size: CGSize

    @Environment(\.isWidgetPreview) private var isPreview
    @Environment(\.locale) private var locale
    @State private var space: (free: Int64, total: Int64)?

    var body: some View {
        ReadingWidget(widget: widget, size: size,
                      reading: isPreview ? Readouts.picture(widget, locale: locale) : SystemReadings.disk(space, locale: locale))
            .whileShown {
                guard !isPreview else { return }
                Task {
                    let read = await Task.detached(priority: .utility) { SystemReadings.disk() }.value
                    space = read
                }
            }
    }
}

/// The chip's temperature, read every two seconds while shown (`ThermalMonitor`, shared with Fan
/// Control); a sample in a picture.
struct ChipTemperatureWidget: View {
    let widget: IslandWidget
    let size: CGSize

    @Environment(AppModel.self) private var model
    @Environment(\.isWidgetPreview) private var isPreview
    @Environment(\.locale) private var locale

    var body: some View {
        let thermals = model.thermals
        ReadingWidget(widget: widget, size: size,
                      reading: isPreview ? Readouts.picture(widget, locale: locale)
                          : SystemReadings.chip(thermals.chip, name: ChipSensors.name, locale: locale))
            .whileShown { if !isPreview { withoutAnimation { thermals.startObserving() } } } stop: { if !isPreview { thermals.stopObserving() } }
    }
}
