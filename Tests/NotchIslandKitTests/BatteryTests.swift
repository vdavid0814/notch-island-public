import Foundation
import SwiftUI
import Synchronization
import Testing
@testable import NotchIslandKit

// MARK: - Fixtures

private func reading(_ level: Int, plugged: Bool = false, charging: Bool? = nil, minutes: Int? = nil) -> PowerState {
    PowerState(hasBattery: true, level: level, isCharging: charging ?? plugged, isPluggedIn: plugged,
               isCharged: level >= 100, minutesRemaining: minutes, isLowPowerMode: false)
}

private func temporaryHistory() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("battery-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("battery-history.bin")
}

private func write(_ records: [BatteryRecord], to url: URL, extra: [UInt8] = []) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(records.flatMap(\.bytes) + extra).write(to: url)
}

/// Waits for the recorder's I/O queue, then for the main-thread hops it queued.
private func drain(_ recorder: BatteryRecorder) async {
    await withCheckedContinuation { continuation in
        recorder.queue.async { DispatchQueue.main.async { continuation.resume() } }
    }
}

/// A recorder without a file and with a clock the test moves; `records` is everything appended.
@MainActor private final class Recording {
    var now = Date(timeIntervalSince1970: 1_790_000_000)
    var records: [BatteryRecord] = []
    private(set) var recorder: BatteryRecorder!

    init(url: URL? = nil) {
        recorder = BatteryRecorder(url: url) { [unowned self] in self.now }
        recorder.onAppend = { [unowned self] in self.records.append($0) }
    }

    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

private let t0: UInt32 = 1_790_000_000

// MARK: - Records and the file

@Suite struct BatteryHistoryFileTests {

    @Test func recordRoundTripsThroughEightBytes() {
        let record = BatteryRecord(time: 0x6A_B1_C2_D3, level: 87, flags: [.charging, .pluggedIn, .gapBefore],
                                   kind: .systemWake)
        #expect(record.bytes == [0xD3, 0xC2, 0xB1, 0x6A, 87, 0b1011, 2, 0])
        #expect(BatteryRecord(bytes: record.bytes) == record)

        let fromState = BatteryRecord(date: Date(timeIntervalSince1970: 1_790_000_123.9),
                                      state: reading(42, plugged: true, charging: false), kind: .appStart)
        #expect(fromState == BatteryRecord(time: 1_790_000_123, level: 42, flags: [.pluggedIn], kind: .appStart))
        // A kind from a newer build is skipped, not misread.
        #expect(BatteryRecord(bytes: [0, 0, 0, 0, 50, 0, 99, 0]) == nil)
    }

    @Test func aTornTailIsIgnoredAndCutOffBeforeAppending() throws {
        let url = temporaryHistory()
        let records = (0 ..< 3).map { BatteryRecord(time: t0 + UInt32($0) * 60, level: UInt8(90 - $0)) }
        try write(records, to: url, extra: [1, 2, 3, 4, 5])

        #expect(BatteryHistory.read(url) == records)
        #expect(BatteryHistory.tail(url) == records[2])

        BatteryHistory.prepare(url, now: records[2].date)
        let next = BatteryRecord(time: t0 + 600, level: 80)
        BatteryHistory.append([next], to: url)
        #expect(BatteryHistory.read(url) == records + [next])
    }

    @Test func compactionKeepsEightDaysOnceTheOldestPassesNine() throws {
        let url = temporaryHistory()
        let now = Date(timeIntervalSince1970: TimeInterval(t0))
        func record(daysAgo: Double) -> BatteryRecord {
            BatteryRecord(time: t0 - UInt32(daysAgo * 86_400), level: 50)
        }
        let young = [record(daysAgo: 8.5), record(daysAgo: 7), record(daysAgo: 1)]
        try write(young, to: url)
        BatteryHistory.prepare(url, now: now)
        #expect(BatteryHistory.read(url) == young, "the oldest is not 9 days old: no rewrite")

        try write([record(daysAgo: 10)] + young, to: url)
        BatteryHistory.prepare(url, now: now)
        #expect(BatteryHistory.read(url) == Array(young.dropFirst()))
    }

    @Test func theRecorderFlushesAtTwelveRecordsAndAtStop() async throws {
        let url = temporaryHistory()
        let recording = Recording(url: url)
        recording.recorder.start()
        await drain(recording.recorder)

        recording.recorder.powerReading(from: .unknown, to: reading(100))
        for level in stride(from: 99, to: 88, by: -1) {
            recording.advance(60)
            recording.recorder.powerReading(from: reading(level + 1), to: reading(level))
        }
        await drain(recording.recorder)
        #expect(BatteryHistory.read(url).count == 12)
        #expect(recording.recorder.pending.isEmpty)

        recording.recorder.powerReading(from: reading(89), to: reading(88))
        #expect(BatteryHistory.read(url).count == 12, "buffered until the next flush")
        recording.recorder.stop()
        #expect(BatteryHistory.read(url) == recording.records)
    }
}

// MARK: - Recording

@Suite struct BatteryRecorderTests {

    @Test func onlyRealLevelAndPlugChangesAreRecorded() {
        var state = reading(50, minutes: 300)
        let monitor = PowerMonitor(readState: { state })
        let recording = Recording()
        recording.recorder.start()
        monitor.onRealReading = { recording.recorder.powerReading(from: $0, to: $1) }

        monitor.start()
        #expect(recording.records.map(\.kind) == [.appStart])

        state.minutesRemaining = 290
        monitor.refresh()
        #expect(recording.records.count == 1, "minutes alone are not recorded")

        monitor.injectDemo(reading(12), event: .low(threshold: 20))
        monitor.injectDemo(nil, event: nil)
        #expect(recording.records.count == 1, "a demo state is never recorded")

        state = reading(49, minutes: 290)
        monitor.refresh()
        state = reading(49, plugged: true)
        monitor.refresh()
        monitor.stop()
        #expect(recording.records.map(\.kind) == [.appStart, .sample, .sample])
        #expect(recording.records.map(\.level) == [50, 49, 49])
        #expect(recording.records.last?.flags == [.charging, .pluggedIn])
    }

    @Test func aLongSleepFlagsTheFirstReadingAfterIt() {
        let recording = Recording()
        let recorder = recording.recorder!
        recorder.start()
        recorder.powerReading(from: .unknown, to: reading(80, minutes: 200))

        recording.advance(60)
        recorder.activityEdge(.screensDidSleep)
        recorder.activityEdge(.systemWillSleep)
        recording.advance(1200)
        recorder.activityEdge(.systemDidWake)
        recorder.activityEdge(.screensDidWake)
        recording.advance(5)
        // Nothing but the estimate changed: still recorded, as the line's restart.
        recorder.powerReading(from: reading(80, minutes: 200), to: reading(80, minutes: 190))
        #expect(recording.records.map(\.kind) == [.appStart, .displayOff, .systemSleep, .systemWake, .displayOn, .sample])
        #expect(recording.records.last?.flags.contains(.gapBefore) == true)

        // A short sleep is no gap and forces nothing.
        recorder.activityEdge(.systemWillSleep)
        recording.advance(300)
        recorder.activityEdge(.systemDidWake)
        recorder.powerReading(from: reading(80, minutes: 190), to: reading(80, minutes: 185))
        #expect(recording.records.count == 8)
        recorder.powerReading(from: reading(80), to: reading(79))
        #expect(recording.records.last?.flags.contains(.gapBefore) == false)
    }

    @Test func aReadingThatBeatsTheWakeMarkerCarriesTheGap() {
        let recording = Recording()
        let recorder = recording.recorder!
        recorder.start()
        recorder.powerReading(from: .unknown, to: reading(80))
        recorder.activityEdge(.systemWillSleep)
        recording.advance(3600)
        recorder.powerReading(from: reading(80), to: reading(74))
        recorder.activityEdge(.systemDidWake)
        recorder.powerReading(from: reading(74, minutes: 100), to: reading(74, minutes: 90))
        #expect(recording.records.map(\.kind) == [.appStart, .systemSleep, .sample, .systemWake])
        #expect(recording.records[2].flags.contains(.gapBefore))
    }

    @Test func aRelaunchAfterTenMinutesStartsWithAGap() async throws {
        let url = temporaryHistory()
        try write([BatteryRecord(time: t0, level: 60)], to: url)

        let late = Recording(url: url)
        late.now = Date(timeIntervalSince1970: TimeInterval(t0) + 900)
        late.recorder.start()
        // The first reading usually arrives before the file's tail has been read.
        late.recorder.powerReading(from: .unknown, to: reading(58))
        #expect(late.records.isEmpty)
        await drain(late.recorder)
        #expect(late.records.map(\.flags) == [[.gapBefore]])
        late.recorder.stop()

        let soon = Recording(url: url)
        soon.now = late.now.addingTimeInterval(300)
        soon.recorder.start()
        await drain(soon.recorder)
        soon.recorder.powerReading(from: .unknown, to: reading(58))
        #expect(soon.records.map(\.flags) == [[]])
    }

    @Test func aQuitRecordsTheLastReadingSoAQuickRelaunchIsNoGap() async throws {
        let url = temporaryHistory()
        let quiet = Recording(url: url)
        quiet.recorder.start()
        await drain(quiet.recorder)
        quiet.recorder.powerReading(from: .unknown, to: reading(80, plugged: true, charging: false))
        quiet.advance(8 * 3600)   // 8 h plugged in at a steady level: nothing is recorded
        quiet.recorder.stop()
        #expect(BatteryHistory.read(url).map(\.kind) == [.appStart, .appQuit])
        #expect(BatteryHistory.tail(url)?.date == quiet.now)
        #expect(BatteryHistory.tail(url)?.flags == [.pluggedIn])

        let relaunch = Recording(url: url)
        relaunch.now = quiet.now.addingTimeInterval(60)
        relaunch.recorder.start()
        relaunch.recorder.powerReading(from: .unknown, to: reading(80, plugged: true, charging: false))
        await drain(relaunch.recorder)
        #expect(relaunch.records.map(\.flags) == [[.pluggedIn]])

        // A crash writes no quit record: the relaunch 8 h later is a gap.
        let crashed = Recording(url: url)
        crashed.now = relaunch.now.addingTimeInterval(8 * 3600)
        crashed.recorder.start()
        crashed.recorder.powerReading(from: .unknown, to: reading(80, plugged: true, charging: false))
        await drain(crashed.recorder)
        #expect(crashed.records.map(\.flags) == [[.pluggedIn, .gapBefore]])
    }

    @Test func desktopsRecordNothing() {
        let recording = Recording()
        recording.recorder.start()
        recording.recorder.powerReading(from: .unknown, to: .unknown)
        recording.recorder.activityEdge(.systemWillSleep)
        #expect(recording.records.isEmpty)
    }

    @Test func lastChargeIsTheLastChargingToNotChargingEdge() {
        let records = [
            BatteryRecord(time: t0, level: 40, flags: [.charging, .pluggedIn], kind: .appStart),
            BatteryRecord(time: t0 + 3600, level: 80, flags: [.charging, .pluggedIn]),
            BatteryRecord(time: t0 + 3700, level: 80, flags: [.charging, .pluggedIn], kind: .displayOff),
            BatteryRecord(time: t0 + 3800, level: 81, flags: []),
            BatteryRecord(time: t0 + 7200, level: 70, flags: [], kind: .systemSleep),
            BatteryRecord(time: t0 + 9000, level: 65, flags: []),
        ]
        #expect(BatteryHistory.lastCharge(in: records)
                == BatteryLastCharge(level: 81, date: Date(timeIntervalSince1970: TimeInterval(t0 + 3800))))
        #expect(BatteryHistory.lastCharge(in: Array(records.prefix(3))) == nil)
    }

    @Test func theCenterLoadsTheFileOnceAndFollowsTheRecorder() async throws {
        let url = temporaryHistory()
        let old = BatteryRecord(time: UInt32(Date().timeIntervalSince1970) - 3600, level: 90)
        try write([old], to: url)
        let recorder = BatteryRecorder(url: url)
        let center = BatteryCenter(recorder: recorder)
        center.start(power: PowerMonitor(readState: { reading(88) }), activity: SystemActivity())
        await drain(recorder)
        recorder.powerReading(from: .unknown, to: reading(88))
        #expect(center.history == nil, "nothing is loaded without a lease")

        center.acquire(.history)
        recorder.powerReading(from: reading(88), to: reading(87))
        await drain(recorder)
        #expect(center.history?.records.map(\.level) == [90, 88, 87])
        let version = center.history?.version

        recorder.powerReading(from: reading(87), to: reading(86))
        #expect(center.history?.records.count == 4)
        #expect(center.history?.version != version)
        center.release(.history)
        center.stop()
        #expect(BatteryHistory.read(url).map(\.level) == [90, 88, 87, 86, 86])
        #expect(BatteryHistory.read(url).last?.kind == .appQuit)
    }

    @Test func aHistoryLoadedBeforeTheFileIsReadHoldsEachRecordOnce() async throws {
        let recorder = BatteryRecorder(url: temporaryHistory())
        let center = BatteryCenter(recorder: recorder)
        center.start(power: PowerMonitor(readState: { reading(88) }), activity: SystemActivity())
        // The launch's reading and a lease both before the file's last record is known.
        recorder.powerReading(from: .unknown, to: reading(88))
        center.acquire(.history)
        await drain(recorder)
        await drain(recorder)
        #expect(center.history?.records.map(\.kind) == [.appStart])
        center.stop()
    }

    @Test func theDetailsAreReadAgainOnlyAfterAPowerChange() async throws {
        let reads = Mutex(0)
        let center = BatteryCenter(recorder: BatteryRecorder(url: nil)) { power in
            reads.withLock { $0 += 1 }
            return BatteryDetails.demo(power: power)
        }
        var state = reading(80)
        let power = PowerMonitor(readState: { state })
        center.start(power: power, activity: SystemActivity())
        power.refresh()
        /// A read reports from a detached task: waits for `count` of them, then a little for one more
        /// that must not come.
        func settle(_ count: Int) async throws {
            for _ in 0..<100 where reads.withLock({ $0 }) < count || center.details == nil {
                try await Task.sleep(for: .milliseconds(10))
            }
            try await Task.sleep(for: .milliseconds(100))
        }

        center.acquire(.details)
        try await settle(1)
        #expect(reads.withLock { $0 } == 1)
        center.release(.details)

        // The page shown again with nothing changed: what was read stands.
        center.acquire(.details)
        try await settle(1)
        #expect(reads.withLock { $0 } == 1)
        #expect(center.details?.cycleCount == 212)
        center.release(.details)

        // A power change while nobody looks is only noted; the next showing reads.
        state = reading(79)
        power.refresh()
        try await settle(1)
        #expect(reads.withLock { $0 } == 1)
        center.acquire(.details)
        try await settle(2)
        #expect(reads.withLock { $0 } == 2)
        center.release(.details)
        center.stop()
    }

    @Test func theDemoIsNeverWrittenAndGivesTheRealHistoryBack() async throws {
        let url = temporaryHistory()
        let recorder = BatteryRecorder(url: url)
        let center = BatteryCenter(recorder: recorder) { BatteryDetails.demo(power: $0) }
        var state = reading(76)
        let power = PowerMonitor(readState: { state })
        center.start(power: power, activity: SystemActivity())
        power.refresh()
        center.acquire(.history)
        await drain(recorder)
        await drain(recorder)
        #expect(center.history?.records.map(\.level) == [76])

        let demo = BatteryHistory.demoRecords(now: Date(), calendar: .autoupdatingCurrent)
        center.injectDemo((demo, BatteryDetails.demo(power: reading(64))))
        #expect(center.history?.records == demo)
        // The demo's last charge (today's, or yesterday's to 100 % before today's first one).
        #expect(center.lastCharge != nil)
        #expect(center.lastCharge == BatteryHistory.lastCharge(in: demo))
        // The real readings go on being recorded under the demo, and only they.
        state = reading(75)
        power.refresh()
        #expect(center.history?.records == demo)
        recorder.stop()
        let real: [BatteryRecord.Kind] = [.appStart, .sample, .appQuit]
        #expect(BatteryHistory.read(url).map(\.kind) == real)
        #expect(BatteryHistory.read(url).map(\.level) == [76, 75, 75])

        center.injectDemo(nil)
        #expect(center.details == nil)
        await drain(recorder)
        #expect(center.history?.records.map(\.kind) == real)
        center.release(.history)
    }
}

// MARK: - Chart

@Suite struct BatteryChartTests {

    private func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    @Test func todayHasAQuarterHourBucketPerClockQuarterAcrossDST() {
        let budapest = calendar("Europe/Budapest")
        // 25 October 2026: clocks go back from 03:00 to 02:00.
        let autumn = budapest.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 0))!
        let noon = autumn.addingTimeInterval(13 * 3600)
        let records = [
            BatteryRecord(date: autumn.addingTimeInterval(600), state: reading(90), kind: .appStart),
            BatteryRecord(date: autumn.addingTimeInterval(4 * 3600), state: reading(70), kind: .sample),
        ]
        let model = BatteryChartModel(records: records, range: .today, now: noon, calendar: budapest)
        #expect(model.buckets.count == 100)
        #expect(model.buckets.first?.start == autumn)
        #expect(model.buckets.last?.end == autumn.addingTimeInterval(25 * 3600))
        #expect(model.buckets.allSatisfy { $0.end.timeIntervalSince($0.start) == 900 })
        #expect(model.buckets[0].level.map { $0 > 89 && $0 < 90 } == true, "on the way from 90 to 70")
        #expect(model.buckets[15].level == 70, "the bucket ending when the 70 % reading came")
        #expect(model.buckets[60].level == nil, "the future")
        // Ticks on the clock's 0, 6, 12, 18 and 24 h: 06:00 is 7 hours after midnight today.
        #expect(model.ticks.map { $0.timeIntervalSince(autumn) / 3600 } == [0, 7, 13, 19, 25])

        // 29 March 2026: clocks go forward from 02:00 to 03:00.
        let spring = budapest.date(from: DateComponents(year: 2026, month: 3, day: 29, hour: 0))!
        let springModel = BatteryChartModel(records: records, range: .today, now: spring.addingTimeInterval(3600),
                                            calendar: budapest)
        #expect(springModel.buckets.count == 92)
    }

    @Test func rollingRangesEndAtTheNextLocalBoundary() {
        let kathmandu = calendar("Asia/Kathmandu")   // UTC+5:45
        let midnight = kathmandu.date(from: DateComponents(year: 2026, month: 9, day: 29, hour: 0))!
        let now = midnight.addingTimeInterval(10 * 3600 + 20 * 60)
        let day = BatteryChartRange.last24Hours.interval(now: now, calendar: kathmandu)
        #expect(day.end == midnight.addingTimeInterval(10 * 3600 + 30 * 60))
        #expect(day.duration == 86_400)
        let twoDays = BatteryChartModel(records: [], range: .last48Hours, now: now, calendar: kathmandu)
        #expect(twoDays.interval.end == midnight.addingTimeInterval(10.5 * 3600))
        #expect(twoDays.buckets.count == 96)
    }

    @Test func aLongSleepIsAGapAndChargingAndDisplayOffAreSegments() {
        let utc = calendar("UTC")
        let midnight = utc.date(from: DateComponents(year: 2026, month: 9, day: 29))!
        func at(_ hours: Double) -> Date { midnight.addingTimeInterval(hours * 3600) }
        var wake = BatteryRecord(date: at(4), state: reading(60), kind: .sample)
        wake.flags.insert(.gapBefore)
        let records = [
            BatteryRecord(date: at(1), state: reading(80), kind: .appStart),
            BatteryRecord(date: at(1.5), state: reading(75), kind: .displayOff),
            BatteryRecord(date: at(2), state: reading(75), kind: .systemSleep),
            BatteryRecord(date: at(3.75), state: reading(75), kind: .systemWake),
            BatteryRecord(date: at(3.76), state: reading(75), kind: .displayOn),
            wake,
            BatteryRecord(date: at(5), state: reading(55, plugged: true), kind: .sample),
            BatteryRecord(date: at(6), state: reading(75, plugged: true), kind: .sample),
        ]
        let model = BatteryChartModel(records: records, range: .today, now: at(7), calendar: utc)
        let spans = model.segments.map { ($0.kind, $0.start.timeIntervalSince(midnight) / 3600, $0.end.timeIntervalSince(midnight) / 3600) }
        #expect(spans.map(\.0) == [.normal, .displayOff, .gap, .normal, .charging])
        #expect(spans[1].1 == 1.5 && spans[1].2 == 2)
        #expect(spans[2].1 == 2 && spans[2].2 == 3.75)
        #expect(spans[3].1 == 3.75 && spans[3].2 == 5)
        #expect(spans[4].1 == 5 && spans[4].2 == 7)
        #expect(model.segments[0].points.last?.level == 80, "the level before the sleep holds until it")
        #expect(model.segments[3].points.first?.level == 60, "the line restarts at the wake")

        #expect(model.buckets[10].isGap)                  // 02:30
        #expect(model.buckets[10].level == nil)
        #expect(model.buckets[6].isDisplayOff)            // 01:30
        #expect(!model.buckets[10].isDisplayOff, "the displays' stretch ends where the sleep starts")
        #expect(model.buckets[21].isCharging)             // 05:15
        #expect(model.buckets[27].level == 75)            // 06:45, held since 06:00

        for style in BatteryChartStyle.allCases {
            let geometry = BatteryChartGeometry(model: model, style: style, size: CGSize(width: 300, height: 100))
            #expect(!geometry.level.isEmpty && !geometry.charging.isEmpty && !geometry.gaps.isEmpty)
            #expect(geometry.ticks.map(\.x) == [0, 75, 150, 225, 300])
            let hatch = geometry.gaps.boundingRect
            #expect(hatch.minX >= 2 * 12.5 - 0.001 && hatch.maxX <= 3.75 * 12.5 + 0.001, "hatching stays in the gap")
        }
    }

    @Test func aShortSleepDoesNotWidenALaterGap() {
        let utc = calendar("UTC")
        let midnight = utc.date(from: DateComponents(year: 2026, month: 9, day: 29))!
        func at(_ hours: Double) -> Date { midnight.addingTimeInterval(hours * 3600) }
        // Plugged in at a steady level: no reading arrives between the markers.
        let steady = reading(80, plugged: true, charging: false)
        var woke = BatteryRecord(date: at(8), state: steady, kind: .sample)
        woke.flags.insert(.gapBefore)
        let markers = [
            BatteryRecord(date: at(1), state: steady, kind: .appStart),
            BatteryRecord(date: at(2), state: steady, kind: .systemSleep),
            BatteryRecord(date: at(2.08), state: steady, kind: .systemWake),
            BatteryRecord(date: at(6), state: steady, kind: .systemSleep),
            BatteryRecord(date: at(8), state: steady, kind: .systemWake),
        ]
        for records in [markers + [woke], markers] {
            let model = BatteryChartModel(records: records, range: .today, now: at(9), calendar: utc)
            let gaps = model.segments.filter { $0.kind == .gap }
                .map { [$0.start.timeIntervalSince(midnight) / 3600, $0.end.timeIntervalSince(midnight) / 3600] }
            #expect(gaps == [[6, 8]], "with \(records.count) records")
        }
    }

    @Test func aQuitMarkerHoldsTheLineUntilTheQuit() {
        let utc = calendar("UTC")
        let midnight = utc.date(from: DateComponents(year: 2026, month: 9, day: 29))!
        func at(_ hours: Double) -> Date { midnight.addingTimeInterval(hours * 3600) }
        var relaunch = BatteryRecord(date: at(5), state: reading(70), kind: .appStart)
        relaunch.flags.insert(.gapBefore)
        let records = [
            BatteryRecord(date: at(1), state: reading(80), kind: .appStart),
            BatteryRecord(date: at(3), state: reading(80), kind: .appQuit),
            relaunch,
        ]
        let model = BatteryChartModel(records: records, range: .today, now: at(6), calendar: utc)
        let spans = model.segments.map { [$0.start.timeIntervalSince(midnight) / 3600, $0.end.timeIntervalSince(midnight) / 3600] }
        #expect(model.segments.map(\.kind) == [.normal, .gap, .normal])
        #expect(spans == [[1, 3], [3, 5], [5, 6]])
    }
}

// MARK: - Details

@Suite struct BatteryDetailsTests {

    /// The development Mac on 29 September 2026 (MacBook, bq40z651, charging on a 65 W charger):
    /// `ioreg -r -c AppleSmartBattery` gave these values, and `system_profiler SPPowerDataType`
    /// said "Cycle Count: 38", "Condition: Normal", "Maximum Capacity: 100%". As an app sees them:
    /// no top-level capacities, no temperature and no permanent failure status.
    private let thisMac: [String: Any] = [
        "CycleCount": 38,
        "DesignCycleCount9C": 1000,
        "Voltage": 13285,
        "Amperage": 725,
        "InstantAmperage": 725,
        "AvgTimeToFull": 23,
        "AvgTimeToEmpty": 65535,
        "CurrentCapacity": 98,
        "MaxCapacity": 100,
        "BatteryData": [
            "DesignCapacity": 6249, "NominalChargeCapacity": 6460, "FullChargeCapacity": 6308,
            "AvgTimeToEmpty": 65535, "MaxCapacity": 100, "CurrentCapacity": 98,
        ] as [String: Any],
        "PowerTelemetryData": ["SystemLoad": 8149] as [String: Any],
    ]

    @Test func thisMacsReadingMatchesSystemInformation() {
        let details = BatteryDetails(properties: thisMac, adapter: ["Watts": 65, "Description": "pd charger"],
                                     power: reading(98, plugged: true))
        #expect(details.cycleCount == 38)
        #expect(details.designCycleCount == 1000)
        #expect(details.designCapacity == 6249)
        #expect(details.nominalChargeCapacity == 6460)
        #expect(details.fullChargeCapacity == 6308)
        #expect(details.maximumCapacityPercent == 100)
        #expect(details.condition == .normal)
        #expect(details.voltage == 13.285)
        #expect(details.amperage == 725)
        #expect(abs((details.chargeWatts ?? 0) - 9.631) < 0.001)
        #expect(details.systemDrawWatts == 8.149)
        #expect(details.adapterWatts == 65)
        #expect(details.minutesToFull == 23, "the gauge's average while macOS has no estimate")
        #expect(details.minutesToEmpty == nil)
        #expect(details.temperature == nil)
    }

    /// On the development Mac both candidates round to 100 % (nominal 6465 and full charge 6313
    /// over design 6249 mAh), so these numbers are made up to tell them apart: nominal over design
    /// is 81.6 %, full charge over design 84.8 %. The nominal capacity is the one System Settings
    /// rates by. `FullChargeCapacity` (equal to `AppleRawMaxCapacity`, `FccComp1` and `FccComp2`
    /// in the registry) is the gauge's figure compensated for the present temperature and load,
    /// so it moves from one charge to the next; `NominalChargeCapacity` is the cells' own
    /// uncompensated capacity, the steady figure a health rating needs, and it is the one that
    /// stays above design (as "100 %") on a new battery. `MaxCapacity` is pinned at 100.
    @Test func maximumCapacityFollowsTheNominalCapacity() {
        var worn = thisMac
        worn["BatteryData"] = ["DesignCapacity": 6249, "NominalChargeCapacity": 5100, "FullChargeCapacity": 5300,
                               "MaxCapacity": 100]
        worn["AppleRawMaxCapacity"] = 5300
        worn["PermanentFailureStatus"] = 4
        let details = BatteryDetails(properties: worn, adapter: nil, power: reading(60))
        #expect(details.maximumCapacityPercent == 82, "5100 / 6249, not 5300 / 6249 (85)")
        #expect(details.condition == .serviceRecommended(4))
        #expect(details.adapterWatts == nil)
    }

    /// A MacBook Air M5 on 30 September 2026 (bq40z651, 58 cycles, charging on a 65 W charger):
    /// `system_profiler SPPowerDataType` said "Maximum Capacity: 98%", which neither candidate gives
    /// (nominal 4591 / 4629 is 99 %, full charge 4464 / 4629 is 96 %), so macOS's figure is taken.
    /// The gauge shows no temperature here; the pack below it does (2969: 29.69 °C).
    private let macBookAirM5: [String: Any] = [
        "CycleCount": 58,
        "DesignCycleCount9C": 1000,
        "Voltage": 12520,
        "Amperage": 3537,
        "AvgTimeToEmpty": 65535,
        "CurrentCapacity": 61,
        "MaxCapacity": 100,
        "BatteryData": [
            "DesignCapacity": 4629, "NominalChargeCapacity": 4591, "FullChargeCapacity": 4464,
            "AvgTimeToEmpty": 65535, "MaxCapacity": 100, "CurrentCapacity": 61,
        ] as [String: Any],
    ]
    private let macBookAirM5Pack: [String: Any] = ["Temperature": 2969, "VirtualTemperature": 2969, "DesignCapacity": 4629]

    @Test func theMacBookAirTakesSystemSettingsFigureAndThePacksTemperature() {
        let details = BatteryDetails(properties: macBookAirM5, pack: macBookAirM5Pack, adapter: ["Watts": 65],
                                     power: reading(61, plugged: true), systemMaximumCapacity: 98)
        #expect(details.maximumCapacityPercent == 98)
        #expect(details.temperature == 29.69)
        #expect(details.cycleCount == 58)
        #expect(details.adapterWatts == 65)
        // Without macOS's figure: nominal over design.
        let fallback = BatteryDetails(properties: macBookAirM5, adapter: nil, power: reading(61))
        #expect(fallback.maximumCapacityPercent == 99)
        #expect(fallback.temperature == nil)
        // A pack reading zero has not measured yet.
        let unread = BatteryDetails(properties: macBookAirM5, pack: ["Temperature": 0], adapter: nil, power: reading(61))
        #expect(unread.temperature == nil)
    }

    @Test func systemInformationsFigureIsParsedAndKeptForADay() throws {
        let json = #"{"SPPowerDataType":[{"_name":"spbattery_information","sppower_battery_health_info":{"sppower_battery_cycle_count":58,"sppower_battery_health":"Good","sppower_battery_health_maximum_capacity":"98%"}}]}"#
        #expect(SystemBatteryHealth.parse(json) == 98)
        #expect(SystemBatteryHealth.parse(#"{"SPPowerDataType":[{"_name":"spbattery_information"}]}"#) == nil)
        #expect(SystemBatteryHealth.parse("not json") == nil)

        let defaults = try #require(UserDefaults(suiteName: "SystemBatteryHealthTests-\(UUID().uuidString)"))
        var reads = 0
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        func read(_ cycles: Int, at date: Date) -> Int? {
            SystemBatteryHealth.maximumCapacity(cycleCount: cycles, defaults: defaults, now: date) {
                reads += 1
                return 98
            }
        }
        #expect(read(58, at: start) == 98)
        #expect(read(58, at: start.addingTimeInterval(3600)) == 98)
        #expect(reads == 1, "kept within the day")
        #expect(read(59, at: start.addingTimeInterval(7200)) == 98)
        #expect(reads == 2, "read again after a cycle")
        #expect(read(59, at: start.addingTimeInterval(7200 + 25 * 3600)) == 98)
        #expect(reads == 3, "read again after a day")
    }

    @Test func unknownEstimatesAreNil() {
        #expect(BatteryDetails.estimate(65535) == nil)
        #expect(BatteryDetails.estimate(0) == nil)
        #expect(BatteryDetails.estimate(-1) == nil)
        #expect(BatteryDetails.estimate(95) == 95)

        var onBattery = thisMac
        onBattery["Amperage"] = -1200
        onBattery["InstantAmperage"] = -1200
        let unknown = BatteryDetails(properties: onBattery, adapter: nil, power: reading(98))
        #expect(unknown.minutesToEmpty == nil)
        #expect(unknown.minutesToFull == nil)
        #expect(unknown.chargeWatts == nil)
        let estimated = BatteryDetails(properties: onBattery, adapter: nil, power: reading(98, minutes: 410))
        #expect(estimated.minutesToEmpty == 410)
    }
}
