import Foundation
import Testing
@testable import NotchIslandKit

@Suite("Openings' energy and memory in the report")
struct OpeningMeterTests {
    @Test("Each transition is the kind of opening it is")
    func kinds() {
        typealias Kind = OpeningMeter.Kind
        #expect(Kind.of(from: .idle, to: .expanded(.home), panelKept: true) == .panelKept)
        #expect(Kind.of(from: .idle, to: .expanded(.home), panelKept: false) == .panelBuilt)
        #expect(Kind.of(from: .idle, to: .assistant(.field), panelKept: false) == .siri)
        #expect(Kind.of(from: .expanded(.home), to: .settings, panelKept: true) == .settings)
        #expect(Kind.of(from: .expanded(.home), to: .idle, panelKept: true) == .close)
        #expect(Kind.of(from: .assistant(.field), to: .assistant(.list), panelKept: false) == nil)
        #expect(Kind.of(from: .expanded(.home), to: .expanded(.timer), panelKept: true) == nil)
        #expect(Kind.of(from: .idle, to: .banner(.level(.volume)), panelKept: false) == nil)
        #expect(Kind.siriSearch.lane != Kind.siri.lane)
    }

    @Test("Count, median and the worst tenth")
    func summary() throws {
        let summary = try #require(OpeningMeter.summary([10, 20, 30, 40, 50, 60, 70, 80, 90, 1000]))
        #expect(summary.count == 10)
        #expect(summary.medianMJ == 55)
        #expect(summary.worstTenthMJ == 1000)
        #expect(OpeningMeter.summary([]) == nil)
        #expect(try #require(OpeningMeter.summary([7])).medianMJ == 7)
    }

    @Test("An opening is measured from its start, and a newer one ends it")
    func measures() async throws {
        let meter = OpeningMeter()
        meter.begin(.panelBuilt)
        // Some work, so the counter moves.
        var x = 0.0
        for i in 0..<2_000_000 { x += sin(Double(i)) }
        meter.begin(.close)
        let summaries = meter.summaries()
        #expect(summaries[.panelBuilt]?.count == 1)
        #expect((summaries[.panelBuilt]?.medianMJ ?? 0) > 0)
        #expect(summaries[.close] == nil)
        #expect(x != 1)
    }

    @Test("The panel's openings are judged once there are five, Siri's and Settings' once there are three")
    func metrics() {
        let few = DiagnosticsMemory.openings([.panelKept: .init(count: 2, medianMJ: 15, worstTenthMJ: 20)])
        #expect(few.metrics[.openingMJ] == nil)
        let many = DiagnosticsMemory.openings([
            .panelKept: .init(count: 6, medianMJ: 15, worstTenthMJ: 20),
            .panelBuilt: .init(count: 2, medianMJ: 95, worstTenthMJ: 100),
            .siri: .init(count: 3, medianMJ: 40, worstTenthMJ: 700),
        ])
        #expect(many.metrics[.openingMJ] == 35)
        #expect(many.metrics[.siriOpeningMJ] == 40)
        #expect(many.metrics[.settingsOpeningMJ] == nil)
        #expect(many.lines.count == OpeningMeter.Kind.allCases.count)
    }

    @Test("A rising floor is growth; a high reading now and then is not")
    func growth() throws {
        let start = Date(timeIntervalSince1970: 1_000_000)
        func readings(_ floor: (Int) -> Double) -> [(date: Date, megabytes: Double)] {
            (0..<36).map { step in
                let hour = step / 6
                // Every hour: its floor, and one Settings opening at 260 MB.
                let value = step % 6 == 3 ? 260 : floor(hour)
                return (start.addingTimeInterval(Double(step) * 600), value)
            }
        }
        let flat = try #require(DiagnosticsMemory.growthPerHour(readings { _ in 192 }))
        #expect(abs(flat) < 0.01)
        let leaking = try #require(DiagnosticsMemory.growthPerHour(readings { 192 + Double($0) * 12 }))
        #expect(abs(leaking - 12) < 0.01)
        // Two hours are not enough to tell.
        #expect(DiagnosticsMemory.growthPerHour(Array(readings { _ in 192 }.prefix(12))) == nil)
        // Past the rule for growth, whatever the reference.
        #expect(DiagnosticsComparison.isUnusual(12, reference: 0.5, rule: DiagnosticsMetric.memoryGrowthMBPerHour.defaultRule))
        #expect(!DiagnosticsComparison.isUnusual(3, reference: 0.5, rule: DiagnosticsMetric.memoryGrowthMBPerHour.defaultRule))
    }

    @Test("The heap's numbers are read")
    func heap() {
        let heap = DiagnosticsMemory.heap()
        #expect(heap.inUse > 0)
        #expect(heap.held >= heap.inUse)
        #expect(DiagnosticsMemory.lines().count == 2)
    }
}
