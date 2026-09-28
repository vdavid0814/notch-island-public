import CoreGraphics
import Foundation
import Testing
@testable import NotchIslandKit

@Suite struct LiquidFlowTests {
    // A 1280 × 832 screen, its notch, and macOS's card where the desktop puts it (measured).
    private let screen = CGRect(x: 0, y: 0, width: 1280, height: 832)
    private let notch = CGRect(x: 562, y: 804, width: 156, height: 28)
    private let window = CGRect(x: 848, y: 655, width: 352, height: 148)

    @Test func theDropLeavesFromInsideTheNotchAndLandsOverTheCard() {
        let cover = LiquidFlow.cover(overCardWindow: window)
        let card = SystemVolumeCard.card(inWindow: window)
        #expect(cover.rect.contains(card))
        let start = LiquidFlow.start(notch: notch, towards: cover.rect)
        #expect(notch.contains(start.rect))
        #expect(LiquidFlow.drop(0, from: start, to: cover) == start)
        let landed = LiquidFlow.drop(1, from: start, to: cover)
        #expect(abs(landed.rect.midX - cover.rect.midX) < 0.5 && abs(landed.rect.width - cover.rect.width) < 0.5)
        // The overshoot spreads it wider over the card, never off it.
        let splash = LiquidFlow.drop(1.03, from: start, to: cover)
        #expect(splash.rect.contains(card))
    }

    @Test func theCurveEasesInOvershootsAndSettles() {
        let curve = LiquidFlow.out
        #expect(curve.value(at: 0) == 0)
        #expect(curve.value(at: curve.duration * 0.1) < 0.02)
        #expect(curve.value(at: curve.duration) > 1)
        #expect(abs(curve.value(at: curve.total) - 1) < 0.001)
        #expect(abs(LiquidFlow.back.value(at: LiquidFlow.back.total) - 1) < 0.001)
    }

    @Test func theNeckPartsWhenThin() {
        #expect(LiquidFlow.neck(notch: notch, to: window, thickness: 0.5) == nil)
        #expect(LiquidFlow.neck(notch: notch, to: window, thickness: 20) != nil)
    }

    @Test @MainActor func theCardsPlaceIsGuessedThenLearned() {
        let name = "volume-card-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let memory = SystemVolumeCardMemory(defaults: defaults)
        let desktop = memory.expected(fullscreenApps: 0, notch: notch, screen: screen)
        #expect(desktop == window)
        #expect(!SystemVolumeCard.isUnderNotch(desktop, notch: notch))
        #expect(SystemVolumeCard.isUnderNotch(memory.expected(fullscreenApps: 1, notch: notch, screen: screen), notch: notch))
        // Split View put it elsewhere once: expected there from then on.
        let seen = CGRect(x: 464, y: 655, width: 352, height: 148)
        memory.learn(seen, fullscreenApps: 2, screen: screen)
        #expect(memory.expected(fullscreenApps: 2, notch: notch, screen: screen) == seen)
        #expect(memory.expected(fullscreenApps: 0, notch: notch, screen: screen) == window)
    }
}
