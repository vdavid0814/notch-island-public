import Foundation

/// A file the user parked on the shelf. The shelf only ever references files — it never
/// copies, moves or deletes them.
nonisolated struct ShelfItem: Sendable, Hashable, Identifiable, Codable {
    let id: UUID
    let url: URL
    let addedAt: Date
    /// Finder's name for the file (localised, extension hidden when Finder hides it).
    var displayName: String
}

extension ShelfItem {
    /// The key two URLs must share to be the same shelf entry.
    ///
    /// Standardised (`.`/`..` removed), symlinks resolved and the trailing slash dropped,
    /// so `/var/…` vs `/private/var/…` and `Folder` vs `Folder/` (Finder hands out
    /// directory URLs with a slash; paths rebuilt from disk may not have one) collapse
    /// into one entry.
    nonisolated static func identity(of url: URL) -> String {
        var path = url.standardizedFileURL.resolvingSymlinksInPath().path(percentEncoded: false)
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        return path
    }
}
