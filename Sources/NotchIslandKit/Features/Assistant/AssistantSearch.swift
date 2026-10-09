import CoreServices
import Foundation
import Synchronization

/// An app or a file the assistant found for the query.
nonisolated struct AssistantHit: Sendable, Hashable, Identifiable {
    nonisolated enum Kind: Sendable, Hashable { case app, file, folder }

    let kind: Kind
    let url: URL
    let name: String
    /// The Uniform Type Identifier, for the file's icon.
    let contentType: String?
    let lastUsed: Date?

    var id: URL { url }

}

/// Live results from the Spotlight index, off the main actor.
///
/// Synchronous `MDQuery` runs in a `@concurrent` function: in this package a plain
/// `nonisolated async` function would run on the main actor (measured). Word-prefix predicates
/// ("q*"cdw) with a result cap and ranking in code: a capped query returns arbitrary, unranked
/// hits, and a substring query over the home folder surfaces ~/Library caches (measured).
nonisolated enum AssistantSearch {
    static let appScopes: [String] = [
        "/Applications", "/System/Applications", NSHomeDirectory() + "/Applications",
    ]
    /// The system's apps that live outside the app folders and that Spotlight lists (Finder, Archive
    /// Utility, Screen Sharing…).
    static let finder = "/System/Library/CoreServices/Finder.app"
    /// The apps among macOS's own services a user opens (Screen Time, Paired Devices, Apple
    /// Diagnostics…): an app category and not a background agent (Dock, loginwindow and the like
    /// are agents), read once from their Info.plist.
    static let coreServicesUserApps: Set<String> = {
        let folder = "/System/Library/CoreServices"
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
        return Set(names.filter { $0.hasSuffix(".app") }.compactMap { name -> String? in
            let path = folder + "/" + name
            guard let info = Bundle(path: path)?.infoDictionary, info["LSApplicationCategoryType"] != nil,
                  !flag(info["LSUIElement"]), !flag(info["LSBackgroundOnly"]) else { return nil }
            return path
        })
    }()

    private static func flag(_ value: Any?) -> Bool {
        (value as? Bool) ?? (value as? NSNumber)?.boolValue ?? ((value as? String).map { $0 == "1" || $0.lowercased() == "yes" } ?? false)
    }
    static let coreServicesApps = "/System/Library/CoreServices/Applications"
    /// Apps are looked for everywhere Spotlight indexes, as the system's Spotlight does: an app
    /// anywhere else (an Xcode unpacked in Downloads, a game in Documents) was never found — the
    /// search kept to the three app folders (a tester's "Siri does not bring up my apps", v0.4.9).
    static let everywhere = [kMDQueryScopeComputer as String]
    static let iCloudDrive = NSHomeDirectory() + "/Library/Mobile Documents/com~apple~CloudDocs"
    static let homeLibrary = NSHomeDirectory() + "/Library/"
    static let fileScopes: [String] = ["Desktop", "Documents", "Downloads"].map { NSHomeDirectory() + "/" + $0 }
        + [iCloudDrive]

    @concurrent static func apps(matching query: String, limit: Int = 3) async -> [AssistantHit] {
        let term = escaped(query)
        guard !term.isEmpty else { return [] }
        let predicate = """
            kMDItemContentTypeTree == "com.apple.application-bundle" && \
            (kMDItemDisplayName == "\(term)*"cdw || kMDItemAlternateNames == "\(term)*"cdw)
            """
        // More than shown: the index's other apps (builds, helpers) are left out afterwards.
        let indexed = await run(predicate, scopes: everywhere, fetch: 80, kind: .app)
        let onDisk = cachedDiskApps().filter { AssistantMatch.matches($0.name, query) }
        return Array(rank(merged(indexed, onDisk), for: query).prefix(limit))
    }

    /// Spotlight's hits, then the apps on disk it did not return (by resolved path).
    static func merged(_ indexed: [AssistantHit], _ onDisk: [AssistantHit]) -> [AssistantHit] {
        var seen = Set(indexed.map { $0.url.resolvingSymlinksInPath().path })
        return indexed + onDisk.filter { seen.insert($0.url.resolvingSymlinksInPath().path).inserted }
    }

    /// `diskApps` as read at most `diskAppsLifetime` ago: every keystroke's search read the folders
    /// again (~10–50 ms of a core per keystroke, the first one cold, measured).
    static func cachedDiskApps(now: Date = Date()) -> [AssistantHit] {
        if let cached = diskAppsCache.withLock({ $0 }), now.timeIntervalSince(cached.read) < diskAppsLifetime { return cached.hits }
        let hits = diskApps()
        diskAppsCache.withLock { $0 = (now, hits) }
        return hits
    }

    static let diskAppsLifetime: TimeInterval = 60
    private static let diskAppsCache = Mutex<(read: Date, hits: [AssistantHit])?>(nil)

    /// Every app in the app folders (and one folder down, like /Applications/Utilities), read
    /// from disk. Spotlight's index misses apps: on a tester's Mac 19 of 28 apps in /Applications
    /// (ChatGPT, Word, Keynote, …) were not in it, and Siri could not find them (report, v0.4.5).
    /// A directory listing of a few folders, about a millisecond.
    static func diskApps(defaults: UserDefaults = .standard) -> [AssistantHit] {
        let manager = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .contentAccessDateKey]
        var hits: [AssistantHit] = []
        func scan(_ folder: URL, depth: Int) {
            guard let entries = try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys,
                                                                 options: [.skipsHiddenFiles]) else { return }
            for url in entries {
                if url.pathExtension == "app" {
                    let name = manager.displayName(atPath: url.path)
                    hits.append(AssistantHit(
                        kind: .app,
                        url: url,
                        name: name.hasSuffix(".app") ? String(name.dropLast(4)) : name,
                        contentType: "com.apple.application-bundle",
                        lastUsed: nil
                    ))
                    // Its own tools (Xcode's Device Hub, Simulator…), listed as Spotlight does.
                    for tools in ["Contents/Applications", "Contents/Developer/Applications"] {
                        let folder = url.appendingPathComponent(tools, isDirectory: true)
                        if manager.fileExists(atPath: folder.path) { scan(folder, depth: 0) }
                    }
                } else if depth > 0, (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    scan(url, depth: depth - 1)
                }
            }
        }
        for scope in appScopes { scan(URL(fileURLWithPath: scope), depth: 1) }
        scan(URL(fileURLWithPath: coreServicesApps), depth: 0)
        // The apps Spotlight found elsewhere (an Xcode in Downloads), from its last answer: listed
        // without asking it, so a slow or stuck index no longer loses them. Not looked at on disk
        // inside a protected folder (Downloads, Desktop, Documents) unless Siri may read files
        // there: a look would ask for the folder.
        let readsFolders = defaults.bool(forKey: AssistantModel.filesKey)
        for path in remembered(defaults) {
            let url = URL(fileURLWithPath: path)
            hits.append(AssistantHit(kind: .app, url: url, name: url.deletingPathExtension().lastPathComponent,
                                     contentType: "com.apple.application-bundle", lastUsed: nil))
            guard readsFolders || !isProtected(path) else { continue }
            for tools in ["Contents/Applications", "Contents/Developer/Applications"] {
                let folder = url.appendingPathComponent(tools, isDirectory: true)
                if manager.fileExists(atPath: folder.path) { scan(folder, depth: 0) }
            }
        }
        for path in coreServicesUserApps.union([finder]).sorted() where manager.fileExists(atPath: path) {
            let name = manager.displayName(atPath: path)
            hits.append(AssistantHit(kind: .app, url: URL(fileURLWithPath: path), name: name.hasSuffix(".app") ? String(name.dropLast(4)) : name,
                                     contentType: "com.apple.application-bundle", lastUsed: nil))
        }
        return hits
    }

    static let rememberedKey = "ni2.siriAppsElsewhere"
    /// At most this many kept (a Mac with hundreds of copies in build folders keeps a few).
    static let rememberedLimit = 200

    /// The apps outside the app folders that Spotlight's last full answer listed.
    static func remembered(_ defaults: UserDefaults = .standard) -> [String] {
        defaults.stringArray(forKey: rememberedKey) ?? []
    }

    /// Replaces the kept list with this answer's apps outside the app folders: one that is gone
    /// leaves it with the next answer.
    static func remember(_ answer: [AssistantHit], defaults: UserDefaults = .standard) {
        let elsewhere = answer.map(\.url.path).filter(isElsewhere)
        let kept = Array(elsewhere.prefix(rememberedLimit))
        guard kept != remembered(defaults) else { return }
        defaults.set(kept, forKey: rememberedKey)
        diskAppsCache.withLock { $0 = nil }
    }

    /// Not in an app folder (nor inside an app there) and not the system's: what the disk scan
    /// does not find by itself.
    static func isElsewhere(_ path: String) -> Bool {
        guard !path.hasPrefix("/System/"), embeddingApp(path) == nil else { return false }
        return !appScopes.contains { path.hasPrefix($0 + "/") }
    }

    /// In a folder macOS asks the user about before an app may look into it.
    static func isProtected(_ path: String) -> Bool {
        (["Desktop", "Documents", "Downloads"].map { NSHomeDirectory() + "/" + $0 + "/" } + [iCloudDrive + "/"])
            .contains { path.hasPrefix($0) }
    }

    /// The apps on disk, by name, without Spotlight (`AssistantSources.quickApps`).
    @concurrent static func quickApps() async -> [AssistantHit] {
        listable(cachedDiskApps()).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Apps inside another app only as its own tools (`isListedApp`); NotchIsland itself never (it
    /// is active while the assistant is open, so it would always come first).
    static func listable(_ hits: [AssistantHit]) -> [AssistantHit] {
        let own = Bundle.main.bundleURL.resolvingSymlinksInPath().path
        return hits.filter { ($0.url.deletingLastPathComponent().path.contains(".app") ? embeddingApp($0.url.path) != nil : true)
            && $0.url.resolvingSymlinksInPath().path != own }
    }

    /// Every app, most recently used first (the Applications suggestion). Apps inside other apps'
    /// bundles (helpers, Xcode's tools) are left out.
    @concurrent static func allApps() async -> [AssistantHit] {
        let predicate = #"kMDItemContentTypeTree == "com.apple.application-bundle""#
        let answer: [AssistantHit]? = await SourceDeadline.value("Spotlight", within: .seconds(5), fallback: nil) {
            query(predicate, scopes: everywhere, fetch: 4000, kind: .app)
        }
        if let answer { remember(answer) }
        let hits = listable(merged(answer ?? [], cachedDiskApps()))
        return hits.sorted { a, b in
            let da = a.lastUsed ?? .distantPast, db = b.lastUsed ?? .distantPast
            if da != db { return da > db }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    @concurrent static func files(matching query: String, limit: Int, scope: FileScope = FileScope()) async -> [AssistantHit] {
        // Desktop, Documents, Downloads and iCloud Drive are privacy-protected: the first search
        // there asks the user for access (one prompt per folder). `AssistantModel` therefore
        // reads files only once the user has asked for them.
        let term = escaped(query)
        guard !term.isEmpty, !scope.paths.isEmpty else { return [] }
        // Word starts ("q*"cdw), or anywhere in the name ("*q*"cd).
        let pattern = scope.anywhere ? "\"*\(term)*\"cd" : "\"\(term)*\"cdw"
        // Folders too, as in Spotlight (the recent list keeps to files). With the contents on,
        // also the files that say it (whole words from three letters on, as Spotlight indexes them).
        let name = "kMDItemDisplayName == \(pattern)"
        let match = scope.contents && query.count >= 3 ? "(\(name) || kMDItemTextContent == \"\(term)*\"cdw)" : name
        let predicate = "\(match) && \(notApps)"
        let hits = await run(predicate, scopes: scope.paths, fetch: max(40, limit * 3), kind: .file)
        // By name first: a file that only says the word comes after the ones called it.
        let named = hits.filter { AssistantMatch.matches($0.name, query, scope.anywhere ? .anywhere : .wordStart) }
        return Array((rank(named, for: query) + rank(hits.filter { !named.contains($0) }, for: query)).prefix(limit))
    }

    /// Files used in the last month, most recent first (the Files suggestion).
    @concurrent static func recentFiles(limit: Int = 30, scope: FileScope = FileScope()) async -> [AssistantHit] {
        guard !scope.paths.isEmpty else { return [] }
        let predicate = "kMDItemLastUsedDate >= $time.today(-\(max(1, scope.days))) && \(fileFilter)"
        let hits = await run(predicate, scopes: scope.paths, fetch: 400, kind: .file)
        let sorted = hits.sorted { ($0.lastUsed ?? .distantPast) > ($1.lastUsed ?? .distantPast) }
        return Array(sorted.prefix(limit))
    }

    private static let notApps = #"kMDItemContentTypeTree != "com.apple.application-bundle""#
    private static let fileFilter = notApps + #" && kMDItemContentType != "public.folder""#

    /// Inside something no one looks for by name: hidden folders, dependencies, build output, and
    /// the insides of packages (an app, a project, a library).
    /// An app Spotlight lists to the user: not one inside another app or package, in a Library
    /// (builds in DerivedData, helpers in Application Support, the system's agents), hidden, in the
    /// Trash or on a mounted disk image; the system's own only from its app folders and Finder.
    static func isListedApp(_ path: String) -> Bool {
        var path = path
        if path.hasPrefix("/System/Volumes/Data/") { path.removeFirst("/System/Volumes/Data".count) }
        // The tools an app carries for the user, as Spotlight lists them: Xcode's Device Hub,
        // Simulator, Instruments (in Contents/Applications or Contents/Developer/Applications).
        if let outer = embeddingApp(path) { return isListedApp(outer) }
        if path.hasPrefix("/System/") {
            return path.hasPrefix("/System/Applications/") || path.hasPrefix(coreServicesApps + "/") || path == finder
                || coreServicesUserApps.contains(path)
        }
        if path.hasPrefix("/Volumes/") || path.hasPrefix("/usr/") || path.hasPrefix("/opt/") || path.hasPrefix("/private/") { return false }
        if path.contains("/Library/") || path.contains("/.Trash/") { return false }
        return !isBuried(path)
    }

    /// The app whose own Applications folder holds `path` ("/Applications/Xcode.app" for
    /// ".../Xcode.app/Contents/Applications/DeviceHub.app"), nil otherwise.
    static func embeddingApp(_ path: String) -> String? {
        for folder in ["/Contents/Applications/", "/Contents/Developer/Applications/"] {
            guard let range = path.range(of: folder, options: .backwards), path.hasSuffix(".app") else { continue }
            let outer = String(path[..<range.lowerBound]), inner = path[range.upperBound...]
            guard outer.hasSuffix(".app"), !inner.contains("/") else { continue }
            return outer
        }
        return nil
    }

    static func isBuried(_ path: String) -> Bool {
        path.split(separator: "/").dropLast().contains { component in
            component.hasPrefix(".") || buriedFolders.contains(String(component))
                || packageExtensions.contains { component.hasSuffix($0) }
        }
    }

    static let buriedFolders: Set<String> = ["node_modules", "DerivedData", "Pods", "build", "__pycache__", "venv"]
    static let packageExtensions = [".app", ".bundle", ".framework", ".xcodeproj", ".xcworkspace", ".photoslibrary",
                                    ".musiclibrary", ".pages", ".numbers", ".key", ".rtfd", ".playground"]

    static let shortcutsTool = "/usr/bin/shortcuts"
    static let shortcutsApp = "/System/Applications/Shortcuts.app"

    /// The user's shortcuts by name (`shortcuts list`, about 40 ms).
    @concurrent static func shortcuts() async -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shortcutsTool)
        process.arguments = ["list"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return []
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return [] }
        var seen = Set<String>()
        return String(decoding: data, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// Name starts with the query first, then most recently used.
    static func rank(_ hits: [AssistantHit], for query: String) -> [AssistantHit] {
        let q = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        func prefixed(_ hit: AssistantHit) -> Bool {
            hit.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).hasPrefix(q)
        }
        return hits.sorted { a, b in
            let pa = prefixed(a), pb = prefixed(b)
            if pa != pb { return pa }
            return (a.lastUsed ?? .distantPast) > (b.lastUsed ?? .distantPast)
        }
    }

    /// Spotlight query-language escaping: backslash, quote and the wildcard.
    static func escaped(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "*", with: "\\*")
    }

    /// Spotlight's answer, waited for at most `limit` (`SourceDeadline`); none after it.
    private static func run(_ predicate: String, scopes: [String], fetch: Int, kind: AssistantHit.Kind,
                            within limit: Duration = SourceDeadline.standard) async -> [AssistantHit] {
        await SourceDeadline.value("Spotlight", within: limit, fallback: []) {
            query(predicate, scopes: scopes, fetch: fetch, kind: kind)
        }
    }

    private static func query(_ predicate: String, scopes: [String], fetch: Int, kind: AssistantHit.Kind) -> [AssistantHit] {
        guard let query = MDQueryCreate(kCFAllocatorDefault, predicate as CFString, nil, nil) else { return [] }
        MDQuerySetSearchScope(query, scopes as CFArray, 0)
        MDQuerySetMaxCount(query, fetch)
        guard MDQueryExecute(query, CFOptionFlags(kMDQuerySynchronous.rawValue)) else { return [] }
        var hits: [AssistantHit] = []
        var seen = Set<String>()
        for index in 0..<MDQueryGetResultCount(query) {
            guard let raw = MDQueryGetResultAtIndex(query, index) else { continue }
            let item = Unmanaged<MDItem>.fromOpaque(raw).takeUnretainedValue()
            guard let path = MDItemCopyAttribute(item, kMDItemPath) as? String, seen.insert(path).inserted else { continue }
            // The home folder's Library is nobody's documents (caches, containers, mail stores).
            if kind == .app ? !isListedApp(path) : (isBuried(path) || path.hasPrefix(homeLibrary)) && !path.hasPrefix(iCloudDrive) { continue }
            let url = URL(fileURLWithPath: path)
            var name = MDItemCopyAttribute(item, kMDItemDisplayName) as? String ?? url.lastPathComponent
            if kind == .app, name.hasSuffix(".app") { name.removeLast(4) }
            let type = MDItemCopyAttribute(item, kMDItemContentType) as? String
            hits.append(AssistantHit(
                kind: kind == .file && type == "public.folder" ? .folder : kind,
                url: url,
                name: name,
                contentType: type,
                lastUsed: MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
            ))
        }
        return hits
    }
}
