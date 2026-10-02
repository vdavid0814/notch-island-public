// smooth <x> <y> <pixels per frame> <frames> : trackpad-like scroll (pixel units, gesture phases) at 120 Hz.
import CoreGraphics
import Foundation
let a = CommandLine.arguments
let p = CGPoint(x: Double(a[1])!, y: Double(a[2])!)
let step = Int32(a[3])!, frames = Int(a[4])!
CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
usleep(50000)
for i in 0..<frames {
    guard let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -step, wheel2: 0, wheel3: 0) else { continue }
    e.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
    e.setIntegerValueField(.scrollWheelEventScrollPhase, value: i == 0 ? 1 : (i == frames - 1 ? 4 : 2))
    e.post(tap: .cghidEventTap)
    usleep(8333)
}
