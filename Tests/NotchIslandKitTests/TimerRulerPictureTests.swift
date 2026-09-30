import AppKit
import SwiftUI
import Testing
@testable import NotchIslandKit

/// The resting ruler draws its ticks as two shapes and its numbers alone (`RulerPicture`); before,
/// each minute was a view of its own. These are that drawing, kept as the reference the picture
/// must match to the pixel.
private struct TickViewsReference: View {
    let value: Int
    let range: ClosedRange<Int>
    let showsLabels: Bool
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let spacing = TimerRuler.tickSpacing
            let centre = proxy.size.width / 2
            let reach = Int(ceil(centre / spacing)) + 1
            ZStack(alignment: .topLeading) {
                ForEach(max(range.lowerBound, value - reach)...min(range.upperBound, value + reach), id: \.self) { minute in
                    ReferenceTick(minute: minute, isPast: minute > value, showsLabel: showsLabels, tint: tint)
                        .frame(width: spacing, height: proxy.size.height)
                        .offset(x: centre + CGFloat(minute - value) * spacing - spacing / 2)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.18),
                    .init(color: .black, location: 0.82),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }
}

private struct ReferenceTick: View {
    let minute: Int
    let isPast: Bool
    let showsLabel: Bool
    let tint: Color

    var body: some View {
        let major = minute % 5 == 0
        let style = tint.opacity(isPast ? 0.35 : 1)
        VStack(spacing: 3) {
            if showsLabel {
                Group {
                    if major {
                        Text("\(minute)")
                            .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(tint.opacity(isPast ? 0.4 : 0.9))
                            .fixedSize()
                    } else {
                        Color.clear
                    }
                }
                .frame(width: TimerRuler.tickSpacing, height: ceil(NSFont.systemFont(ofSize: 10, weight: .semibold).boundingRectForFont.height))
            }
            Capsule()
                .fill(style)
                .frame(width: 2.5)
                .frame(maxHeight: .infinity)
                .padding(.vertical, major ? 0 : 3)
        }
    }
}

@MainActor @Suite struct TimerRulerPictureTests {
    /// Drawn by SwiftUI's renderer (as `ImageRenderer` draws) and through the window's layers (as
    /// `cacheDisplay` draws them), at 2×, on the island's black.
    static func pixels(_ view: some View, size: CGSize) -> ([UInt8], [UInt8]) {
        let framed = view.frame(width: size.width, height: size.height).background(.black).environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: framed)
        renderer.scale = 2
        let rendered = renderer.nsImage.flatMap { NSBitmapImageRep(data: $0.tiffRepresentation ?? Data()) }
        let host = NSHostingView(rootView: framed)
        let window = NSWindow(contentRect: CGRect(x: -10_000, y: -10_000, width: size.width, height: size.height),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 32)!
        rep.size = size
        host.cacheDisplay(in: host.bounds, to: rep)
        window.contentView = nil
        func bytes(_ rep: NSBitmapImageRep?) -> [UInt8] {
            guard let rep, let data = rep.bitmapData else { return [] }
            return Array(UnsafeBufferPointer(start: data, count: rep.bytesPerRow * rep.pixelsHigh))
        }
        return (bytes(rendered), bytes(rep))
    }

    /// Every size the widget and the timer page give it (labelled or not, short ones whose ticks
    /// barely fit, widths that put the centre between two pixels, placed off the pixel grid as a
    /// board's fractional cells place it), values at both ends of the scale and between, each
    /// unit's range and tint.
    @Test func restingRulerDrawsItsTicksAsTheirViewsDo() {
        for size in [CGSize(width: 160, height: 22), CGSize(width: 161, height: 44), CGSize(width: 233.5, height: 30),
                     CGSize(width: 187.37, height: 30.3), CGSize(width: 300, height: 58), CGSize(width: 420, height: 17)] {
            for origin in [CGPoint.zero, CGPoint(x: 0.25, y: 0.5), CGPoint(x: 0.37, y: 0.13)] {
            for showsLabels in [false, true] {
                for (range, tint) in [(0...120, TimerRuler.tint), (0...59, Color.cyan.opacity(0.8))] {
                    for value in [1, 3, 25, 58, 59, 120] where range.contains(value) {
                        func placed(_ view: some View) -> some View {
                            view.frame(width: size.width, height: size.height).offset(x: origin.x, y: origin.y)
                        }
                        let room = CGSize(width: ceil(size.width + 1), height: ceil(size.height + 1))
                        let picture = Self.pixels(placed(RulerPicture(value: value, range: range, showsLabels: showsLabels, tint: tint)),
                                                  size: room)
                        let reference = Self.pixels(placed(TickViewsReference(value: value, range: range, showsLabels: showsLabels, tint: tint)),
                                                    size: room)
                        #expect(!picture.0.isEmpty && !picture.1.isEmpty)
                        #expect(picture.0 == reference.0, "rendered \(size) at \(origin) labels \(showsLabels) \(range) value \(value)")
                        #expect(picture.1 == reference.1, "window \(size) at \(origin) labels \(showsLabels) \(range) value \(value)")
                    }
                }
            }
            }
        }
    }
}

