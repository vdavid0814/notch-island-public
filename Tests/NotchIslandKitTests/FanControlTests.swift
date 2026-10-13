import AppKit
import SwiftUI
import Testing
@testable import NotchIslandKit

@MainActor final class FanCalls {
    var speeds: [Double] = []
    var automatic = 0
}

/// Fan Control: the SMC's numbers, a fan's range, where on the dial is which speed, the graph's
/// reach and rhythm, and the dial taking real mouse events — a drag on the ring sets the speed, a
/// click on Manual gives it back.
@MainActor @Suite(.serialized) struct FanControlTests {
    @Test func smcNumbersRoundTrip() {
        for rpm in [0.0, 1200, 2450, 5800, 6550] {
            #expect(SMC.decode(SMC.Value(type: "fpe2", bytes: SMC.encode(rpm, type: "fpe2")!)) == rpm)
            #expect(SMC.decode(SMC.Value(type: "flt ", bytes: SMC.encode(rpm, type: "flt ")!)) == rpm)
        }
        #expect(SMC.decode(SMC.Value(type: "ui8 ", bytes: [2])) == 2)
        #expect(SMC.decode(SMC.Value(type: "sp78", bytes: [0x2e, 0x80])) == 46.5)
        #expect(SMC.code("F0Ac").map(SMC.text) == "F0Ac")
        #expect(SMC.code("F0A") == nil)
    }

    @Test func aFansRange() {
        let fan = FanReading(index: 0, rpm: 2450, minimum: 1200, maximum: 5800, target: 0, isManual: false)
        // From nothing — the fan stopped — to its fastest: not from the slowest macOS turns it.
        #expect(fan.rpm(at: 0) == 0 && fan.rpm(at: 1) == 5800)
        #expect(fan.rpm(at: 0.5) == 2900)
        #expect(fan.rpm(at: 2) == 5800 && fan.rpm(at: -1) == 0)
        #expect(abs(fan.fraction(of: 2450) - 2450.0 / 5800) < 0.0001)
        #expect(fan.fraction(of: 9000) == 1 && fan.fraction(of: 0) == 0)
    }

    /// A speed set by hand is the user's until they give it back: fans read as not held at it are
    /// asked for again, ones held where the Mac will have them (their slowest for less) are left.
    @Test func whetherAFanIsHeldAsAsked() {
        var fan = FanReading(index: 0, rpm: 2450, minimum: 1200, maximum: 5800, target: 2900, isManual: true)
        #expect(FanCenter.holds(fan, at: 0.5))
        #expect(!FanCenter.holds(fan, at: 0.8))
        fan.isManual = false
        #expect(!FanCenter.holds(fan, at: 0.5))
        fan = FanReading(index: 0, rpm: 0, minimum: 1200, maximum: 5800, target: 0, isManual: true)
        #expect(FanCenter.holds(fan, at: 0))
        fan.target = 1200
        #expect(FanCenter.holds(fan, at: 0) && FanCenter.holds(fan, at: 0.1) && !FanCenter.holds(fan, at: 0.5))
    }

    /// Simulated fans (`NI_DEMO_FANS`): held where the dial was turned to — to none too — and they
    /// stay held whatever time passes, until Automatic.
    @Test(.enabled(if: FanSensors.isSimulated, "needs NI_DEMO_FANS=1")) func aSpeedSetStaysUntilAutomatic() async throws {
        let center = FanCenter()
        center.startObserving()
        defer {
            center.setAutomatic()
            center.stopObserving()
        }
        center.setSpeed(0)
        #expect(center.isManual && center.heldFraction == 0)
        try await Task.sleep(for: .seconds(7))
        #expect(center.isManual && center.heldFraction == 0)
        #expect(center.fans.first?.isManual == true && center.fans.first?.target == 0)
        center.setSpeed(0.5)
        #expect(center.heldFraction == 0.5)
        center.setAutomatic()
        #expect(!center.isManual && center.heldFraction == nil)
    }

    /// The graph reaches back ten seconds to ten minutes (ten its own), and the history keeps ten.
    @Test func theGraphReachesBackAsSet() {
        #expect(ThermalMonitor.window == 600)
        var widget = IslandWidget(kind: .fanControl, frame: GridRect(column: 0, row: 0, width: 7, height: 2),
                                  options: IslandWidgetKind.fanControl.defaultOptions)
        #expect(FanControlWidget.seconds(widget) == 600)
        widget.config.seconds = 150
        #expect(FanControlWidget.seconds(widget) == 150)
        widget.config.seconds = 4000
        widget.config.sanitize()
        #expect(widget.config.seconds == 600 && FanControlWidget.stored(600) == nil && FanControlWidget.stored(0) == 10)
        #expect(FanControlWidget.span(600) == "10 min" && FanControlWidget.span(150) == "2 min 30 s" && FanControlWidget.span(45) == "45 s")
        #expect(IslandWidgetKind.fanControl.spec.settings == [.history])
        let now = Date(timeIntervalSince1970: 1_790_235_660)
        let pictured = FanControlWidget.sampleHistory(now: now)
        #expect(pictured.temperatures.first?.date == now.addingTimeInterval(-600) && pictured.temperatures.last?.date == now)
        #expect(FanHeatGraph.reach(600) == "10 min ago" && FanHeatGraph.reach(150) == "2 min 30 s ago")
        // The ruler: no 0 to 9 seconds while the minutes are 0; from 0 once a minute is set.
        #expect(FanHistorySetter.range(of: .seconds, at: 10) == 10...59 && FanHistorySetter.range(of: .seconds, at: 45) == 10...59)
        #expect(FanHistorySetter.range(of: .seconds, at: 60) == 0...59 && FanHistorySetter.range(of: .seconds, at: 125) == 0...59)
        #expect(FanHistorySetter.range(of: .minutes, at: 10) == 0...10)
        #expect(FanControlWidget.clamped(0 * 60 + 5) == 10)
        // A reading between two: in proportion, as the line draws it; across a gap, none.
        let samples = [SensorSample(date: now, value: 40), SensorSample(date: now.addingTimeInterval(10), value: 60),
                       SensorSample(date: now.addingTimeInterval(100), value: 80)]
        #expect(FanHeatGraph.value(samples, at: now.addingTimeInterval(5)) == 50)
        #expect(FanHeatGraph.value(samples, at: now.addingTimeInterval(50)) == nil)
    }

    /// The fans' rhythm: strokes closer the faster they turn, none while they stand still or across
    /// a gap, and each stroke at its moment however much of the past is cut away.
    @Test func theFansRhythm() throws {
        #expect(FanRhythm.share(1) < FanRhythm.share(0.5) && FanRhythm.share(0.5) < FanRhythm.share(0))
        #expect(FanRhythm.advance(rpm: 0, maximum: 5800, seconds: 1) == 0)
        #expect(FanRhythm.advance(rpm: 3000, maximum: 5800, seconds: FanRhythm.gap + 1) == 0)
        let start = Date(timeIntervalSince1970: 1_790_235_000)
        func run(_ rpms: [Double]) -> [SensorSample] {
            var samples: [SensorSample] = []
            for (index, rpm) in rpms.enumerated() {
                let date = start.addingTimeInterval(Double(index))
                let phase = samples.last.map { $0.phase + FanRhythm.advance(rpm: $0.value, maximum: 5800, seconds: 1) } ?? 0
                samples.append(SensorSample(date: date, value: rpm, phase: phase))
            }
            return samples
        }
        let slow = FanRhythm.strokes(run(Array(repeating: 1500, count: 600)), window: 600, after: start)
        let fast = FanRhythm.strokes(run(Array(repeating: 5800, count: 600)), window: 600, after: start)
        #expect(fast.count > slow.count * 2 && !slow.isEmpty)
        #expect(FanRhythm.strokes(run(Array(repeating: 0, count: 600)), window: 600, after: start).isEmpty)
        // Cut the first five minutes away: the strokes after the cut are where they were.
        let all = run(Array(repeating: 3000, count: 600))
        let later = start.addingTimeInterval(300)
        let cut = FanRhythm.strokes(Array(all.drop { $0.date < later.addingTimeInterval(-1) }), window: 600, after: later)
        #expect(cut == FanRhythm.strokes(all, window: 600, after: later))
        // A shorter graph, the same past: more strokes in it, as close on the graph.
        #expect(FanRhythm.strokes(all, window: 60, after: start).count > fast.count)
    }

    @Test func whereOnTheDialIsWhichSpeed() {
        let center = CGPoint(x: 50, y: 50)
        func at(_ degrees: Double, previous: Double? = nil) -> Double {
            let angle = degrees * .pi / 180
            return FanDial.fraction(at: CGPoint(x: 50 + cos(angle) * 40, y: 50 + sin(angle) * 40),
                                                         center: center, previous: previous)
        }
        // Screen angles, y down: 135° bottom left (slowest), 270° top (half), 45° bottom right (fastest).
        #expect(abs(at(135)) < 0.0001)
        #expect(abs(at(270) - 0.5) < 0.0001)
        #expect(abs(at(180) - 1.0 / 6) < 0.0001)
        #expect(abs(at(45) - 1) < 0.0001)
        // In the opening at the bottom: the end the drag came from, else the nearer one.
        #expect(at(90, previous: 0.9) == 1 && at(90, previous: 0.1) == 0)
        #expect(at(60) == 1 && at(120) == 0)
    }

    /// The dial (136 pt) in a window, a drag or a click `from` → `to` (points from its middle, y up).
    func use(manual: Bool, from: CGPoint, to: CGPoint) -> FanCalls {
        let calls = FanCalls()
        let fans = [FanReading(index: 0, rpm: 2450, minimum: 1200, maximum: 5800, target: 3000, isManual: manual)]
        let view = FanDial(fans: fans, held: manual ? 0.4 : nil, isManual: manual, diameter: 136, number: "2 450",
                           mode: manual ? "Manual" : "Auto", name: "Fan",
                           set: { calls.speeds.append($0) }, automatic: { calls.automatic += 1 })
            .frame(width: 150, height: 150)
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: CGRect(x: 200, y: 200, width: 150, height: 150), styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.contentView = host
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        func send(_ type: NSEvent.EventType, _ offset: CGPoint) {
            let event = NSEvent.mouseEvent(with: type, location: CGPoint(x: 75 + offset.x, y: 75 + offset.y), modifierFlags: [],
                                           timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                           context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            window.sendEvent(event)
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        send(.leftMouseDown, from)
        if from != to {
            let steps = 6
            for step in 1...steps {
                let t = CGFloat(step) / CGFloat(steps)
                send(.leftMouseDragged, CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t))
            }
        }
        send(.leftMouseUp, to)
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        window.orderOut(nil)
        return calls
    }

    @Test func dragOnTheRingSetsTheSpeed() throws {
        // From the left of the ring (a sixth) up to its top (half).
        let calls = use(manual: false, from: CGPoint(x: -60, y: 0), to: CGPoint(x: 0, y: 60))
        #expect(calls.automatic == 0)
        let first = try #require(calls.speeds.first), last = try #require(calls.speeds.last)
        #expect(abs(first - 1.0 / 6) < 0.02)
        #expect(abs(last - 0.5) < 0.02)
    }

    @Test func aClickOnManualGivesItBack() {
        // The word sits over the speed (y up here, down in the dial).
        let point = CGPoint(x: 0, y: -FanDial.modeCenter(diameter: 136))
        let calls = use(manual: true, from: point, to: point)
        #expect(calls.automatic == 1)
        #expect(calls.speeds.isEmpty)
        // Automatic: the word is no button, and a click there sets the speed as anywhere on the dial.
        #expect(use(manual: false, from: point, to: point).automatic == 0)
    }

    /// The row: the fan's dial, the temperature's, then the graph where it has room.
    @Test func theRowFillsAsTheWidgetWidens() {
        let widget = IslandWidget(kind: .fanControl, frame: GridRect(column: 0, row: 0, width: 7, height: 2),
                                  options: IslandWidgetKind.fanControl.defaultOptions)
        let narrow = FanControlWidget.layout(widget, inner: CGSize(width: 80, height: 80))
        #expect(!narrow.showsTempDial && narrow.graphs.isEmpty)
        let standard = FanControlWidget.layout(widget, inner: CGSize(width: 320, height: 80))
        #expect(standard.showsTempDial && standard.graphs == [.tempGraph] && standard.graphWidth >= FanControlWidget.Layout.minimumGraph)
        // Small: the fan alone, without its texts.
        #expect(!FanControlWidget.hasRoom(for: .value, in: widget, inner: CGSize(width: 80, height: 36)))
        // The graph's texts from 56 pt; under 22, no strokes.
        #expect(FanHeatGraph.layout(CGSize(width: 200, height: 80), caption: 10).showsTexts)
        #expect(!FanHeatGraph.layout(CGSize(width: 200, height: 32), caption: 10).showsTexts)
        #expect(FanHeatGraph.layout(CGSize(width: 200, height: 18), caption: 10).row == nil)
    }

    @Test func fanControlIsOfferedOnlyWithAFan() {
        #expect(IslandWidgetKind.fanControl.isOffered == FanSensors.hasFans)
        #expect(IslandWidgetKind.chipTemperature.isReadout)
    }
}
