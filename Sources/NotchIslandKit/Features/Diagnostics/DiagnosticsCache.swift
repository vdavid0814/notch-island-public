import CoreAudio
import CoreGraphics
import CryptoKit
import Foundation

/// The full report's sections that seldom change, kept in Caches so an automatic report reads them
/// again only when they may have changed:
/// - **Hardware** (`system_profiler`'s displays and sound devices): once per boot and build, and
///   again when a display or a sound device comes, goes or changes its mode, or the defaults move.
/// - **Installed apps** (every app's Info.plist read): once per boot and build, and again when an
///   app folder or an app's Info.plist changes. The Dock line is read every time.
/// - **Spotlight** (`mdutil`, `mdfind`, the index queries, Siri's gallery): for `spotlightLifetime`.
///
/// A report by hand, a bug report, the preview and the reference read everything afresh (the user
/// may be telling about what just changed) and keep it for the automatic reports. A kept section
/// says since when; its numbers (Siri's app list read, Spotlight's missing apps) are not sent again,
/// where they would be judged against the reference as this report's.
nonisolated struct DiagnosticsCache: Sendable {
    let folder: URL?
    /// False: read afresh (and kept).
    var reuses = true

    static let spotlightLifetime: TimeInterval = 6 * 3600

    static let caches = DiagnosticsCache(folder: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
        .appendingPathComponent("com.davidvarga.notchisland/Diagnostics", isDirectory: true))

    struct Entry: Codable, Equatable {
        /// What the sections were read for (`hardwareKey`, `appsKey`, `spotlightKey`).
        var key: String
        var written: Date
        var sections: [DiagnosticsReport.Section]
    }

    /// `entry` still stands for what `key` describes now: read for the same key, and not older than
    /// `lifetime` (never from the future: a clock set back).
    static func isFresh(_ entry: Entry, key: String, lifetime: TimeInterval?, now: Date) -> Bool {
        guard entry.key == key else { return false }
        guard let lifetime else { return true }
        let age = now.timeIntervalSince(entry.written)
        return age >= 0 && age < lifetime
    }

    /// `name`'s sections as kept for `key` (without numbers), or `read` afresh and kept.
    func report(_ name: String, key: String, lifetime: TimeInterval? = nil, now: Date = Date(),
                read: () async -> DiagnosticsReport) async -> DiagnosticsReport {
        let file = folder?.appendingPathComponent(name + ".json")
        if reuses, let file, let data = try? Data(contentsOf: file), let entry = try? JSONDecoder().decode(Entry.self, from: data),
           Self.isFresh(entry, key: key, lifetime: lifetime, now: now) {
            return DiagnosticsReport(sections: entry.sections.map { section in
                var section = section
                section.add("Kept since", DiagnosticsFormat.date(entry.written))
                return section
            })
        }
        let report = await read()
        if let folder, let file {
            let entry = Entry(key: key, written: now, sections: report.sections)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? JSONEncoder().encode(entry).write(to: file, options: .atomic)
        }
        return report
    }

    // MARK: Keys

    /// This build of the app.
    static func build() -> String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "dev") (\(info?["CFBundleVersion"] as? String ?? "0"))"
    }

    /// This boot of the Mac and this build of the app.
    static func bootAndBuild() -> String {
        "boot \(DiagnosticsProbes.sysctlString("kern.bootsessionuuid") ?? "?"), \(build())"
    }

    static func hardwareKey() -> String {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &displays, &count)
        let screens = displays.prefix(Int(count)).map { display in
            "\(display) \(CGDisplayBounds(display)) \(CGDisplayPixelsWide(display))×\(CGDisplayPixelsHigh(display))"
        }
        let defaults = [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultInputDevice,
                        kAudioHardwarePropertyDefaultSystemOutputDevice].map { DiagnosticsEnvironment.defaultDevice($0).map(String.init) ?? "-" }
        return "\(bootAndBuild()); main \(CGMainDisplayID()); displays \(screens.joined(separator: ", ")); "
            + "audio \(DiagnosticsEnvironment.audioDevices().map(String.init).joined(separator: ",")), defaults \(defaults.joined(separator: ","))"
    }

    /// Every app folder's and every app's Info.plist's date, hashed (a few hundred of them).
    static func appsKey() -> String {
        let manager = FileManager.default
        var dates: [String] = []
        for folder in DiagnosticsEnvironment.appFolders {
            let names = ((try? manager.contentsOfDirectory(atPath: folder)) ?? []).filter { $0.hasSuffix(".app") }.sorted()
            dates.append("\(folder) \(modified(folder))")
            dates += names.map { "\($0) \(modified("\(folder)/\($0)/Contents/Info.plist"))" }
        }
        let digest = SHA256.hash(data: Data(dates.joined(separator: "\n").utf8)).map { String(format: "%02x", $0) }.joined()
        return "\(bootAndBuild()); apps \(digest)"
    }

    static func spotlightKey() -> String {
        build()
    }

    private static func modified(_ path: String) -> Double {
        ((try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate]) as? Date)?.timeIntervalSinceReferenceDate ?? 0
    }
}
