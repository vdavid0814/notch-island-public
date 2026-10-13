import AppKit
import ApplicationServices
// axfocus <pid>: the app's focused element: role, subrole, title/description/placeholder, frame.
let pid = pid_t(CommandLine.arguments[1])!
let app = AXUIElementCreateApplication(pid)
var v: CFTypeRef?
func attr(_ e: AXUIElement, _ a: String) -> String {
    var r: CFTypeRef?
    guard AXUIElementCopyAttributeValue(e, a as CFString, &r) == .success, let r else { return "" }
    if CFGetTypeID(r) == AXValueGetTypeID() {
        var p = CGPoint.zero, s = CGSize.zero
        let av = r as! AXValue
        if AXValueGetValue(av, .cgPoint, &p) { return "\(Int(p.x)),\(Int(p.y))" }
        if AXValueGetValue(av, .cgSize, &s) { return "\(Int(s.width))x\(Int(s.height))" }
    }
    return "\(r)"
}
guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &v) == .success, let v else { print("none"); exit(0) }
let e = v as! AXUIElement
print([kAXRoleAttribute, kAXSubroleAttribute, kAXTitleAttribute, kAXDescriptionAttribute, kAXPlaceholderValueAttribute, kAXPositionAttribute, kAXSizeAttribute].map { attr(e, $0 as String) }.joined(separator: " | "))
