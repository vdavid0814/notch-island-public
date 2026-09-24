import CoreGraphics
import Foundation
import Testing
@testable import NotchIslandKit

@Suite struct FullscreenDetectionTests {
    let screen = CGRect(x: 0, y: 0, width: 1280, height: 832)
    typealias Window = FullscreenMonitor.WindowInfo

    func window(_ pid: pid_t, _ bounds: CGRect, owner: String = "App", layer: Int = 0, alpha: Double = 1) -> Window {
        Window(pid: pid, owner: owner, layer: layer, alpha: alpha, bounds: bounds)
    }

    /// The window manager's wallpaper (every space) and full-screen backdrop (full-screen spaces).
    var wallpaper: Window { window(2, screen, owner: "WindowManager", layer: -2147483624) }
    var backdrop: Window { window(2, screen, owner: "WindowManager", layer: -2147483622) }

    @Test func fullScreenWindowBelowTheMenuBarCountsInAFullScreenSpace() {
        // Measured: a native full-screen window on a 28-pt notch starts below the 29-pt menu bar.
        let video = window(10, CGRect(x: 0, y: 29, width: 1280, height: 803))
        #expect(FullscreenMonitor.fullscreenOwners([video, backdrop, wallpaper], screen: screen, band: 29, excluding: 1) == [10])
        let borderless = window(11, screen)
        #expect(FullscreenMonitor.fullscreenOwners([video, borderless, backdrop, wallpaper], screen: screen, band: 29,
                                                    excluding: 1) == [10, 11])
    }

    @Test func zoomedWindowOnADesktopIsNotFullScreen() {
        // With the Dock hidden, a zoomed window has the same bounds, but there is no backdrop.
        let zoomed = window(10, CGRect(x: 0, y: 29, width: 1280, height: 803))
        #expect(FullscreenMonitor.fullscreenOwners([zoomed, wallpaper], screen: screen, band: 29, excluding: 1).isEmpty)
        // A borderless window covering the whole screen counts without one.
        let borderless = window(11, screen)
        #expect(FullscreenMonitor.fullscreenOwners([borderless, wallpaper], screen: screen, band: 29, excluding: 1) == [11])
    }

    @Test func ordinaryWindowsDoNotCount() {
        let menuBar = window(11, screen, layer: 24)
        let invisible = window(12, screen, alpha: 0)
        let ours = window(1, screen)
        let otherScreen = window(13, CGRect(x: 1280, y: 0, width: 1920, height: 1080))
        let short = window(14, CGRect(x: 0, y: 60, width: 1280, height: 772))
        #expect(FullscreenMonitor.fullscreenOwners([menuBar, invisible, ours, otherScreen, short, backdrop, wallpaper],
                                                    screen: screen, band: 29, excluding: 1).isEmpty)
    }

    @Test func hiddenIslandShowsNothingByItselfButAnswersKeysAndStillOpens() {
        var inputs = IslandInputs()
        inputs.banner = .timerFinished
        inputs.nowPlayingActive = true
        inputs.isDragInProgress = true
        inputs.isHidden = true
        #expect(IslandResolver.resolve(inputs) == .idle)
        inputs.banner = .power(.connected)
        #expect(IslandResolver.resolve(inputs) == .idle)
        // A key press's level, and the Siri glow, answer the user even over a full-screen video.
        inputs.banner = .level(.volume)
        #expect(IslandResolver.resolve(inputs) == .banner(.level(.volume)))
        inputs.wantsExpanded = true
        #expect(IslandResolver.resolve(inputs) == .expanded(.home))
        // The assistant outranks everything, the open panel and hiding included.
        inputs.wantsAssistant = true
        #expect(IslandResolver.resolve(inputs) == .assistant(.field))
        inputs.assistantRoom = .list
        #expect(IslandResolver.resolve(inputs) == .assistant(.list))
    }

    @Test func hidingKeepsTheKeys() {
        func state(fullscreen: Bool, pref: Bool = true) -> FeatureState {
            FeatureState(showNowPlaying: true, showLevelHUD: true, replaceSystemHUD: true, accessibilityTrusted: true,
                         shelfEnabled: true, suspended: false, hideInFullscreen: pref, fullscreenActive: fullscreen)
        }
        #expect(state(fullscreen: true).hidden && state(fullscreen: true).interception)
        #expect(FeatureState.actions(from: state(fullscreen: false), to: state(fullscreen: true)) == [.setHidden(true)])
        #expect(!state(fullscreen: true, pref: false).hidden)
        // The monitor keeps running without the preference: the menu-bar guard needs it.
        #expect(FeatureState.actions(from: state(fullscreen: false), to: state(fullscreen: false, pref: false)).isEmpty)
    }

    @Test func menuBarGuardFeature() {
        let present = FeatureState(showNowPlaying: true, showLevelHUD: true, replaceSystemHUD: true,
                                   accessibilityTrusted: true, shelfEnabled: true, suspended: false,
                                   hideInFullscreen: false, fullscreenActive: false, fullscreenPresent: true)
        #expect(present.fullscreenPresent && !present.hidden && present.interception)
        #expect(FeatureState.actions(from: nil, to: present).contains(.setFullscreenPresent(true)))
    }

    @Test func siriRoute() {
        #expect(AppCommand.parse(URL(string: "notchisland://siri")!) == .assistant)
        #expect(AppCommand.parse(URL(string: "notchisland://assistant")!) == .assistant)
    }
}

@Suite struct BandCoverPolicyTests {
    // AppKit coordinates: the screen is 0…832 tall, the 30-pt covered band 802…832, the notch 562…718.
    let geometry = BandCoverPolicy.Geometry(
        screen: CGRect(x: 0, y: 0, width: 1280, height: 832),
        band: 30,
        notch: CGRect(x: 562, y: 804, width: 156, height: 28)
    )
    let t0 = Date(timeIntervalSinceReferenceDate: 0)

    func decide(_ x: CGFloat, _ y: CGFloat, open: Bool = false, _ state: inout BandCoverPolicy.State,
                at seconds: TimeInterval = 0) -> BandCoverPolicy.Decision {
        BandCoverPolicy.decide(pointer: CGPoint(x: x, y: y), geometry: geometry, islandOpen: open, state: &state,
                               now: t0.addingTimeInterval(seconds))
    }

    @Test func zoneReachesBesideAndBelowTheNotch() {
        // The notch ± 48 (just past the compact pill), from 120 pt below the band to the top.
        #expect(geometry.zone == CGRect(x: 514, y: 682, width: 252, height: 150))
        #expect(geometry.bandRect == CGRect(x: 0, y: 802, width: 1280, height: 30))
    }

    @Test func coversOnApproachAndKeepsItWhileInTheBand() {
        var state = BandCoverPolicy.State()
        #expect(!decide(640, 400, &state).covered)
        #expect(decide(700, 700, &state).covered)               // approaching, still below the band
        #expect(decide(1000, 820, &state).covered)              // sideways along the band, near
        #expect(decide(640, 830, &state).covered)
    }

    @Test func releasesOnlyOnceThePointerIsOutOfTheZoneForAMoment() {
        var state = BandCoverPolicy.State()
        _ = decide(640, 830, &state)
        let leaving = decide(640, 600, &state, at: 1)
        #expect(leaving.covered && leaving.recheckAfter != nil)
        #expect(decide(640, 600, &state, at: 1.2).covered == false)
        // A pointer that goes back up before the hold ends keeps it.
        var other = BandCoverPolicy.State()
        _ = decide(640, 830, &other)
        _ = decide(640, 600, &other, at: 1)
        #expect(decide(640, 820, &other, at: 1.1).covered)
        #expect(decide(640, 600, &other, at: 1.2).covered)      // the hold starts again
    }

    @Test func lingeringNearTheNotchNeverFlickers() {
        var state = BandCoverPolicy.State()
        _ = decide(640, 830, &state)
        #expect(decide(640, 740, &state, at: 1).covered)
        #expect(decide(645, 740, &state, at: 2).covered)
        #expect(decide(650, 745, &state, at: 3).recheckAfter == nil)
    }

    @Test func aDisplayAboveIsNotTheBand() {
        var state = BandCoverPolicy.State()
        _ = decide(640, 1200, &state)                               // above the notch, on the upper display
        _ = decide(60, 1200, &state, at: 1)
        _ = decide(60, 1200, &state, at: 1.6)                       // resting far away there: no menu-bar trip
        #expect(decide(640, 820, &state, at: 2).covered)            // coming down into the notch: guarded
    }

    @Test func aMenuBarReachedAwayFromTheNotchStaysUsable() {
        var state = BandCoverPolicy.State()
        #expect(!decide(60, 820, &state).covered)
        #expect(!decide(400, 820, &state, at: 1).covered)           // sliding along it into the zone
        #expect(!decide(400, 790, &state, at: 2).covered)           // the top of an open menu
        #expect(!decide(640, 500, &state, at: 3).covered)           // left it…
        #expect(decide(640, 700, &state, at: 4).covered)            // …so the notch is guarded again
    }

    @Test func staysWhileTheIslandIsOpen() {
        var state = BandCoverPolicy.State()
        _ = decide(640, 830, &state)
        #expect(decide(640, 300, open: true, &state, at: 5).covered)
    }

    @Test func yieldsToADeliberateTripToTheMenuBar() {
        var state = BandCoverPolicy.State()
        _ = decide(640, 830, &state)
        #expect(decide(60, 820, &state, at: 1).covered)          // far along the band…
        #expect(!decide(60, 820, &state, at: 1.6).covered)       // …for a moment: the menu bar is wanted
        #expect(!decide(600, 820, &state, at: 2).covered)        // and stays usable while in the band
        #expect(!decide(600, 500, &state, at: 3).covered)        // until the pointer leaves it
        #expect(decide(640, 700, &state, at: 4).covered)         // then the notch is guarded again
    }
}

@Suite struct MediaKeyPressTrackerTests {
    let policy = MediaKeyPolicy(volume: true, mute: true, brightness: true)

    func event(_ key: MediaKey, down: Bool, repeating: Bool = false) -> MediaKeyEvent {
        MediaKeyEvent(key: key, isDown: down, isRepeat: repeating, isFine: false)
    }

    @Test func aPressEndsWhereItBegan() {
        var tracker = MediaKeyPressTracker()
        // Taken press: down handled, up swallowed.
        #expect(tracker.action(for: event(.volumeUp, down: true), policy: policy) == .handle)
        #expect(tracker.action(for: event(.volumeUp, down: false), policy: policy) == .swallow)
        // A press the system began before the tap: its repeats and its release stay the system's.
        #expect(tracker.action(for: event(.brightnessUp, down: true, repeating: true), policy: policy) == .passThrough)
        #expect(tracker.action(for: event(.brightnessUp, down: false), policy: policy) == .passThrough)
        // A held mute key is still swallowed on repeat.
        #expect(tracker.action(for: event(.mute, down: true), policy: policy) == .handle)
        #expect(tracker.action(for: event(.mute, down: true, repeating: true), policy: policy) == .swallow)
        #expect(tracker.action(for: event(.mute, down: false), policy: policy) == .swallow)
    }
}
