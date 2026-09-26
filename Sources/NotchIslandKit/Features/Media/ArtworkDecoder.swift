import CoreGraphics
import Foundation
import ImageIO

/// Decodes artwork bytes into a display-sized bitmap off the main actor.
///
/// `NSImage(data:)` decodes lazily at first draw — on the main thread, at full resolution (a 3000 px
/// cover is ~36 MB). ImageIO's thumbnail path decodes eagerly (`ShouldCacheImmediately`) and downsamples
/// to the largest size the island ever draws (72 pt artwork at up to 3× scale, rounded up).
nonisolated enum ArtworkDecoder {
    static let maxPixelSize = 320

    @concurrent static func decode(_ data: Data) async -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// The cover's overall colour, for widgets that tint themselves from it: the average of a
    /// 1 × 1 downsample, pushed toward a readable brightness (a black cover still gives a colour
    /// the controls can sit on).
    @concurrent static func averageColor(_ image: CGImage) async -> ArtworkColor? {
        var pixel = [UInt8](repeating: 0, count: 4)
        let drawn = pixel.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard drawn else { return nil }
        return ArtworkColor(red: Double(pixel[0]) / 255, green: Double(pixel[1]) / 255, blue: Double(pixel[2]) / 255)
    }
    /// The cover's leading colours, most present first (up to `limit`), each made an accent: an
    /// 8 × 8 downsample, its pixels grouped by hue (twelve sectors), a sector weighted by how much of
    /// the cover it covers and how vivid it is. Near-grey pixels count only when nothing is vivid,
    /// so a black-and-white cover stays grey instead of picking up noise.
    @concurrent static func palette(_ image: CGImage, limit: Int = 3) async -> [ArtworkColor] {
        let side = 8
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return [] }
        let colors = stride(from: 0, to: pixels.count, by: 4).map {
            ArtworkColor(red: Double(pixels[$0]) / 255, green: Double(pixels[$0 + 1]) / 255, blue: Double(pixels[$0 + 2]) / 255)
        }
        return dominantColors(colors, limit: limit)
    }

    /// `palette`'s grouping, on plain colours (testable).
    static func dominantColors(_ colors: [ArtworkColor], limit: Int) -> [ArtworkColor] {
        struct Sector { var weight = 0.0, red = 0.0, green = 0.0, blue = 0.0 }
        var sectors = Array(repeating: Sector(), count: 12)
        for color in colors {
            let (hue, saturation, value) = color.hsv
            guard saturation > 0.18, value > 0.15 else { continue }
            let index = min(Int(hue * 12), 11)
            let weight = saturation * value
            sectors[index].weight += weight
            sectors[index].red += color.red * weight
            sectors[index].green += color.green * weight
            sectors[index].blue += color.blue * weight
        }
        let ranked = sectors.filter { $0.weight > 0 }.sorted { $0.weight > $1.weight }
        guard let top = ranked.first else {
            // Nothing vivid: the cover's overall tone (grey stays grey through `accent`).
            guard !colors.isEmpty else { return [] }
            let n = Double(colors.count)
            let mean = ArtworkColor(red: colors.map(\.red).reduce(0, +) / n,
                                    green: colors.map(\.green).reduce(0, +) / n,
                                    blue: colors.map(\.blue).reduce(0, +) / n)
            return [mean.accent]
        }
        // A sector far smaller than the leading one is a detail, not one of the cover's colours.
        return ranked.prefix(limit).filter { $0.weight >= top.weight * 0.18 }.map {
            ArtworkColor(red: $0.red / $0.weight, green: $0.green / $0.weight, blue: $0.blue / $0.weight).accent
        }
    }
}

/// A cover's colour, as plain components (Sendable, comparable).
nonisolated struct ArtworkColor: Sendable, Equatable {
    var red: Double
    var green: Double
    var blue: Double

    /// Hue (0…1), saturation and value.
    var hsv: (hue: Double, saturation: Double, value: Double) {
        let high = max(red, green, blue), low = min(red, green, blue), delta = high - low
        guard high > 0, delta > 0.0001 else { return (0, 0, high) }
        var hue: Double
        if high == red { hue = (green - blue) / delta }
        else if high == green { hue = 2 + (blue - red) / delta }
        else { hue = 4 + (red - green) / delta }
        hue /= 6
        if hue < 0 { hue += 1 }
        return (hue, delta / high, high)
    }

    /// Saturation and brightness lifted so it works as an accent on the dark island: a muddy or
    /// near-black cover still gives a visible colour, a grey one stays grey.
    var accent: ArtworkColor {
        let high = max(red, green, blue), low = min(red, green, blue)
        guard high > 0.001 else { return ArtworkColor(red: 0.6, green: 0.6, blue: 0.6) }
        let saturation = (high - low) / high
        let targetValue = max(high, 0.72)
        let targetSaturation = saturation < 0.12 ? saturation : min(max(saturation, 0.45), 0.85)
        func channel(_ value: Double) -> Double {
            let s = high - low > 0.001 ? (high - value) / (high - low) : 0
            return targetValue * (1 - targetSaturation * s)
        }
        return ArtworkColor(red: channel(red), green: channel(green), blue: channel(blue))
    }
}
