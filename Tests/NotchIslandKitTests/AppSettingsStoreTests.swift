import Foundation
import Testing
@testable import NotchIslandKit

@MainActor @Suite struct AppSettingsStoreTests {
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "AppSettingsStoreTests.\(UUID().uuidString)")! }

    @Test func onlyChoicesCountAsSettings() {
        for key in ["ni2.theme", "ni2.siri", "ni2.header", "ni2.widgetBoard", "ni2.widgetBoard.page.ABC", "ni2.anchor.size", "ni2.diagnostics.detailed"] {
            #expect(AppSettingsStore.isSetting(key), "\(key)")
        }
        for key in ["recentColors", "ni2.notchStyles", "ni2.widgetVersions", "ni2.appSettings", "ni2.appSettings.pending", "ni2.shelf",
                    "ni2.battery", "ni2.diagnostics.install", "ni2.telemetry.crashTimes", "ni2.widgetBoard.v2backup", "ni2.settings.pane"] {
            #expect(!AppSettingsStore.isSetting(key), "\(key)")
        }
    }

    @Test func openingPutsBackWhatWasSavedAndNothingElse() throws {
        let defaults = defaults()
        defaults.set("fade", forKey: "ni2.glassStyle")
        defaults.set(0.98, forKey: "ni2.nowPlayingWidth")
        defaults.set(Data([1, 2]), forKey: "ni2.notchStyles")
        let store = AppSettingsStore(defaults: defaults)
        let saved = try #require(store.save())
        #expect(saved.name == "Settings 1" && store.isCurrent(saved))

        defaults.set("black", forKey: "ni2.glassStyle")
        defaults.set(true, forKey: "ni2.widgetBoard.page.New")
        defaults.set(Data([3]), forKey: "ni2.notchStyles")
        #expect(!store.isCurrent(saved))

        store.openAtNextLaunch(saved)
        // Nothing yet: the next launch does it.
        #expect(defaults.string(forKey: "ni2.glassStyle") == "black")
        AppSettingsStore.applyPending(defaults: defaults)
        #expect(defaults.string(forKey: "ni2.glassStyle") == "fade")
        #expect(defaults.double(forKey: "ni2.nowPlayingWidth") == 0.98)
        #expect(defaults.object(forKey: "ni2.widgetBoard.page.New") == nil)
        #expect(defaults.data(forKey: "ni2.notchStyles") == Data([3]))
        #expect(defaults.string(forKey: AppSettingsStore.pendingKey) == nil)
        // Once.
        defaults.set("black", forKey: "ni2.glassStyle")
        AppSettingsStore.applyPending(defaults: defaults)
        #expect(defaults.string(forKey: "ni2.glassStyle") == "black")
    }

    /// What was set before is kept, in the place of the last one kept so.
    @Test func openingKeepsWhatWasSetToComeBackTo() throws {
        let defaults = defaults()
        defaults.set("fade", forKey: "ni2.glassStyle")
        let store = AppSettingsStore(defaults: defaults)
        let first = try #require(store.save())
        defaults.set("black", forKey: "ni2.glassStyle")
        store.openAtNextLaunch(first)
        #expect(store.saved.count == 2 && store.saved.filter({ $0.isAutomatic }).count == 1)
        AppSettingsStore.applyPending(defaults: defaults)
        defaults.set("liquidGlass", forKey: "ni2.glassStyle")
        store.openAtNextLaunch(first)
        #expect(store.saved.count == 2 && store.saved.filter({ $0.isAutomatic }).count == 1)
        // Renamed, it is the user's: kept.
        let automatic = try #require(store.saved.first(where: { $0.isAutomatic }))
        store.rename(automatic.id, to: "Mine")
        #expect(!store.saved.contains(where: { $0.isAutomatic }))
    }
}
