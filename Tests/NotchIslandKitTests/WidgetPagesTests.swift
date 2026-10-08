import Foundation
import Testing
@testable import NotchIslandKit

/// The pages of widgets: the island's own as boards, and the pages the user adds.
@MainActor @Suite struct WidgetPagesTests {
    private func defaults() -> (UserDefaults, String) {
        let name = "notchisland.tests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    @Test func aPageOfTheUsersIsNamedAndReadsBack() throws {
        var header = HeaderLayout.standard
        let added = header.addCustomPage(title: header.nextCustomTitle)
        let page = try #require(added)
        #expect(page.isCustom && page.isBoard)
        #expect(ExpandedPage(rawValue: page.rawValue) == page)
        #expect(header.customPage(page)?.title == "Page 2")
        #expect(header.orderedPages.last == page)
        header.editCustomPage(page, title: "  Work ", symbol: "briefcase")
        #expect(header.customPage(page)?.title == "Work" && header.customPage(page)?.symbol == "briefcase")
        // An empty name keeps the one it had.
        header.editCustomPage(page, title: "   ")
        #expect(header.customPage(page)?.title == "Work")

        let decoded = try JSONDecoder().decode(HeaderLayout.self, from: JSONEncoder().encode(header))
        #expect(decoded == header)
        #expect(decoded.pages(among: ExpandedPage.allCases + [page]).contains(page))
    }

    @Test func pagesStopAtTheLimitAndGoAwayWithTheirPlace() {
        var header = HeaderLayout.standard
        let pages = (0..<CustomPage.limit).compactMap { _ in header.addCustomPage(title: header.nextCustomTitle) }
        #expect(pages.count == CustomPage.limit)
        #expect(Set(header.customPages.map(\.title)).count == CustomPage.limit)
        #expect(header.addCustomPage(title: "One too many") == nil)
        _ = header.setPage(pages[0], hidden: true, among: ExpandedPage.allCases + pages)
        header.removeCustomPage(pages[0])
        #expect(!header.orderedPages.contains(pages[0]) && !header.hiddenPages.contains(pages[0]))
    }

    /// Only the island's own names and `page.<UUID>` are pages: a name a later version might use
    /// is not taken for one.
    @Test func aNameIsAPageOnlyWhenItIsOne() {
        #expect(ExpandedPage(rawValue: "battery") == .battery)
        #expect(ExpandedPage(rawValue: "page.not-a-uuid") == nil)
        #expect(ExpandedPage(rawValue: "weather") == nil)
    }

    @Test func eachPageKeepsItsOwnBoard() throws {
        let (store, name) = defaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }
        let home = WidgetStore(defaults: store)
        let pages = WidgetPages(home: home, defaults: store)
        let custom = ExpandedPage.newCustom()
        pages.sync([.home, .timer, .battery, custom])
        #expect(pages.store(for: .home) === home)
        #expect(pages.store(for: .shelf) === home)
        #expect(pages.store(for: .timer).board.widgets.isEmpty)
        #expect(pages.store(for: custom).board.widgets.isEmpty)

        let clock = pages.store(for: custom).add(.dateTime)
        let added = try #require(clock)
        #expect(pages.page(containing: added) == custom)
        #expect(!home.board.contains(added))
        pages.flush()
        #expect(store.data(forKey: WidgetPages.key(for: custom)) != nil)

        // A page taken away takes its board with it.
        pages.sync([.home, .timer, .battery])
        #expect(store.data(forKey: WidgetPages.key(for: custom)) == nil)
        #expect(pages.page(containing: added) == nil)
    }
}
