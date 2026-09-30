import Foundation
import Testing
@testable import NotchIslandKit

@MainActor @Suite struct WidgetInstanceStoreTests {
    private func temporaryStore() -> WidgetInstanceStore {
        WidgetInstanceStore(root: FileManager.default.temporaryDirectory
            .appendingPathComponent("WidgetInstanceStoreTests-\(UUID().uuidString)", isDirectory: true))
    }

    @Test func dataIsKeptPerWidgetAndGoesWithIt() throws {
        let store = temporaryStore()
        let a = WidgetID(), b = WidgetID()
        try store.write(Data("a".utf8), "photo.heic", for: a)
        try store.write(Data("b".utf8), "photo.heic", for: b)
        #expect(store.read("photo.heic", for: a) == Data("a".utf8))
        store.purge(a)
        #expect(store.read("photo.heic", for: a) == nil)
        #expect(store.read("photo.heic", for: b) == Data("b".utf8))
    }

    @Test func orphansArePurgedAndOtherFoldersLeft() throws {
        let store = temporaryStore()
        let kept = WidgetID(), gone = WidgetID()
        try store.write(Data([1]), "x", for: kept)
        try store.write(Data([2]), "x", for: gone)
        let other = store.root.appendingPathComponent("not-an-id", isDirectory: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        store.purge(keeping: [kept])
        #expect(store.read("x", for: kept) == Data([1]))
        #expect(store.read("x", for: gone) == nil)
        #expect(FileManager.default.fileExists(atPath: other.path))
    }

    @Test func aDuplicateGetsItsOwnCopy() throws {
        let store = temporaryStore()
        let original = WidgetID(), copy = WidgetID()
        try store.write(Data([7]), "photo.heic", for: original)
        store.copy(from: original, to: copy)
        store.purge(original)
        #expect(store.read("photo.heic", for: copy) == Data([7]))
    }

    @Test func removingAWidgetRemovesItsFolder() async throws {
        let store = temporaryStore()
        let defaults = try #require(UserDefaults(suiteName: "WidgetInstanceStoreTests-\(UUID().uuidString)"))
        let widgets = WidgetStore(defaults: defaults, instances: store)
        let id = WidgetID.legacy(.timer)
        #expect(widgets.board.contains(id))
        try store.write(Data([3]), "x", for: id)
        widgets.remove(id)
        for _ in 0..<100 where store.read("x", for: id) != nil { try await Task.sleep(for: .milliseconds(10)) }
        #expect(store.read("x", for: id) == nil)
    }
}
