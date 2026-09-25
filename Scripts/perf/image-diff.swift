import AppKit
func load(_ p: String) -> NSBitmapImageRep { NSBitmapImageRep(data: try! Data(contentsOf: URL(fileURLWithPath: p)))! }
let a = load(CommandLine.arguments[1]), b = load(CommandLine.arguments[2])
var maxd = 0, sum = 0.0, n = 0, over8 = 0
for y in 0..<min(a.pixelsHigh, b.pixelsHigh) { for x in 0..<min(a.pixelsWide, b.pixelsWide) {
    var pa = [Int](repeating: 0, count: 4), pb = [Int](repeating: 0, count: 4)
    a.getPixel(&pa, atX: x, y: y); b.getPixel(&pb, atX: x, y: y)
    let d = max(abs(pa[0]-pb[0]), abs(pa[1]-pb[1]), abs(pa[2]-pb[2]))
    maxd = max(maxd, d); sum += Double(d); n += 1; if d > 8 { over8 += 1 }
}}
print(String(format: "mean diff %.2f / 255, max %d, pixels differing > 8/255: %.2f%%", sum / Double(n), maxd, Double(over8) / Double(n) * 100))
