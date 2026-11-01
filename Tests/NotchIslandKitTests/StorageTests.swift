import Foundation
import Testing
@testable import NotchIslandKit

/// About's Storage page: measuring and clearing, in a folder of the test's own (nothing goes to the
/// user's Trash: the moves are caught).
@Suite struct StorageTests {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "storage-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func file(_ url: URL, bytes: Int) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 7, count: bytes).write(to: url)
    }

    private func spot(_ paths: [URL], removal: StorageSpot.Removal = .contents, skipping: Set<String> = [],
                      skipsApple: Bool = false) -> StorageSpot {
        StorageSpot(id: "test", symbol: "folder", tint: .white, title: "Test", detail: "", consequence: "", category: .systemData,
                    paths: paths, verdict: .filler, removal: removal, skipping: skipping, skipsApple: skipsApple)
    }

    @Test func measuresWhatIsOnDisk() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        try file(root.appending(path: "a/one.bin"), bytes: 1 << 20)
        try file(root.appending(path: "b/two.bin"), bytes: 2 << 20)
        guard case .bytes(let bytes) = StorageScanner.measure(spot([root])) else { Issue.record("not measured"); return }
        #expect(bytes >= 3 << 20)
        #expect(bytes < 4 << 20)
    }

    @Test func leavesMacOSAndItsOwnAlone() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        try file(root.appending(path: "com.apple.Music/big.bin"), bytes: 4 << 20)
        try file(root.appending(path: "com.davidvarga.notchisland/own.bin"), bytes: 4 << 20)
        try file(root.appending(path: "com.example.app/cache.bin"), bytes: 1 << 20)
        let caches = spot([root], skipping: ["com.davidvarga.notchisland"], skipsApple: true)
        guard case .bytes(let bytes) = StorageScanner.measure(caches) else { Issue.record("not measured"); return }
        #expect(bytes < 2 << 20)

        var moved: [String] = []
        StorageScanner.remove(caches, trash: { moved.append($0.lastPathComponent) }, delete: { _ in Issue.record("deleted") })
        #expect(moved == ["com.example.app"])
    }

    @Test func movesTheFolderOrItsContents() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        try file(root.appending(path: "x.bin"), bytes: 10)
        try file(root.appending(path: "y.bin"), bytes: 10)

        var moved: [String] = []
        StorageScanner.remove(spot([root], removal: .folder), trash: { moved.append($0.lastPathComponent) }, delete: { _ in })
        #expect(moved == [root.lastPathComponent])

        moved = []
        StorageScanner.remove(spot([root]), trash: { moved.append($0.lastPathComponent) }, delete: { _ in })
        #expect(moved.sorted() == ["x.bin", "y.bin"])

        var deleted: [String] = []
        StorageScanner.remove(spot([root], removal: .emptyTrash), trash: { _ in Issue.record("moved") },
                              delete: { deleted.append($0.lastPathComponent) })
        #expect(deleted.sorted() == ["x.bin", "y.bin"])

        StorageScanner.remove(spot([root], removal: .none), trash: { _ in Issue.record("moved") }, delete: { _ in Issue.record("deleted") })
    }

    @Test func skipsWhatIsCountedElsewhere() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        try file(root.appending(path: "kept/deep/one.bin"), bytes: 1 << 20)
        try file(root.appending(path: "counted/two.bin"), bytes: 4 << 20)
        let bytes = StorageScanner.allocatedSize(of: root, skipping: [root.appending(path: "counted").standardizedFileURL.path])
        #expect(bytes >= 1 << 20)
        #expect(bytes < 2 << 20)
        #expect(StorageScanner.allocatedSize(of: root.appending(path: "counted/two.bin")) >= 4 << 20)
    }

    @Test func aMissingPlaceIsEmpty() {
        let nowhere = FileManager.default.temporaryDirectory.appending(path: "storage-missing-\(UUID().uuidString)")
        #expect(StorageScanner.measure(spot([nowhere])) == .bytes(0))
    }

    @Test func appFoldersReadAsNames() {
        #expect(StorageScanner.appName(for: "com.example.notinstalled.native") == "Notinstalled")
        #expect(StorageScanner.appName(for: "Steam") == "Steam")
    }

    @Test func fullDiskAccessIsAPermission() {
        #expect(PermissionKind.allCases.contains(.fullDiskAccess))
        #expect(PermissionKind.fullDiskAccess.pane == "Privacy_AllFiles")
        #expect(!PermissionKind.fullDiskAccess.appearsWhenAsked)
    }

    @Test func route() {
        #expect(AppCommand.parse(URL(string: "notchisland://settings/storage")!) == .showStorage)
    }
}
