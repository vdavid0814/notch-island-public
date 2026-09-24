import AppKit
import Foundation
import IOKit.ps
import Testing
@testable import NotchIslandKit

// MARK: - Fixtures

private func battery(_ level: Int, plugged: Bool = false, charging: Bool? = nil,
                     charged: Bool? = nil, minutes: Int? = nil) -> PowerState {
    PowerState(hasBattery: true, level: level, isCharging: charging ?? plugged, isPluggedIn: plugged,
               isCharged: charged ?? (level >= 100), minutesRemaining: minutes, isLowPowerMode: false)
}

private func desktop(plugged: Bool = true, lowPower: Bool = false) -> PowerState {
    var state = PowerState.unknown
    state.isPluggedIn = plugged
    state.isLowPowerMode = lowPower
    return state
}

/// Feeds consecutive readings to an announcer, the way `PowerMonitor` does.
private final class AnnouncerHarness {
    var announcer = PowerAnnouncer()
    var last: PowerState = .unknown

    func step(_ next: PowerState) -> [PowerEvent] {
        defer { last = next }
        return announcer.events(from: last, to: next)
    }

    /// Steps through every reading and returns all events, in order.
    func run(_ readings: [PowerState]) -> [PowerEvent] {
        readings.flatMap { step($0) }
    }
}

// MARK: - PowerAnnouncer

@Suite struct PowerAnnouncerTests {

    @Test func firstReadingOnlySeeds() {
        let onBattery = AnnouncerHarness()
        #expect(onBattery.step(battery(4)).isEmpty)
        let charging = AnnouncerHarness()
        #expect(charging.step(battery(100, plugged: true)).isEmpty)
    }

    @Test func plugAndUnplug() {
        let harness = AnnouncerHarness()
        _ = harness.step(battery(60))
        #expect(harness.step(battery(60, plugged: true)) == [.connected])
        #expect(harness.step(battery(61, plugged: true)).isEmpty)
        #expect(harness.step(battery(61)) == [.disconnected])
    }

    @Test func chargedFiresOnceWhenReachingFull() {
        let harness = AnnouncerHarness()
        _ = harness.step(battery(98, plugged: true))
        #expect(harness.step(battery(99, plugged: true)).isEmpty)
        #expect(harness.step(battery(100, plugged: true, charging: false)) == [.charged])
        // Drifting down and topping up again on AC is not a new charge.
        #expect(harness.step(battery(99, plugged: true, charging: false, charged: false)).isEmpty)
        #expect(harness.step(battery(100, plugged: true)).isEmpty)
        // A new connection earns a new announcement.
        #expect(harness.step(battery(97)) == [.disconnected])
        #expect(harness.step(battery(97, plugged: true)) == [.connected])
        #expect(harness.step(battery(100, plugged: true)) == [.charged])
    }

    @Test func pluggingInAFullBatteryIsOnlyAConnection() {
        let harness = AnnouncerHarness()
        _ = harness.step(battery(100))
        #expect(harness.step(battery(100, plugged: true, charging: false)) == [.connected])
        #expect(harness.step(battery(100, plugged: true, charging: false)).isEmpty)
    }

    @Test func firstReadingAlreadyFullDoesNotAnnounceLater() {
        let harness = AnnouncerHarness()
        _ = harness.step(battery(100, plugged: true))
        #expect(harness.step(battery(99, plugged: true, charged: false)).isEmpty)
        #expect(harness.step(battery(100, plugged: true)).isEmpty)
    }

    @Test func optimisedChargingHoldNeverClaimsCharged() {
        let harness = AnnouncerHarness()
        _ = harness.step(battery(80))
        // Held at 80 %: plugged in, not charging, firmware says "charged".
        #expect(harness.step(battery(80, plugged: true, charging: false, charged: true)) == [.connected])
        #expect(harness.step(battery(80, plugged: true, charging: false, charged: true)).isEmpty)
        #expect(harness.step(battery(80, charged: false)) == [.disconnected])
    }

    @Test func lowThresholdsFireOnceEachOnTheWayDown() {
        let harness = AnnouncerHarness()
        let events = harness.run((3...25).reversed().map { battery($0) })
        #expect(events == [.low(threshold: 20), .low(threshold: 10), .low(threshold: 5)])
    }

    @Test func hoveringAroundAThresholdDoesNotNag() {
        let harness = AnnouncerHarness()
        _ = harness.step(battery(21))
        #expect(harness.step(battery(20)) == [.low(threshold: 20)])
        #expect(harness.step(battery(21)).isEmpty)
        #expect(harness.step(battery(20)).isEmpty)
        #expect(harness.step(battery(19)).isEmpty)
    }

    @Test func severalThresholdsAtOnceAnnounceTheMostSevere() {
        let harness = AnnouncerHarness()
        _ = harness.step(battery(25))
        #expect(harness.step(battery(8)) == [.low(threshold: 10)])
        #expect(harness.step(battery(5)) == [.low(threshold: 5)])
    }

    @Test func thresholdsAboveTheStartingLevelAreSpent() {
        let harness = AnnouncerHarness()
        _ = harness.step(battery(15))   // launched at 15 % on battery
        #expect(harness.step(battery(14)).isEmpty)
        #expect(harness.step(battery(10)) == [.low(threshold: 10)])
    }

    @Test func unpluggingBelowAThresholdOnlySpendsIt() {
        let harness = AnnouncerHarness()
        _ = harness.step(battery(15, plugged: true))
        #expect(harness.step(battery(15)) == [.disconnected])
        #expect(harness.step(battery(14)).isEmpty)
        #expect(harness.step(battery(10)) == [.low(threshold: 10)])
    }

    @Test func chargingReArmsThresholds() {
        let harness = AnnouncerHarness()
        _ = harness.step(battery(21))
        #expect(harness.step(battery(20)) == [.low(threshold: 20)])
        #expect(harness.step(battery(20, plugged: true)) == [.connected])
        #expect(harness.step(battery(60, plugged: true)).isEmpty)
        #expect(harness.step(battery(60)) == [.disconnected])
        #expect(harness.step(battery(20)) == [.low(threshold: 20)])
    }

    @Test func noLowAlertsWhilePluggedIn() {
        let harness = AnnouncerHarness()
        _ = harness.step(battery(22, plugged: true, charging: false))
        // A weak charger that cannot keep up: still on external power, never "low".
        #expect(harness.run([19, 9, 4].map { battery($0, plugged: true, charging: false) }).isEmpty)
    }

    @Test func desktopsNeverAnnounce() {
        let harness = AnnouncerHarness()
        let events = harness.run([desktop(), desktop(plugged: false), desktop(), desktop(lowPower: true)])
        #expect(events.isEmpty)
    }

    @Test func batteryReappearingOnlySeeds() {
        let harness = AnnouncerHarness()
        _ = harness.step(battery(50))
        #expect(harness.step(.unknown).isEmpty)
        #expect(harness.step(battery(4, plugged: true)).isEmpty)
    }
}

// MARK: - IOKit dictionary parsing

@Suite struct PowerSourceParserTests {

    private func internalBattery(current: Int, max: Int = 100, source: String = kIOPSBatteryPowerValue,
                                 charging: Bool = false, charged: Bool = false,
                                 toEmpty: Int = -1, toFull: Int = -1) -> [String: Any] {
        [
            kIOPSTypeKey: kIOPSInternalBatteryType,
            kIOPSIsPresentKey: true,
            kIOPSCurrentCapacityKey: current,
            kIOPSMaxCapacityKey: max,
            kIOPSPowerSourceStateKey: source,
            kIOPSIsChargingKey: charging,
            kIOPSIsChargedKey: charged,
            kIOPSTimeToEmptyKey: toEmpty,
            kIOPSTimeToFullChargeKey: toFull,
        ]
    }

    @Test func desktopHasNoBattery() {
        let ups: [String: Any] = [kIOPSTypeKey: kIOPSUPSType, kIOPSCurrentCapacityKey: 90]
        for descriptions in [[], [ups]] {
            let state = PowerSourceParser.state(descriptions: descriptions, providingType: kIOPMACPowerKey,
                                                isLowPowerMode: true)
            #expect(!state.hasBattery)
            #expect(state.minutesRemaining == nil)
            #expect(state.isLowPowerMode)
        }
    }

    @Test func absentBatteryIsNoBattery() {
        var description = internalBattery(current: 50)
        description[kIOPSIsPresentKey] = false
        let state = PowerSourceParser.state(descriptions: [description], providingType: nil, isLowPowerMode: false)
        #expect(!state.hasBattery)
    }

    @Test func onBatteryCountsDownToEmpty() {
        let state = PowerSourceParser.state(
            descriptions: [internalBattery(current: 76, toEmpty: 312, toFull: 40)],
            providingType: kIOPSBatteryPowerValue, isLowPowerMode: false)
        #expect(state == PowerState(hasBattery: true, level: 76, isCharging: false, isPluggedIn: false,
                                    isCharged: false, minutesRemaining: 312, isLowPowerMode: false))
    }

    @Test func chargingCountsUpToFull() {
        let state = PowerSourceParser.state(
            descriptions: [internalBattery(current: 40, source: kIOPSACPowerValue, charging: true,
                                           toEmpty: 500, toFull: 72)],
            providingType: kIOPMACPowerKey, isLowPowerMode: false)
        #expect(state.isPluggedIn)
        #expect(state.isCharging)
        #expect(state.minutesRemaining == 72)
    }

    @Test func optimisedChargingHoldIsPluggedInNotCharging() {
        let state = PowerSourceParser.state(
            descriptions: [internalBattery(current: 80, source: kIOPSACPowerValue, charging: false,
                                           charged: true, toFull: 0)],
            providingType: kIOPMACPowerKey, isLowPowerMode: false)
        #expect(state.isPluggedIn)
        #expect(!state.isCharging)
        #expect(state.isCharged)
        #expect(state.minutesRemaining == nil)
    }

    @Test(arguments: [-1, 0, 0xFFFF])
    func unknownEstimatesAreNil(minutes: Int) {
        let state = PowerSourceParser.state(descriptions: [internalBattery(current: 50, toEmpty: minutes)],
                                            providingType: kIOPSBatteryPowerValue, isLowPowerMode: false)
        #expect(state.minutesRemaining == nil)
    }

    @Test func milliampHourCapacitiesAreNormalised() {
        let state = PowerSourceParser.state(descriptions: [internalBattery(current: 4_500, max: 6_000)],
                                            providingType: kIOPSBatteryPowerValue, isLowPowerMode: false)
        #expect(state.level == 75)
        let overfull = PowerSourceParser.state(descriptions: [internalBattery(current: 6_100, max: 6_000)],
                                               providingType: kIOPSBatteryPowerValue, isLowPowerMode: false)
        #expect(overfull.level == 100)
    }

    @Test func fallsBackToTheBatteryStateWithoutAProvidingType() {
        let plugged = PowerSourceParser.state(
            descriptions: [internalBattery(current: 50, source: kIOPSACPowerValue, charging: true, toFull: 30)],
            providingType: nil, isLowPowerMode: false)
        #expect(plugged.isPluggedIn && plugged.isCharging)
        let unplugged = PowerSourceParser.state(descriptions: [internalBattery(current: 50, toEmpty: 200)],
                                                providingType: nil, isLowPowerMode: false)
        #expect(!unplugged.isPluggedIn)
        #expect(unplugged.minutesRemaining == 200)
    }

    @Test func chargingFlagIsIgnoredOnBatteryPower() {
        let state = PowerSourceParser.state(
            descriptions: [internalBattery(current: 50, charging: true, toEmpty: 100)],
            providingType: kIOPSBatteryPowerValue, isLowPowerMode: false)
        #expect(!state.isCharging)
        #expect(state.minutesRemaining == 100)
    }

    @Test func picksTheInternalBatteryAmongSources() {
        let ups: [String: Any] = [kIOPSTypeKey: kIOPSUPSType, kIOPSCurrentCapacityKey: 10]
        let state = PowerSourceParser.state(descriptions: [ups, internalBattery(current: 64)],
                                            providingType: kIOPSBatteryPowerValue, isLowPowerMode: false)
        #expect(state.hasBattery)
        #expect(state.level == 64)
    }
}

// MARK: - PowerMonitor

@Suite struct PowerMonitorTests {

    @Test func refreshPublishesChangesAndForwardsEvents() {
        var reading = battery(50)
        let monitor = PowerMonitor(readState: { reading })
        var events: [PowerEvent] = []
        monitor.onEvent = { events.append($0) }

        monitor.refresh()
        #expect(monitor.state == battery(50))
        #expect(events.isEmpty)

        reading = battery(50, plugged: true)
        monitor.refresh()
        #expect(monitor.state == reading)
        #expect(events == [.connected])
    }

    @Test func demoStateOwnsTheScreenUntilCleared() {
        var reading = battery(50)
        let monitor = PowerMonitor(readState: { reading })
        var events: [PowerEvent] = []
        monitor.onEvent = { events.append($0) }
        monitor.refresh()

        let demo = battery(12)
        monitor.injectDemo(demo, event: .low(threshold: 20))
        #expect(monitor.state == demo)
        #expect(events == [.low(threshold: 20)])

        // Real changes are tracked but neither shown nor announced under a demo.
        reading = battery(50, plugged: true)
        monitor.refresh()
        #expect(monitor.state == demo)
        #expect(events == [.low(threshold: 20)])

        monitor.injectDemo(nil, event: nil)
        #expect(monitor.state == reading)
    }

    @Test func startAndStopAreIdempotentAndStartPublishesTheFirstReading() {
        var reading = desktop(lowPower: true)
        let monitor = PowerMonitor(readState: { reading })
        var events: [PowerEvent] = []
        monitor.onEvent = { events.append($0) }

        monitor.start()
        monitor.start()
        #expect(monitor.isRunning)
        #expect(monitor.state.isLowPowerMode)
        monitor.stop()
        monitor.stop()
        #expect(!monitor.isRunning)

        // Low Power Mode went off while stopped: the reading equals `.unknown`, and must
        // still replace the stale state on screen.
        reading = desktop(plugged: false)
        monitor.start()
        #expect(monitor.state == reading)
        monitor.stop()
        #expect(events.isEmpty)
    }
}

// MARK: - DragLatch

@Suite struct DragLatchTests {

    /// One gesture against a fake drag pasteboard that counts how often the latch touches
    /// it (every touch is IPC in the real monitor).
    private final class Gesture {
        var latch = DragLatch()
        var changeCount = 7
        var carriesFiles = true
        var changeCountReads = 0
        var typeReads = 0

        init(carriesFiles: Bool = true) { self.carriesFiles = carriesFiles }

        func down(ownProcess: Bool = false) -> Bool {
            latch.mouseDown(changeCount: changeCount, inOwnProcess: ownProcess)
        }

        func drag(at time: TimeInterval) -> Bool {
            latch.mouseDragged(at: time,
                               changeCount: { changeCountReads += 1; return changeCount },
                               carriesFileURLs: { typeReads += 1; return carriesFiles })
        }

        func up() -> Bool { latch.mouseUp() }
    }

    @Test func clickIsNotADrag() {
        let gesture = Gesture()
        #expect(!gesture.down())
        #expect(!gesture.up())
        #expect(gesture.latch.phase == .idle)
    }

    @Test func fileDragIsAnnouncedOnceAndEndsOnce() {
        let gesture = Gesture()
        _ = gesture.down()
        #expect(!gesture.drag(at: 10.00))   // moving, session not started yet
        gesture.changeCount += 1
        #expect(gesture.drag(at: 10.05))
        #expect(!gesture.drag(at: 10.10))
        #expect(!gesture.drag(at: 30.00))
        #expect(gesture.changeCountReads == 2)
        #expect(gesture.typeReads == 1)
        #expect(gesture.up())
        #expect(!gesture.up())
    }

    @Test func nonFileDragIsIgnoredUntilMouseUp() {
        let gesture = Gesture(carriesFiles: false)
        _ = gesture.down()
        gesture.changeCount += 1
        #expect(!gesture.drag(at: 1.0))
        gesture.carriesFiles = true
        #expect(!gesture.drag(at: 1.1))
        #expect(gesture.typeReads == 1)
        #expect(gesture.latch.phase == .ignored)
        #expect(!gesture.up())
    }

    @Test func windowClosesAfterTheDecisionWindow() {
        let gesture = Gesture()
        _ = gesture.down()
        #expect(!gesture.drag(at: 5.0))                                   // text selection…
        #expect(!gesture.drag(at: 5.0 + DragLatch.decisionWindow + 0.01))
        gesture.changeCount += 1                                          // …something else writes
        #expect(!gesture.drag(at: 6.0))
        #expect(gesture.changeCountReads == 1)
        #expect(gesture.typeReads == 0)
        #expect(!gesture.up())
    }

    @Test func windowStartsAtTheFirstDragEventNotThePress() {
        let gesture = Gesture()
        _ = gesture.down()
        // Pressed and held for a while before moving: the press time is not recorded at all.
        #expect(!gesture.drag(at: 102.0))
        gesture.changeCount += 1
        #expect(gesture.drag(at: 102.3))
    }

    @Test func dragsFromOurOwnWindowsAreIgnored() {
        let gesture = Gesture()
        _ = gesture.down(ownProcess: true)
        gesture.changeCount += 1
        #expect(!gesture.drag(at: 0.1))
        #expect(gesture.changeCountReads == 0)
        #expect(!gesture.up())
    }

    @Test func missedMouseUpIsReportedOnTheNextPress() {
        let gesture = Gesture()
        _ = gesture.down()
        gesture.changeCount += 1
        #expect(gesture.drag(at: 0.1))
        #expect(gesture.down())
        #expect(!gesture.down())
    }

    @Test func dragWithoutAPressIsIgnored() {
        let gesture = Gesture()
        gesture.changeCount += 1
        #expect(!gesture.drag(at: 0.1))
        #expect(gesture.changeCountReads == 0)
    }
}

// MARK: - ShelfStore

@Suite final class ShelfStoreTests {
    let directory: URL
    let suiteName: String
    let defaults: UserDefaults

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appending(path: "ni2-shelf-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "ni2.tests.shelf.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suiteName))
    }

    deinit {
        UserDefaults().removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeFile(_ name: String) throws -> URL {
        let url = directory.appending(path: name, directoryHint: .notDirectory)
        try Data(name.utf8).write(to: url)
        return url
    }

    private func makeFolder(_ name: String) throws -> URL {
        let url = directory.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func addDeduplicatesEveryWay() throws {
        let store = ShelfStore(defaults: defaults)
        let file = try makeFile("a.txt")
        let folder = try makeFolder("Folder")
        // /var and /tmp are symlinks into /private: the same file under both spellings.
        let path = file.path(percentEncoded: false)
        let aliasedPath = path.hasPrefix("/private/") ? String(path.dropFirst("/private".count)) : "/private" + path
        #expect(FileManager.default.fileExists(atPath: aliasedPath))
        let dotted = directory.appending(path: "Folder/../a.txt")
        let unslashed = URL(filePath: String(folder.path(percentEncoded: false).dropLast()),
                            directoryHint: .notDirectory)

        #expect(store.add([file, file, folder]) == 2)
        #expect(store.add([file, URL(filePath: aliasedPath), dotted, unslashed, folder]) == 0)
        #expect(store.items.count == 2)
    }

    @Test func addSkipsNonFileAndMissingURLs() throws {
        let store = ShelfStore(defaults: defaults)
        let missing = directory.appending(path: "missing.txt")
        let web = try #require(URL(string: "https://www.apple.com"))
        #expect(store.add([web, missing]) == 0)
        #expect(store.items.isEmpty)
        #expect(defaults.data(forKey: ShelfStore.defaultsKey) == nil)
    }

    @Test func persistenceRoundTrip() throws {
        let store = ShelfStore(defaults: defaults)
        let urls = [try makeFile("one.pdf"), try makeFolder("Two"), try makeFile("three.png")]
        #expect(store.add(urls) == 3)

        let reloaded = ShelfStore(defaults: defaults)
        #expect(reloaded.items == store.items)
        #expect(reloaded.items[1].url.hasDirectoryPath)
    }

    @Test func removeAndClearPersist() throws {
        let store = ShelfStore(defaults: defaults)
        store.add([try makeFile("a"), try makeFile("b"), try makeFile("c")])
        store.remove(store.items[1].id)
        #expect(ShelfStore(defaults: defaults).items.map(\.url.lastPathComponent) == ["a", "c"])
        store.clear()
        #expect(store.items.isEmpty)
        #expect(ShelfStore(defaults: defaults).items.isEmpty)
    }

    @Test func pruneDropsVanishedFilesAndPersists() throws {
        let store = ShelfStore(defaults: defaults)
        let doomed = try makeFile("doomed.txt")
        store.add([doomed, try makeFile("kept.txt")])
        try FileManager.default.removeItem(at: doomed)

        store.pruneMissing()
        #expect(store.items.map(\.url.lastPathComponent) == ["kept.txt"])
        #expect(ShelfStore(defaults: defaults).items.count == 1)
    }

    /// Loading does no file-system work on the main thread; the start-up pass prunes in the
    /// background and applies the result.
    @Test func startupPrunesFilesDeletedWhileQuit() async throws {
        let doomed = try makeFile("doomed.txt")
        ShelfStore(defaults: defaults).add([doomed, try makeFile("kept.txt")])
        try FileManager.default.removeItem(at: doomed)
        let store = ShelfStore(defaults: defaults)
        #expect(store.items.count == 2)
        store.pruneMissingInBackground()
        for _ in 0..<200 where store.items.count != 1 {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(store.items.map(\.url.lastPathComponent) == ["kept.txt"])
    }

    @Test func followsARenamedFile() throws {
        let store = ShelfStore(defaults: defaults)
        let original = try makeFile("draft.txt")
        store.add([original])
        let id = try #require(store.items.first?.id)
        try FileManager.default.moveItem(at: original, to: directory.appending(path: "final.txt"))

        store.pruneMissing()
        #expect(store.items.map(\.id) == [id])
        #expect(store.items.first?.url.lastPathComponent == "final.txt")
        #expect(ShelfStore(defaults: defaults).items.first?.url.lastPathComponent == "final.txt")
    }

    @Test func unreadableDataIsDiscarded() {
        defaults.set(Data("not a plist".utf8), forKey: ShelfStore.defaultsKey)
        let store = ShelfStore(defaults: defaults)
        #expect(store.items.isEmpty)
        #expect(defaults.data(forKey: ShelfStore.defaultsKey) == nil)
    }

    @Test func itemIsCodable() throws {
        let item = ShelfItem(id: UUID(), url: try makeFile("x"), addedAt: .now, displayName: "x")
        let decoded = try JSONDecoder().decode(ShelfItem.self, from: JSONEncoder().encode(item))
        #expect(decoded == item)
    }
}

// MARK: - TimerStore

/// A wall clock the test moves by hand.
private final class TestClock {
    var now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    func advance(_ seconds: TimeInterval) { now += seconds }
}

/// A sleeper whose wake-ups the test releases by hand. Not cancellation-aware on purpose:
/// a stale wake-up that still returns must be ignored by the store itself.
private final class ManualSleeper {
    private(set) var requests: [Duration] = []
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func sleep(_ duration: Duration) async {
        requests.append(duration)
        await withCheckedContinuation { waiting.append($0) }
    }

    func wakeAll() {
        let released = waiting
        waiting.removeAll()
        for continuation in released { continuation.resume() }
    }
}

/// Lets main-actor tasks that were just unblocked run.
private func settle(until condition: () -> Bool) async {
    var attempts = 0
    while !condition() && attempts < 200 {
        attempts += 1
        await Task.yield()
    }
}

/// Serialized: the wake test posts `didWakeNotification`, which every live store observes.
@Suite(.serialized) struct TimerStoreTests {
    private let clock = TestClock()

    /// For tests that drive `reconcile()` by hand: the wake-up never comes on its own.
    private func makeStore() -> TimerStore {
        TimerStore(now: { [clock] in clock.now }, sleep: { _ in try await Task.sleep(for: .seconds(86_400)) })
    }

    private func makeStore(sleeper: ManualSleeper) -> TimerStore {
        TimerStore(now: { [clock] in clock.now }, sleep: { await sleeper.sleep($0) })
    }

    @Test func startRunsFromNow() {
        let store = makeStore()
        store.start(minutes: 5)
        #expect(store.countdown == .running(endDate: clock.now + 300, total: 300))
        #expect(store.isCountdownActive)
    }

    @Test(arguments: [0, -5, .nan, .infinity] as [TimeInterval])
    func invalidDurationsAreIgnored(duration: TimeInterval) {
        let store = makeStore()
        store.start(duration: duration)
        #expect(store.countdown == .idle)
        #expect(!store.isCountdownActive)
    }

    @Test func pauseAndResumeKeepTheRemainingTime() {
        let store = makeStore()
        store.start(duration: 300)
        clock.advance(100)
        store.pause()
        #expect(store.countdown == .paused(remaining: 200, total: 300))
        #expect(store.isCountdownActive)
        clock.advance(1_000)
        store.reconcile()
        #expect(store.countdown == .paused(remaining: 200, total: 300))
        store.resume()
        #expect(store.countdown == .running(endDate: clock.now + 200, total: 300))
    }

    @Test func addExtendsWithoutMovingProgress() {
        let store = makeStore()
        store.start(duration: 120)
        clock.advance(60)
        #expect(store.progress(at: clock.now) == 0.5)
        store.add(seconds: 60)
        #expect(store.countdown == .running(endDate: clock.now + 120, total: 180))
        #expect(abs(store.progress(at: clock.now) - 60.0 / 180.0) < 1e-9)

        store.pause()
        store.add(seconds: 30)
        #expect(store.countdown == .paused(remaining: 150, total: 210))
    }

    @Test func addOnIdleOrFinishedStartsANewCountdown() {
        let store = makeStore()
        store.add(seconds: 60)
        #expect(store.countdown == .running(endDate: clock.now + 60, total: 60))
        clock.advance(61)
        store.reconcile()
        #expect(store.countdown == .finished(at: clock.now - 1))
        store.add(seconds: 60)
        #expect(store.countdown == .running(endDate: clock.now + 60, total: 60))
    }

    @Test func progressAcrossStates() {
        let store = makeStore()
        #expect(store.progress(at: clock.now) == 0)
        store.start(duration: 100)
        #expect(store.progress(at: clock.now) == 0)
        #expect(store.progress(at: clock.now + 25) == 0.25)
        #expect(store.progress(at: clock.now + 500) == 1)
        clock.advance(40)
        store.pause()
        #expect(store.progress(at: clock.now + 1_000) == 0.4)
        store.resume()
        clock.advance(60)
        store.reconcile()
        #expect(store.progress(at: clock.now) == 1)
    }

    @Test func finishesOnceAndWaitsForAcknowledgement() {
        let store = makeStore()
        var finishedCount = 0
        store.onFinished = { finishedCount += 1 }
        store.start(duration: 10)
        let end = clock.now + 10

        clock.advance(9)
        store.reconcile()
        #expect(finishedCount == 0)

        clock.advance(5)
        store.reconcile()
        store.reconcile()
        #expect(store.countdown == .finished(at: end))
        #expect(store.isCountdownActive)
        #expect(finishedCount == 1)

        store.pause()
        store.resume()
        #expect(store.countdown == .finished(at: end))

        store.acknowledge()
        #expect(store.countdown == .idle)
        #expect(finishedCount == 1)
    }

    @Test func acknowledgeOnlyClearsAFinishedCountdown() {
        let store = makeStore()
        store.start(duration: 10)
        store.acknowledge()
        #expect(store.isCountdownActive)
    }

    @Test func cancelNeverFinishes() {
        let store = makeStore()
        var finishedCount = 0
        store.onFinished = { finishedCount += 1 }
        store.start(duration: 10)
        store.cancel()
        clock.advance(20)
        store.reconcile()
        #expect(store.countdown == .idle)
        #expect(finishedCount == 0)
    }

    @Test func pausingAfterTheEndFinishes() {
        let store = makeStore()
        var finishedCount = 0
        store.onFinished = { finishedCount += 1 }
        store.start(duration: 10)
        clock.advance(12)
        store.pause()
        #expect(store.countdown == .finished(at: clock.now - 2))
        #expect(finishedCount == 1)
    }

    @Test func scheduledWakeUpFinishesTheCountdown() async {
        let sleeper = ManualSleeper()
        let store = makeStore(sleeper: sleeper)
        defer { store.cancel(); sleeper.wakeAll() }
        var finishedCount = 0
        store.onFinished = { finishedCount += 1 }

        store.start(duration: 10)
        await settle { sleeper.requests.count == 1 }
        #expect(sleeper.requests == [.seconds(10)])

        clock.advance(10)
        sleeper.wakeAll()
        await settle { finishedCount > 0 }
        #expect(store.countdown == .finished(at: clock.now))
        #expect(finishedCount == 1)
    }

    @Test func earlyWakeUpReArmsForTheRest() async {
        let sleeper = ManualSleeper()
        let store = makeStore(sleeper: sleeper)
        defer { store.cancel(); sleeper.wakeAll() }

        store.start(duration: 10)
        await settle { sleeper.requests.count == 1 }
        clock.advance(6)
        sleeper.wakeAll()
        await settle { sleeper.requests.count == 2 }
        #expect(sleeper.requests == [.seconds(10), .seconds(4)])
        #expect(store.countdown == .running(endDate: clock.now + 4, total: 10))
    }

    @Test func pauseResumeAndAddReArmTheOneWakeUp() async {
        let sleeper = ManualSleeper()
        let store = makeStore(sleeper: sleeper)
        defer { store.cancel(); sleeper.wakeAll() }
        var finishedCount = 0
        store.onFinished = { finishedCount += 1 }

        store.start(duration: 10)
        await settle { sleeper.requests.count == 1 }
        clock.advance(4)
        store.pause()
        clock.advance(100)
        store.resume()
        await settle { sleeper.requests.count == 2 }
        store.add(seconds: 60)
        await settle { sleeper.requests.count == 3 }
        #expect(sleeper.requests == [.seconds(10), .seconds(6), .seconds(66)])

        // Stale wake-ups from the cancelled arms return too, and must change nothing.
        clock.advance(66)
        sleeper.wakeAll()
        await settle { finishedCount > 0 }
        await settle { false }   // give any stale task the chance to misbehave
        #expect(finishedCount == 1)
        #expect(store.countdown == .finished(at: clock.now))
    }

    @Test func countdownThatExpiredDuringSleepFinishesOnWake() async {
        let sleeper = ManualSleeper()
        let store = makeStore(sleeper: sleeper)
        defer { store.cancel(); sleeper.wakeAll() }
        var finishedCount = 0
        store.onFinished = { finishedCount += 1 }

        store.start(duration: 60)
        await settle { sleeper.requests.count == 1 }
        clock.advance(3_600)   // the lid was closed for an hour
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: NSWorkspace.shared)
        await settle { finishedCount > 0 }
        #expect(store.countdown == .finished(at: clock.now - 3_540))
        #expect(finishedCount == 1)

        // The original wake-up arriving late must not finish it a second time.
        sleeper.wakeAll()
        await settle { false }
        #expect(finishedCount == 1)
    }

    @Test func draftMinutesIsClamped() {
        let store = makeStore()
        #expect(store.draftMinutes == 5)
        store.draftMinutes = 0
        #expect(store.draftMinutes == 1)
        store.draftMinutes = 500
        #expect(store.draftMinutes == 120)
        store.draftMinutes = 30
        store.draftMinutes = .nan
        #expect(store.draftMinutes == 30)
    }

    @Test func stopwatchStartPauseResumeReset() {
        let store = makeStore()
        #expect(!store.isStopwatchActive)
        store.startStopwatch()
        let started = clock.now
        clock.advance(10)
        store.startStopwatch()   // no-op while running
        #expect(store.stopwatch == .running(startDate: started, accumulated: 0))
        #expect(store.stopwatch.elapsed(at: clock.now) == 10)

        store.pauseStopwatch()
        #expect(store.stopwatch == .paused(accumulated: 10))
        clock.advance(5)
        #expect(store.stopwatch.elapsed(at: clock.now) == 10)
        #expect(store.isStopwatchActive)

        store.startStopwatch()
        clock.advance(3)
        #expect(store.stopwatch.elapsed(at: clock.now) == 13)

        store.resetStopwatch()
        #expect(store.stopwatch == .idle)
        #expect(!store.isStopwatchActive)
    }

    @Test func stopwatchPausedAtZeroIsNotActive() {
        let store = makeStore()
        store.startStopwatch()
        store.pauseStopwatch()   // same instant
        #expect(store.stopwatch == .paused(accumulated: 0))
        #expect(!store.isStopwatchActive)
    }
}

@Suite struct DragLatchMonitoringTests {
    /// Drag events are only listened to between a press and the gesture's decision.
    @Test func undecidedOnlyBetweenPressAndDecision() {
        var latch = DragLatch()
        #expect(!latch.isUndecided)
        _ = latch.mouseDown(changeCount: 1, inOwnProcess: false)
        #expect(latch.isUndecided)
        _ = latch.mouseDragged(at: 0, changeCount: { 1 }, carriesFileURLs: { false })
        #expect(latch.isUndecided)
        _ = latch.mouseDragged(at: 1, changeCount: { 1 }, carriesFileURLs: { false })
        #expect(!latch.isUndecided)   // past the decision window
        _ = latch.mouseUp()
        _ = latch.mouseDown(changeCount: 1, inOwnProcess: true)
        #expect(!latch.isUndecided)   // our own press is never watched
    }
}

@Suite struct TimerDraftUnitsTests {
    @Test func minutesOnlyIsTheRulerAsItWas() {
        let units = TimerDraftUnits()
        #expect(units.units == [.minutes] && units.range(of: .minutes) == 1...120)
        #expect(units.normalized(95) == 120)          // whole minutes
        #expect(units.normalized(0) == 60)            // never below a minute
        #expect(units.value(of: .minutes, in: 300) == 5)
    }

    @Test func secondsAfterMinutes() {
        let units = TimerDraftUnits(seconds: true)
        #expect(units.units == [.minutes, .seconds])
        var draft = units.duration(setting: .minutes, to: 2, in: 300)
        #expect(draft == 120)
        draft = units.duration(setting: .seconds, to: 45, in: draft)
        #expect(draft == 165)
        #expect(units.value(of: .minutes, in: draft) == 2 && units.value(of: .seconds, in: draft) == 45)
        // 0 minutes and some seconds is a timer; 0:00 is not.
        #expect(units.duration(setting: .minutes, to: 0, in: 45) == 45)
        #expect(units.duration(setting: .seconds, to: 0, in: 45) == 1)
        #expect(units.next(after: .seconds) == .minutes)
    }

    @Test func hoursWrapTheMinutes() {
        let units = TimerDraftUnits(hours: true, seconds: true)
        #expect(units.units == [.hours, .minutes, .seconds] && units.range(of: .minutes) == 0...59)
        let draft = units.duration(setting: .hours, to: 1, in: 5 * 60 + 30)
        #expect(draft == 3600 + 330)
        #expect(units.value(of: .hours, in: draft) == 1 && units.value(of: .minutes, in: draft) == 5)
        #expect(units.duration(setting: .minutes, to: 90, in: draft) == 3600 + 59 * 60 + 30)
        #expect(units.next(after: .minutes) == .seconds && units.next(after: .seconds) == .hours)
    }

    @Test func switchingUnitsOffDropsWhatTheyCannotShow() {
        let draft: TimeInterval = 2 * 3600 + 5 * 60 + 30
        #expect(TimerDraftUnits(hours: true).normalized(draft) == 2 * 3600 + 6 * 60)
        #expect(TimerDraftUnits(seconds: true).normalized(draft) == 120 * 60 + 59)
    }
}
