import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import NotchIslandKit

// MARK: - New Track

@Suite struct TrackAnnouncerTests {
    private func snapshot(_ title: String, playing: Bool = true) -> NowPlayingSnapshot {
        NowPlayingSnapshot(item: NowPlayingItem(title: title, artist: "Artist", album: "Album", duration: 200),
                           isPlaying: playing, clock: nil)
    }

    /// `isNewTrack` outside `#expect`, which cannot call a mutating member.
    private func step(_ announcer: inout TrackAnnouncer, _ snapshot: NowPlayingSnapshot?, quiet: Bool = false) -> Bool {
        announcer.isNewTrack(snapshot, quiet: quiet)
    }

    @Test func anotherTitleIsANewTrack() {
        var announcer = TrackAnnouncer()
        #expect(step(&announcer, snapshot("One")))
        #expect(step(&announcer, snapshot("Two")))
    }

    @Test func pausesResumesAndRepeatsAreNone() {
        var announcer = TrackAnnouncer()
        #expect(step(&announcer, snapshot("One")))
        #expect(!step(&announcer, snapshot("One")))
        #expect(!step(&announcer, snapshot("One", playing: false)))
        // The gap between two tracks, then the same one again.
        #expect(!step(&announcer, nil))
        #expect(!step(&announcer, snapshot("One")))
        // The same title from another source, with spaces round it.
        #expect(!step(&announcer, snapshot(" One ")))
    }

    @Test func aPausedTrackWaitsUntilItPlays() {
        var announcer = TrackAnnouncer()
        #expect(step(&announcer, snapshot("One")))
        #expect(!step(&announcer, snapshot("Two", playing: false)))
        #expect(step(&announcer, snapshot("Two")))
    }

    @Test func whatPlaysAtTheStartIsNotedNotAnnounced() {
        var announcer = TrackAnnouncer()
        #expect(!step(&announcer, snapshot("One"), quiet: true))
        #expect(!step(&announcer, snapshot("One")))
        #expect(step(&announcer, snapshot("Two")))
    }

    @Test func noTitleIsNoTrack() {
        var announcer = TrackAnnouncer()
        #expect(!step(&announcer, snapshot("  ")))
    }
}

@Suite struct TrackTitleLayoutTests {
    private let notch = CGSize(width: 185, height: 32)

    @Test func theNoticeIsThePillLowerAndWider() {
        let layout = IslandLayout(notch: notch, scale: .standard)
        let pill = layout.size(for: .compact(.nowPlaying))
        let banner = layout.size(for: .banner(.trackTitle))
        #expect(banner.width == pill.width + 2 * IslandLayout.trackTitleWidening)
        #expect(banner.height == notch.height + IslandLayout.trackTitleRowHeight)
        #expect(layout.bottomRadius(for: .banner(.trackTitle)) <= banner.height / 2)
    }

    @Test func itGrowsWithItsSize() {
        var small = IslandLayout(notch: notch, scale: .standard)
        small.trackTitleSize = 0.8
        var large = IslandLayout(notch: notch, scale: .standard)
        large.trackTitleSize = 1.3
        let a = small.size(for: .banner(.trackTitle)), b = large.size(for: .banner(.trackTitle))
        #expect(a.width < b.width && a.height < b.height)
        #expect(small.trackTitleFont < large.trackTitleFont)
        // The pill itself keeps its size.
        #expect(small.size(for: .compact(.nowPlaying)) == large.size(for: .compact(.nowPlaying)))
    }

    @Test func neverWiderThanTheScreen() {
        var layout = IslandLayout(notch: notch, scale: .standard, screen: CGSize(width: 400, height: 300))
        layout.trackTitleSize = 1.3
        #expect(layout.size(for: .banner(.trackTitle)).width <= 400 - 2 * IslandLayout.settingsSideMargin)
    }

    @Test func aNoticeNobodyClicks() {
        #expect(!BannerKind.trackTitle.isInteractive)
        #expect(!BannerKind.trackTitle.showsWhileHidden)
        #expect(IslandPresentation.banner(.trackTitle).contentKey == "banner.trackTitle")
    }

    @Test func theGlideEndsBeforeTheNoticeGoes() {
        let timing = MarqueeTitleView.Timing(hold: 0.5, speed: 32, within: 4)
        // Slow where there is time for it.
        #expect(timing.glide(64) == 2)
        // Faster where there is not: done before the notice's end.
        #expect(timing.glide(640) <= 4 - 0.5 - MarqueeTitleView.Timing.restAtEnd)
    }
}

// MARK: - Listen Again

@Suite struct ListenAgainTests {
    @Test func onlyMusicsSongsAreKept() {
        let music = NowPlayingItem(title: "Song", artist: "Artist", album: "Album", duration: 200, artworkData: nil,
                                   bundleIdentifier: ScriptablePlayer.music.bundleID)
        var video = music
        video.bundleIdentifier = "com.apple.Safari"
        var untitled = music
        untitled.title = " "
        #expect(LastPlayedTrack(music)?.title == "Song")
        #expect(LastPlayedTrack(video) == nil)
        #expect(LastPlayedTrack(untitled) == nil)
    }

    @Test func theSameSongWhateverTheDate() {
        let a = LastPlayedTrack(title: "Song", artist: "Artist", album: "Album", playedAt: .distantPast)
        let b = LastPlayedTrack(title: "Song", artist: "Artist", album: "Album")
        #expect(a.isSameSong(as: b))
        #expect(!a.isSameSong(as: LastPlayedTrack(title: "Other", artist: "Artist", album: "Album")))
    }

    @Test func titlesAreQuotedForTheScript() {
        #expect(ListenAgain.quoted(#"Say "Hi" \ Bye"#) == #""Say \"Hi\" \\ Bye""#)
        let script = ListenAgain.script(for: LastPlayedTrack(title: #"A "B""#, artist: "", album: ""))
        #expect(script.contains(#"whose name is "A \"B\"""#))
        #expect(!script.contains("artist is \"\" "))
    }

    @Test func theScriptCompilesAndOnlyShowsTheSong() {
        let source = ListenAgain.script(for: LastPlayedTrack(title: "Song", artist: "Artist", album: "Album"))
        #expect(source.contains("activate"))
        #expect(source.contains("reveal theTrack"))
        // Shown, never played (asked for).
        #expect(!source.split(separator: "\n").contains { $0.trimmingCharacters(in: .whitespaces).hasPrefix("play") })
        var error: NSDictionary?
        #expect(NSAppleScript(source: source)?.compileAndReturnError(&error) == true)
        #expect(error == nil)
    }

    @Test func aSongOutsideTheLibraryIsSearchedFor() {
        let url = ListenAgain.searchURL(for: LastPlayedTrack(title: "Song & Co", artist: "Artist", album: ""))
        #expect(url?.scheme == "music")
        #expect(url?.absoluteString.contains("term=Song%20%26%20Co%20Artist") == true)
    }

    @Test func demoRoutes() {
        #expect(AppCommand.parse(URL(string: "notchisland://demo/track?title=Hello")!) == .demo(.track("Hello")))
        #expect(AppCommand.parse(URL(string: "notchisland://demo/track")!) == .demo(.track("Island Lights")))
        #expect(AppCommand.parse(URL(string: "notchisland://demo/lastplayed")!) == .demo(.lastPlayed(true)))
        #expect(AppCommand.parse(URL(string: "notchisland://demo/lastplayed?on=0")!) == .demo(.lastPlayed(false)))
    }

    @Test func preferencesKeepTheirRanges() {
        let defaults = UserDefaults(suiteName: "TrackTitleTests.\(UUID().uuidString)")!
        defaults.set(5.0, forKey: Preferences.Key.trackTitleSize)
        defaults.set(99.0, forKey: Preferences.Key.trackTitleDuration)
        let preferences = Preferences(defaults: defaults)
        #expect(preferences.trackTitleSize == Preferences.trackTitleSizeRange.upperBound)
        #expect(preferences.trackTitleDuration == Preferences.noticeDurationRange.upperBound)
        #expect(preferences.trackTitle)
        #expect(preferences.listenAgain)
    }
}
