import AppKit
import Foundation
import Testing
@testable import NotchIslandKit

@Suite struct IslandThemeTests {
    @Test func defaultIsWhite() {
        #expect(IslandTheme.default.preset == .white)
        #expect(IslandTheme.default.rgb == IslandTheme.RGB(red: 1, green: 1, blue: 1))
    }

    @Test func mixBlendsInLinearLight() {
        let red = IslandTheme.RGB(red: 1, green: 0, blue: 0), blue = IslandTheme.RGB(red: 0, green: 0, blue: 1)
        #expect(red.mixed(with: blue, by: 0) == red)
        #expect(red.mixed(with: blue, by: 1) == blue)
        let half = red.mixed(with: blue, by: 0.5)
        // Half of each in linear light is ~0.735 in sRGB, not the muddy 0.5.
        #expect(abs(half.red - 0.735) < 0.01 && abs(half.blue - 0.735) < 0.01 && half.green == 0)
        var theme = IslandTheme(preset: .custom, first: red, second: blue, mix: 0.5)
        #expect(theme.rgb == half)
        theme.preset = .green
        #expect(theme.rgb == IslandTheme.RGB(NSColor.systemGreen))
    }

    @Test @MainActor func storedAndSharedAsItChanges() throws {
        let name = "theme-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = Preferences(defaults: defaults)
        #expect(preferences.theme == .default)
        let before = IslandThemeStore.shared.theme
        defer { IslandThemeStore.shared.theme = before }
        preferences.theme.preset = .purple
        #expect(IslandThemeStore.shared.theme.preset == .purple)
        #expect(Preferences(defaults: defaults).theme.preset == .purple)
    }
}
