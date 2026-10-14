import AppKit
import Photos

/// The pictures in Siri's answers, which Siri AI does not hand over through Accessibility (only
/// its icons): a picture it shows of something (the Moon) is Wikipedia's for that title; a photo it
/// found is looked up in the library by the date it reads out ("2026. Jul 8. at 20:20").
///
/// Wikipedia is asked only for the picture's title, never the question. The library is read on
/// this Mac only, once the user has allowed it (asked from the answer, not before).
@MainActor final class SiriPictures {
    static let shared = SiriPictures()

    private var pictures: [String: NSImage] = [:]
    private var missing: Set<String> = []

    // MARK: Pictures of things

    /// Wikipedia's picture for `title`, kept for the session.
    func picture(_ title: String) async -> NSImage? {
        let key = "web:" + title
        if let image = pictures[key] { return image }
        guard !missing.contains(key) else { return nil }
        let image = await Self.wikipediaPicture(title)
        if let image { pictures[key] = image } else { missing.insert(key) }
        return image
    }

    @concurrent private static func wikipediaPicture(_ title: String) async -> NSImage? {
        let path = title.replacingOccurrences(of: " ", with: "_")
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? title
        guard let summary = URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/\(path)") else { return nil }
        var request = URLRequest(url: summary, timeoutInterval: 8)
        request.setValue("NotchIsland (macOS)", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let thumbnail = (json["originalimage"] ?? json["thumbnail"]) as? [String: Any],
              let source = thumbnail["source"] as? String,
              let url = URL(string: source.replacingOccurrences(of: "http://", with: "https://")),
              let (bytes, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return NSImage(data: bytes)
    }

    // MARK: Photos

    /// The library may be read.
    var photosAllowed: Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return status == .authorized || status == .limited
    }

    /// Not asked yet (the answer offers to).
    var photosUndecided: Bool { PHPhotoLibrary.authorizationStatus(for: .readWrite) == .notDetermined }

    func allowPhotos() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return status == .authorized || status == .limited
    }

    /// The photo Siri describes, `side` points square, kept for the session.
    func photo(_ photo: SiriPhoto, side: CGFloat) async -> NSImage? {
        let key = "photo:\(photo.label)"
        if let image = pictures[key] { return image }
        guard photosAllowed, !missing.contains(key), let asset = Self.asset(for: photo) else { return nil }
        let image = await Self.thumbnail(of: asset, side: side * 2)
        if let image { pictures[key] = image } else { missing.insert(key) }
        return image
    }

    /// The asset taken in the minute Siri reads out (a video when it says a duration, a favourite
    /// when it says so).
    nonisolated static func asset(for photo: SiriPhoto) -> PHAsset? {
        guard let minute = date(in: photo.label) else { return nil }
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate < %@",
                                        minute as NSDate, minute.addingTimeInterval(60) as NSDate)
        let found = PHAsset.fetchAssets(with: options)
        var candidates: [PHAsset] = []
        found.enumerateObjects { asset, _, _ in candidates.append(asset) }
        let kind: PHAssetMediaType = photo.isVideo ? .video : .image
        return candidates.first { $0.mediaType == kind && $0.isFavorite == photo.isFavourite }
            ?? candidates.first { $0.mediaType == kind } ?? candidates.first
    }

    /// "2026. Jul 8. at 20:20" (and "Jul 8, 2026 at 20:20"): that minute, in this Mac's time zone.
    nonisolated static func date(in label: String) -> Date? {
        let patterns = [#"(\d{4})\.\s*(\p{L}+)\.?\s*(\d{1,2})\.?\s*(?:at\s*)?(\d{1,2}):(\d{2})"#,
                        #"(\p{L}+)\.?\s+(\d{1,2}),?\s+(\d{4})\s+(?:at\s+)?(\d{1,2}):(\d{2})"#]
        for (index, pattern) in patterns.enumerated() {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: label, range: NSRange(label.startIndex..., in: label)) else { continue }
            func group(_ i: Int) -> String { Range(match.range(at: i), in: label).map { String(label[$0]) } ?? "" }
            let (year, monthName, day) = index == 0 ? (group(1), group(2), group(3)) : (group(3), group(1), group(2))
            guard let month = month(named: monthName) else { continue }
            var parts = DateComponents()
            parts.year = Int(year)
            parts.month = month
            parts.day = Int(day)
            parts.hour = Int(group(4))
            parts.minute = Int(group(5))
            return Calendar.current.date(from: parts)
        }
        return nil
    }

    nonisolated private static func month(named name: String) -> Int? {
        let wanted = name.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        for identifier in [Locale.current.identifier, "en_US", "hu_HU"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: identifier)
            for symbols in [formatter.shortMonthSymbols, formatter.monthSymbols, formatter.shortStandaloneMonthSymbols] {
                if let index = symbols?.firstIndex(where: { $0.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) == wanted }) {
                    return index + 1
                }
            }
        }
        return nil
    }

    private static func thumbnail(of asset: PHAsset, side: CGFloat) async -> NSImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false
            PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: side, height: side),
                                                  contentMode: .aspectFill, options: options) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    /// The photo in Photos.
    func openPhotos() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Photos") {
            NSWorkspace.shared.open(url)
        }
    }
}
