import Foundation
import Testing
@testable import NotchIslandKit

/// When a main thread lowered to background counts as stalled (`StallMeter`): the readings are
/// those `Scripts/perf/thrift_watch.c` printed on a quiet Mac and with all ten cores taken.
@Suite struct ThriftWatchTests {
    private let tick = ThriftWatch.interval

    /// The readings of `count` intervals with `share` of each run; the verdict and at which reading.
    private func feed(_ meter: inout StallMeter, share: Double, runnable: Bool = true, count: Int) -> (StallMeter.Verdict, Int)? {
        for index in 1...count {
            if let verdict = meter.note(interval: tick, ran: tick * share, runnable: runnable) { return (verdict, index) }
        }
        return nil
    }

    @Test func aThreadThatRunsIsLeftAlone() {
        // A quiet Mac: the thread ran 39–46 ms of every 40–45 ms interval, for seconds.
        var meter = StallMeter()
        #expect(feed(&meter, share: 1, count: 400) == nil)
        // The efficiency cores shared with other background work: a tenth missed at every reading.
        #expect(feed(&meter, share: 0.9, count: 400) == nil)
    }

    @Test func aThreadWithNothingIsStarvedWithinTwoReadings() throws {
        var meter = StallMeter()
        let (verdict, reading) = try #require(feed(&meter, share: 0, count: 10))
        #expect(verdict == .starved)
        #expect(reading == 2)
    }

    @Test func aThirdOfTheProcessorIsStarvedToo() throws {
        // All ten cores taken at utility: the lowered thread ran ~15 ms of every 45 (2 s of work in 10).
        var meter = StallMeter()
        let (verdict, reading) = try #require(feed(&meter, share: 0.35, count: 20))
        #expect(verdict == .starved)
        #expect(Double(reading) * tick <= 0.15)
    }

    @Test func aStutterDoesNotAddUpForever() {
        // One reading with nothing among many that ran: forgotten, not carried to the next one.
        var meter = StallMeter()
        for _ in 0..<50 {
            #expect(meter.note(interval: tick, ran: 0, runnable: true) == nil)
            #expect(feed(&meter, share: 1, count: 12) == nil)
        }
    }

    @Test func aLongWaitCountsAsBlockedAndAShortOneDoesNot() throws {
        // Waiting for another process's answer (a window ordered in: tens of ms) is not a stall…
        var meter = StallMeter()
        #expect(feed(&meter, share: 0, runnable: false, count: 4) == nil)
        #expect(feed(&meter, share: 1, count: 3) == nil)
        // …a quarter of a second of it without a break is (a page read back in at low priority).
        let (verdict, reading) = try #require(feed(&meter, share: 0, runnable: false, count: 20))
        #expect(verdict == .blocked)
        #expect(Double(reading) * tick >= StallMeter.blockedLimit - tick)
        #expect(Double(reading) * tick <= StallMeter.blockedLimit + tick)
    }

    @Test func aReadingThatWentBackwardsIsNotCountedAsRun() {
        // The thread's clock read lower than before (a failed read gives 0): the interval counts as missed.
        var meter = StallMeter()
        #expect(meter.note(interval: tick, ran: -4, runnable: true) == nil)
        #expect(meter.starved == tick)
    }

    @Test func theGateAnswersOnTheLiveMac() {
        // What it reads is the Mac's own state: here only that both readings can be taken, and
        // that "busy" starts past a share of the cores, not at any load.
        _ = SystemLoad.isLoaded
        _ = SystemLoad.isShortOfMemory
        #expect(SystemLoad.busyShare > 0.5 && SystemLoad.busyShare <= 1)
    }
}
