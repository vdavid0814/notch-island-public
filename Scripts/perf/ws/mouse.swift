import CoreGraphics
import Foundation
// mouse move x y [steps] [stepMs] | click x y | scroll x y lines | pos
let a = CommandLine.arguments
func post(_ e: CGEvent?) { e?.post(tap: .cghidEventTap) }
func cur() -> CGPoint { CGEvent(source: nil)!.location }
switch a[1] {
case "move":
    let to = CGPoint(x: Double(a[2])!, y: Double(a[3])!)
    let steps = a.count > 4 ? Int(a[4])! : 20, ms = a.count > 5 ? Double(a[5])! : 12
    let from = cur()
    for i in 1...steps {
        let t = Double(i) / Double(steps)
        let p = CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t)
        post(CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left))
        usleep(useconds_t(ms * 1000))
    }
case "click":
    let p = CGPoint(x: Double(a[2])!, y: Double(a[3])!)
    post(CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)); usleep(60000)
    post(CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: p, mouseButton: .left)); usleep(50000)
    post(CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: p, mouseButton: .left))
case "scroll":
    let p = CGPoint(x: Double(a[2])!, y: Double(a[3])!)
    post(CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)); usleep(30000)
    let n = Int(a[4])!
    for _ in 0..<abs(n) { post(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: Int32(n > 0 ? -1 : 1), wheel2: 0, wheel3: 0)); usleep(40000) }
case "drag":
    let p = CGPoint(x: Double(a[2])!, y: Double(a[3])!), q = CGPoint(x: Double(a[4])!, y: Double(a[5])!)
    post(CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)); usleep(80000)
    post(CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: p, mouseButton: .left)); usleep(80000)
    for i in 1...20 { let t = Double(i) / 20
        post(CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged, mouseCursorPosition: CGPoint(x: p.x + (q.x - p.x) * t, y: p.y + (q.y - p.y) * t), mouseButton: .left)); usleep(20000) }
    usleep(100000)
    post(CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: q, mouseButton: .left))
case "pos":
    print(cur())
default: break
}
