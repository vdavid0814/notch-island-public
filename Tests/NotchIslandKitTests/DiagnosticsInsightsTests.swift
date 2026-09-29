import Foundation
import Testing
@testable import NotchIslandKit

@Suite struct DiagnosticsInsightsTests {
    @Test func crashReportIsTakenApart() {
        let header = #"{"bug_type":"309","app_version":"0.4.9","build_version":"19","timestamp":"2026-09-29 01:00:00"}"#
        let body = #"""
        {"exception":{"type":"EXC_BREAKPOINT","signal":"SIGTRAP"},"termination":{"namespace":"SIGNAL","indicator":"Trace/BPT trap: 5"},
         "usedImages":[{"name":"NotchIsland"},{"name":"SwiftUI"}],
         "threads":[{"frames":[]},{"triggered":true,"queue":"com.apple.main-thread","frames":[{"imageIndex":0,"symbol":"LiquidCard.hide()"},{"imageIndex":1,"imageOffset":1234}]}]}
        """#
        let summary = DiagnosticsInsights.crashSummary(header + "\n" + body)
        #expect(summary.contains("EXC_BREAKPOINT SIGTRAP"))
        #expect(summary.contains("crashed thread 1 (com.apple.main-thread)"))
        #expect(summary.contains("0 NotchIsland  LiquidCard.hide()"))
        #expect(summary.contains("1 SwiftUI  offset 1234"))
        #expect(DiagnosticsInsights.crashSummary("not a report").hasPrefix("not a report"))
    }

    @Test func errorsAreCountedBySource() {
        let log = """
            2026-09-29 00:00:00.000 E  NotchIsland[1:2] [com.apple.network:connection] timed out
            2026-09-29 00:00:01.000 E  NotchIsland[1:2] [com.apple.network:connection] timed out again
            2026-09-29 00:00:02.000 E  NotchIsland[1:2] [com.davidvarga.notchisland:levels] listener failed
            2026-09-29 00:00:03.000 Df NotchIsland[1:2] [com.davidvarga.notchisland:app] fine
            """
        let section = DiagnosticsInsights.errorSection(log)
        #expect(section.entries.first?.value == "[com.davidvarga.notchisland:levels] 1×")
        #expect(section.entries.contains { $0.key == "2× [com.apple.network:connection]" })
    }

    @Test @MainActor func flowKeepsTheLastSteps() {
        for index in 0..<(DiagnosticsFlow.capacity + 5) { DiagnosticsFlow.record("step \(index)") }
        #expect(DiagnosticsFlow.steps.count == DiagnosticsFlow.capacity)
        #expect(DiagnosticsFlow.steps.last?.hasSuffix("step \(DiagnosticsFlow.capacity + 4)") == true)
        #expect(DiagnosticsFlow.section().entries.count == 2)
    }
}

@Suite struct DiagnosticsAlertTests {
    @Test @MainActor func aLastingFindingAlertsOnceADay() {
        let name = "alerts-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let center = DiagnosticsCenter(defaults: defaults, destinations: DiagnosticsDestinations(), outbox: nil)
        func envelope(_ findings: [String], kind: DiagnosticsEnvelope.Kind = .report) -> DiagnosticsEnvelope {
            DiagnosticsEnvelope(kind: kind, reason: .periodic, sender: "T", installID: "i", facts: [], findings: findings,
                                feedback: nil, files: [], comparison: [], reference: nil)
        }
        #expect(center.shouldAlertForTests(envelope(["4 copies of NotchIsland on disk"])))
        #expect(!center.shouldAlertForTests(envelope(["5 copies of NotchIsland on disk"])))
        // A new finding alerts; a lighter report without the earlier one does not.
        #expect(center.shouldAlertForTests(envelope(["4 copies of NotchIsland on disk", "2 apps are missing from Spotlight"])))
        #expect(!center.shouldAlertForTests(envelope(["4 copies of NotchIsland on disk"])))
        #expect(center.shouldAlertForTests(envelope(["4 copies of NotchIsland on disk"], kind: .crash)))
        #expect(!center.shouldAlertForTests(envelope([])))
    }
}

@Suite struct DiagnosticsSystemReportsTests {
    @Test func systemReportsAreNotCrashReports() {
        #expect(DiagnosticsReport.Attachment(name: "NotchIsland-2026-09-29.ips", text: "").isCrashReport)
        #expect(!DiagnosticsReport.Attachment(name: "log.txt", text: "").isCrashReport)
        #expect(!DiagnosticsReport.Attachment(name: "system-20260929T010000-hang-AB12.json", text: "").isCrashReport)
    }

    @Test func sentReportsGoAndOthersStay() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("system-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for name in ["system-b-hang.json", "system-a-cpu.json", "other.json", "system-c.txt"] {
            try Data("{}".utf8).write(to: folder.appendingPathComponent(name))
        }
        #expect(DiagnosticsSystemReports.pending(in: folder).map(\.lastPathComponent) == ["system-a-cpu.json", "system-b-hang.json"])
        DiagnosticsSystemReports.markSent(["system-a-cpu.json", "other.json"], in: folder)
        #expect(DiagnosticsSystemReports.pending(in: folder).map(\.lastPathComponent) == ["system-b-hang.json"])
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("other.json").path))
    }
}

@Suite struct DiagnosticsLogWindowTests {
    @Test func anAutomaticReportReadsTheLogBackToThePreviousFullOne() {
        let now = Date()
        let hourAgo = now.addingTimeInterval(-3600)
        #expect(DiagnosticsCenter.logStart(for: .periodic, lastFull: hourAgo, now: now) == hourAgo.addingTimeInterval(-60))
        #expect(DiagnosticsCenter.logStart(for: .launch, lastFull: hourAgo, now: now) == hourAgo.addingTimeInterval(-60))
        #expect(DiagnosticsCenter.logStart(for: .launch, lastFull: .distantPast, now: now) == now.addingTimeInterval(-6 * 3600))
        #expect(DiagnosticsCenter.logStart(for: .manual, lastFull: hourAgo, now: now) == now.addingTimeInterval(-6 * 3600))
    }
}

@Suite struct DiagnosticsSignatureTests {
    @Test func theSignatureIsReadFromTheKernel() {
        let signature = DiagnosticsProbes.checkSignature()
        #expect(!signature.hasPrefix("unreadable"))
        #expect(signature.contains("valid"))
    }
}

@Suite struct DiagnosticsStableSettingsTests {
    @Test func setsReadTheSameEveryTime() {
        var siri = SiriSettings()
        siri.folders = [.downloads, .desktop, .iCloudDrive]
        let encoder = JSONEncoder()
        let json = String(data: try! encoder.encode(siri), encoding: .utf8)!
        let text = DiagnosticsAppState.setsSorted(json, of: siri)
        #expect(text?.contains(#""folders":["desktop","downloads","iCloudDrive"]"#) == true)
        #expect(DiagnosticsAppState.setsSorted(#"["b","a"]"#, of: Set(["a", "b"])) == #"["a","b"]"#)
        #expect(DiagnosticsAppState.setsSorted(#"{"x":1}"#, of: 1) == nil)
    }
}

@Suite struct DiagnosticsTrailTests {
    @Test func theTrailIsThisRunsOwnLines() {
        let log = """
            Timestamp               Ty Process[PID:TID]
            2026-09-29 04:01:50.413 E  NotchIsland[7:2a5612] [com.apple.CFBundle:plugin] AddInstanceForFactory
            2026-09-29 04:01:51.000 Df NotchIsland[7:2a5612] [com.davidvarga.notchisland:app] launched
            2026-09-29 03:01:51.000 Df NotchIsland[6:2a5612] [com.davidvarga.notchisland:app] earlier run
            2026-09-29 04:02:26.860 E  NotchIsland[7:2a5612] [com.davidvarga.notchisland:levels] tap failed
            """
        let section = DiagnosticsEnvironment.trail(fromLog: log, pid: 7)
        #expect(section.entries.first { $0.key == "Lines" }?.value == "2")
        #expect(section.entries.first { $0.key == "Log" }?.value == "04:01:51.000 Df [app] launched\n04:02:26.860 E  [levels] tap failed")
    }
}

@Suite struct DiagnosticsThrottleTests {
    @Test func aThrottledToolStillRunsToTheEnd() async {
        // Off the test's shared threads: blocking one for half a second starved the timing tests.
        let output = await withCheckedContinuation { continuation in
            Thread.detachNewThread {
                continuation.resume(returning: DiagnosticsProbes.run(
                    "/bin/sh", ["-c", "echo a; i=0; while [ $i -lt 5000 ]; do i=$((i+1)); done; echo b"],
                    timeout: 20, throttled: true))
            }
        }
        #expect(output == "a\nb")
    }
}

@Suite struct DiagnosticsTopUsersTests {
    @Test func theHeaviestProcessComesFirst() {
        let before: [pid_t: (name: String, usage: ProcessUsage)] = [
            1: ("Quiet", ProcessUsage(energyNJ: 0, cpuNS: 0)), 2: ("Busy", ProcessUsage(energyNJ: 0, cpuNS: 0)),
        ]
        let after: [pid_t: (name: String, usage: ProcessUsage)] = [
            1: ("Quiet", ProcessUsage(energyNJ: 1_000_000, cpuNS: 1_000_000)), 2: ("Busy", ProcessUsage(energyNJ: 500_000_000, cpuNS: 250_000_000)),
            3: ("New", ProcessUsage(energyNJ: 9_000_000_000)),
        ]
        let lines = BatteryProbe.topLines(before: before, after: after, seconds: 1)
        #expect(lines.count == 2)
        #expect(lines.first?.contains("Busy") == true)
        #expect(lines.first?.contains("500.0 mW") == true)
        #expect(lines.first?.contains("CPU  25.0%") == true)
    }

    @Test func everyProcessIncludesThisOne() {
        #expect(BatteryProbe.everyProcess()[getpid()] != nil)
    }
}

@Suite struct DiagnosticsVerdictTests {
    static func health(_ entries: [(String, String)]) -> DiagnosticsReport.Section {
        .init("Feature health", entries.map { .init(key: $0.0, value: $0.1) })
    }

    @Test func aHealthyReportCountsWhatWorks() {
        var report = DiagnosticsReport()
        report.sections = [Self.health([("Now Playing", "✅ running — on"), ("AirPods", "✅ running"), ("Timers", "off (by the user)")])]
        let verdict = DiagnosticsVerdict.make(report: report, metrics: [:], comparisons: [], crashes: 0)
        #expect(verdict.issues == 0 && verdict.warnings == 0 && verdict.healthy == 2)
        #expect(verdict.mostLikely == nil)
        #expect(verdict.section.entries.first { $0.key == DiagnosticsVerdict.causeKey }?.value == "nothing wrong found")
    }

    @Test func accessibilityOffIsAnIssueWithItsFix() {
        var report = DiagnosticsReport()
        report.sections = [Self.health([("Accessibility", "⚠︎ wanted but not running"), ("Now Playing", "✅ running")])]
        let verdict = DiagnosticsVerdict.make(report: report, metrics: [:], comparisons: [], crashes: 0)
        #expect(verdict.issues == 1)
        #expect(verdict.mostLikely?.feature == DiagnosticsVerdict.Feature.keys)
        #expect(verdict.mostLikely?.action.contains("Accessibility") == true)
    }

    @Test func searchesWithoutAppsPointAtTheAppOutsideTheFolders() {
        var report = DiagnosticsReport()
        report.sections = [
            .init("User flow", [.init(key: "Flow", value: """
                10:00:00.000 siri: "xc" in root → 0 apps, 1 files (anywhere)
                10:00:00.100 siri: "xco" in root → 0 apps, 2 files (anywhere)
                10:00:00.200 siri: "xcode" in root → 0 apps, 3 files (anywhere)
                10:00:01.000 siri: "safari" in root → 1 apps, 0 files (anywhere)
                """)]),
            .init(DiagnosticsProbes.spotlightTitle, [.init(key: DiagnosticsProbes.elsewhereKey, value: "1: ~/Downloads/Xcode.app")]),
        ]
        #expect(DiagnosticsVerdict.searchesWithoutApps(report) == ["xcode"])
        let verdict = DiagnosticsVerdict.make(report: report, metrics: [:], comparisons: [], crashes: 0)
        #expect(verdict.mostLikely?.id == "siri.appOutsideFolders")
        #expect(verdict.mostLikely?.cause.contains("Downloads/Xcode.app") == true)
    }

    @Test func aCrashNamesItsFeature() {
        var report = DiagnosticsReport()
        report.sections = [.init("Crash analysis", [.init(key: "NotchIsland.ips", value: """
            type 309, app 0.4.9 (19), 2026-09-29
            exception: EXC_BREAKPOINT SIGTRAP
            crashed thread 0 (com.apple.main-thread):
              0 NotchIsland  LiquidCard.hide()
            """)])]
        let verdict = DiagnosticsVerdict.make(report: report, metrics: [:], comparisons: [], crashes: 1)
        #expect(verdict.mostLikely?.feature == DiagnosticsVerdict.Feature.liquid)
        #expect(verdict.mostLikely?.cause.contains("EXC_BREAKPOINT") == true)
    }

    @Test func newAndResolvedSinceThePreviousReport() {
        var report = DiagnosticsReport()
        report.sections = [Self.health([("Now Playing", "⚠︎ wanted but not running")])]
        let verdict = DiagnosticsVerdict.make(report: report, metrics: [:], comparisons: [], crashes: 0,
                                              previous: ["install.outdated": "Outdated: runs 0.4.8"])
        #expect(verdict.new == ["[Now Playing] Now Playing is on but not running"])
        #expect(verdict.resolved == ["Outdated: runs 0.4.8"])
        #expect(verdict.remembered.keys.sorted() == ["feature.Now Playing"])
    }

    @Test func theComplaintChoosesTheCause() {
        var report = DiagnosticsReport()
        report.sections = [
            Self.health([("Now Playing", "⚠︎ wanted but not running"), ("⌘Space for Siri", "⚠︎ wanted but not running")]),
        ]
        let plain = DiagnosticsVerdict.make(report: report, metrics: [:], comparisons: [], crashes: 0)
        let complaint = DiagnosticsVerdict.make(report: report, metrics: [:], comparisons: [], crashes: 0,
                                                complaint: "A spotlight nem hozza be az alkalmazásokat")
        #expect(complaint.focus == DiagnosticsVerdict.Feature.siri)
        #expect(complaint.mostLikely?.feature == DiagnosticsVerdict.Feature.siri)
        #expect(plain.focus == nil)
        #expect(DiagnosticsVerdict.focus("a zene borítója nem jelenik meg") == DiagnosticsVerdict.Feature.nowPlaying)
        #expect(DiagnosticsVerdict.focus("hello") == nil)
    }

    @Test func ownErrorsAreCountedByFeature() {
        var report = DiagnosticsReport()
        report.sections = [.init("Errors by source", [.init(key: "NotchIsland's own",
                                                            value: "[com.davidvarga.notchisland:levels] 3×, [com.davidvarga.notchisland:media] 1×")])]
        let verdict = DiagnosticsVerdict.make(report: report, metrics: [:], comparisons: [], crashes: 0)
        #expect(verdict.ownErrors == "4 (levels 3, media 1)")
        #expect(verdict.affectedFeatures == [DiagnosticsVerdict.Feature.keys, DiagnosticsVerdict.Feature.nowPlaying])
        var light = DiagnosticsReport()
        light.sections = [.init("App", [.init(key: "Report depth", value: "light (hourly…)")])]
        #expect(DiagnosticsVerdict.make(report: light, metrics: [:], comparisons: [], crashes: 0).ownErrors.hasPrefix("not read"))
    }
}
