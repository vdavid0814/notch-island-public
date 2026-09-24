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
}
