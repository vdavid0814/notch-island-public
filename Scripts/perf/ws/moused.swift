import CoreGraphics
import Foundation
// One long-lived process for a whole scenario: commands on stdin, one per line, "ok" after each.
//   move x y [steps] [stepMs] | click x y | down x y | up x y | pos
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
    case "pos":
        print(cur())
        continue
    default: break
    }
    print("ok")
}
