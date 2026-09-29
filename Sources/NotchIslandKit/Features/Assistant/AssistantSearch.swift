import CoreServices
import Foundation

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
    static let coreServicesApps = "/System/Library/CoreServices/Applications"
    /// Apps are looked for everywhere Spotlight indexes, as the system's Spotlight does: an app
    /// anywhere else (an Xcode unpacked in Downloads, a game in Documents) was never found — the
    /// search kept to the three app folders (a tester's "Siri does not bring up my apps", v0.4.9).
    static let everywhere = [kMDQueryScopeComputer as String]
    static let iCloudDrive = NSHomeDirectory() + "/Library/Mobile Documents/com~apple~CloudDocs"
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
        let indexed = run(predicate, scopes: everywhere, fetch: 80, kind: .app)
        let onDisk = diskApps().filter { AssistantMatch.matches($0.name, query) }
        return Array(rank(merged(indexed, onDisk), for: query).prefix(limit))
    }

    /// Spotlight's hits, then the apps on disk it did not return (by resolved path).
    static func merged(_ indexed: [AssistantHit], _ onDisk: [AssistantHit]) -> [AssistantHit] {
        var seen = Set(indexed.map { $0.url.resolvingSymlinksInPath().path })
        return indexed + onDisk.filter { seen.insert($0.url.resolvingSymlinksInPath().path).inserted }
    }

    /// Every app in the app folders (and one folder down, like /Applications/Utilities), read
    /// from disk. Spotlight's index misses apps: on a tester's Mac 19 of 28 apps in /Applications
    /// (ChatGPT, Word, Keynote, …) were not in it, and Siri could not find them (report, v0.4.5).
    /// A directory listing of a few folders, about a millisecond.
    static func diskApps() -> [AssistantHit] {
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
                } else if depth > 0, (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    scan(url, depth: depth - 1)
                }
            }
        }
        for scope in appScopes { scan(URL(fileURLWithPath: scope), depth: 1) }
        scan(URL(fileURLWithPath: coreServicesApps), depth: 0)
        if manager.fileExists(atPath: finder) {
            hits.append(AssistantHit(kind: .app, url: URL(fileURLWithPath: finder), name: manager.displayName(atPath: finder)
                .replacingOccurrences(of: ".app", with: ""), contentType: "com.apple.application-bundle", lastUsed: nil))
        }
        return hits
    }

    /// Every app, most recently used first (the Applications suggestion). Apps inside other apps'
    /// bundles (helpers, Xcode's tools) are left out.
    @concurrent static func allApps() async -> [AssistantHit] {
        // NotchIsland itself would always come first (it is active while the assistant is open).
        let own = Bundle.main.bundleURL.resolvingSymlinksInPath().path
        let hits = merged(run(#"kMDItemContentTypeTree == "com.apple.application-bundle""#, scopes: everywhere, fetch: 4000, kind: .app),
                          diskApps())
            .filter { !$0.url.deletingLastPathComponent().path.contains(".app") && $0.url.resolvingSymlinksInPath().path != own }
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
        // Folders too, as in Spotlight (the recent list keeps to files).
        let predicate = "kMDItemDisplayName == \(pattern) && \(notApps)"
        let hits = run(predicate, scopes: scope.paths, fetch: max(40, limit * 3), kind: .file)
        return Array(rank(hits, for: query).prefix(limit))
    }

    /// Files used in the last month, most recent first (the Files suggestion).
    @concurrent static func recentFiles(limit: Int = 30, scope: FileScope = FileScope()) async -> [AssistantHit] {
        guard !scope.paths.isEmpty else { return [] }
        let predicate = "kMDItemLastUsedDate >= $time.today(-\(max(1, scope.days))) && \(fileFilter)"
        let hits = run(predicate, scopes: scope.paths, fetch: 400, kind: .file)
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
        if path.hasPrefix("/System/") {
            return path.hasPrefix("/System/Applications/") || path.hasPrefix(coreServicesApps + "/") || path == finder
        }
        if path.hasPrefix("/Volumes/") || path.hasPrefix("/usr/") || path.hasPrefix("/opt/") || path.hasPrefix("/private/") { return false }
        if path.contains("/Library/") || path.contains("/.Trash/") { return false }
        return !isBuried(path)
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

    private static func run(_ predicate: String, scopes: [String], fetch: Int, kind: AssistantHit.Kind) -> [AssistantHit] {
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
            if kind == .app ? !isListedApp(path) : isBuried(path) { continue }
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
