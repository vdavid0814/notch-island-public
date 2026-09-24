import AppKit
import Foundation
import Testing
@testable import NotchIslandKit

// MARK: - AppCommand.parse

@Suite("AppCommand.parse")
struct AppCommandParseTests {
    nonisolated static let valid: [(String, AppCommand)] = [
        ("notchisland://open", .open(nil)),
        ("notchisland://open?page=home", .open(.home)),
        ("notchisland://open?page=shelf", .open(.shelf)),
        ("notchisland://open?page=timer", .open(.timer)),
        ("notchisland://close", .close),
        ("notchisland://pin", .togglePin),
        ("notchisland://settings", .showSettings),
        ("notchisland://media/play", .media(.play)),
        ("notchisland://media/pause", .media(.pause)),
        ("notchisland://media/toggle", .media(.togglePlayPause)),
        ("notchisland://media/next", .media(.next)),
        ("notchisland://media/previous", .media(.previous)),
        ("notchisland://timer", .startTimer(minutes: AppCommand.defaultTimerMinutes)),
        ("notchisland://timer?minutes=25", .startTimer(minutes: 25)),
        ("notchisland://timer?minutes=0.5", .startTimer(minutes: 0.5)),
        ("notchisland://timer?minutes=1440", .startTimer(minutes: 1440)),
        ("notchisland://timer/cancel", .cancelTimer),
        ("notchisland://stopwatch", .startStopwatch),
        ("notchisland://demo/media", .demo(.media)),
        ("notchisland://demo/charging", .demo(.charging)),
        ("notchisland://demo/unplug", .demo(.unplug)),
        ("notchisland://demo/low", .demo(.low)),
        ("notchisland://demo/timerdone", .demo(.timerDone)),
        ("notchisland://demo/drop", .demo(.drop)),
        ("notchisland://demo/shelf", .demo(.shelf)),
        ("notchisland://demo/reset", .demo(.reset)),
        ("notchisland://demo/volume", .demo(.volume(AppCommand.defaultDemoVolume))),
        ("notchisland://demo/volume?level=0.6", .demo(.volume(0.6))),
        ("notchisland://demo/volume?level=0", .demo(.volume(0))),
        ("notchisland://demo/volume?level=1", .demo(.volume(1))),
        ("notchisland://demo/brightness", .demo(.brightness(AppCommand.defaultDemoBrightness))),
        ("notchisland://demo/brightness?level=0.4", .demo(.brightness(0.4))),
        ("notchisland://demo/hover", .demo(.hover(true))),
        ("notchisland://demo/hover?inside=1", .demo(.hover(true))),
        ("notchisland://demo/hover?inside=0", .demo(.hover(false))),
        ("notchisland://demo/hover?inside=false", .demo(.hover(false))),
        ("notchisland://demo/state", .demo(.state)),
        // Case-insensitive scheme, route, parameter names and page values.
        ("NotchIsland://OPEN?Page=Shelf", .open(.shelf)),
        ("notchisland://Media/Next", .media(.next)),
        ("notchisland://demo/TimerDone", .demo(.timerDone)),
        // Without the authority slashes, and with a trailing slash.
        ("notchisland:media/next", .media(.next)),
        ("notchisland://open/", .open(nil)),
        // Unknown parameters are ignored; the first of a repeated parameter wins.
        ("notchisland://close?from=shortcut", .close),
        ("notchisland://timer?minutes=10&minutes=20", .startTimer(minutes: 10)),
    ]

    nonisolated static let invalid: [String] = [
        "https://open",
        "notchisland://",
        "notchisland://unknown",
        "notchisland://open?page=settings",
        "notchisland://open?page=",
        "notchisland://media",
        "notchisland://media/stop",
        "notchisland://media/next/extra",
        "notchisland://timer?minutes=0",
        "notchisland://timer?minutes=-5",
        "notchisland://timer?minutes=abc",
        "notchisland://timer?minutes=",
        "notchisland://timer?minutes=1441",
        "notchisland://timer?minutes=nan",
        "notchisland://timer?minutes=inf",
        "notchisland://timer/pause",
        "notchisland://demo",
        "notchisland://demo/volume?level=1.5",
        "notchisland://demo/volume?level=-0.1",
        "notchisland://demo/brightness?level=loud",
        "notchisland://demo/party",
        "notchisland://demo/hover?inside=maybe",
    ]

    @Test(arguments: valid)
    func parsesValidRoute(_ string: String, _ expected: AppCommand) throws {
        let url = try #require(URL(string: string))
        #expect(AppCommand.parse(url) == expected)
    }

    @Test(arguments: invalid)
    func rejectsInvalidRoute(_ string: String) throws {
        let url = try #require(URL(string: string))
        #expect(AppCommand.parse(url) == nil)
    }
}

// MARK: - Preferences

@Suite("Preferences")
struct PreferencesTests {
    /// A throwaway defaults domain per test.
    private static func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let name = "ni2.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }

    @Test func defaultsMatchSpec() {
        Self.withDefaults { defaults in
            let preferences = Preferences(defaults: defaults)
            #expect(preferences.openOnHover)
            #expect(preferences.hoverDelay == 0.22)
            #expect(preferences.scale == .standard)
            #expect(preferences.hapticsEnabled)
            #expect(preferences.showNowPlaying)
            #expect(preferences.showPowerAlerts)
            #expect(preferences.showLevelHUD)
            #expect(preferences.replaceSystemHUD)
            #expect(preferences.shelfEnabled)
            #expect(preferences.timerSound)
            #expect(preferences.showMenuBarIcon)
        }
    }

    @Test func writesPersistUnderPrefixedKeysAndReload() {
        Self.withDefaults { defaults in
            let preferences = Preferences(defaults: defaults)
            preferences.openOnHover = false
            preferences.hoverDelay = 0.5
            preferences.scale = .large
            preferences.hapticsEnabled = false
            preferences.showNowPlaying = false
            preferences.showPowerAlerts = false
            preferences.showLevelHUD = false
            preferences.replaceSystemHUD = false
            preferences.shelfEnabled = false
            preferences.timerSound = false
            preferences.showMenuBarIcon = false

            #expect(defaults.object(forKey: "ni2.openOnHover") as? Bool == false)
            #expect(defaults.object(forKey: "ni2.hoverDelay") as? Double == 0.5)
            #expect(defaults.string(forKey: "ni2.scale") == "large")
            #expect(defaults.object(forKey: "ni2.showMenuBarIcon") as? Bool == false)

            let reloaded = Preferences(defaults: defaults)
            #expect(!reloaded.openOnHover)
            #expect(reloaded.hoverDelay == 0.5)
            #expect(reloaded.scale == .large)
            #expect(!reloaded.hapticsEnabled)
            #expect(!reloaded.showNowPlaying)
            #expect(!reloaded.showPowerAlerts)
            #expect(!reloaded.showLevelHUD)
            #expect(!reloaded.replaceSystemHUD)
            #expect(!reloaded.shelfEnabled)
            #expect(!reloaded.timerSound)
            #expect(!reloaded.showMenuBarIcon)
        }
    }

    @Test func sanitisesStoredValues() {
        Self.withDefaults { defaults in
            defaults.set(5.0, forKey: "ni2.hoverDelay")
            defaults.set("gigantic", forKey: "ni2.scale")
            defaults.set("yes", forKey: "ni2.openOnHover")
            var preferences = Preferences(defaults: defaults)
            #expect(preferences.hoverDelay == Preferences.hoverDelayRange.upperBound)
            #expect(preferences.scale == .standard)
            #expect(preferences.openOnHover)

            defaults.set(-1.0, forKey: "ni2.hoverDelay")
            preferences = Preferences(defaults: defaults)
            #expect(preferences.hoverDelay == Preferences.hoverDelayRange.lowerBound)

            defaults.set(Double.nan, forKey: "ni2.hoverDelay")
            preferences = Preferences(defaults: defaults)
            #expect(preferences.hoverDelay == 0.22)
        }
    }

    @Test func doesNotReadLegacyKeys() {
        Self.withDefaults { defaults in
            defaults.set(0.7, forKey: "dwellDelay")
            defaults.set(false, forKey: "haptics")
            let preferences = Preferences(defaults: defaults)
            #expect(preferences.hoverDelay == 0.22)
            #expect(preferences.hapticsEnabled)
        }
    }
}

// MARK: - Haptics

@Suite("Haptics")
struct HapticsTests {
    @Test func throttlesEachEventSeparately() {
        var throttle = HapticThrottle()
        func admit(_ event: Haptics.Event, at time: TimeInterval) -> Bool { throttle.admit(event, at: time) }
        #expect(admit(.open, at: 10.000))
        // A burst of volume ticks does not swallow the close pulse that lands inside it.
        #expect(admit(.tick, at: 10.010))
        #expect(admit(.close, at: 10.020))
        #expect(!admit(.open, at: 10.100))
        #expect(admit(.open, at: 10.125))
    }

    @Test func tickAllowsFortyMilliseconds() {
        var throttle = HapticThrottle()
        func admit(_ event: Haptics.Event, at time: TimeInterval) -> Bool { throttle.admit(event, at: time) }
        #expect(admit(.tick, at: 1.000))
        #expect(!admit(.tick, at: 1.039))
        #expect(admit(.tick, at: 1.040))
        #expect(!admit(.tick, at: 1.060))
        #expect(admit(.tick, at: 1.085))
    }

    @Test func rejectedPulsesDoNotExtendTheWindow() {
        var throttle = HapticThrottle()
        func admit(_ event: Haptics.Event, at time: TimeInterval) -> Bool { throttle.admit(event, at: time) }
        #expect(admit(.alert, at: 0))
        #expect(!admit(.alert, at: 0.1))
        #expect(admit(.alert, at: 0.12))
    }

    @Test func patterns() {
        #expect(Haptics.pattern(for: .open) == .alignment)
        #expect(Haptics.pattern(for: .close) == .alignment)
        #expect(Haptics.pattern(for: .snap) == .alignment)
        #expect(Haptics.pattern(for: .tick) == .levelChange)
        #expect(Haptics.pattern(for: .drop) == .levelChange)
        #expect(Haptics.pattern(for: .alert) == .generic)
    }
}

// MARK: - System activity

@Suite("SystemActivity")
struct SystemActivityTests {
    @Test func everyEdgePairTogglesSuspension() {
        let pairs: [(ActivitySignals.Edge, ActivitySignals.Edge)] = [
            (.screensDidSleep, .screensDidWake),
            (.sessionDidResignActive, .sessionDidBecomeActive),
            (.systemWillSleep, .systemDidWake),
            (.screenLocked, .screenUnlocked),
        ]
        for (down, up) in pairs {
            var signals = ActivitySignals()
            #expect(!signals.isSuspended)
            signals.apply(down)
            #expect(signals.isSuspended)
            signals.apply(up)
            #expect(!signals.isSuspended)
        }
    }

    @Test func darkWakeKeepsSuspendedWhileScreensSleep() {
        var signals = ActivitySignals()
        signals.apply(.screensDidSleep)
        signals.apply(.systemWillSleep)
        signals.apply(.systemDidWake)   // maintenance wake: screens stay dark
        #expect(signals.isSuspended)
        signals.apply(.screensDidWake)
        #expect(!signals.isSuspended)
    }

    @Test func unlockAfterWakeResumes() {
        var signals = ActivitySignals()
        signals.apply(.screenLocked)
        signals.apply(.screensDidSleep)
        signals.apply(.screensDidWake)
        #expect(signals.isSuspended)    // lock screen still up
        signals.apply(.screenUnlocked)
        #expect(!signals.isSuspended)
    }

    @Test func thermalConstraint() {
        #expect(!SystemActivity.isConstrained(.nominal))
        #expect(!SystemActivity.isConstrained(.fair))
        #expect(SystemActivity.isConstrained(.serious))
        #expect(SystemActivity.isConstrained(.critical))
    }
}

// MARK: - Feature plan

@Suite("FeatureState")
struct FeatureStateTests {
    private func state(
        nowPlaying: Bool = true,
        webMedia: Bool = true,
        levelHUD: Bool = true,
        replaceHUD: Bool = true,
        trusted: Bool = true,
        shelf: Bool = true,
        suspended: Bool = false
    ) -> FeatureState {
        FeatureState(
            showNowPlaying: nowPlaying,
            showWebMedia: webMedia,
            showLevelHUD: levelHUD,
            replaceSystemHUD: replaceHUD,
            accessibilityTrusted: trusted,
            shelfEnabled: shelf,
            suspended: suspended
        )
    }

    @Test func firstApplicationStartsEverythingInOrder() {
        #expect(FeatureState.actions(from: nil, to: state()) == [
            .startMedia, .setWebMedia(true), .startLevels, .setInterception(true), .startDragMonitor,
            .setFullscreenMonitor(true),
        ])
    }

    @Test func firstApplicationWhileSuspendedAndUntrusted() {
        #expect(FeatureState.actions(from: nil, to: state(trusted: false, suspended: true)) == [
            .startMedia, .setWebMedia(true), .startLevels, .requestAccessibility, .startDragMonitor, .setSuspended(true),
            .setFullscreenMonitor(true),
        ])
    }

    @Test func unchangedStateDoesNothing() {
        #expect(FeatureState.actions(from: state(), to: state()).isEmpty)
    }

    @Test func stoppingDisarmsBeforeStoppingLevels() {
        #expect(FeatureState.actions(from: state(), to: .off) == [
            .stopMedia, .setWebMedia(false), .setInterception(false), .stopLevels, .stopDragMonitor,
            .setFullscreenMonitor(false),
        ])
        #expect(FeatureState.actions(from: state(suspended: true), to: .off) == [
            .stopMedia, .setWebMedia(false), .stopLevels, .stopDragMonitor, .setSuspended(false),
            .setFullscreenMonitor(false),
        ])
    }

    @Test func trustArrivingArmsInterceptionOnly() {
        let before = state(trusted: false)
        #expect(FeatureState.actions(from: nil, to: before).contains(.requestAccessibility))
        #expect(FeatureState.actions(from: before, to: state()) == [.setInterception(true)])
    }

    @Test func accessibilityIsRequestedOnRisingEdgeOnly() {
        let untrusted = state(replaceHUD: false, trusted: false)
        #expect(FeatureState.actions(from: untrusted, to: state(trusted: false)) == [.requestAccessibility])
        #expect(FeatureState.actions(from: state(trusted: false), to: state(nowPlaying: false, trusted: false)) == [.stopMedia, .setWebMedia(false)])
    }

    @Test func hidingTheLevelHUDReleasesTheKeys() {
        let hidden = state(levelHUD: false)
        #expect(!hidden.interception)
        #expect(!hidden.needsAccessibility)
        #expect(FeatureState.actions(from: state(), to: hidden) == [.setInterception(false), .stopLevels])
        #expect(FeatureState.actions(from: hidden, to: state()) == [.startLevels, .setInterception(true)])
    }

    @Test func suspensionHandsKeysBackToTheSystem() {
        #expect(FeatureState.actions(from: state(), to: state(suspended: true)) == [
            .setInterception(false), .setSuspended(true),
        ])
        #expect(FeatureState.actions(from: state(suspended: true), to: state()) == [
            .setInterception(true), .setSuspended(false),
        ])
    }

    @Test func togglingSingleFeatures() {
        #expect(FeatureState.actions(from: state(), to: state(nowPlaying: false)) == [.stopMedia, .setWebMedia(false)])
        #expect(FeatureState.actions(from: state(nowPlaying: false), to: state()) == [.startMedia, .setWebMedia(true)])
        #expect(FeatureState.actions(from: state(), to: state(webMedia: false)) == [.setWebMedia(false)])
        // Web media rides on Now Playing: with Now Playing off the preference changes nothing.
        #expect(FeatureState.actions(from: state(nowPlaying: false), to: state(nowPlaying: false, webMedia: false)).isEmpty)
        #expect(FeatureState.actions(from: state(), to: state(shelf: false)) == [.stopDragMonitor])
        #expect(FeatureState.actions(from: state(), to: state(replaceHUD: false)) == [.setInterception(false)])
    }
}

// MARK: - Menu and Settings copy

@Suite("Shell copy")
struct ShellCopyTests {
    private let english = Locale(identifier: "en_US")

    @Test func timerTitlesArePluralised() {
        #expect(MenuBarMenu.timerTitle(minutes: 1, locale: english) == "1 minute")
        #expect(MenuBarMenu.timerTitle(minutes: 5, locale: english) == "5 minutes")
        #expect(MenuBarMenu.timerTitle(minutes: 45, locale: english) == "45 minutes")
        #expect(MenuBarMenu.timerPresets == [1, 5, 10, 15, 25, 45])
    }

    @Test func hoverDelayReadsInMilliseconds() {
        #expect(SettingsFormat.hoverDelay(0.22, locale: english) == "220 ms")
        #expect(SettingsFormat.hoverDelay(0, locale: english) == "0 ms")
        #expect(SettingsFormat.hoverDelay(0.8, locale: english) == "800 ms")
    }

    @Test func mediaStatus() {
        #expect(SettingsFormat.mediaStatus(.on(web: .listening, automationIssue: nil), enabled: false).tone == .neutral)
        #expect(SettingsFormat.mediaStatus(.off, enabled: true).tone == .neutral)
        #expect(SettingsFormat.mediaStatus(.on(web: .listening, automationIssue: nil), enabled: true).title
                == "Music, Spotify and browsers")
        #expect(SettingsFormat.mediaStatus(.on(web: .standby, automationIssue: nil), enabled: true).tone == .ok)
        #expect(SettingsFormat.mediaStatus(.on(web: .off, automationIssue: nil), enabled: true).tone == .ok)
        #expect(SettingsFormat.mediaStatus(.on(web: .notInstalled, automationIssue: nil), enabled: true).tone == .attention)
        #expect(SettingsFormat.mediaStatus(.on(web: .retrying, automationIssue: nil), enabled: true).tone == .attention)
        let denied = SettingsFormat.mediaStatus(.on(web: .standby, automationIssue: "Automation denied"), enabled: true)
        #expect(denied.tone == .attention)
        #expect(denied.detail == "Automation denied")
    }

    @Test func interceptionStatus() {
        #expect(SettingsFormat.interceptionStatus(.off).tone == .neutral)
        #expect(SettingsFormat.interceptionStatus(.needsPermission).tone == .attention)
        #expect(SettingsFormat.interceptionStatus(.active).tone == .ok)
        #expect(SettingsFormat.interceptionStatus(.failed("tap refused")).detail == "tap refused")
    }

    @Test func version() {
        #expect(SettingsFormat.version(nil) == "Development build")
        #expect(SettingsFormat.version(["CFBundleShortVersionString": "2.0.0"]) == "Version 2.0.0")
        #expect(SettingsFormat.version(["CFBundleShortVersionString": "2.0.0", "CFBundleVersion": "1"]) == "Version 2.0.0 (1)")
    }

    @Test func settingsSections() {
        #expect(SettingsSection.allCases.map(\.title) == ["General", "Activities", "Permissions", "About"])
        for section in SettingsSection.allCases {
            #expect(NSImage(systemSymbolName: section.systemImage, accessibilityDescription: nil) != nil)
        }
    }

    @Test func menuSymbolsExist() {
        let symbols = [
            "capsule.tophalf.filled", "rectangle.topthird.inset.filled", "pin", "timer", "xmark.circle", "stopwatch",
            "music.note", "play.fill", "pause.fill", "forward.fill", "backward.fill", "gearshape",
            "checkmark.circle.fill", "exclamationmark.triangle.fill", "minus.circle.fill",
        ]
        for symbol in symbols {
            #expect(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil, "\(symbol)")
        }
    }
}

// MARK: - AppModel wiring

@Suite("AppModel wiring")
struct AppModelWiringTests {
    /// A model on a throwaway defaults domain, with the side effects a test must not cause (a
    /// trackpad pulse, a sound) switched off.
    private static func withModel(_ body: (AppModel) throws -> Void) rethrows {
        let name = "ni2.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = Preferences(defaults: defaults)
        preferences.hapticsEnabled = false
        preferences.timerSound = false
        try body(AppModel(preferences: preferences))
    }

    @Test func powerEventsPostBannersWhenEnabled() {
        Self.withModel { model in
            model.power.onEvent?(.connected)
            #expect(model.banners.current == .power(.connected))
        }
        Self.withModel { model in
            model.preferences.showPowerAlerts = false
            model.power.onEvent?(.low(threshold: 10))
            #expect(model.banners.current == nil)
        }
    }

    @Test func levelChangesFromTheIslandDoNotPostBanners() {
        Self.withModel { model in
            model.levels.onChange?(.volume, .island)
            #expect(model.banners.current == nil)
            model.levels.onChange?(.brightness, .external)
            #expect(model.banners.current == .level(.brightness))
            model.levels.onChange?(.volume, .key)
            #expect(model.banners.current == .level(.volume))
        }
        Self.withModel { model in
            model.preferences.showLevelHUD = false
            model.levels.onChange?(.volume, .key)
            #expect(model.banners.current == nil)
        }
    }

    @Test func finishedTimerPostsBanner() {
        Self.withModel { model in
            model.timers.onFinished?()
            #expect(model.banners.current == .timerFinished)
        }
    }

    @Test func layoutFollowsScaleAndFallsBackWithoutScreen() {
        Self.withModel { model in
            #expect(model.metrics == nil)
            #expect(model.layout.notch == AppModel.fallbackNotchSize)
            model.preferences.scale = .large
            #expect(model.layout.scale == .large)
        }
    }
}
