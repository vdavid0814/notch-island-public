import Foundation
import Testing
@testable import NotchIslandKit

@MainActor @Suite struct WidgetVersionsTests {
    private func defaults() -> UserDefaults {
        let name = "WidgetVersionsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func widget(_ kind: IslandWidgetKind = .nowPlaying, column: Int = 0) -> IslandWidget {
        IslandWidget(kind: kind, frame: GridRect(column: column, row: 0, width: 7, height: 3), options: kind.defaultOptions, id: WidgetID())
    }

    /// Saved versions are numbered per kind, kept across launches, newest first.
    @Test func savesNumbersAndKeepsVersions() {
        let defaults = defaults()
        let store = WidgetVersionStore(defaults: defaults)
        let start = Date(timeIntervalSince1970: 1_000_000)
        store.save(widget(), date: start)
        store.save(widget(), date: start.addingTimeInterval(60))
        store.save(widget(.dateTime), date: start.addingTimeInterval(120))
        #expect(store.versions(of: .nowPlaying).map(\.name) == ["Version 2", "Version 1"])
        #expect(store.versions(of: .dateTime).map(\.name) == ["Version 1"])
        let reopened = WidgetVersionStore(defaults: defaults)
        #expect(reopened.versions == store.versions)
    }

    @Test func renamesAndDeletes() {
        let store = WidgetVersionStore(defaults: defaults())
        let version = store.save(widget())
        store.rename(version.id, to: "  Big title  ")
        #expect(store.versions.first?.name == "Big title")
        store.rename(version.id, to: "   ")
        #expect(store.versions.first?.name == "Big title")
        store.delete(version.id)
        #expect(store.versions.isEmpty)
    }

    /// Delete All takes the versions of one kind, not the others'.
    @Test func deletesAllOfAKind() {
        let store = WidgetVersionStore(defaults: defaults())
        store.save(widget())
        store.save(widget())
        store.save(widget(.dateTime))
        store.deleteAll(of: .nowPlaying)
        #expect(store.versions(of: .nowPlaying).isEmpty)
        #expect(store.versions(of: .dateTime).count == 1)
    }

    /// Opening a version takes its look, not its id or its place on the board.
    @Test func openingKeepsTheWidgetWhereItIs() {
        var saved = widget(column: 3)
        saved.background = .none
        saved.setOffset(ElementOffset(x: 4, y: 2), of: .artist)
        var style = TextStyle()
        style.isBold = true
        saved.setTextStyle(style, of: .trackInfo)
        let version = WidgetVersion(name: "Bold", widget: saved)
        let current = widget(column: 0)
        let opened = version.applied(to: current)
        #expect(opened.id == current.id)
        #expect(opened.frame == current.frame)
        #expect(opened.background == .none)
        #expect(opened.offset(of: .artist) == ElementOffset(x: 4, y: 2))
        #expect(opened.textStyle(of: .trackInfo).isBold)
    }
}
