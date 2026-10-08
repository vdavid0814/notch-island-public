import Foundation
import Testing
@testable import NotchIslandKit

@MainActor @Suite struct NotchStyleTests {
    private func defaults() -> UserDefaults {
        let name = "NotchStyleTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func style(date: Date, columns: Int = 12) -> NotchStyle {
        let panel = PanelSettings(cell: 40, gap: 8, columns: columns, rows: 3)
        return NotchStyle(name: "", panel: panel, scale: .compact, header: .standard,
                          boards: [ExpandedPage.home.rawValue: .standard], date: date)
    }

    /// Saved styles are numbered, kept across launches whole, newest first.
    @Test func savesNumbersAndKeepsStyles() {
        let defaults = defaults()
        let store = NotchStyleStore(defaults: defaults)
        let start = Date(timeIntervalSince1970: 1_000_000)
        store.save(style(date: start))
        store.save(style(date: start.addingTimeInterval(60), columns: 14))
        #expect(store.newestFirst.map(\.name) == ["Style 2", "Style 1"])
        #expect(store.newestFirst.first?.panel.columns == 14 && store.newestFirst.first?.widgetCount == WidgetBoard.standard.widgets.count)
        let reopened = NotchStyleStore(defaults: defaults)
        #expect(reopened.styles == store.styles)
    }

    @Test func renamesAndDeletes() {
        let store = NotchStyleStore(defaults: defaults())
        let first = store.save(style(date: .now))
        store.save(style(date: .now))
        store.rename(first.id, to: "  Evening  ")
        store.rename(first.id, to: "   ")
        #expect(store.styles.first { $0.id == first.id }?.name == "Evening")
        store.delete(first.id)
        #expect(store.styles.count == 1 && store.nextName == "Style 3")
        store.deleteAll()
        #expect(store.styles.isEmpty && store.nextName == "Style 1")
    }
}
