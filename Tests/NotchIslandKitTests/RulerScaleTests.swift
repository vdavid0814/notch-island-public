import SwiftUI
import Testing
@testable import NotchIslandKit

/// The live ruler's scale: which value is under the marker at an offset, and where a value rests.
@MainActor struct RulerScaleTests {
    private func scale(_ range: ClosedRange<Int>, first: Int) -> RulerScrollView.Scale {
        RulerScrollView.Scale(range: range, first: first, isEditable: true, showsLabels: false,
                              tint: Color.Resolved(red: 1, green: 0.6, blue: 0.2), ends: .round)
    }

    @Test func theValueUnderTheMarkerIsTheNearestTick() {
        let minutes = scale(0...120, first: 1)
        let spacing = TimerRuler.tickSpacing
        #expect(minutes.value(at: 0) == 1)
        #expect(minutes.value(at: spacing * 0.49) == 1)
        #expect(minutes.value(at: spacing * 0.5) == 2)
        #expect(minutes.value(at: spacing * 4) == 5)
        #expect(minutes.offset(of: 5) == spacing * 4)
    }

    @Test func pastItsEndsItStaysOnTheLastValue() {
        // The rubber band pulls the scale past its ends: the value does not follow.
        let seconds = scale(0...59, first: 0)
        #expect(seconds.value(at: -30) == 0)
        #expect(seconds.value(at: seconds.offset(of: 59) + 40) == 59)
        // Landmarks under the first value it settles on are no values of its own.
        #expect(scale(0...120, first: 1).value(at: -TimerRuler.tickSpacing) == 1)
    }

    @Test func aMomentumEndsOnAWholeTick() {
        let minutes = scale(0...120, first: 1)
        for proposed in stride(from: CGFloat(-20), through: 1000, by: 3.7) {
            let rest = minutes.offset(of: minutes.value(at: proposed))
            #expect(rest.truncatingRemainder(dividingBy: TimerRuler.tickSpacing) == 0)
            #expect(rest >= 0 && rest <= minutes.offset(of: 120))
            if proposed >= 0, proposed <= minutes.offset(of: 120) { #expect(abs(rest - proposed) <= TimerRuler.tickSpacing / 2) }
        }
    }
}
