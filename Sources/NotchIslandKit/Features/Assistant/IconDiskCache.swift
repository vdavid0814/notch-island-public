import CoreGraphics
import CryptoKit
import Foundation

/// Siri's app icons as they were drawn, kept in Caches across launches: the gallery's thumbnails
/// and the rows' pictures come back from disk (a 36 KB read) instead of being looked up and drawn
/// again at every launch's prewarm and first opening.
///
/// An entry is the picture's own bytes and format (the same pixels come back), for one app, one
/// size and one icon style. It stands while the app is unchanged (an update or a new custom icon
/// replaces it); entries of apps that are gone or of an icon style that is gone, then the least
/// recently used beyond `limit`, go in `purge(style:)`.
nonisolated struct IconDiskCache: Sendable {
    let folder: URL?
    /// Entries kept at most: a few hundred apps at the gallery's and the rows' sizes (36 KB each at
    /// the gallery's, 19 KB at the rows'): under 22 MB in all.
    var limit = 600

    static let caches = IconDiskCache(folder: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
        .appendingPathComponent("com.davidvarga.notchisland/Icons", isDirectory: true))

    /// What an entry was drawn from and how its bytes are laid out.
    struct Header: Codable, Equatable {
        var app: String
        var variant: String
        var style: String
        /// When the app last changed as it was drawn (seconds since 2001, `modified(_:)`).
        var modified: Double
        var width: Int
        var height: Int
        var bitsPerComponent: Int
        var bitsPerPixel: Int
        var bytesPerRow: Int
        var bitmapInfo: UInt32
        /// The colour space by name, or else its ICC profile.
        var colorSpace: String?
        var iccProfile: Data?
        var interpolates: Bool
        var intent: Int32
    }

    /// The icons' look this moment: light or dark first, then the icon style and tint (System
    /// Settings ▸ Appearance) and the macOS build, which the system draws app icons in.
    static func iconStyle(defaults: UserDefaults = .standard) -> String {
        let keys = ["AppleInterfaceStyle", "AppleIconAppearanceTheme", "AppleIconAppearanceTintColor", "AppleIconAppearanceCustomTintColor"]
        let values = keys.map { defaults.object(forKey: $0).map { "\($0)" } ?? "-" }
        return (values + [ProcessInfo.processInfo.operatingSystemVersionString]).joined(separator: "|")
    }

    /// `style` but light or dark: an automatic appearance switches between the two every day, so
    /// the entries of either stay.
    static func lasting(_ style: String) -> Substring { style.drop { $0 != "|" } }

    /// `app`'s picture as `variant` (a size) in `style` (`iconStyle`): from disk while the app is
    /// unchanged, else `draw`n and kept. An app that cannot be read is drawn and not kept.
    /// `writes` false (the main thread) only reads: nothing is kept or marked used.
    func image(forApp app: String, variant: String, style: String, writes: Bool = true, draw: () -> CGImage?) -> CGImage? {
        guard let folder, let modified = Self.modified(app) else { return draw() }
        let file = folder.appendingPathComponent(Self.name(app: app, variant: variant, style: style))
        if let data = try? Data(contentsOf: file), let (header, image) = Self.decode(data),
           header.app == app, header.variant == variant, header.style == style, header.modified == modified {
            // Used now: `purge` removes the least recently used first.
            if writes { try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path) }
            return image
        }
        guard let image = draw() else { return nil }
        if writes, let data = Self.encode(image, app: app, variant: variant, style: style, modified: modified) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? data.write(to: file, options: .atomic)
        }
        return image
    }

    /// Removes the entries of apps that are gone, of another icon style than `style` (another
    /// theme, tint or macOS build) and unreadable ones, then the least recently used beyond
    /// `limit`. Reads only each entry's header.
    func purge(style: String) {
        guard let folder else { return }
        let manager = FileManager.default
        let files = (try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        var kept: [(file: URL, used: Date)] = []
        for file in files {
            guard let header = Self.header(of: file), Self.lasting(header.style) == Self.lasting(style),
                  manager.fileExists(atPath: header.app) else {
                try? manager.removeItem(at: file)
                continue
            }
            let used = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            kept.append((file, used))
        }
        for old in kept.sorted(by: { $0.used > $1.used }).dropFirst(limit) {
            try? manager.removeItem(at: old.file)
        }
    }

    // MARK: Entries

    static func name(app: String, variant: String, style: String) -> String {
        SHA256.hash(data: Data([app, variant, style].joined(separator: "\n").utf8)).prefix(16).map { String(format: "%02x", $0) }.joined() + ".icon"
    }

    /// When the app (its target, for a linked app) last changed: the newest of its bundle's
    /// modification date (a custom icon) and its `Contents/Info.plist`'s (an update, which rewrites
    /// the bundle's contents in place and leaves the bundle's own date). Nil when the bundle cannot
    /// be read.
    static func modified(_ app: String) -> Double? {
        let url = URL(fileURLWithPath: app).resolvingSymlinksInPath()
        func date(_ url: URL) -> Double? {
            (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate?.timeIntervalSinceReferenceDate
        }
        guard let bundle = date(url) else { return nil }
        return max(bundle, date(url.appendingPathComponent("Contents/Info.plist")) ?? bundle)
    }

    /// The header's length (4 bytes, little-endian), the header (a binary property list), the pixels.
    static func encode(_ image: CGImage, app: String, variant: String, style: String, modified: Double) -> Data? {
        guard image.decode == nil, let space = image.colorSpace,
              let pixels = image.dataProvider?.data as Data?, pixels.count >= image.height * image.bytesPerRow else { return nil }
        let name = space.name as String?
        let icc = name == nil ? space.copyICCData() as Data? : nil
        guard name != nil || icc != nil else { return nil }
        let header = Header(app: app, variant: variant, style: style, modified: modified, width: image.width, height: image.height,
                            bitsPerComponent: image.bitsPerComponent, bitsPerPixel: image.bitsPerPixel,
                            bytesPerRow: image.bytesPerRow, bitmapInfo: image.bitmapInfo.rawValue,
                            colorSpace: name, iccProfile: icc, interpolates: image.shouldInterpolate,
                            intent: image.renderingIntent.rawValue)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        guard let head = try? encoder.encode(header) else { return nil }
        var data = withUnsafeBytes(of: UInt32(head.count).littleEndian) { Data($0) }
        data.append(head)
        data.append(pixels.prefix(image.height * image.bytesPerRow))
        return data
    }

    static func decode(_ data: Data) -> (Header, CGImage)? {
        guard let (header, start) = decodeHeader(data) else { return nil }
        let pixels = data.subdata(in: data.startIndex + start..<data.endIndex)
        guard pixels.count == header.height * header.bytesPerRow,
              let space = header.colorSpace.flatMap({ CGColorSpace(name: $0 as CFString) })
                ?? header.iccProfile.flatMap({ CGColorSpace(iccData: $0 as CFData) }),
              let provider = CGDataProvider(data: pixels as CFData),
              let intent = CGColorRenderingIntent(rawValue: header.intent),
              let image = CGImage(width: header.width, height: header.height, bitsPerComponent: header.bitsPerComponent,
                                  bitsPerPixel: header.bitsPerPixel, bytesPerRow: header.bytesPerRow, space: space,
                                  bitmapInfo: CGBitmapInfo(rawValue: header.bitmapInfo), provider: provider,
                                  decode: nil, shouldInterpolate: header.interpolates, intent: intent) else { return nil }
        return (header, image)
    }

    private static func decodeHeader(_ data: Data) -> (Header, Int)? {
        guard data.count >= 4 else { return nil }
        let length = Int(data.prefix(4).withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self)) })
        guard data.count >= 4 + length,
              let header = try? PropertyListDecoder().decode(Header.self, from: data.subdata(in: data.startIndex + 4..<data.startIndex + 4 + length))
        else { return nil }
        return (header, 4 + length)
    }

    /// An entry's header alone, without reading its pixels.
    private static func header(of file: URL) -> Header? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.read(upToCount: 4), size.count == 4 else { return nil }
        let length = Int(size.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self)) })
        guard length < 1 << 20, let head = try? handle.read(upToCount: length) else { return nil }
        return decodeHeader(size + head)?.0
    }
}
