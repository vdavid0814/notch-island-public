import AppKit
import SwiftUI
import Testing
@testable import NotchIslandKit

@MainActor private final class ClickFlag { var count = 0 }

/// A restyled button takes a click anywhere on its shape, not only on its symbol (a shape larger than
/// the symbol's room lost the clicks beside the symbol: Now Playing's glass buttons).
@MainActor @Suite(.serialized) struct ButtonHitTests {
    func click(material: ButtonLook.Material, at offset: CGPoint) -> Int {
        let flag = ClickFlag()
        var look = ButtonLook()
        look.material = material
        let view = NowPlayingButton(title: "Play", symbol: "play.fill", points: 20, look: look) { flag.count += 1 }
            .frame(width: 120, height: 120)
            .environment(AppModel())
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: CGRect(x: 200, y: 200, width: 120, height: 120), styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.contentView = host
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        let point = CGPoint(x: 60 + offset.x, y: 60 + offset.y)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            window.sendEvent(event)
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        window.orderOut(nil)
        return flag.count
    }

    @Test(arguments: [ButtonLook.Material.solid, .glass])
    func aClickAnywhereOnTheShapeTakes(material: ButtonLook.Material) {
        // A 20-pt symbol on a 27-pt circle (`WidgetButtonLabel.size`): its middle, its edge beside
        // the symbol, and past the shape.
        #expect(click(material: material, at: .zero) == 1)
        #expect(click(material: material, at: CGPoint(x: 11, y: 0)) == 1)
        #expect(click(material: material, at: CGPoint(x: 0, y: -11)) == 1)
        #expect(click(material: material, at: CGPoint(x: 18, y: 0)) == 0)
    }
}
