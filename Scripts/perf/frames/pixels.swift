import AppKit
// pixels stats a.png b.png [x0,y0,x1,y1]    mean/max difference and share of pixels > 2/255
// pixels heat  a.png b.png out.png          dimmed a with pixels > 8/255 apart in red; prints their bbox
// pixels top   a.png b.png x0,y0,x1,y1 [n]  the n most different pixels
// pixels cut   in.png x y w h scale out.png crop (top-left pixel coordinates), nearest-neighbour zoom
func load(_ p: String) -> NSBitmapImageRep { NSBitmapImageRep(data: try! Data(contentsOf: URL(fileURLWithPath: p)))! }
func px(_ r: NSBitmapImageRep, _ x: Int, _ y: Int) -> [Int] { var p = [Int](repeating: 0, count: 4); r.getPixel(&p, atX: x, y: y); return p }
func d(_ a: [Int], _ b: [Int]) -> Int { max(abs(a[0] - b[0]), abs(a[1] - b[1]), abs(a[2] - b[2])) }
func save(_ r: NSBitmapImageRep, _ p: String) { try! r.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: p)) }
let a = CommandLine.arguments
switch a[1] {
case "stats", "top":
    let x = load(a[2]), y = load(a[3])
    let w = min(x.pixelsWide, y.pixelsWide), h = min(x.pixelsHigh, y.pixelsHigh)
    let r = a.count > 4 ? a[4].split(separator: ",").map { Int($0)! } : [0, 0, w, h]
    var maxd = 0, sum = 0.0, n = 0, over = 0, list: [(Int, Int, Int, [Int], [Int])] = []
    for j in r[1]..<min(r[3], h) { for i in r[0]..<min(r[2], w) {
        let p = px(x, i, j), q = px(y, i, j), e = d(p, q)
        maxd = max(maxd, e); sum += Double(e); n += 1
        if e > 2 { over += 1; if a[1] == "top" { list.append((e, i, j, p, q)) } }
    }}
    if a[1] == "stats" { print(String(format: "mean %.3f, max %d, >2/255: %.3f%%", sum / Double(max(n, 1)), maxd, Double(over) / Double(max(n, 1)) * 100)) }
    else { for e in list.sorted(by: { $0.0 > $1.0 }).prefix(a.count > 5 ? Int(a[5])! : 10) { print("d \(e.0) at \(e.1),\(e.2): \(e.3.prefix(3)) vs \(e.4.prefix(3))") } }
case "heat":
    let x = load(a[2]), y = load(a[3])
    let w = min(x.pixelsWide, y.pixelsWide), h = min(x.pixelsHigh, y.pixelsHigh)
    let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    var b = [w, h, 0, 0]
    for j in 0..<h { for i in 0..<w {
        let p = px(x, i, j), q = px(y, i, j)
        var o = [p[0] / 3, p[1] / 3, p[2] / 3, 255]
        if d(p, q) > (Int(ProcessInfo.processInfo.environment["HEAT"] ?? "") ?? 8) { o = [255, 0, 0, 255]; b = [min(b[0], i), min(b[1], j), max(b[2], i), max(b[3], j)] }
        out.setPixel(&o, atX: i, y: j)
    }}
    save(out, a[4]); print("bbox \(b[0]),\(b[1]) – \(b[2]),\(b[3])")
case "cut":
    let rep = load(a[2])
    let r = CGRect(x: Double(a[3])!, y: Double(a[4])!, width: Double(a[5])!, height: Double(a[6])!), s = Double(a[7])!
    let cg = rep.cgImage!.cropping(to: r)!
    let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(r.width * s), pixelsHigh: Int(r.height * s), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: out)!; NSGraphicsContext.current = ctx
    ctx.cgContext.interpolationQuality = .none
    ctx.cgContext.draw(cg, in: CGRect(x: 0, y: 0, width: r.width * s, height: r.height * s))
    NSGraphicsContext.restoreGraphicsState()
    save(out, a[8])
default: print("usage: pixels stats|heat|top|cut …")
}
