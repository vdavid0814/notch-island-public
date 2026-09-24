import AppKit
import Observation

/// The files the user parked on the island, persisted across launches.
///
/// Each entry is stored as a path plus bookmark data. The bookmark follows the file when
/// it is moved or renamed (it resolves by file identity, then by path); the path is the
/// fallback when there is no bookmark. Entries whose file is gone — deleted, in the
/// Trash, or on a volume that is not mounted — are dropped rather than shown broken.
@Observable final class ShelfStore {

    static let defaultsKey = "ni2.shelf"

    /// In the order they were added.
    private(set) var items: [ShelfItem] = []

    /// True while a drag that started on one of our own tiles is in flight. Drag-session
    /// observers ignore drags while it is set, so dragging a file *out* of the shelf does
    /// not announce itself as an incoming drop.
    var isDraggingOut = false

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var bookmarks: [ShelfItem.ID: Data] = [:]
    /// The last AirDrop service, held until the next one replaces it: the service is not
    /// documented to retain itself while its picker is up, and one idle object is cheaper
    /// than a delegate that tracks when the picker closes.
    @ObservationIgnored private var sharingService: NSSharingService?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    // MARK: Intents

    /// Adds the file URLs that are not on the shelf yet, in order. Non-file URLs and files
    /// that do not exist are skipped. Returns how many were added.
    @discardableResult func add(_ urls: [URL]) -> Int {
        var known = Set(items.map { ShelfItem.identity(of: $0.url) })
        var added: [ShelfItem] = []
        for url in urls where url.isFileURL {
            let url = url.standardizedFileURL
            guard ShelfFiles.isReachable(url), known.insert(ShelfItem.identity(of: url)).inserted else {
                continue
            }
            let item = ShelfItem(id: UUID(), url: url, addedAt: .now,
                                 displayName: ShelfFiles.displayName(of: url))
            bookmarks[item.id] = ShelfFiles.bookmark(for: url)
            added.append(item)
        }
        guard !added.isEmpty else { return 0 }
        items.append(contentsOf: added)
        persist()
        return added.count
    }

    /// Forgets the entry. The file itself is never touched.
    func remove(_ id: ShelfItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items.remove(at: index)
        bookmarks[id] = nil
        persist()
    }

    /// Forgets every entry. Files are never touched.
    func clear() {
        guard !items.isEmpty else { return }
        items.removeAll()
        bookmarks.removeAll()
        persist()
    }

    func open(_ item: ShelfItem) {
        guard let url = locate(item.id) else { return }
        NSWorkspace.shared.open(url)
    }

    func reveal(_ item: ShelfItem) {
        guard let url = locate(item.id) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Hands the files (all of them when `selection` is nil) to the system AirDrop picker.
    func airDrop(_ selection: [ShelfItem]? = nil) {
        let urls = (selection ?? items).compactMap { locate($0.id) }
        guard !urls.isEmpty else { return }
        guard let service = NSSharingService(named: .sendViaAirDrop),
              service.canPerform(withItems: urls) else {
            Log.shelf.info("AirDrop unavailable (turned off, or Wi-Fi/Bluetooth is off)")
            return
        }
        // The picker is a window of this process; an accessory app that is not active
        // would open it behind the frontmost app.
        NSApp.activate()
        sharingService = service
        service.perform(withItems: urls)
    }

    /// Follows moved files and drops entries whose file is gone. Cheap enough to call
    /// whenever the shelf is about to be shown.
    func pruneMissing() {
        apply(items.map { Self.reconcile($0, bookmark: bookmarks[$0.id]) }, to: items)
    }

    /// `pruneMissing()` with the file-system work (bookmark resolution, existence checks) on a
    /// background thread; only the result is applied on the main actor, and only if the shelf has
    /// not changed meanwhile.
    func pruneMissingInBackground() {
        let base = items
        guard !base.isEmpty else { return }
        let marks = base.map { bookmarks[$0.id] }
        Task.detached(priority: .utility) { [weak self] in
            let results = zip(base, marks).map { ShelfStore.reconcile($0, bookmark: $1) }
            await self?.apply(results, to: base)
        }
    }

    private func apply(_ results: [(item: ShelfItem, bookmark: Data?)?], to base: [ShelfItem]) {
        guard items == base else { return }
        let bookmarksBefore = bookmarks
        var seen = Set<String>()
        var next: [ShelfItem] = []
        for (item, result) in zip(base, results) {
            guard let result, seen.insert(ShelfItem.identity(of: result.item.url)).inserted else {
                bookmarks[item.id] = nil
                continue
            }
            bookmarks[item.id] = result.bookmark
            next.append(result.item)
        }
        guard next != items || bookmarks != bookmarksBefore else { return }
        if next != items {
            let before = items.count, after = next.count
            Log.shelf.info("shelf reconciled: \(before) → \(after) item(s)")
            items = next
        }
        persist()
    }

    // MARK: Resolution

    /// The item's current URL, following a move; removes the entry if its file is gone.
    private func locate(_ id: ShelfItem.ID) -> URL? {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        let item = items[index]
        let bookmarkBefore = bookmarks[id]
        guard let current = reconciled(item) else {
            Log.shelf.info("shelf file vanished; removing its entry")
            remove(id)
            return nil
        }
        if current != item { items[index] = current }
        if current != item || bookmarks[id] != bookmarkBefore { persist() }
        return current.url
    }

    private func reconciled(_ item: ShelfItem) -> ShelfItem? {
        guard let result = Self.reconcile(item, bookmark: bookmarks[item.id]) else { return nil }
        bookmarks[item.id] = result.bookmark
        return result.item
    }

    /// Where the item's file is now, with its (refreshed) bookmark, or nil if it is gone. The
    /// bookmark is refreshed when the system reports it stale (the file moved). File-system work
    /// only, no state: safe off the main actor.
    nonisolated static func reconcile(_ item: ShelfItem, bookmark: Data?) -> (item: ShelfItem, bookmark: Data?)? {
        var url: URL?
        var bookmark = bookmark
        if let stored = bookmark, let resolved = ShelfFiles.resolve(stored), ShelfFiles.isReachable(resolved.url) {
            url = resolved.url
            if resolved.isStale {
                bookmark = ShelfFiles.bookmark(for: resolved.url) ?? stored
            }
        } else if ShelfFiles.isReachable(item.url) {
            url = item.url
            if bookmark == nil {
                bookmark = ShelfFiles.bookmark(for: item.url)
            }
        }
        guard let url else { return nil }
        let standardized = url.standardizedFileURL
        if ShelfItem.identity(of: standardized) == ShelfItem.identity(of: item.url) {
            return (item, bookmark)
        }
        return (ShelfItem(id: item.id, url: standardized, addedAt: item.addedAt,
                          displayName: ShelfFiles.displayName(of: standardized)), bookmark)
    }

    // MARK: Persistence

    /// The on-disk shape. `path` is what a human (or a future version) can read back even
    /// if the bookmark no longer resolves.
    private nonisolated struct Record: Codable {
        let id: UUID
        let path: String
        let bookmark: Data?
        let addedAt: Date
        let displayName: String
    }

    private func persist() {
        let records = items.map { item in
            Record(id: item.id, path: item.url.path(percentEncoded: false), bookmark: bookmarks[item.id],
                   addedAt: item.addedAt, displayName: item.displayName)
        }
        do {
            defaults.set(try PropertyListEncoder().encode(records), forKey: Self.defaultsKey)
        } catch {
            Log.shelf.error("could not save the shelf: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func load() {
        guard let data = defaults.data(forKey: Self.defaultsKey) else { return }
        let records: [Record]
        do {
            records = try PropertyListDecoder().decode([Record].self, from: data)
        } catch {
            Log.shelf.error("discarding unreadable shelf data: \(error.localizedDescription, privacy: .public)")
            defaults.removeObject(forKey: Self.defaultsKey)
            return
        }

        var stored: [ShelfItem] = []
        for record in records {
            // `.checkFileSystem`: a folder must come back as a directory URL (drag-out
            // and QuickLook treat it differently), and the stored path alone cannot say.
            let url = URL(filePath: record.path, directoryHint: .checkFileSystem)
            stored.append(ShelfItem(id: record.id, url: url, addedAt: record.addedAt,
                                    displayName: record.displayName))
            bookmarks[record.id] = record.bookmark
        }
        // Missing files are pruned by `pruneMissingInBackground()` when the app starts, not here:
        // no file-system work on the main thread at launch.
        items = stored
    }
}

/// File-system helpers for the shelf. Stateless.
nonisolated enum ShelfFiles {

    /// A file URL whose file exists and is not sitting in a Trash. A bookmark follows a
    /// deleted file into the Trash, but from the user's point of view it is gone.
    static func isReachable(_ url: URL) -> Bool {
        guard url.isFileURL, !url.pathComponents.contains(where: { $0 == ".Trash" || $0 == ".Trashes" }) else {
            return false
        }
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    /// Plain (not security-scoped) bookmark data: the app is not sandboxed, so a scope
    /// would add nothing but a start/stop dance.
    static func bookmark(for url: URL) -> Data? {
        do {
            return try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        } catch {
            Log.shelf.error("no bookmark for a shelf file: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// `.withoutUI` and `.withoutMounting`: resolution happens at launch and on hover, so
    /// it must never block on a dialog or a network volume.
    static func resolve(_ bookmark: Data) -> (url: URL, isStale: Bool)? {
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting],
                                 relativeTo: nil, bookmarkDataIsStale: &isStale) else { return nil }
        return (url, isStale)
    }

    static func displayName(of url: URL) -> String {
        FileManager.default.displayName(atPath: url.path(percentEncoded: false))
    }
}
