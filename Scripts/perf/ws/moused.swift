import CoreGraphics
import Foundation
// One long-lived process for a whole scenario: commands on stdin, one per line, "ok" after each.
//   move x y [steps] [stepMs] | click x y | down x y | drag x y [steps] [stepMs] | up x y | pos
//   scroll dx dy frames [momentum] [pause ms]
//   key <virtual key code> [cmd|shift|opt|ctrl…] | type <text>
// Every new process that posts events is checked by TCC (and its signature by trustd and
// syspolicyd) — work the system bills to the app receiving the events, ~100 mJ per spawn, which a
// person's hand never costs. Spawned once, it is checked once.
setvbuf(stdout, nil, _IOLBF, 0)
func post(_ e: CGEvent?) { e?.post(tap: .cghidEventTap) }
func cur() -> CGPoint { CGEvent(source: nil)!.location }
while let line = readLine() {
    let a = line.split(separator: " ").map(String.init)
    guard let verb = a.first else { continue }
    switch verb {
    case "move":
        let to = CGPoint(x: Double(a[1])!, y: Double(a[2])!)
        let steps = a.count > 3 ? Int(a[3])! : 20, ms = a.count > 4 ? Double(a[4])! : 12
        let from = cur()
        for i in 1...steps {
            let t = Double(i) / Double(steps)
            let p = CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t)
            post(CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left))
            usleep(useconds_t(ms * 1000))
        }
    case "drag":
        // drag x y [steps] [stepMs]: the button held (after `down`), moved there.
        let to = CGPoint(x: Double(a[1])!, y: Double(a[2])!)
        let steps = a.count > 3 ? Int(a[3])! : 20, ms = a.count > 4 ? Double(a[4])! : 12
        let from = cur()
        for i in 1...steps {
            let t = Double(i) / Double(steps)
            let p = CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t)
            post(CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged, mouseCursorPosition: p, mouseButton: .left))
            usleep(useconds_t(ms * 1000))
        }
    case "click", "down", "up":
        let p = CGPoint(x: Double(a[1])!, y: Double(a[2])!)
        if verb != "up" {
            post(CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)); usleep(40000)
            post(CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: p, mouseButton: .left))
        }
        if verb == "click" { usleep(50000) }
        if verb != "down" {
            post(CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: p, mouseButton: .left))
        }
    case "key":
        let code = CGKeyCode(a[1])!
        var flags: CGEventFlags = []
        for f in a.dropFirst(2) {
            switch f {
            case "cmd": flags.insert(.maskCommand)
            case "shift": flags.insert(.maskShift)
            case "opt": flags.insert(.maskAlternate)
            case "ctrl": flags.insert(.maskControl)
            default: break
            }
        }
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)
            e?.flags = flags
            post(e)
            usleep(30000)
        }
    case "flags":
        // A modifier pressed or let go (`flags cmd` … `flags`): a flagsChanged event, as a keyboard sends.
        var flags: CGEventFlags = []
        for f in a.dropFirst() {
            switch f {
            case "cmd": flags.insert(.maskCommand)
            case "shift": flags.insert(.maskShift)
            case "opt": flags.insert(.maskAlternate)
            case "ctrl": flags.insert(.maskControl)
            default: break
            }
        }
        let e = CGEvent(keyboardEventSource: nil, virtualKey: 55, keyDown: !flags.isEmpty)
        e?.type = .flagsChanged
        e?.flags = flags
        post(e)
        usleep(30000)
    case "type":
        let text = a.dropFirst().joined(separator: " ")
        for scalar in text.utf16 {
            for down in [true, false] {
                let e = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down)
                var unit = scalar
                e?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unit)
                post(e)
                usleep(20000)
            }
            usleep(100000)
        }
    case "scroll":
        // scroll <dx> <dy> <frames> [momentum frames] [pause ms]: a trackpad-like scroll where the
        // pointer is (pixel units, gesture phases, 120 Hz), the fingers lifted with an event that
        // moves nothing, as a trackpad's (after `pause`: the fingers at rest first), then a
        // momentum tail whose step shrinks by 5 % a frame.
        let dx = Int32(a[1])!, dy = Int32(a[2])!, frames = Int(a[3])!, momentum = a.count > 4 ? Int(a[4])! : 0
        let pause = a.count > 5 ? Double(a[5])! : 0
        let momentumPhase = CGEventField(rawValue: 123)!
        for i in 0..<frames {
            guard let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: -dy, wheel2: -dx, wheel3: 0) else { continue }
            e.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
            e.setIntegerValueField(.scrollWheelEventScrollPhase, value: i == 0 ? 1 : 2)
            post(e); usleep(8333)
        }
        if pause > 0 { usleep(useconds_t(pause * 1000)) }
        if let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: 0, wheel2: 0, wheel3: 0) {
            e.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
            e.setIntegerValueField(.scrollWheelEventScrollPhase, value: 4)
            post(e); usleep(8333)
        }
        var fx = Double(dx), fy = Double(dy)
        for i in 0..<momentum {
            fx *= 0.95; fy *= 0.95
            guard let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: -Int32(fy.rounded()), wheel2: -Int32(fx.rounded()), wheel3: 0) else { continue }
            e.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
            e.setIntegerValueField(.scrollWheelEventScrollPhase, value: 0)
            e.setIntegerValueField(momentumPhase, value: i == 0 ? 1 : (i == momentum - 1 ? 3 : 2))
            post(e); usleep(8333)
        }
    case "pos":
        print(cur())
        continue
    default: break
    }
    print("ok")
}
