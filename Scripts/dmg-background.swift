import AppKit

// dmg-background <output.png> <scale>: the disk image window's background, 660 × 400 pt.
// The app sits on the left (165, 190), Applications on the right (495, 190); an arrow between,
// the instruction under it and a line about updates at the bottom. Dark, like the island.
let arguments = CommandLine.arguments
guard arguments.count == 3, let scale = Double(arguments[2]) else {
    FileHandle.standardError.write("usage: dmg-background <output.png> <scale>\n".data(using: .utf8)!)
    exit(64)
}
let size = CGSize(width: 660, height: 400)
let pixels = NSSize(width: size.width * scale, height: size.height * scale)
guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(pixels.width), pixelsHigh: Int(pixels.height),
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }
rep.size = NSSize(width: size.width, height: size.height)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let context = NSGraphicsContext.current!.cgContext
// Finder draws the background with a top-left origin; this context is bottom-left.
func y(_ top: CGFloat) -> CGFloat { size.height - top }

// Night-blue to black, a soft glow behind each icon.
let base = NSGradient(colors: [NSColor(srgbRed: 0.09, green: 0.10, blue: 0.16, alpha: 1),
                               NSColor(srgbRed: 0.02, green: 0.02, blue: 0.04, alpha: 1)])!
base.draw(in: NSRect(origin: .zero, size: size), angle: -90)
for (x, hue) in [(165.0, NSColor(srgbRed: 0.35, green: 0.45, blue: 1, alpha: 0.30)),
                 (495.0, NSColor(srgbRed: 0.55, green: 0.35, blue: 1, alpha: 0.22))] {
    let glow = NSGradient(colors: [hue, hue.withAlphaComponent(0)])!
    glow.draw(fromCenter: NSPoint(x: x, y: y(190)), radius: 0, toCenter: NSPoint(x: x, y: y(190)), radius: 130, options: [])
}

// Finder draws icon labels in black over a background picture, whatever the appearance: a light
// pill under each label (centred 74 pt below its icon's centre) keeps them readable.
for x in [165.0, 495.0] {
    let pill = NSBezierPath(roundedRect: NSRect(x: x - 62, y: y(274) - 0, width: 124, height: 22), xRadius: 11, yRadius: 11)
    NSColor(white: 1, alpha: 0.82).setFill()
    pill.fill()
}

// The notch the island grows out of, at the top centre.
let notch = NSBezierPath(roundedRect: NSRect(x: size.width / 2 - 60, y: y(14), width: 120, height: 22), xRadius: 11, yRadius: 11)
NSColor.black.setFill()
notch.fill()
NSColor(white: 1, alpha: 0.10).setStroke()
notch.lineWidth = 1
notch.stroke()

func text(_ string: String, size points: CGFloat, weight: NSFont.Weight, alpha: CGFloat, top: CGFloat) {
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: points, weight: weight),
        .foregroundColor: NSColor(white: 1, alpha: alpha),
        .paragraphStyle: style,
        .kern: points > 20 ? -0.4 : 0,
    ]
    let height = points * 1.45 * CGFloat(string.split(separator: "\n").count)
    let rect = NSRect(x: 20, y: y(top) - height, width: size.width - 40, height: height)
    (string as NSString).draw(in: rect, withAttributes: attributes)
}

text("NotchIsland", size: 26, weight: .bold, alpha: 0.95, top: 44)
text("The notch as a Liquid Glass island", size: 13, weight: .regular, alpha: 0.55, top: 78)

// The arrow from the app to Applications.
context.saveGState()
let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 262, y: y(190)))
arrow.curve(to: NSPoint(x: 392, y: y(190)), controlPoint1: NSPoint(x: 300, y: y(170)), controlPoint2: NSPoint(x: 354, y: y(170)))
arrow.lineWidth = 3
arrow.lineCapStyle = .round
let dash: [CGFloat] = [1, 9]
arrow.setLineDash(dash, count: 2, phase: 0)
NSColor(white: 1, alpha: 0.55).setStroke()
arrow.stroke()
let head = NSBezierPath()
head.move(to: NSPoint(x: 384, y: y(181)))
head.line(to: NSPoint(x: 395, y: y(190)))
head.line(to: NSPoint(x: 383, y: y(198)))
head.lineWidth = 3
head.lineCapStyle = .round
head.lineJoinStyle = .round
head.stroke()
context.restoreGState()

text("Drag NotchIsland onto Applications", size: 15, weight: .semibold, alpha: 0.9, top: 300)
text("Then open it from Applications. Later versions install themselves from Settings ▸ About,\nkeeping your settings and permissions — you won't need this window again.",
     size: 11, weight: .regular, alpha: 0.5, top: 328)

NSGraphicsContext.restoreGraphicsState()
guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: arguments[1]))
