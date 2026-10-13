import Foundation
import Testing
@testable import NotchIslandKit

/// Settings ▸ Widgets ▸ Size sets the page it shows, not the others; Apply to All Pages makes that
/// size every page's; General's Size when Open is every page's.
@MainActor @Suite(.serialized) struct PageSizeTests {
    private static func withModel(_ body: (AppModel) throws -> Void) rethrows {
        let name = "ni2.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = Preferences(defaults: defaults)
        preferences.hapticsEnabled = false
        preferences.timerSound = false
        try body(AppModel(preferences: preferences))
    }

    @Test func sizeSetsThePageShownAlone() {
        Self.withModel { model in
            let every = model.preferences.panel
            model.studio.showPage(.timer)
            let small = PanelSettings(cell: 36, gap: 8, columns: 9, rows: 2)
            model.setPanel(small)
            #expect(model.panel(for: .timer) == small)
            #expect(model.panel(for: .home) == every)
            #expect(model.boards.store(for: .timer).board.grid == small.grid)
            #expect(model.boards.store(for: .home).board.grid == every.grid)
            // The island at the page it shows: home's size there, the timer's on its page.
            #expect(model.layout(for: .timer).panel == small.layout)
            #expect(model.layout.panel == every.layout)
            model.setScale(.large)
            #expect(model.size(of: .timer).scale == .large && model.size(of: .home).scale == model.preferences.scale)
            #expect(model.pagesDifferInSize)
        }
    }

    @Test func applyToAllPagesMakesItEveryPages() {
        Self.withModel { model in
            model.studio.showPage(.timer)
            let small = PanelSettings(cell: 36, gap: 8, columns: 9, rows: 2)
            model.setPanel(small)
            model.applySizeToAllPages()
            #expect(model.preferences.pageSizes.isEmpty)
            #expect(model.panel(for: .home) == small && model.panel(for: .timer) == small)
            #expect(model.boards.store(for: .home).board.grid == small.grid)
            #expect(!model.pagesDifferInSize)
        }
    }

    @Test func aSizeLikeEveryPagesIsNotKept() {
        Self.withModel { model in
            model.studio.showPage(.timer)
            let every = model.preferences.panel
            model.setPanel(PanelSettings(cell: 36, gap: 8, columns: 9, rows: 2))
            model.setPanel(every)
            #expect(model.preferences.pageSizes.isEmpty)
        }
    }

    @Test func generalsSizeIsEveryPages() {
        Self.withModel { model in
            model.studio.showPage(.timer)
            model.setScale(.large)
            model.setScaleEverywhere(.small)
            #expect(model.size(of: .timer).scale == .small && model.size(of: .home).scale == .small)
        }
    }

    @Test func aPageSizeComesBackAndTravelsWithAStyle() throws {
        let name = "ni2.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = Preferences(defaults: defaults)
        let size = PageSize(panel: PanelSettings(cell: 36, gap: 8, columns: 9, rows: 2), scale: .large)
        preferences.pageSizes = [ExpandedPage.timer.rawValue: size]
        #expect(Preferences(defaults: defaults).pageSizes == [ExpandedPage.timer.rawValue: size])
        // A style saved before page sizes reads as none.
        let style = NotchStyle(name: "Old", panel: PanelSettings(), scale: .standard, header: HeaderLayout(leading: [.pages], trailing: [.settings]), boards: [:])
        let old = try JSONDecoder().decode(NotchStyle.self, from: JSONEncoder().encode(style))
        #expect(old.pageSizes == nil)
    }
}
