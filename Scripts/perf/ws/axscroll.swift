import AppKit
import ApplicationServices
// axscroll <pid>: every scroll area of the app with its vertical scroll bar value (0 top … 1 bottom),
// through Accessibility — where a scroll really is, in any build (swiftc -O axscroll.swift -o axscroll).
let pid = pid_t(CommandLine.arguments[1])!
let app = AXUIElementCreateApplication(pid)
func attr(_ e: AXUIElement, _ a: String) -> AnyObject? { var v: AnyObject?; AXUIElementCopyAttributeValue(e, a as CFString, &v); return v }
var out: [String] = []
func visit(_ e: AXUIElement, _ depth: Int) {
    if depth > 14 { return }
    let role = attr(e, kAXRoleAttribute) as? String ?? ""
    if role == "AXScrollArea" {
        var size = CGSize.zero
        if let s = attr(e, kAXSizeAttribute) { AXValueGetValue(s as! AXValue, .cgSize, &size) }
        if let bar = attr(e, kAXVerticalScrollBarAttribute) {
            out.append("area h=\(Int(size.height)) value=\(attr(bar as! AXUIElement, kAXValueAttribute) ?? "nil" as AnyObject)")
        }
    }
    for c in (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] { visit(c, depth + 1) }
}
print("trusted", AXIsProcessTrusted())
for w in (attr(app, kAXWindowsAttribute) as? [AXUIElement]) ?? [] { visit(w, 0) }
print(out.joined(separator: "\n"))
