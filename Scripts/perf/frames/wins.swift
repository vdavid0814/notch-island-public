import CoreGraphics
import Foundation
// wins: the on-screen windows of NotchIsland: "<id> <layer> <x> <y> <w> <h>" a line.
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
for w in list where (w[kCGWindowOwnerName as String] as? String) == "NotchIsland" {
    let b = w[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
    print(w[kCGWindowNumber as String] as? Int ?? 0, w[kCGWindowLayer as String] as? Int ?? 0, Int(b["X"] ?? 0), Int(b["Y"] ?? 0), Int(b["Width"] ?? 0), Int(b["Height"] ?? 0), w[kCGWindowAlpha as String] as? Double ?? 1)
}
