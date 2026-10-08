import CoreGraphics

/// Where a part of a widget is really drawn — its text's glyphs, its symbol, its picture — rather
/// than the box the layout gives it (a line of text is taller than its letters, a button wider than
/// its symbol). Read from a picture of the widget without its background, in the widget's points.
nonisolated enum ElementInk {
    /// Fainter than this (of 255) is not ink: the last fringe of a letter's edge.
    static let threshold: UInt8 = 8

    /// For each part, the smallest rectangle holding every pixel of `image` (drawn `scale` times
    /// the widget's size) within its layout box; a part with nothing drawn there keeps its box.
    static func bounds(in image: CGImage, scale: CGFloat, boxes: [ElementID: CGRect]) -> [ElementID: CGRect] {
        let width = image.width, height = image.height
        guard width > 0, height > 0, scale > 0 else { return boxes }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return boxes }
        // The bitmap's first row is the picture's top.
        return boxes.mapValues { box in
            let left = max(Int((box.minX * scale).rounded(.down)), 0)
            let right = min(Int((box.maxX * scale).rounded(.up)), width)
            let top = max(Int((box.minY * scale).rounded(.down)), 0)
            let bottom = min(Int((box.maxY * scale).rounded(.up)), height)
            guard left < right, top < bottom else { return box }
            var minX = Int.max, maxX = Int.min, minY = Int.max, maxY = Int.min
            for y in top..<bottom {
                let row = y * width * 4
                for x in left..<right where pixels[row + x * 4 + 3] > threshold {
                    minX = min(minX, x)
                    maxX = max(maxX, x)
                    minY = min(minY, y)
                    maxY = max(maxY, y)
                }
            }
            guard minX <= maxX else { return box }
            return CGRect(x: CGFloat(minX) / scale, y: CGFloat(minY) / scale,
                          width: CGFloat(maxX - minX + 1) / scale, height: CGFloat(maxY - minY + 1) / scale)
        }
    }
}
