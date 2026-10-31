import Foundation

/// What the App Gallery (⌘1) lists, and how, as the system's Apps does: the last used in a row of
/// their own, then every app by name, then the system's tools under "Other". Only the gallery:
/// searching from the root still finds every app on the Mac.
nonisolated struct AssistantGallery: Equatable, Sendable {
    var recent: [AssistantHit] = []
    var main: [AssistantHit] = []
    var other: [AssistantHit] = []

    /// The cells in order, as the assistant's rows.
    var all: [AssistantHit] { recent + main + other }
    var counts: [Int] { [recent.count, main.count, other.count] }

    init(apps: [AssistantHit], sort: SiriGallerySort, columns: Int, region: String? = Locale.current.region?.identifier) {
        let listed = apps.filter { Self.isListed($0.url.path, region: region) }
        let byName = listed.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        if sort == .recent {
            let used = listed.filter { $0.lastUsed != nil }.sorted { $0.lastUsed ?? .distantPast > $1.lastUsed ?? .distantPast }
            recent = Array(used.prefix(columns))
        }
        main = byName.filter { !Self.isOther($0.url.path) }
        other = byName.filter { Self.isOther($0.url.path) }
    }

    /// The folders the system's Apps shows, and what it leaves out of them. Not the home folder's
    /// Applications, CoreServices (Finder), another app's own tools, or a copy elsewhere.
    static func isListed(_ path: String, region: String? = Locale.current.region?.identifier) -> Bool {
        let path = path.hasPrefix(dataVolume) ? String(path.dropFirst(dataVolume.count)) : path
        let url = URL(fileURLWithPath: path)
        let folder = url.deletingLastPathComponent().path
        let inSystem = folder.hasSuffix("/System/Applications") || folder.hasSuffix("/System/Applications/Utilities")
        guard inSystem || folder == "/Applications" || folder == "/Applications/Utilities" else { return false }
        let name = url.deletingPathExtension().lastPathComponent
        if hidden.contains(name) { return false }
        if name == "News", let region, !newsRegions.contains(region) { return false }
        if name == "iPhone Mirroring", let region, europeanUnion.contains(region) { return false }
        return true
    }

    static func isOther(_ path: String) -> Bool {
        path.contains("/System/Applications/") && otherNames.contains(URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent)
    }

    /// From `index` a row up or down (`delta` −1 or 1), keeping the column as far as the row has it:
    /// the sections' last rows may be short, so a plain step of `columns` would leave the column.
    static func index(from index: Int, rows delta: Int, counts: [Int], columns: Int) -> Int {
        let columns = max(1, columns)
        var start = 0
        let sections = counts.filter { $0 > 0 }.map { count in
            defer { start += count }
            return start..<(start + count)
        }
        guard let at = sections.firstIndex(where: { $0.contains(index) }) else { return index }
        let section = sections[at]
        let column = (index - section.lowerBound) % columns
        let row = (index - section.lowerBound) / columns
        let lastRow = (section.count - 1) / columns
        if delta < 0 {
            if row > 0 { return index - columns }
            guard at > 0 else { return index }
            let above = sections[at - 1]
            return min(above.lowerBound + (above.count - 1) / columns * columns + column, above.upperBound - 1)
        }
        if row < lastRow { return min(index + columns, section.upperBound - 1) }
        guard at + 1 < sections.count else { return index }
        let below = sections[at + 1]
        return min(below.lowerBound + column, below.upperBound - 1)
    }

    private static let dataVolume = "/System/Volumes/Data"
    private static let hidden: Set<String> = ["Apps", "Siri AI", "Feedback Assistant"]
    private static let newsRegions: Set<String> = ["US", "CA", "GB", "AU"]
    private static let europeanUnion: Set<String> = [
        "AT", "BE", "BG", "HR", "CY", "CZ", "DK", "EE", "FI", "FR", "DE", "GR", "HU", "IE", "IT", "LV", "LT",
        "LU", "MT", "NL", "PL", "PT", "RO", "SK", "SI", "ES", "SE",
    ]
    /// What the system's Apps lists under Other, by the bundle's name (the shown one is localized).
    private static let otherNames: Set<String> = [
        "Activity Monitor", "AirPort Utility", "Audio MIDI Setup", "Automator", "Bluetooth File Exchange",
        "ColorSync Utility", "Console", "Dictionary", "Digital Color Meter", "Disk Utility", "Font Book", "Grapher",
        "Image Capture", "Migration Assistant", "Mission Control", "Preview", "Print Center", "QuickTime Player",
        "Screen Sharing", "Screenshot", "Script Editor", "Shortcuts", "Stickies", "System Information", "Terminal",
        "TextEdit", "Time Machine", "Tips", "VoiceOver Utility",
    ]
}
