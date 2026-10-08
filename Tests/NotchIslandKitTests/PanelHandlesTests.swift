import CoreGraphics
import Testing
@testable import NotchIslandKit

@MainActor @Suite struct PanelHandlesTests {
    /// A thin line keeps the middles of its sides (its length and its thickness) and drops its
    /// corners, which would sit on them; a part with room has all eight.
    @Test func handlesKeepApart() {
        let thin = PanelHandles.handles(for: CGRect(x: 0, y: 0, width: 300, height: 6))
        #expect(thin.count == 4)
        #expect(!thin.contains { $0.x != 0 && $0.y != 0 })
        #expect(PanelHandles.handles(for: CGRect(x: 0, y: 0, width: 60, height: 40)).count == 8)
    }

    /// A press takes the nearest handle within reach, and none farther off.
    @Test func aPressTakesTheNearestHandle() {
        let frame = CGRect(x: 100, y: 100, width: 60, height: 40)
        // The bottom-right corner's handle is at (162, 142).
        #expect(PanelHandles.hit(CGPoint(x: 163, y: 144), round: frame) == ButtonSymbolPanel.Handle(x: 1, y: 1))
        #expect(PanelHandles.hit(CGPoint(x: 131, y: 99), round: frame) == ButtonSymbolPanel.Handle(x: 0, y: -1))
        #expect(PanelHandles.hit(CGPoint(x: 168, y: 148), round: frame) == nil)
        #expect(PanelHandles.hit(CGPoint(x: 130, y: 120), round: frame) == nil)
    }
}
