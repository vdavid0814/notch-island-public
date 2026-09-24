import CoreServices
import Foundation

/// An app or a file the assistant found for the query.
nonisolated struct AssistantHit: Sendable, Hashable, Identifiable {
    nonisolated enum Kind: Sendable, Hashable { case app, file }

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
        let hits = run(predicate, scopes: appScopes, fetch: 20, kind: .app)
        return Array(rank(hits, for: query).prefix(limit))
    }

    /// Every app, most recently used first (the Applications suggestion). Apps inside other apps'
    /// bundles (helpers, Xcode's tools) are left out.
    @concurrent static func allApps() async -> [AssistantHit] {
        // NotchIsland itself would always come first (it is active while the assistant is open).
        let own = Bundle.main.bundleURL.resolvingSymlinksInPath().path
        let hits = run(#"kMDItemContentTypeTree == "com.apple.application-bundle""#, scopes: appScopes, fetch: 2000, kind: .app)
            .filter { !$0.url.deletingLastPathComponent().path.contains(".app") && $0.url.resolvingSymlinksInPath().path != own }
        return hits.sorted { a, b in
            let da = a.lastUsed ?? .distantPast, db = b.lastUsed ?? .distantPast
            if da != db { return da > db }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    @concurrent static func files(matching query: String, limit: Int) async -> [AssistantHit] {
        // Desktop, Documents, Downloads and iCloud Drive are privacy-protected: the first search
        // there asks the user for access (one prompt per folder). `AssistantModel` therefore
        // reads files only once the user has asked for them.
        let term = escaped(query)
        guard !term.isEmpty else { return [] }
        let predicate = """
            kMDItemDisplayName == "\(term)*"cdw && \(fileFilter)
            """
        let hits = run(predicate, scopes: fileScopes, fetch: max(40, limit * 3), kind: .file)
        return Array(rank(hits, for: query).prefix(limit))
    }

    /// Files used in the last month, most recent first (the Files suggestion).
    @concurrent static func recentFiles(limit: Int = 30) async -> [AssistantHit] {
        let predicate = "kMDItemLastUsedDate >= $time.today(-30) && \(fileFilter)"
        let hits = run(predicate, scopes: fileScopes, fetch: 400, kind: .file)
        let sorted = hits.sorted { ($0.lastUsed ?? .distantPast) > ($1.lastUsed ?? .distantPast) }
        return Array(sorted.prefix(limit))
    }

    private static let fileFilter = """
        kMDItemContentTypeTree != "com.apple.application-bundle" && kMDItemContentType != "public.folder"
        """

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
            let url = URL(fileURLWithPath: path)
            var name = MDItemCopyAttribute(item, kMDItemDisplayName) as? String ?? url.lastPathComponent
            if kind == .app, name.hasSuffix(".app") { name.removeLast(4) }
            hits.append(AssistantHit(
                kind: kind,
                url: url,
                name: name,
                contentType: MDItemCopyAttribute(item, kMDItemContentType) as? String,
                lastUsed: MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
            ))
        }
        return hits
    }
}
