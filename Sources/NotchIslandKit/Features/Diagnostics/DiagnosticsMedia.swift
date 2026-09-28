import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A screenshot or a screen recording the user attached to a bug report, copied (and made small
/// enough) into NotchIsland's own folder, so it survives in the outbox until it is sent.
nonisolated struct DiagnosticsMediaFile: Sendable, Codable, Equatable, Identifiable, Hashable {
    var id = UUID()
    /// The name shown in Discord.
    var name: String
    /// The prepared copy (`DiagnosticsMedia.folder`).
    var path: String
    var contentType: String
    var bytes: Int
    var isVideo: Bool
    /// A video longer than fits was cut to what does.
    var wasTrimmed = false

    var url: URL { URL(fileURLWithPath: path) }
}

/// Prepares screenshots and recordings for Discord: at most `maxBytes` each (one file per message,
/// under the 10 MB a webhook takes without boosts), in formats Discord shows in place.
nonisolated enum DiagnosticsMedia {
    static let maxFiles = 4
    static let maxBytes = 8_000_000
    /// Longest side of a picture that has to be made smaller.
    static let maxPixels = 2400

    nonisolated enum Failure: Error, LocalizedError, Equatable {
        case unsupported(String)
        case unreadable(String)
        case tooLarge(String)

        var errorDescription: String? {
            switch self {
            case .unsupported(let name): "“\(name)” is not a picture or a video."
            case .unreadable(let name): "“\(name)” could not be read."
            case .tooLarge(let name): "“\(name)” could not be made small enough to send."
            }
        }
    }

    static var folder: URL? {
        DiagnosticsCenter.supportFolder?.appendingPathComponent("DiagnosticsMedia", isDirectory: true)
    }

    static func isSupported(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image) || type.conforms(to: .movie)
    }

    /// A copy of `source` ready to send: pictures past the limit, or in a format Discord does not
    /// show (HEIC, TIFF…), become JPEGs; videos past the limit are re-encoded smaller, and cut only
    /// if even the smallest size does not fit.
    @concurrent static func prepare(_ source: URL) async throws -> DiagnosticsMediaFile {
        let name = source.lastPathComponent
        guard let type = UTType(filenameExtension: source.pathExtension),
              type.conforms(to: .image) || type.conforms(to: .movie) else { throw Failure.unsupported(name) }
        guard let folder else { throw Failure.unreadable(name) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        let size = (try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let stem = UUID().uuidString
        if type.conforms(to: .image) {
            let shown: [UTType] = [.png, .jpeg, .gif]
            if size > 0, size <= maxBytes, shown.contains(where: { type.conforms(to: $0) }) {
                return try copy(source, to: folder.appendingPathComponent("\(stem).\(source.pathExtension)"),
                                name: name, type: type, isVideo: false)
            }
            let target = folder.appendingPathComponent("\(stem).jpg")
            try shrinkPicture(source, to: target, name: name)
            return try file(target, name: (name as NSString).deletingPathExtension + ".jpg", type: .jpeg, isVideo: false)
        }
        if size > 0, size <= maxBytes, type.conforms(to: .mpeg4Movie) || type.conforms(to: .quickTimeMovie) {
            return try copy(source, to: folder.appendingPathComponent("\(stem).\(source.pathExtension)"),
                            name: name, type: type, isVideo: true)
        }
        return try await shrinkVideo(source, folder: folder, stem: stem, name: name)
    }

    /// Deletes a prepared copy (sent, removed from the form, or the form cancelled).
    static func discard(_ files: [DiagnosticsMediaFile]) {
        for file in files where file.path.hasPrefix(folder?.path ?? "/nonexistent") {
            try? FileManager.default.removeItem(atPath: file.path)
        }
    }

    private static func copy(_ source: URL, to target: URL, name: String, type: UTType, isVideo: Bool) throws -> DiagnosticsMediaFile {
        do {
            try FileManager.default.copyItem(at: source, to: target)
        } catch {
            throw Failure.unreadable(name)
        }
        return try file(target, name: name, type: type, isVideo: isVideo)
    }

    private static func file(_ url: URL, name: String, type: UTType, isVideo: Bool, trimmed: Bool = false) throws -> DiagnosticsMediaFile {
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard bytes > 0, bytes <= maxBytes else {
            try? FileManager.default.removeItem(at: url)
            throw Failure.tooLarge(name)
        }
        return DiagnosticsMediaFile(name: name, path: url.path, contentType: type.preferredMIMEType ?? "application/octet-stream",
                                    bytes: bytes, isVideo: isVideo, wasTrimmed: trimmed)
    }

    private static func shrinkPicture(_ source: URL, to target: URL, name: String) throws {
        guard let image = CGImageSourceCreateWithURL(source as CFURL, nil) else { throw Failure.unreadable(name) }
        for pixels in [maxPixels, 1600, 1200] {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: pixels,
            ]
            guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(image, 0, options as CFDictionary),
                  let destination = CGImageDestinationCreateWithURL(target as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
            else { throw Failure.unreadable(name) }
            CGImageDestinationAddImage(destination, thumbnail, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { throw Failure.unreadable(name) }
            let bytes = (try? target.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? .max
            if bytes <= maxBytes { return }
        }
        throw Failure.tooLarge(name)
    }

    /// 720p, then 540p, then 480p cut to the limit (`fileLengthLimit`): a screen recording of a
    /// minute or two fits whole at one of the first two.
    private static func shrinkVideo(_ source: URL, folder: URL, stem: String, name: String) async throws -> DiagnosticsMediaFile {
        let asset = AVURLAsset(url: source)
        guard (try? await asset.load(.isExportable)) == true else { throw Failure.unreadable(name) }
        let presets = [AVAssetExportPreset1280x720, AVAssetExportPreset960x540, AVAssetExportPreset640x480]
        let outName = (name as NSString).deletingPathExtension + ".mp4"
        for (index, preset) in presets.enumerated() {
            let target = folder.appendingPathComponent("\(stem)-\(index).mp4")
            guard let session = AVAssetExportSession(asset: asset, presetName: preset) else { continue }
            session.shouldOptimizeForNetworkUse = true
            let isLast = index == presets.count - 1
            if isLast { session.fileLengthLimit = Int64(maxBytes - 200_000) }
            do {
                try await session.export(to: target, as: .mp4)
            } catch {
                try? FileManager.default.removeItem(at: target)
                continue
            }
            let bytes = (try? target.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? .max
            if bytes <= maxBytes {
                var trimmed = false
                if isLast, let whole = try? await asset.load(.duration),
                   let kept = try? await AVURLAsset(url: target).load(.duration) {
                    trimmed = kept.seconds < whole.seconds - 0.5
                }
                return try file(target, name: outName, type: .mpeg4Movie, isVideo: true, trimmed: trimmed)
            }
            try? FileManager.default.removeItem(at: target)
        }
        throw Failure.tooLarge(name)
    }
}
