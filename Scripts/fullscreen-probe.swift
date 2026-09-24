// Prints 1 when a full-screen window (a full-screen space, or a borderless window covering the
// whole screen) is on the built-in display, else 0. Used by energy-monitor.sh to tag samples.
import AppKit
import CoreGraphics

let screen = NSScreen.screens.first { $0.localizedName.localizedCaseInsensitiveContains("built") } ?? NSScreen.screens.first
guard let screen else { print(0); exit(0) }
let primaryHeight = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
let f = screen.frame
let region = CGRect(x: f.minX, y: primaryHeight - f.maxY, width: f.width, height: f.height)
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
func bounds(_ info: [String: Any]) -> CGRect {
    (info[kCGWindowBounds as String] as? NSDictionary).flatMap { CGRect(dictionaryRepresentation: $0) } ?? .zero
}
func covers(_ b: CGRect, top: CGFloat) -> Bool {
    b.minX <= region.minX + 1 && b.maxX >= region.maxX - 1 && b.minY <= region.minY + top + 1 && b.maxY >= region.maxY - 1
}
let backdrops = list.filter { ($0[kCGWindowOwnerName as String] as? String) == "WindowManager"
    && ($0[kCGWindowLayer as String] as? Int ?? 0) < 0 && covers(bounds($0), top: 0) }.count
let full = list.contains { info in
    guard (info[kCGWindowLayer as String] as? Int) == 0, (info[kCGWindowAlpha as String] as? Double ?? 1) > 0.01,
          (info[kCGWindowOwnerName as String] as? String) != "NotchIsland" else { return false }
    return covers(bounds(info), top: 0) || (backdrops >= 2 && covers(bounds(info), top: 40))
}
print(full ? 1 : 0)
