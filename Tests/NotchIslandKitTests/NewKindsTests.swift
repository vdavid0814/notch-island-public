import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import NotchIslandKit

/// What the widgets added in 0.6 read: pure values in, a reading out.
@Suite struct BatteryReadingTests {
    private let format = WidgetFormat(FormatStyle(), locale: Locale(identifier: "en_US"), timeZone: TimeZone(identifier: "Europe/Budapest")!)

    private func state(level: Int = 76, charging: Bool = false, plugged: Bool = false, charged: Bool = false, minutes: Int? = nil) -> PowerState {
        PowerState(hasBattery: true, level: level, isCharging: charging, isPluggedIn: plugged || charging, isCharged: charged,
                   minutesRemaining: minutes, isLowPowerMode: false)
    }

    /// This Mac's battery: 58 cycles of 1000, 98 % maximum capacity, 29.7 °C, on a 65 W charger.
    private var details: BatteryDetails {
        var details = BatteryDetails.demo(power: state(charging: true))
        details.cycleCount = 58
        details.designCycleCount = 1000
        details.maximumCapacityPercent = 98
        details.temperature = 29.7
        details.adapterWatts = 65
        details.chargeWatts = 31.2
        details.systemDrawWatts = 8.4
        details.minutesToFull = 72
        return details
    }

    @Test func theTimeSaysWhatTheBatteryIsDoing() {
        let charging = BatteryReadings.reading(.batteryTime, state: state(charging: true), details: details, format: format)
        #expect(charging.value == format.duration(minutes: 72) && charging.caption == "Until Full")
        let draining = BatteryReadings.reading(.batteryTime, state: state(minutes: 340), details: nil, format: format)
        #expect(draining.value == format.duration(minutes: 340) && draining.caption == "Remaining" && draining.tint == nil)
        let low = BatteryReadings.reading(.batteryTime, state: state(level: 8, minutes: 12), details: nil, format: format)
        #expect(low.tint == .red)
        let full = BatteryReadings.reading(.batteryTime, state: state(level: 100, plugged: true, charged: true), details: details, format: format)
        #expect(full.value == "Charged")
        let unknown = BatteryReadings.reading(.batteryTime, state: state(), details: nil, format: format)
        #expect(unknown.value == "—")
    }

    @Test func healthCyclesAndTemperatureAreThisMacs() {
        let health = BatteryReadings.reading(.batteryHealth, state: state(), details: details, format: format)
        #expect(health.value == "98%" && health.caption == "Maximum Capacity" && health.tint == nil)
        var failing = details
        failing.condition = .serviceRecommended(1)
        #expect(BatteryReadings.reading(.batteryHealth, state: state(), details: failing, format: format).tint == .orange)
        let cycles = BatteryReadings.reading(.batteryCycles, state: state(), details: details, format: format)
        #expect(cycles.value == "58" && cycles.caption.hasPrefix("of 1") && cycles.caption.hasSuffix("000 Cycles"))
        let temperature = BatteryReadings.reading(.batteryTemperature, state: state(), details: details, format: format)
        #expect(temperature.value == format.temperature(celsius: 29.7) && temperature.tint == nil)
        var hot = details
        hot.temperature = 46
        #expect(BatteryReadings.reading(.batteryTemperature, state: state(), details: hot, format: format).tint == .red)
    }

    @Test func powerAndChargerFollowThePlug() {
        let charging = BatteryReadings.reading(.batteryPower, state: state(charging: true), details: details, format: format)
        #expect(charging.value.hasPrefix("+") && charging.value.contains("31.2") && charging.tint == .green)
        let onBattery = BatteryReadings.reading(.batteryPower, state: state(), details: details, format: format)
        #expect(onBattery.value.hasPrefix("−") && onBattery.value.contains("8.4") && onBattery.caption == "From the Battery")
        let charger = BatteryReadings.reading(.charger, state: state(charging: true), details: details, format: format)
        #expect(charger.value.contains("65") && charger.caption == "Charging")
        let held = BatteryReadings.reading(.charger, state: state(plugged: true), details: details, format: format)
        #expect(held.caption == "Not Charging" && held.tint == nil)
        let away = BatteryReadings.reading(.charger, state: state(), details: details, format: format)
        #expect(away.value == "—" && away.caption == "Not Connected")
    }

    /// Before the details have been read, every figure still draws.
    @Test func everyFigureDrawsWithoutDetails() {
        for kind in [IslandWidgetKind.batteryTime, .batteryHealth, .batteryCycles, .batteryPower, .batteryTemperature, .charger] {
            let reading = BatteryReadings.reading(kind, state: state(), details: nil, format: format)
            #expect(!reading.value.isEmpty && !reading.caption.isEmpty && !reading.symbol.isEmpty, "\(kind)")
        }
    }
}

@Suite struct TimeReadingTests {
    private let budapest = TimeZone(identifier: "Europe/Budapest")!
    private var format: WidgetFormat { WidgetFormat(FormatStyle(), locale: Locale(identifier: "en_GB"), timeZone: budapest) }
    /// Thursday 24 September 2026, 9:41 in Budapest.
    private let date = Date(timeIntervalSince1970: 1_790_235_660)

    @Test func aWorldClockShowsItsCitysTimeAndDay() {
        var config = WidgetConfig()
        config.timeZone = "Asia/Tokyo"
        let tokyo = TimeReadings.worldClock(config, at: date, format: format, home: budapest)
        #expect(tokyo.value == "16:41" && tokyo.caption == "Tokyo")
        config.timeZone = "America/Los_Angeles"
        let west = TimeReadings.worldClock(config, at: date, format: format, home: budapest)
        #expect(west.value == "00:41" && west.caption == "Los Angeles")
        config.timeZone = "Pacific/Auckland"
        config.label = "Anna"
        let late = Date(timeIntervalSince1970: 1_790_235_660 + 6 * 3600)
        let auckland = TimeReadings.worldClock(config, at: late, format: format, home: budapest)
        #expect(auckland.caption == "Anna · Tomorrow")
        config.timeZone = "Pacific/Honolulu"
        config.label = nil
        #expect(TimeReadings.worldClock(config, at: date, format: format, home: budapest).caption == "Honolulu · Yesterday")
        // Nothing chosen: Cupertino's time.
        #expect(TimeReadings.worldClock(WidgetConfig(), at: date, format: format, home: budapest).caption == "Cupertino")
    }

    @Test func aCountdownCountsWholeDays() {
        var config = WidgetConfig()
        #expect(TimeReadings.countdown(config, at: date, locale: Locale(identifier: "en_GB")).value == "—")
        config.label = "Holiday"
        config.date = Calendar.current.date(byAdding: .day, value: 91, to: date)
        let ahead = TimeReadings.countdown(config, at: date, locale: Locale(identifier: "en_GB"))
        #expect(ahead.value.contains("91") && ahead.caption == "Holiday")
        config.date = date.addingTimeInterval(60)
        #expect(TimeReadings.countdown(config, at: date, locale: Locale(identifier: "en_GB")).value == "Today")
        config.date = Calendar.current.date(byAdding: .day, value: -3, to: date)
        #expect(TimeReadings.countdown(config, at: date, locale: Locale(identifier: "en_GB")).value == "3 days ago")
    }

    @Test func aMonthIsLaidOutInWeeksFromTheCalendarsFirstDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = budapest
        calendar.firstWeekday = 2   // Monday
        let september = MonthGrid(date: date, calendar: calendar, locale: Locale(identifier: "en_GB"))
        #expect(september.weekdays.count == 7 && september.weekdays.first == "M")
        // 1 September 2026 is a Tuesday: one empty cell before it, thirty days, five weeks.
        #expect(september.weeks.count == 5)
        #expect(september.weeks[0] == [nil, 1, 2, 3, 4, 5, 6])
        #expect(september.weeks.flatMap { $0 }.compactMap { $0 } == Array(1...30))
        #expect(september.today == 24 && september.title == "September 2026")
        calendar.firstWeekday = 1   // Sunday
        let sunday = MonthGrid(date: date, calendar: calendar, locale: Locale(identifier: "en_US"))
        #expect(sunday.weekdays.first == "S" && sunday.weeks[0] == [nil, nil, 1, 2, 3, 4, 5])
        #expect(sunday.weeks.allSatisfy { $0.count == 7 })
    }

    @Test func anEventsTimeIsTheNearestWayToSayIt() {
        let now = date
        func event(_ start: TimeInterval, allDay: Bool = false) -> CalendarEvent {
            CalendarEvent(id: "e", title: "T", start: now.addingTimeInterval(start), end: now.addingTimeInterval(start + 3600), isAllDay: allDay,
                          calendarID: "", red: 0, green: 0, blue: 0, location: nil)
        }
        #expect(UpNextWidget.time(event(-600), format: format, now: now) == "Now")
        #expect(UpNextWidget.time(event(3 * 3600), format: format, now: now) == "12:41")
        #expect(UpNextWidget.time(event(3 * 3600, allDay: true), format: format, now: now) == "Today")
        #expect(UpNextWidget.time(event(24 * 3600), format: format, now: now) == "Tomorrow")
        #expect(UpNextWidget.time(event(3 * 86400), format: format, now: now) == "Sun")
    }
}

@MainActor @Suite struct SystemReadingTests {
    @Test func ratesAreReadableAtEverySpeed() {
        #expect(NetworkMonitor.rate(0) == "0 KB/s")
        #expect(NetworkMonitor.rate(640) == "0 KB/s")
        #expect(NetworkMonitor.rate(-5) == "0 KB/s")
        #expect(NetworkMonitor.rate(12_000).hasSuffix("KB/s"))
        #expect(NetworkMonitor.rate(2_400_000).hasSuffix("MB/s"))
        let reading = SystemReadings.network(download: 2_400_000, upload: 310_000)
        #expect(reading.value.hasPrefix("↓") && reading.caption.hasPrefix("↑"))
    }

    /// The interfaces' counters are there and only grow.
    @Test func theNetworksTotalsAreRead() throws {
        let first = try #require(NetworkMonitor.totals())
        let second = try #require(NetworkMonitor.totals())
        #expect(second.received >= first.received && second.sent >= first.sent)
    }

    @Test func theDiskAndTheUptimeRead() throws {
        let space = try #require(SystemReadings.disk())
        #expect(space.free > 0 && space.total >= space.free)
        let low = SystemReadings.disk((free: 5_000_000_000, total: 500_000_000_000))
        #expect(low.tint == .orange && low.caption.hasPrefix("Free of"))
        let format = WidgetFormat(FormatStyle(), locale: Locale(identifier: "en_US"))
        let hours = SystemReadings.uptime(5 * 3600 + 40 * 60, thermal: .nominal, format: format)
        #expect(hours.value == format.duration(minutes: 340) && hours.tint == nil)
        let days = SystemReadings.uptime(3 * 86400 + 4 * 3600, thermal: .serious, format: format)
        #expect(days.value.contains("3") && days.value.contains("4") && days.tint == .orange)
    }

    @Test func theAirPodsReadingIsTheLowerBud() {
        let format = WidgetFormat(FormatStyle(), locale: Locale(identifier: "en_US"))
        #expect(AirPodsReadingSource<EmptyView>.reading(nil, format: format).value == "—")
        let pair = AirPodsBatteryStore.Reading(name: "AirPods Pro", left: 86, right: 84, chargingCase: 60, single: nil, date: Date())
        let reading = AirPodsReadingSource<EmptyView>.reading(pair, format: format)
        #expect(reading.value == "84%" && reading.caption == "L 86% · R 84% · Case 60%" && reading.tint == nil)
        let low = AirPodsBatteryStore.Reading(name: "AirPods", left: 9, right: 9, chargingCase: nil, single: nil, date: Date())
        let lowReading = AirPodsReadingSource<EmptyView>.reading(low, format: format)
        #expect(lowReading.tint == .red && lowReading.caption == "AirPods")
    }

    /// The last reading is kept across launches, and nothing is read for AirPods that are away.
    @Test func theLastAirPodsReadingIsKept() async throws {
        let name = "notchisland.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }
        let store = AirPodsBatteryStore(defaults: defaults)
        #expect(store.last == nil)
        store.note(AirPodsInfo(name: "AirPods Pro", model: .airPodsPro, left: 70, right: 72, chargingCase: 40, single: nil))
        #expect(AirPodsBatteryStore(defaults: defaults).last?.left == 70)
        // Without batteries nothing replaces what is known.
        store.note(AirPodsInfo(name: "AirPods Pro", model: .airPodsPro, left: nil, right: nil, chargingCase: nil, single: nil))
        #expect(store.last?.right == 72)
        nonisolated(unsafe) var reads = 0
        store.read = { _ in reads += 1; return nil }
        store.connectedOutputs = { [] }
        store.acquire()
        try await Task.sleep(for: .milliseconds(80))
        store.release()
        #expect(reads == 0)
    }
}

@MainActor @Suite struct ToolKindTests {
    @Test func launcherIconsFillTheWidget() {
        // One row in a strip, a square for four in a square.
        #expect(AppLauncherWidget.grid(count: 4, in: CGSize(width: 200, height: 40)).rows == 1)
        let square = AppLauncherWidget.grid(count: 4, in: CGSize(width: 100, height: 100))
        #expect(square.rows == 2 && square.columns == 2)
        for count in 1...8 {
            for size in [CGSize(width: 40, height: 40), CGSize(width: 330, height: 40), CGSize(width: 160, height: 86)] {
                let grid = AppLauncherWidget.grid(count: count, in: size)
                #expect(grid.rows * grid.columns >= count)
                #expect(grid.side <= 56 && grid.side > 0)
                #expect(CGFloat(grid.columns) * grid.side + CGFloat(grid.columns - 1) * 6 <= size.width + 0.01)
                #expect(CGFloat(grid.rows) * grid.side + CGFloat(grid.rows - 1) * 6 <= size.height + 0.01)
            }
        }
        #expect(AppLauncherWidget.grid(count: 0, in: CGSize(width: 100, height: 40)).side == 0)
    }

    @Test func aMissingPhotoLoadsNothing() {
        #expect(PhotoLoader.thumbnail(path: "/nonexistent/picture.png", maxPixels: 200) == nil)
    }

    @Test func theNewKindsConfigIsWhatTheirEditorOffers() {
        #expect(IslandWidgetKind.clipboard.spec.defaultConfig.count == 3)
        #expect(IslandWidgetKind.upNext.spec.defaultConfig.count == 2)
        #expect(IslandWidgetKind.worldClock.configFields.contains(.timeZone))
        #expect(IslandWidgetKind.countdown.configFields.contains(.date))
        #expect(IslandWidgetKind.shortcut.configFields.contains(.shortcut))
        #expect(IslandWidgetKind.focus.configFields == [.shortcut])
        // One button, one block: not laid out freely.
        for kind in [IslandWidgetKind.analogClock, .upNext, .appLauncher, .clipboard, .photoFrame] {
            #expect(!kind.spec.supportsCustomLayout, "\(kind)")
        }
    }
}
