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
}

/// A cover's colour, as plain components (Sendable, comparable).
nonisolated struct ArtworkColor: Sendable, Equatable {
    var red: Double
    var green: Double
    var blue: Double

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
