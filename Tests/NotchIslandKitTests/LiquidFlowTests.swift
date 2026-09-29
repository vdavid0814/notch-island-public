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

@Suite struct LiquidFieldTests {
    private let notch = CGRect(x: 562, y: 804, width: 156, height: 28)
    private let clip = CGRect(x: 520, y: 600, width: 740, height: 262)

    private func scene(drop: CGRect, neck: CGFloat) -> LiquidScene {
        LiquidScene(notch: CGRect(x: notch.minX, y: notch.minY, width: notch.width, height: notch.height + 30), notchRadius: 8,
                    drop: LiquidBlob(rect: drop, radius: 20), neckFrom: CGPoint(x: notch.maxX - 17, y: notch.maxY - 13),
                    neckTo: CGPoint(x: drop.midX, y: drop.midY), neckThickness: neck)
    }

    @Test func outlineHoldsTheNotchAndTheDrop() {
        let drop = CGRect(x: 900, y: 700, width: 280, height: 64)
        let path = LiquidField.path(scene(drop: drop, neck: 0), clip: clip)
        #expect(path.contains(CGPoint(x: drop.midX, y: drop.midY)))
        #expect(path.contains(CGPoint(x: notch.midX, y: notch.midY)))
        #expect(!path.contains(CGPoint(x: 820, y: 760)))
        // Its edge lies on the drop's, within the grid.
        #expect(path.contains(CGPoint(x: drop.minX + 2, y: drop.midY)))
        #expect(!path.contains(CGPoint(x: drop.minX - 3, y: drop.midY)))
    }

    @Test func aThickNeckJoinsAndAThinOneParts() {
        let drop = CGRect(x: 900, y: 700, width: 280, height: 64)
        // Halfway along the neck, towards the drop.
        let a = CGPoint(x: notch.maxX - 17, y: notch.maxY - 13), b = CGPoint(x: drop.midX, y: drop.midY)
        let middle = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        #expect(LiquidField.path(scene(drop: drop, neck: 28), clip: clip).contains(middle))
        #expect(!LiquidField.path(scene(drop: drop, neck: 5), clip: clip).contains(middle))
    }

    @Test func smoothMinimumFillsBetween() {
        #expect(LiquidField.smoothMin(3, 3, 12) < 3)
        #expect(LiquidField.smoothMin(1, 40, 12) == 1)
    }
}
