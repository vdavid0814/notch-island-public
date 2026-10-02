// smooth <x> <y> <pixels per frame> <frames> [momentum frames] [decay]: trackpad-like scroll (pixel
// units, gesture phases) at 120 Hz; then, if asked, a momentum tail whose step shrinks by `decay`
// (default 0.95) per frame. HOLD=1 leaves the fingers down.
import CoreGraphics
import Foundation
let a = CommandLine.arguments
let p = CGPoint(x: Double(a[1])!, y: Double(a[2])!)
let step = Int32(a[3])!, frames = Int(a[4])!
let momentum = a.count > 5 ? Int(a[5])! : 0
let decay = a.count > 6 ? Double(a[6])! : 0.95
let momentumPhase = CGEventField(rawValue: 123)!
/// HOLD=1: the fingers stay down (no ended phase).
let hold = ProcessInfo.processInfo.environment["HOLD"] == "1"
CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
usleep(50000)
for i in 0..<frames {
    guard let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -step, wheel2: 0, wheel3: 0) else { continue }
    e.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
    e.setIntegerValueField(.scrollWheelEventScrollPhase, value: i == 0 ? 1 : (i == frames - 1 && !hold ? 4 : 2))
    e.post(tap: .cghidEventTap)
    usleep(8333)
}
var delta = Double(step)
for i in 0..<momentum {
    delta *= decay
    guard let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -Int32(delta.rounded()), wheel2: 0, wheel3: 0) else { continue }
    e.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
    e.setIntegerValueField(.scrollWheelEventScrollPhase, value: 0)
    e.setIntegerValueField(momentumPhase, value: i == 0 ? 1 : (i == momentum - 1 ? 3 : 2))
    e.post(tap: .cghidEventTap)
    usleep(8333)
}
