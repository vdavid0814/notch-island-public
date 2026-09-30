import Darwin
import Foundation
import Testing
@testable import NotchIslandKit

@Suite struct DiagnosticsCacheTests {
    private static func temporaryCache() -> DiagnosticsCache {
        DiagnosticsCache(folder: FileManager.default.temporaryDirectory.appendingPathComponent("DiagnosticsCache-\(UUID().uuidString)"))
    }

    private static func section(_ value: String) -> DiagnosticsReport {
        var section = DiagnosticsReport.Section("Hardware")
        section.add("Audio", value)
        var report = DiagnosticsReport(sections: [section])
        report.metrics[.gallerySeconds] = 0.25
        return report
    }

    @Test func aLaunchSoonAfterAFullReportSendsALightOne() {
        let now = Date()
        let hourAgo = now.addingTimeInterval(-3600)
        let longAgo = now.addingTimeInterval(-DiagnosticsCenter.fullReportInterval - 60)
        #expect(DiagnosticsCenter.isLight(.launch, lastFull: hourAgo, now: now))
        #expect(DiagnosticsCenter.isLight(.periodic, lastFull: hourAgo, now: now))
        #expect(!DiagnosticsCenter.isLight(.launch, lastFull: longAgo, now: now))
        #expect(!DiagnosticsCenter.isLight(.periodic, lastFull: longAgo, now: now))
        #expect(!DiagnosticsCenter.isLight(.launch, lastFull: .distantPast, now: now))
        // After a crash or an update, by hand, and for an anomaly or a problem: always full.
        for reason in [DiagnosticsReason.crash, .update, .manual, .anomaly, .problem, .enabled] {
            #expect(!DiagnosticsCenter.isLight(reason, lastFull: hourAgo, now: now))
        }
    }

    @Test func keptSectionsStandForTheirKeyAndLifetime() {
        let now = Date()
        let entry = DiagnosticsCache.Entry(key: "boot a, 0.6 (23)", written: now.addingTimeInterval(-3600), sections: [])
        #expect(DiagnosticsCache.isFresh(entry, key: "boot a, 0.6 (23)", lifetime: nil, now: now))
        // Another boot, another build: read again.
        #expect(!DiagnosticsCache.isFresh(entry, key: "boot b, 0.6 (23)", lifetime: nil, now: now))
        #expect(!DiagnosticsCache.isFresh(entry, key: "boot a, 0.6 (24)", lifetime: nil, now: now))
        // Spotlight: six hours.
        let lifetime = DiagnosticsCache.spotlightLifetime
        #expect(DiagnosticsCache.isFresh(entry, key: entry.key, lifetime: lifetime, now: now))
        #expect(DiagnosticsCache.isFresh(entry, key: entry.key, lifetime: lifetime, now: now.addingTimeInterval(lifetime - 3601)))
        #expect(!DiagnosticsCache.isFresh(entry, key: entry.key, lifetime: lifetime, now: now.addingTimeInterval(lifetime)))
        // Written "later" than now: the clock was set back.
        #expect(!DiagnosticsCache.isFresh(entry, key: entry.key, lifetime: lifetime, now: now.addingTimeInterval(-7200)))
    }

    @Test func sectionsAreReadOnceThenKeptUntilTheirKeyChanges() async {
        var cache = Self.temporaryCache()
        defer { cache.folder.map { try? FileManager.default.removeItem(at: $0) } }
        var reads = 0
        let first = await cache.report("hardware", key: "k1") { reads += 1; return Self.section("one") }
        let again = await cache.report("hardware", key: "k1") { reads += 1; return Self.section("two") }
        #expect(reads == 1)
        #expect(again.sections[0].entries[0] == first.sections[0].entries[0])
        let changed = await cache.report("hardware", key: "k2") { reads += 1; return Self.section("three") }
        #expect(reads == 2)
        #expect(changed.sections[0].entries[0].value == "three")
        // By hand: read afresh, and kept for the next automatic report.
        cache.reuses = false
        let byHand = await cache.report("hardware", key: "k2") { reads += 1; return Self.section("four") }
        #expect(reads == 3)
        #expect(byHand.sections[0].entries[0].value == "four")
        cache.reuses = true
        let after = await cache.report("hardware", key: "k2") { reads += 1; return Self.section("five") }
        #expect(reads == 3)
        #expect(after.sections[0].entries[0].value == "four")
    }

    @Test func keptSectionsSaySinceWhenAndBringNoNumbers() async {
        let cache = Self.temporaryCache()
        defer { cache.folder.map { try? FileManager.default.removeItem(at: $0) } }
        let written = Date(timeIntervalSince1970: 1_800_000_000)
        let lifetime = DiagnosticsCache.spotlightLifetime
        let fresh = await cache.report("spotlight", key: "k", lifetime: lifetime, now: written) { Self.section("one") }
        #expect(fresh.metrics[.gallerySeconds] == 0.25)
        #expect(!fresh.sections[0].entries.contains { $0.key == "Kept since" })
        let kept = await cache.report("spotlight", key: "k", lifetime: lifetime, now: written.addingTimeInterval(3600)) {
            Self.section("two")
        }
        // Siri's numbers of hours ago, sent again, were judged against the reference as this report's.
        #expect(kept.metrics.isEmpty)
        #expect(kept.sections[0].entries == fresh.sections[0].entries
            + [DiagnosticsReport.Entry(key: "Kept since", value: DiagnosticsFormat.date(written))])
    }

    @Test func onlyTheLaunchReportWaitsForTheSystemAndTheHourlyOnesDoNot() {
        let launch = DiagnosticsCenter.reportTimes(firstDelay: DiagnosticsCenter.launchDelay, firstReason: .launch)
        #expect(launch.scheduled)
        // The hourly reports an hour after launch, however long the system holds the launch report back.
        #expect(launch.loopDelay == DiagnosticsCenter.periodicInterval)
        #expect(launch.loopReason == .periodic)
        for reason in [DiagnosticsReason.crash, .update, .enabled] {
            let times = DiagnosticsCenter.reportTimes(firstDelay: .seconds(25), firstReason: reason)
            #expect(!times.scheduled)
            #expect(times.loopDelay == .seconds(25))
            #expect(times.loopReason == reason)
        }
    }

    @Test func automaticReportsReuseKeptSectionsTheOthersReadAfresh() {
        for reason in [DiagnosticsReason.launch, .periodic, .crash, .update, .enabled, .anomaly, .problem] {
            #expect(DiagnosticsCenter.reusesKept(reason))
        }
        // By hand, and a bug report, the preview or the reference (no reason).
        #expect(!DiagnosticsCenter.reusesKept(.manual))
        #expect(!DiagnosticsCenter.reusesKept(nil))
    }

    @Test func aStaleLaunchCallbackSendsNothing() {
        let first = NSBackgroundActivityScheduler(identifier: "test.diagnostics.first")
        let second = NSBackgroundActivityScheduler(identifier: "test.diagnostics.second")
        #expect(DiagnosticsCenter.sendsLaunchReport(fired: ObjectIdentifier(first), current: first))
        // After `stop()`, or once it fired.
        #expect(!DiagnosticsCenter.sendsLaunchReport(fired: ObjectIdentifier(first), current: nil))
        // After a second `reschedule`.
        #expect(!DiagnosticsCenter.sendsLaunchReport(fired: ObjectIdentifier(first), current: second))
    }

    @Test func spotlightIsReadAgainAfterSixHours() async {
        let cache = Self.temporaryCache()
        defer { cache.folder.map { try? FileManager.default.removeItem(at: $0) } }
        let start = Date()
        var reads = 0
        let lifetime = DiagnosticsCache.spotlightLifetime
        _ = await cache.report("spotlight", key: "0.6 (23)", lifetime: lifetime, now: start) { reads += 1; return Self.section("a") }
        _ = await cache.report("spotlight", key: "0.6 (23)", lifetime: lifetime, now: start.addingTimeInterval(5 * 3600)) {
            reads += 1; return Self.section("b")
        }
        #expect(reads == 1)
        _ = await cache.report("spotlight", key: "0.6 (23)", lifetime: lifetime, now: start.addingTimeInterval(6 * 3600 + 1)) {
            reads += 1; return Self.section("c")
        }
        #expect(reads == 2)
    }

    @Test func theKeysDescribeThisMac() {
        #expect(DiagnosticsCache.hardwareKey().hasPrefix(DiagnosticsCache.bootAndBuild()))
        #expect(DiagnosticsCache.appsKey() == DiagnosticsCache.appsKey())
        #expect(DiagnosticsCache.spotlightKey() == DiagnosticsCache.build())
        // The apps section with the Dock line added is the one read in one go.
        let apps = DiagnosticsEnvironment.installedApps()
        #expect(apps.entries.last?.key == "In the Dock")
        #expect(Array(apps.entries.dropLast()) == DiagnosticsEnvironment.appsOnDisk().entries)
    }

    /// CPU seconds of this process and the tools it waited for.
    private static func cpuSeconds() -> Double {
        func seconds(_ who: Int32) -> Double {
            var usage = rusage()
            getrusage(who, &usage)
            return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1e6
        }
        return seconds(RUSAGE_SELF) + seconds(RUSAGE_CHILDREN)
    }

    /// `NI_BENCH=1`: the full report's collection (no log, nothing sent) with nothing kept, then with
    /// its hardware, apps and Spotlight kept, and the light report.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["NI_BENCH"] == "1"))
    func benchmarkCollectColdAgainstCached() async {
        let cache = Self.temporaryCache()
        defer { cache.folder.map { try? FileManager.default.removeItem(at: $0) } }
        func measure(light: Bool) async -> (wall: Double, cpu: Double, report: DiagnosticsReport) {
            let cpu = Self.cpuSeconds()
            let started = Date()
            let report = await DiagnosticsCenter.collect(launchedAt: Date(), logHours: 0, crashesSince: nil, basicOnly: false,
                                                         light: light, cache: cache)
            return (Date().timeIntervalSince(started), Self.cpuSeconds() - cpu, report)
        }
        let cold = await measure(light: false)
        let cached = await measure(light: false)
        let light = await measure(light: true)
        #expect(cold.report.sections.map(\.title) == cached.report.sections.map(\.title))
        print(String(format: "BENCH diagnostics collect (full, no log): cold %.2f s wall / %.2f s CPU, cached %.2f s wall / %.2f s CPU; light %.2f s wall / %.2f s CPU",
                     cold.wall, cold.cpu, cached.wall, cached.cpu, light.wall, light.cpu))
    }
}
