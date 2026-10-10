import AppKit
import SwiftUI
import Testing
@testable import NotchIslandKit

@MainActor final class FanCalls {
    var speeds: [Double] = []
    var automatic = 0
}

/// Fan Control: the SMC's numbers, a fan's range, where on the dial is which speed, and the dial
/// taking real mouse events — a drag on the ring sets the speed, a click on the fan gives it back.
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
        #expect(fan.rpm(at: 0) == 1200 && fan.rpm(at: 1) == 5800)
        #expect(fan.rpm(at: 0.5) == 3500)
        #expect(fan.rpm(at: 2) == 5800 && fan.rpm(at: -1) == 1200)
        #expect(abs(fan.fraction(of: 2450) - 1250.0 / 4600) < 0.0001)
        #expect(fan.fraction(of: 9000) == 1 && fan.fraction(of: 0) == 0)
    }

    @Test func whereOnTheDialIsWhichSpeed() {
        let center = CGPoint(x: 50, y: 50)
        func at(_ degrees: Double, previous: Double? = nil) -> Double {
            let angle = degrees * .pi / 180
            return FanDial<EmptyView, EmptyView>.fraction(at: CGPoint(x: 50 + cos(angle) * 40, y: 50 + sin(angle) * 40),
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
        let view = FanDial(fans: fans, held: manual ? 0.4 : nil, isManual: manual, diameter: 136, showsTexts: true,
                           value: Text("2 450 rpm"), label: Text("Auto"),
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

    @Test func aClickOnTheFanGivesItBack() {
        // The fan sits a little over the middle when the speed is under it.
        let calls = use(manual: true, from: CGPoint(x: 0, y: 6), to: CGPoint(x: 0, y: 6))
        #expect(calls.automatic == 1)
        #expect(calls.speeds.isEmpty)
        // Already automatic: nothing to give back.
        #expect(use(manual: false, from: CGPoint(x: 0, y: 6), to: CGPoint(x: 0, y: 6)).automatic == 0)
    }

    @Test func fanControlIsOfferedOnlyWithAFan() {
        #expect(IslandWidgetKind.fanControl.isOffered == FanSensors.hasFans)
        #expect(IslandWidgetKind.chipTemperature.isReadout)
    }
}
