import AppKit
import Observation
import SwiftUI

/// A place on the disk, where System Settings ▸ Storage counts it, what it is, and whether clearing it
/// would be noticed.
nonisolated struct StorageSpot: Sendable, Identifiable, Equatable {
    /// What clearing it means for the user (asked for: plainly, on every card).
    enum Verdict: Sendable, Equatable {
        /// Filler: made again by whatever made it; nothing of the user's goes.
        case filler
        /// Something goes that the user would miss, or waits to be downloaded again.
        case notice
        /// Only its app or macOS should remove it.
        case keep
        /// The user's own apps and files: not filler, only measured (asked for).
        case yours
    }

    /// The row of System Settings ▸ General ▸ Storage it falls in.
    enum Category: Sendable, Equatable {
        case systemData, developer, messages, trash, iOSFiles, applications, documents, photos, music

        var title: String {
            switch self {
            case .applications: String(localized: "Applications")
            case .documents: String(localized: "Documents")
            case .photos: String(localized: "Photos")
            case .music: String(localized: "Music")
            case .systemData: String(localized: "System Data")
            case .developer: String(localized: "Developer")
            case .messages: String(localized: "Messages")
            case .trash: String(localized: "Trash")
            case .iOSFiles: String(localized: "iOS Files")
            }
        }
    }

    enum Removal: Sendable, Equatable {
        /// Everything inside goes to the Trash, the folder stays.
        case contents
        /// The folder itself goes to the Trash.
        case folder
        /// The Trash emptied: deleted for good.
        case emptyTrash
        /// Not by NotchIsland: shown in Finder.
        case none
    }

    let id: String
    let symbol: String
    let tint: Color
    let title: String
    /// What it is.
    let detail: String
    /// What happens if it goes.
    let consequence: String
    let category: Category
    let paths: [URL]
    let verdict: Verdict
    let removal: Removal
    /// Said before it goes, when it can't simply be made again.
    var caution: String?
    /// Items neither measured nor moved (NotchIsland's own cache).
    var skipping: Set<String> = []
    /// Opened only with Full Disk Access: without it, macOS would ask for each of these folders.
    var needsFullDiskAccess = false
    /// macOS's own items (`com.apple.…`) left alone: its services own them, and reading some (Music's)
    /// asks the user for their media library.
    var skipsApple = false
    /// The app that clears it, opened from its card (Disk Utility for Time Machine's snapshots).
    var opens: URL?

    func skips(_ name: String) -> Bool {
        name == ".DS_Store" || skipping.contains(name) || skipsApple && name.hasPrefix("com.apple.")
    }
}

/// How large a spot measured.
nonisolated enum StorageSize: Sendable, Equatable {
    case measuring
    case bytes(Int64)
    /// macOS keeps it from apps without Full Disk Access.
    case denied
    /// Counted, not measured: Time Machine's snapshots, whose size only Disk Utility knows.
    case items(Int)
}

/// What fills the Mac's disk, measured when the Storage page opens (`StoragePage`), and clearing
/// it. Nothing runs while the page is closed: the report lives with the page.
///
/// Energy: walking ~200 GB of files is the whole cost (measured: ~70 J, 3–4 W for half a minute,
/// Activity Monitor 1200–2600). So the walk reads folders in bulk (not a URL and its resource values
/// per file), on the efficiency cores (background), four places at once, and a report stays for ten
/// minutes: opening the page again shows it without walking anything.
@MainActor @Observable final class StorageReport {
    private(set) var spots: [StorageSpot] = []
    private(set) var sizes: [String: StorageSize] = [:]
    /// The startup disk: its size and what is free (counting what macOS can purge).
    private(set) var capacity: Int64 = 0
    private(set) var available: Int64 = 0
    /// Of what is free, what macOS frees itself when space runs low (purgeable).
    private(set) var purgeable: Int64 = 0
    /// Every spot measured.
    private(set) var isDone = false
    /// How far the measuring is, 0…1, for the line round the notch (`StorageLoadingBand`).
    private(set) var progress: Double = 0
    /// Spots on their way to the Trash.
    private(set) var removing: Set<String> = []
    /// Time Machine's snapshots kept on this disk.
    private(set) var snapshots = 0

    @ObservationIgnored private var scan: Task<Void, Never>?
    @ObservationIgnored private let home: URL

    /// The last whole report, and when it was made.
    private struct Kept {
        var spots: [StorageSpot]
        var sizes: [String: StorageSize]
        var snapshots: Int
        var at: Date
    }
    private static var kept: Kept?
    /// How long a report is shown again without measuring.
    static let keptFor: TimeInterval = 10 * 60

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    func size(of spot: StorageSpot) -> StorageSize { sizes[spot.id] ?? .measuring }

    func bytes(of spot: StorageSpot) -> Int64 {
        if case .bytes(let bytes) = size(of: spot) { bytes } else { 0 }
    }

    /// Spots of a group with more than a megabyte in them (or not measured yet), largest first.
    func shown(_ verdict: StorageSpot.Verdict) -> [StorageSpot] {
        spots.filter { spot in
            guard spot.verdict == verdict else { return false }
            if case .bytes(let bytes) = size(of: spot) { return bytes >= 1 << 20 }
            return true
        }
        .sorted { bytes(of: $0) > bytes(of: $1) }
    }

    /// What could go without the user noticing.
    var freeable: Int64 { spots.filter { $0.verdict == .filler }.reduce(0) { $0 + bytes(of: $1) } }
    /// What of it macOS counts as System Data.
    var systemData: Int64 { spots.filter { $0.category == .systemData }.reduce(0) { $0 + bytes(of: $1) } }
    /// Everything measured.
    var found: Int64 { spots.reduce(0) { $0 + bytes(of: $1) } }

    func start() {
        guard scan == nil else { return }
        if let kept = Self.kept, Date().timeIntervalSince(kept.at) < Self.keptFor {
            spots = kept.spots
            sizes = kept.sizes
            snapshots = kept.snapshots
            progress = 1
            isDone = true
            let volume = StorageScanner.volume()
            capacity = volume.capacity
            available = volume.available
            purgeable = volume.purgeable
            return
        }
        let home = home
        // One task at background, awaited by nobody: a task awaited from the main actor's is lifted
        // to its priority, and walked on the performance cores (measured: 49 J against 13 J).
        scan = Task.detached(priority: .background) { [weak self] in
            await StorageScanner.walk(home: home, into: self)
        }
    }

    fileprivate func began(_ spots: [StorageSpot], volume: (capacity: Int64, available: Int64, purgeable: Int64)) {
        self.spots = spots
        capacity = volume.capacity
        available = volume.available
        purgeable = volume.purgeable
    }

    fileprivate func measured(_ id: String, _ size: StorageSize, progress: Double) {
        sizes[id] = size
        self.progress = progress
    }

    fileprivate func advanced(to progress: Double) { self.progress = progress }

    fileprivate func finished(appData: [(StorageSpot, Int64)], snapshots: Int) {
        for (spot, bytes) in appData {
            spots.append(spot)
            sizes[spot.id] = .bytes(bytes)
        }
        self.snapshots = snapshots
        progress = 1
        isDone = true
        keep()
    }

    private func keep() {
        guard isDone else { return }
        Self.kept = Kept(spots: spots, sizes: sizes, snapshots: snapshots, at: Self.kept?.at ?? Date())
    }

    func stop() {
        scan?.cancel()
        scan = nil
    }

    /// Moves the spot to the Trash (or empties it), then measures it and the Trash again.
    func remove(_ spot: StorageSpot) {
        guard spot.removal != .none, !removing.contains(spot.id) else { return }
        removing.insert(spot.id)
        Task { [weak self] in
            await Task.detached(priority: .userInitiated) { StorageScanner.remove(spot) }.value
            guard let self else { return }
            sizes[spot.id] = await Task.detached(priority: .background) { StorageScanner.measure(spot) }.value
            if let trash = spots.first(where: { $0.removal == .emptyTrash }) {
                sizes[trash.id] = await Task.detached(priority: .background) { StorageScanner.measure(trash) }.value
            }
            let volume = await Task.detached(priority: .background) { StorageScanner.volume() }.value
            capacity = volume.capacity
            available = volume.available
            purgeable = volume.purgeable
            removing.remove(spot.id)
            keep()
            Log.system.notice("storage: cleared \(spot.id, privacy: .public)")
        }
    }

    func reveal(_ spot: StorageSpot) {
        if let app = spot.opens {
            NSWorkspace.shared.open(app)
            return
        }
        let existing = spot.paths.filter { FileManager.default.fileExists(atPath: $0.path) }
        if spot.removal == .emptyTrash, let trash = existing.first {
            NSWorkspace.shared.open(trash)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting(existing.isEmpty ? [home] : existing)
        }
    }

    /// System Settings ▸ Privacy & Security ▸ Full Disk Access.
    func openFullDiskAccess() { PermissionKind.fullDiskAccess.openSettings() }
}

/// The measuring and the removing, off the main thread.
nonisolated enum StorageScanner {
    /// Every place, each handed to the report as it is measured, a few side by side; at the
    /// priority of the task it runs in (`StorageReport.start`: background, the efficiency cores).
    @concurrent static func walk(home: URL, into report: StorageReport?) async {
        let began = ContinuousClock.now
        let disk = volume()
        let fixed = catalog(home: home)
        await report?.began(fixed, volume: disk)
        // The known places, then apps' own folders (a list of their own, largest first), then the snapshots.
        let jobs = fixed.filter { $0.id != snapshotsID }.map(Job.spot) + appFolders(home: home).map(Job.appFolder) + [.snapshots]
        var appData: [(StorageSpot, Int64)] = []
        var snapshots = 0
        await withTaskGroup(of: Done.self) { group in
            var next = jobs.makeIterator()
            var done = 0
            func add() {
                guard let job = next.next() else { return }
                group.addTask { run(job, besides: fixed) }
            }
            for _ in 0..<lanes { add() }
            while let result = await group.next() {
                guard !Task.isCancelled else { group.cancelAll(); return }
                done += 1
                let progress = Double(done) / Double(jobs.count + 1)
                switch result {
                case .spot(let id, let size): await report?.measured(id, size, progress: progress)
                case .appFolder(let found):
                    if let found { appData.append(found) }
                    await report?.advanced(to: progress)
                case .snapshots(let count):
                    snapshots = count
                    await report?.measured(snapshotsID, count > 0 ? .items(count) : .bytes(0), progress: progress)
                }
                add()
            }
        }
        guard !Task.isCancelled else { return }
        await report?.finished(appData: appData.sorted { $0.1 > $1.1 }, snapshots: snapshots)
        Log.system.notice("storage: measured in \((ContinuousClock.now - began).formatted(.units(allowed: [.seconds], fractionalPart: .show(length: 1))), privacy: .public)")
    }

    /// A place to measure.
    private enum Job: Sendable {
        case spot(StorageSpot)
        case appFolder(URL)
        case snapshots
    }

    private enum Done: Sendable {
        case spot(String, StorageSize)
        case appFolder((StorageSpot, Int64)?)
        case snapshots(Int)
    }

    private static func run(_ job: Job, besides known: [StorageSpot]) -> Done {
        switch job {
        case .spot(let spot): .spot(spot.id, measure(spot))
        case .appFolder(let folder): .appFolder(appData(in: folder, besides: known))
        case .snapshots: .snapshots(localSnapshots())
        }
    }

    /// Places measured at once: one per efficiency core, at most four (measured: 54 s → 18 s,
    /// 8.9 → 9.4 J, the same work spread wider).
    static let lanes: Int = {
        var cores: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("hw.perflevel1.logicalcpu", &cores, &size, nil, 0) == 0, cores > 0 else { return 2 }
        return min(4, Int(cores))
    }()

    /// The startup disk: its size, what is free counting what macOS can purge, and that purgeable part.
    static func volume() -> (capacity: Int64, available: Int64, purgeable: Int64) {
        let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [
            .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey,
        ])
        let available = values?.volumeAvailableCapacityForImportantUsage ?? 0
        let free = Int64(values?.volumeAvailableCapacity ?? 0)
        return (Int64(values?.volumeTotalCapacity ?? 0), available, max(0, available - free))
    }

    /// Time Machine's snapshots' spot: counted by `localSnapshots`, not walked.
    static let snapshotsID = "snapshots"

    /// The places that fill System Data on most Macs, a developer's included.
    static func catalog(home: URL) -> [StorageSpot] {
        func at(_ path: String) -> URL { home.appending(path: path, directoryHint: .isDirectory) }
        let ownCache = Bundle.main.bundleIdentifier ?? "com.davidvarga.notchisland"
        return [
            StorageSpot(id: "messages-temporary", symbol: "message.fill", tint: .green, title: String(localized: "Messages leftovers"),
                        detail: String(localized: "Copies Messages made of videos and photos while sending them. Nothing uses them again."),
                        consequence: String(localized: "Nothing changes. Every photo and video stays in its conversation."),
                        category: .systemData, paths: [at("Library/Containers/com.apple.MobileSMS/Data/tmp/TemporaryItems")],
                        verdict: .filler, removal: .contents, caution: String(localized: "Quit Messages first.")),
            StorageSpot(id: "derived-data", symbol: "hammer.fill", tint: .blue, title: String(localized: "Xcode build files"),
                        detail: String(localized: "What Xcode made while building your projects."),
                        consequence: String(localized: "Nothing you'd notice. Each project's next build takes a little longer."),
                        category: .developer, paths: [at("Library/Developer/Xcode/DerivedData")], verdict: .filler, removal: .contents),
            StorageSpot(id: "device-support", symbol: "iphone", tint: .blue, title: String(localized: "Device support"),
                        detail: String(localized: "Copied from every iPhone and Watch you ran an app on from Xcode."),
                        consequence: String(localized: "Nothing. Xcode copies it again when you connect a device."),
                        category: .developer,
                        paths: ["iOS", "watchOS", "tvOS", "visionOS"].map { at("Library/Developer/Xcode/\($0) DeviceSupport") },
                        verdict: .filler, removal: .contents),
            StorageSpot(id: "simulator-caches", symbol: "ipad.and.iphone", tint: .blue, title: String(localized: "Simulator caches"),
                        detail: String(localized: "Made by the iOS Simulator while it runs."),
                        consequence: String(localized: "Nothing. The Simulator makes them again."),
                        category: .developer, paths: [at("Library/Developer/CoreSimulator/Caches")], verdict: .filler, removal: .contents),
            StorageSpot(id: "caches", symbol: "archivebox.fill", tint: .orange, title: String(localized: "App caches"),
                        detail: String(localized: "Copies apps keep to open things faster. macOS's own are left alone."),
                        consequence: String(localized: "Nothing of yours goes. Some apps open things a little slower once."),
                        category: .systemData, paths: [at("Library/Caches")], verdict: .filler, removal: .contents,
                        skipping: [ownCache], skipsApple: true),
            StorageSpot(id: "developer-caches", symbol: "shippingbox.fill", tint: .purple, title: String(localized: "Package caches"),
                        detail: String(localized: "Packages uv, npm, NuGet and other developer tools downloaded, kept in case they're needed again."),
                        consequence: String(localized: "Nothing of yours goes. A project downloads what it needs again."),
                        category: .systemData, paths: [at(".cache"), at(".npm/_cacache"), at(".nuget/packages")],
                        verdict: .filler, removal: .contents),
            StorageSpot(id: "logs", symbol: "doc.text.fill", tint: .gray, title: String(localized: "Logs"),
                        detail: String(localized: "What apps wrote down about their work."),
                        consequence: String(localized: "Nothing. They're only read when something goes wrong."),
                        category: .systemData, paths: [at("Library/Logs")], verdict: .filler, removal: .contents),
            StorageSpot(id: "trash", symbol: "trash.fill", tint: .red, title: String(localized: "Trash"),
                        detail: String(localized: "Files you already deleted. They take their space until the Trash is emptied."),
                        consequence: String(localized: "They're gone for good. Look through the Trash first."),
                        category: .trash, paths: [at(".Trash")], verdict: .filler, removal: .emptyTrash,
                        caution: String(localized: "It can't be undone.")),
            StorageSpot(id: "claude-vm", symbol: "cpu.fill", tint: .orange, title: String(localized: "Claude's virtual machine"),
                        detail: String(localized: "The Linux system Claude runs its tasks in on your Mac."),
                        consequence: String(localized: "Claude downloads it again, several gigabytes, the next time it needs it."),
                        category: .systemData, paths: [at("Library/Application Support/Claude/vm_bundles")],
                        verdict: .notice, removal: .contents, caution: String(localized: "Quit Claude first.")),
            StorageSpot(id: "ios-backups", symbol: "externaldrive.fill", tint: .teal, title: String(localized: "iPhone backups"),
                        detail: String(localized: "Backups of iPhones and iPads made on this Mac."),
                        consequence: String(localized: "A device can't be restored from them any more."),
                        category: .iOSFiles, paths: [at("Library/Application Support/MobileSync/Backup")],
                        verdict: .notice, removal: .contents),
            StorageSpot(id: "archives", symbol: "archivebox.circle.fill", tint: .blue, title: String(localized: "Xcode archives"),
                        detail: String(localized: "Every app you archived for TestFlight or the App Store."),
                        consequence: String(localized: "Crash reports of those versions can't be read, and they can't be uploaded again."),
                        category: .developer, paths: [at("Library/Developer/Xcode/Archives")], verdict: .notice, removal: .contents),
            StorageSpot(id: "simulators", symbol: "iphone.gen3", tint: .blue, title: String(localized: "Simulators"),
                        detail: String(localized: "The iOS Simulator's devices, with the apps and data on them."),
                        consequence: String(localized: "Their apps and data go. Remove unused ones in Xcode ▸ Window ▸ Devices."),
                        category: .developer, paths: [at("Library/Developer/CoreSimulator/Devices")], verdict: .keep, removal: .none),
            StorageSpot(id: "apps", symbol: "square.grid.3x3.fill", tint: .blue, title: String(localized: "Apps"),
                        detail: String(localized: "Everything in Applications."),
                        consequence: String(localized: "Remove an app you don't use by dragging it to the Trash."),
                        category: .applications, paths: [URL(fileURLWithPath: "/Applications"), at("Applications")],
                        verdict: .yours, removal: .none),
            StorageSpot(id: "documents", symbol: "doc.fill", tint: .blue, title: String(localized: "Documents & Desktop"),
                        detail: String(localized: "Your documents and what's on the desktop."),
                        consequence: String(localized: "Your own work. Only you know what can go."),
                        category: .documents, paths: [at("Documents"), at("Desktop")], verdict: .yours, removal: .none,
                        needsFullDiskAccess: true),
            StorageSpot(id: "downloads", symbol: "arrow.down.circle.fill", tint: .blue, title: String(localized: "Downloads"),
                        detail: String(localized: "What you downloaded."),
                        consequence: String(localized: "Often installers and files you've already used. Look through it."),
                        category: .documents, paths: [at("Downloads")], verdict: .yours, removal: .none, needsFullDiskAccess: true),
            StorageSpot(id: "pictures", symbol: "photo.fill", tint: .blue, title: String(localized: "Pictures & Photos"),
                        detail: String(localized: "The Photos library and the Pictures folder."),
                        consequence: String(localized: "Your photos. Optimise Mac Storage in Photos keeps the originals in iCloud."),
                        category: .photos, paths: [at("Pictures")], verdict: .yours, removal: .none, needsFullDiskAccess: true),
            StorageSpot(id: "movies", symbol: "film.fill", tint: .blue, title: String(localized: "Movies"),
                        detail: String(localized: "Videos and iMovie projects."),
                        consequence: String(localized: "Your own videos. Only you know what can go."),
                        category: .documents, paths: [at("Movies")], verdict: .yours, removal: .none, needsFullDiskAccess: true),
            StorageSpot(id: "music", symbol: "music.note", tint: .blue, title: String(localized: "Music"),
                        detail: String(localized: "Your music library and GarageBand projects."),
                        consequence: String(localized: "Your own music. Only you know what can go."),
                        category: .music, paths: [at("Music")], verdict: .yours, removal: .none, needsFullDiskAccess: true),
            StorageSpot(id: "message-attachments", symbol: "paperclip", tint: .green, title: String(localized: "Messages attachments"),
                        detail: String(localized: "The photos and videos in your conversations."),
                        consequence: String(localized: "They'd disappear from your conversations. Delete them in Messages instead."),
                        category: .messages, paths: [at("Library/Messages/Attachments")], verdict: .keep, removal: .none),
            StorageSpot(id: "spotlight-index", symbol: "magnifyingglass", tint: .purple, title: String(localized: "Spotlight's index"),
                        detail: String(localized: "What Spotlight knows about your files, so it finds them at once."),
                        consequence: String(localized: "Spotlight would find nothing for hours while it rebuilds it. macOS keeps it in check."),
                        category: .systemData, paths: [at("Library/Metadata/CoreSpotlight")], verdict: .keep, removal: .none),
            // What System Data holds outside the home folder, the large ones a Mac can grow by hundreds of GB.
            StorageSpot(id: snapshotsID, symbol: "clock.arrow.circlepath", tint: .teal, title: String(localized: "Time Machine snapshots"),
                        detail: String(localized: "Hourly copies of your disk, kept on the Mac while the backup disk is away. They can grow to hundreds of GB."),
                        consequence: String(localized: "The last hours' backups on this Mac go; your backup disk keeps its own. In Disk Utility: View ▸ Show APFS Snapshots."),
                        category: .systemData, paths: [], verdict: .notice, removal: .none,
                        opens: URL(fileURLWithPath: "/System/Applications/Utilities/Disk Utility.app")),
            StorageSpot(id: "simulator-runtimes", symbol: "square.stack.3d.down.right.fill", tint: .blue, title: String(localized: "Simulator runtimes"),
                        detail: String(localized: "The iOS, watchOS and other systems Xcode's Simulator runs, several GB each."),
                        consequence: String(localized: "Their simulators can't start until you download them again. Remove unused ones in Xcode ▸ Settings ▸ Components."),
                        category: .systemData, paths: [URL(fileURLWithPath: "/Library/Developer/CoreSimulator/Images")]
                            + simulatorRuntimeAssets.map { assets.appending(path: $0, directoryHint: .isDirectory) },
                        verdict: .notice, removal: .none),
            StorageSpot(id: "ios-updates", symbol: "arrow.down.app.fill", tint: .teal, title: String(localized: "iPhone updates"),
                        detail: String(localized: "iOS updates Finder downloaded to update your iPhone or iPad."),
                        consequence: String(localized: "Nothing. Finder downloads one again the next time it updates a device."),
                        category: .systemData, paths: ["iPhone", "iPad"].map { at("Library/iTunes/\($0) Software Updates") },
                        verdict: .filler, removal: .contents),
            StorageSpot(id: "macos-assets", symbol: "square.and.arrow.down.on.square.fill", tint: .gray, title: String(localized: "macOS downloads"),
                        detail: String(localized: "Parts macOS downloaded for you: Apple Intelligence, Siri, dictation, voices and fonts."),
                        consequence: String(localized: "Leave them: macOS downloads them again, and removes what it no longer needs."),
                        category: .systemData, paths: [assets], verdict: .keep, removal: .none,
                        skipping: Set(simulatorRuntimeAssets)),
            StorageSpot(id: "temporary", symbol: "hourglass", tint: .gray, title: String(localized: "Temporary files"),
                        detail: String(localized: "What macOS and apps keep for a while in a hidden folder of yours."),
                        consequence: String(localized: "A restart clears much of it. Deleting it while apps run can break them."),
                        category: .systemData, paths: [URL(fileURLWithPath: NSTemporaryDirectory()).deletingLastPathComponent()],
                        verdict: .keep, removal: .none),
            StorageSpot(id: "swap", symbol: "memorychip", tint: .gray, title: String(localized: "Memory on disk"),
                        detail: String(localized: "What didn't fit in memory, and the copy of it kept for sleep."),
                        consequence: String(localized: "Restarting your Mac frees it."),
                        category: .systemData, paths: [URL(fileURLWithPath: "/private/var/vm")], verdict: .keep, removal: .none),
            StorageSpot(id: "system-logs", symbol: "doc.text.magnifyingglass", tint: .gray, title: String(localized: "System logs"),
                        detail: String(localized: "What macOS writes down about itself, kept for a few days."),
                        consequence: String(localized: "Nothing to do: macOS trims them by itself."),
                        category: .systemData, paths: ["diagnostics", "uuidtext"].map { URL(fileURLWithPath: "/private/var/db/\($0)") },
                        verdict: .keep, removal: .none),
        ]
    }

    /// Where macOS keeps what it downloads for itself (`MobileAsset`).
    static let assets = URL(fileURLWithPath: "/System/Library/AssetsV2", isDirectory: true)

    /// The Simulator's systems among them, counted as runtimes, not as macOS's.
    static let simulatorRuntimeAssets = ["iOS", "watchOS", "tvOS", "visionOS", "xrOS"].map { "com_apple_MobileAsset_\($0)SimulatorRuntime" }

    /// Apps' own folders: in Application Support, and with Full Disk Access their containers too (where
    /// Docker's and virtual machines' disks are, often the largest of all). Not macOS's, not NotchIsland's.
    static func appFolders(home: URL) -> [URL] {
        let own = Bundle.main.bundleIdentifier ?? "com.davidvarga.notchisland"
        // Other apps' containers ask the user first without Full Disk Access.
        let places = ["Library/Application Support"] + (hasFullDiskAccess() ? ["Library/Containers", "Library/Group Containers"] : [])
        return places.flatMap { place in
            let folders = (try? FileManager.default.contentsOfDirectory(at: home.appending(path: place, directoryHint: .isDirectory),
                                                                         includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            // macOS's own folders are not opened: some (Contacts, call history) ask the user first.
            return folders.filter { folder in
                let name = folder.lastPathComponent
                return name != own && !name.contains(own) && !name.contains("com.apple.") && !name.hasPrefix("group.com.apple")
                    && !appleFolders.contains(name)
            }
        }
    }

    /// An app's folder as a spot, when it is over a gigabyte without what a spot above already counts.
    static func appData(in folder: URL, besides known: [StorageSpot], over limit: Int64 = 1 << 30) -> (StorageSpot, Int64)? {
        let path = folder.standardizedFileURL.path
        // What a spot above already counts in it (Claude's virtual machine) is not walked.
        let inside = known.flatMap(\.paths).map(\.standardizedFileURL.path).filter { $0.hasPrefix(path + "/") }
        let bytes = allocatedSize(of: folder, skipping: Set(inside))
        guard bytes >= limit else { return nil }
        let name = folder.lastPathComponent
        let place = folder.deletingLastPathComponent().lastPathComponent
        return (StorageSpot(id: "app:\(place)/\(name)", symbol: "app.dashed", tint: .white.opacity(0.7), title: appName(for: name),
                            detail: String(localized: "This app's own data, in \(place) ▸ \(name)."),
                            consequence: String(localized: "The app loses what it kept here: settings, sign-ins, downloads, projects."),
                            category: .systemData, paths: [folder], verdict: .notice, removal: .folder,
                            caution: String(localized: "Quit the app first.")), bytes)
    }

    /// macOS's folders in Application Support without a `com.apple.` name.
    static let appleFolders: Set<String> = [
        "AddressBook", "CallHistoryDB", "CallHistoryTransactions", "Knowledge", "FileProvider", "CloudDocs",
        "MobileSync", "Accounts", "AppleMediaServices", "CrashReporter", "DiskImages", "Dock", "SyncServices",
        "iCloud", "icdd", "Animoji", "AskPermission", "identityservicesd", "networkserviceproxy", "Safari",
        "Mail", "Photos", "Calendars", "Reminders", "Notes", "Maps", "Siri", "Wallpaper",
    ]

    /// An app's name for its folder (`com.davidvarga.cadapp.native` → the app's own name when
    /// installed, else `Cadapp`), never the bare identifier.
    static func appName(for folder: String) -> String {
        guard folder.contains(".") else { return folder }
        // A group container: `group.` or a team's ten letters before the identifier.
        var folder = folder.hasPrefix("group.") ? String(folder.dropFirst(6)) : folder
        if let dot = folder.firstIndex(of: "."), folder.distance(from: folder.startIndex, to: dot) == 10,
           folder[..<dot].allSatisfy({ $0.isUppercase || $0.isNumber }) {
            folder = String(folder[folder.index(after: dot)...])
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: folder),
           let name = FileManager.default.displayName(atPath: url.path).split(separator: ".").first {
            return String(name)
        }
        let parts = folder.split(separator: ".").map(String.init)
        let plain = parts.dropFirst(parts.count > 2 ? 2 : parts.count == 2 ? 1 : 0).filter { !["native", "app", "mac", "macos", "desktop"].contains($0.lowercased()) }
        guard let name = plain.first ?? parts.last else { return folder }
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    static func measure(_ spot: StorageSpot) -> StorageSize {
        if spot.needsFullDiskAccess, !hasFullDiskAccess() { return .denied }
        var total: Int64 = 0
        var denied = false
        for path in spot.paths {
            var isFolder: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path.path, isDirectory: &isFolder) else { continue }
            if isFolder.boolValue, !FileManager.default.isReadableFile(atPath: path.path)
                || (try? FileManager.default.contentsOfDirectory(atPath: path.path)) == nil {
                denied = true
                continue
            }
            if spot.skipping.isEmpty, !spot.skipsApple {
                total += allocatedSize(of: path)
            } else {
                // Item by item: what is left alone is never opened.
                let items = (try? FileManager.default.contentsOfDirectory(at: path, includingPropertiesForKeys: nil)) ?? []
                total += items.filter { !spot.skips($0.lastPathComponent) }.reduce(0) { $0 + allocatedSize(of: $1) }
            }
        }
        return denied && total == 0 ? .denied : .bytes(total)
    }

    /// Full Disk Access, read without asking: a file only it opens (`PermissionProbe`).
    static func hasFullDiskAccess() -> Bool {
        let file = open("/Library/Application Support/com.apple.TCC/TCC.db", O_RDONLY)
        guard file >= 0 else { return false }
        close(file)
        return true
    }

    /// What a file or folder takes on the disk, as `du` counts it, on this volume only. Folders in
    /// `skipping` (full paths) are not entered. A folder's entries come in bulk with their sizes
    /// (`getattrlistbulk`): one call for hundreds of files, where `fts` read the folder and then
    /// asked for each file on its own (measured: 6 % quicker, the same energy).
    static func allocatedSize(of url: URL, skipping: Set<String> = []) -> Int64 {
        let root = url.standardizedFileURL.path
        var info = stat()
        guard lstat(root, &info) == 0 else { return 0 }
        guard info.st_mode & S_IFMT == S_IFDIR else { return Int64(info.st_blocks) * 512 }
        let device = info.st_dev

        var wanted = attrlist()
        wanted.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        wanted.commonattr = attrgroup_t(ATTR_CMN_RETURNED_ATTRS) | attrgroup_t(ATTR_CMN_NAME)
            | attrgroup_t(ATTR_CMN_OBJTYPE) | attrgroup_t(ATTR_CMN_ERROR)
        wanted.fileattr = attrgroup_t(ATTR_FILE_ALLOCSIZE)
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: 128 * 1024, alignment: 16)
        defer { buffer.deallocate() }

        var total: Int64 = 0
        var folders = [root]
        var visited = 0
        while let folder = folders.popLast() {
            let fd = open(folder, O_RDONLY | O_DIRECTORY)
            guard fd >= 0 else { continue }
            defer { close(fd) }
            // Another volume mounted here is not this disk's.
            guard fstat(fd, &info) == 0, info.st_dev == device else { continue }
            while true {
                let count = getattrlistbulk(fd, &wanted, buffer, 128 * 1024, 0)
                guard count > 0 else { break }
                var entry = buffer
                for _ in 0..<count {
                    let length = Int(entry.loadUnaligned(as: UInt32.self))
                    defer { entry += length }
                    // In the order of their bits: name, type, error, then the size.
                    let returned = entry.loadUnaligned(fromByteOffset: 4, as: attribute_set_t.self)
                    var field = entry + 4 + MemoryLayout<attribute_set_t>.size
                    let nameField = field
                    if returned.commonattr & attrgroup_t(ATTR_CMN_NAME) != 0 { field += MemoryLayout<attrreference_t>.size }
                    var type = fsobj_type_t(VNON.rawValue)
                    if returned.commonattr & attrgroup_t(ATTR_CMN_OBJTYPE) != 0 {
                        type = field.loadUnaligned(as: fsobj_type_t.self)
                        field += MemoryLayout<fsobj_type_t>.size
                    }
                    if returned.commonattr & attrgroup_t(ATTR_CMN_ERROR) != 0 {
                        let error = field.loadUnaligned(as: UInt32.self)
                        field += MemoryLayout<UInt32>.size
                        if error != 0 { continue }
                    }
                    if type == fsobj_type_t(VDIR.rawValue) {
                        guard returned.commonattr & attrgroup_t(ATTR_CMN_NAME) != 0 else { continue }
                        let name = nameField.loadUnaligned(as: attrreference_t.self)
                        let child = folder + "/" + String(cString: (nameField + Int(name.attr_dataoffset)).assumingMemoryBound(to: CChar.self))
                        if skipping.isEmpty || !skipping.contains(child) { folders.append(child) }
                    } else if returned.fileattr & attrgroup_t(ATTR_FILE_ALLOCSIZE) != 0 {
                        total += field.loadUnaligned(as: off_t.self)
                    }
                }
                // A page closed mid-walk stops it.
                visited += Int(count)
                if visited >= 4096 {
                    visited = 0
                    if Task.isCancelled { return total }
                }
            }
        }
        return total
    }

    /// Moves to the Trash what the spot says (or empties it). What can't be moved stays.
    static func remove(_ spot: StorageSpot, trash: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) },
                       delete: (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }) {
        for path in spot.paths where FileManager.default.fileExists(atPath: path.path) {
            switch spot.removal {
            case .none:
                return
            case .folder:
                try? trash(path)
            case .contents, .emptyTrash:
                let items = (try? FileManager.default.contentsOfDirectory(at: path, includingPropertiesForKeys: nil)) ?? []
                for item in items where !spot.skips(item.lastPathComponent) {
                    try? (spot.removal == .emptyTrash ? delete : trash)(item)
                }
            }
        }
    }

    /// Time Machine's local snapshots of the startup disk (`tmutil`, no permission asked).
    static func localSnapshots() -> Int {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tmutil")
        process.arguments = ["listlocalsnapshots", "/"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return 0 }
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: output, as: UTF8.self).split(separator: "\n").filter { $0.contains("com.apple.") }.count
    }
}
