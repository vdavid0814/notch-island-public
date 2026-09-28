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

    @Test func causesAreReadFromTheReport() {
        var report = DiagnosticsReport()
        report.sections = [
            .init("Permissions", [.init(key: "Accessibility", value: "false")]),
            .init(DiagnosticsAppStateKeys.copies, [.init(key: "Copies", value: "/Applications/NotchIsland.app\n/Volumes/NotchIsland/NotchIsland.app")]),
        ]
        let causes = DiagnosticsInsights.causes(report, metrics: [.uncleanExits: 1, .crashes: 0])
        #expect(causes.contains { $0.hasPrefix("Accessibility is off") })
        #expect(causes.contains { $0.contains("DMG is still mounted") })
        #expect(causes.contains { $0.hasPrefix("The last run ended without quitting") })
        #expect(DiagnosticsInsights.causes(DiagnosticsReport(), metrics: [:]).isEmpty)
    }

    @Test @MainActor func flowKeepsTheLastSteps() {
        for index in 0..<(DiagnosticsFlow.capacity + 5) { DiagnosticsFlow.record("step \(index)") }
        #expect(DiagnosticsFlow.steps.count == DiagnosticsFlow.capacity)
        #expect(DiagnosticsFlow.steps.last?.hasSuffix("step \(DiagnosticsFlow.capacity + 4)") == true)
        #expect(DiagnosticsFlow.section().entries.count == 2)
    }
}
