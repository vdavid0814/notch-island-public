import AppKit
import Foundation
import Testing
@testable import NotchIslandKit

// Pure media logic only. Nothing here starts a source, spawns perl or sends an Apple Event (that would
// pop Automation prompts); sources are exercised through their pure parsers and reducers.

private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

private func item(_ title: String = "Midnight City", duration: TimeInterval? = 243, artwork: Data? = nil) -> NowPlayingItem {
    NowPlayingItem(title: title, artist: "M83", album: "Hurry Up, We're Dreaming", duration: duration,
                   artworkData: artwork, bundleIdentifier: "com.apple.Music")
}

private func line(_ json: String) -> Data { Data(json.utf8) }

// MARK: - PlaybackClock

@Suite struct PlaybackClockTests {
    @Test func advancesAtRateWhilePlaying() {
        let clock = PlaybackClock(elapsed: 30, at: t0, rate: 1)
        #expect(clock.position(at: t0.addingTimeInterval(12)) == 42)
        let fast = PlaybackClock(elapsed: 30, at: t0, rate: 1.5)
        #expect(fast.position(at: t0.addingTimeInterval(10)) == 45)
    }

    @Test func pausedClockIsConstant() {
        let clock = PlaybackClock(elapsed: 30, at: t0, rate: 0)
        #expect(clock.position(at: t0.addingTimeInterval(500)) == 30)
    }

    @Test func clampsToZeroAndDuration() {
        let clock = PlaybackClock(elapsed: 5, at: t0, rate: 1)
        #expect(clock.position(at: t0.addingTimeInterval(-60)) == 0)
        #expect(clock.position(at: t0.addingTimeInterval(1000), duration: 243) == 243)
        #expect(clock.position(at: t0.addingTimeInterval(1000), duration: nil) == 1005)
    }

    @Test func reanchoringKeepsTheTimeline() {
        let clock = PlaybackClock(elapsed: 10, at: t0, rate: 1)
        let moved = clock.reanchored(at: t0.addingTimeInterval(5), rate: 1)
        #expect(moved.elapsed == 15)
        #expect(moved.isEquivalent(to: clock))
        #expect(clock.isEquivalent(to: moved))
    }

    @Test func equivalenceRejectsSeeksAndRateChanges() {
        let clock = PlaybackClock(elapsed: 10, at: t0, rate: 1)
        #expect(!clock.isEquivalent(to: PlaybackClock(elapsed: 11, at: t0, rate: 1)))
        #expect(!clock.isEquivalent(to: PlaybackClock(elapsed: 10, at: t0, rate: 0)))
        #expect(clock.isEquivalent(to: PlaybackClock(elapsed: 10.1, at: t0, rate: 1)))
    }
}

// MARK: - Snapshot dedupe & optimistic updates

@Suite struct SnapshotTests {
    let playing = NowPlayingSnapshot(item: item(), isPlaying: true, clock: PlaybackClock(elapsed: 30, at: t0, rate: 1))

    @Test func dedupeComparesTheFullItem() {
        var later = playing
        later.clock = playing.clock?.reanchored(at: t0.addingTimeInterval(3), rate: 1)
        #expect(playing.isEquivalent(to: later))

        var withDuration = playing
        withDuration.item.duration = 250
        #expect(!playing.isEquivalent(to: withDuration))

        var newArtwork = playing
        newArtwork.item.artworkData = Data([1, 2, 3])
        #expect(!playing.isEquivalent(to: newArtwork))
        var otherArtwork = newArtwork
        otherArtwork.item.artworkData = Data([4, 5, 6])
        #expect(!newArtwork.isEquivalent(to: otherArtwork))

        var album = playing
        album.item.album = "Saturdays = Youth"
        #expect(!playing.isEquivalent(to: album))

        var smallSeek = playing
        smallSeek.clock = PlaybackClock(elapsed: 30.8, at: t0, rate: 1)
        #expect(!playing.isEquivalent(to: smallSeek))
    }

    @Test func togglePausesAtTheCurrentPosition() {
        let paused = playing.applying(.togglePlayPause, at: t0.addingTimeInterval(10))
        #expect(!paused.isPlaying)
        #expect(paused.clock?.rate == 0)
        #expect(paused.clock?.position(at: t0.addingTimeInterval(100)) == 40)

        let resumed = paused.applying(.play, at: t0.addingTimeInterval(100))
        #expect(resumed.isPlaying)
        #expect(resumed.clock?.position(at: t0.addingTimeInterval(105)) == 45)
    }

    @Test func pauseAndPlayAreIdempotent() {
        let paused = playing.applying(.pause, at: t0).applying(.pause, at: t0.addingTimeInterval(4))
        #expect(!paused.isPlaying)
        #expect(paused.clock?.position(at: t0.addingTimeInterval(9)) == 30)
    }

    @Test func nextAndPreviousRestartTheClock() {
        let next = playing.applying(.next, at: t0.addingTimeInterval(20))
        #expect(next.clock == PlaybackClock(elapsed: 0, at: t0.addingTimeInterval(20), rate: 1))
        #expect(next.item == playing.item)
        let pausedPrevious = playing.applying(.pause, at: t0).applying(.previous, at: t0)
        #expect(pausedPrevious.clock?.rate == 0)
        #expect(pausedPrevious.clock?.elapsed == 0)
    }

    @Test func seekClampsToTheTrack() {
        #expect(playing.applying(.seek(500), at: t0).clock?.elapsed == 243)
        #expect(playing.applying(.seek(-3), at: t0).clock?.elapsed == 0)
        let live = NowPlayingSnapshot(item: item(duration: nil), isPlaying: false, clock: nil)
        #expect(live.applying(.seek(90), at: t0).clock == PlaybackClock(elapsed: 90, at: t0, rate: 0))
    }
}

// MARK: - Adapter stream framing

@Suite struct LineFramerTests {
    @Test func reassemblesLinesAcrossChunks() {
        var framer = LineFramer()
        let lines = framer.append(line("{\"a\":"))
        #expect(lines.isEmpty)
        let lines2 = framer.append(line("1}\n{\"b\":2}\n{\"c\""))
        #expect(lines2 == [line("{\"a\":1}"), line("{\"b\":2}")])
        let lines3 = framer.append(line(":3}\n"))
        #expect(lines3 == [line("{\"c\":3}")])
    }

    @Test func skipsEmptyLines() {
        var framer = LineFramer()
        let lines = framer.append(line("\n\n{}\n\n"))
        #expect(lines == [line("{}")])
    }

    @Test func dropsOnlyTheOversizedLine() {
        var framer = LineFramer(maxLineLength: 8)
        let lines = framer.append(line("{\"ok\":1}\n0123456789"))
        #expect(lines.count == 1)
        #expect(framer.droppedLines == 1)
        // The rest of the oversized line is discarded up to its newline; the next line survives.
        let lines2 = framer.append(line("abcdef\n{\"x\":2}\n"))
        #expect(lines2 == [line("{\"x\":2}")])
        let lines3 = framer.append(line("0123456789ABCDEF\n{}\n"))
        #expect(lines3 == [line("{}")])
        #expect(framer.droppedLines == 2)
    }
}

// MARK: - Adapter JSON

@Suite struct AdapterParsingTests {
    let now = t0

    @Test func parsesAFullSnapshot() throws {
        let art = Data([0x89, 0x50, 0x4E, 0x47]).base64EncodedString()
        let update = try #require(AdapterUpdate.parse(line("""
        {"type":"data","diff":false,"payload":{"title":"Song","artist":"Artist","album":"Album",\
        "duration":200.5,"elapsedTime":12,"timestamp":\((t0.timeIntervalSince1970 - 2) * 1000),\
        "playbackRate":1,"playing":true,"artworkData":"\(art)","bundleIdentifier":"com.apple.WebKit.GPU",\
        "parentApplicationBundleIdentifier":"com.apple.Safari","uniqueIdentifier":42}}
        """)))
        var state = AdapterTrackState()
        state.apply(update, receivedAt: now)
        let snapshot = try #require(state.snapshot)
        #expect(snapshot.item.title == "Song")
        #expect(snapshot.item.duration == 200.5)
        #expect(snapshot.item.artworkData == Data([0x89, 0x50, 0x4E, 0x47]))
        #expect(snapshot.item.bundleIdentifier == "com.apple.Safari")
        #expect(snapshot.isPlaying)
        #expect(state.uniqueIdentifier == "42")
        // Anchored at the adapter's timestamp (2 s before `now`), so the position already moved on.
        let position = try #require(snapshot.clock?.position(at: now))
        #expect(abs(position - 14) < 0.01)
    }

    @Test func diffsMergeAndNullClears() throws {
        var state = AdapterTrackState()
        state.apply(try #require(AdapterUpdate.parse(line("""
        {"diff":false,"payload":{"title":"A","artist":"X","uniqueIdentifier":"id-1","duration":100,"playing":true,"elapsedTime":0}}
        """))), receivedAt: now)
        state.apply(try #require(AdapterUpdate.parse(line("""
        {"diff":true,"payload":{"playing":false,"uniqueIdentifier":null}}
        """))), receivedAt: now)
        #expect(state.title == "A")
        #expect(state.duration == 100)
        #expect(state.isPlaying == false)
        #expect(state.uniqueIdentifier == nil)   // not the string "<null>"
        #expect(state.snapshot?.clock?.rate == 0)
    }

    @Test func fullUpdateReplacesState() throws {
        var state = AdapterTrackState()
        state.apply(try #require(AdapterUpdate.parse(line(#"{"payload":{"title":"A","album":"B"}}"#))), receivedAt: now)
        state.apply(try #require(AdapterUpdate.parse(line(#"{"diff":false,"payload":{"title":"C"}}"#))), receivedAt: now)
        #expect(state.album == nil)
        state.apply(try #require(AdapterUpdate.parse(line(#"{"diff":false,"payload":null}"#))), receivedAt: now)
        #expect(state.snapshot == nil)
    }

    @Test func topLevelObjectWithoutPayloadIsAccepted() throws {
        var state = AdapterTrackState()
        state.apply(try #require(AdapterUpdate.parse(line(#"{"title":"Bare","playing":true}"#))), receivedAt: now)
        #expect(state.snapshot?.item.title == "Bare")
        // Playing without a position: no clock rather than an invented one.
        #expect(state.snapshot?.clock == nil)
    }

    @Test func emptyTitleMeansNothingPlaying() throws {
        var state = AdapterTrackState()
        state.apply(try #require(AdapterUpdate.parse(line(#"{"payload":{"title":"","playing":true}}"#))), receivedAt: now)
        #expect(state.snapshot == nil)
    }

    @Test func elapsedWithoutTimestampAnchorsOnArrival() throws {
        var state = AdapterTrackState()
        state.apply(try #require(AdapterUpdate.parse(line(#"{"payload":{"title":"A","elapsedTime":50,"playing":true,"playbackRate":0}}"#))), receivedAt: now)
        let clock = try #require(state.snapshot?.clock)
        #expect(clock.at == now)
        #expect(clock.rate == 1)   // playing with a reported rate of 0 still advances
    }

    @Test func timestampUnits() {
        let seconds = 1_790_000_000.0
        #expect(AdapterUpdate.epochDate(seconds).timeIntervalSince1970 == seconds)
        #expect(AdapterUpdate.epochDate(seconds * 1_000).timeIntervalSince1970 == seconds)
        #expect(AdapterUpdate.epochDate(seconds * 1_000_000).timeIntervalSince1970 == seconds)
    }

    @Test func microsecondKeysAndISODates() throws {
        let micros = try #require(AdapterUpdate.parse(line("""
        {"payload":{"title":"A","durationMicros":180000000,"elapsedTimeMicros":1500000,"timestampEpochMicros":1790000000000000}}
        """)))
        #expect(micros.duration == .value(180))
        #expect(micros.elapsed == .value(1.5))
        #expect(micros.timestamp == .value(Date(timeIntervalSince1970: 1_790_000_000)))
        let iso = try #require(AdapterUpdate.parse(line(#"{"payload":{"timestamp":"2026-09-21T10:00:00Z"}}"#)))
        #expect(iso.timestamp == .value(Date(timeIntervalSince1970: 1_789_984_800)))
    }

    @Test func rejectsNonObjects() {
        #expect(AdapterUpdate.parse(line("not json")) == nil)
        #expect(AdapterUpdate.parse(line("[1,2]")) == nil)
        #expect(AdapterUpdate.parse(line("{\"title\":\"trunc")) == nil)
        #expect(AdapterUpdate.parse(line(#"{"type":"error","payload":{}}"#)) == nil)
    }

    @Test func optimisticStateSurvivesUnrelatedDiffs() throws {
        var state = AdapterTrackState()
        state.apply(try #require(AdapterUpdate.parse(line(#"{"payload":{"title":"A","playing":true,"elapsedTime":10,"duration":100}}"#))), receivedAt: now)
        let paused = try #require(state.snapshot).applying(.pause, at: now.addingTimeInterval(5))
        state.adopt(paused)
        state.apply(try #require(AdapterUpdate.parse(line(#"{"diff":true,"payload":{"artworkData":"AAEC"}}"#))), receivedAt: now.addingTimeInterval(6))
        let snapshot = try #require(state.snapshot)
        #expect(!snapshot.isPlaying)
        #expect(snapshot.clock?.position(at: now.addingTimeInterval(60)) == 15)
        #expect(snapshot.item.artworkData == Data([0, 1, 2]))
    }
}

// MARK: - Adapter restarts & source selection

@Suite struct AdapterRestartPolicyTests {
    @Test func backsOffThenGivesUp() {
        var policy = AdapterRestartPolicy()
        var decisions: [AdapterRestartDecision] = []
        for index in 0..<5 {
            let start = t0.addingTimeInterval(Double(index) * 10)
            policy.launched(at: start)
            policy.receivedOutput()
            decisions.append(policy.exited(.signal(15), at: start.addingTimeInterval(5)))
        }
        #expect(decisions == [.restart(after: 2), .restart(after: 4), .restart(after: 8), .restart(after: 16),
                              .giveUp("adapter restarted too often")])
    }

    @Test func healthyRunResetsTheCount() {
        var policy = AdapterRestartPolicy()
        for index in 0..<4 {
            let start = t0.addingTimeInterval(Double(index) * 10)
            policy.launched(at: start)
            policy.receivedOutput()
            _ = policy.exited(.status(0), at: start.addingTimeInterval(1))
        }
        #expect(policy.consecutiveFailures == 4)
        policy.launched(at: t0.addingTimeInterval(100))
        policy.receivedOutput()
        let decision = policy.exited(.signal(9), at: t0.addingTimeInterval(100 + AdapterRestartPolicy.healthyRunDuration))
        #expect(decision == .restart(after: 2))
        #expect(policy.consecutiveFailures == 1)
    }

    @Test func fatalExitsGiveUpAtOnce() {
        var policy = AdapterRestartPolicy()
        policy.launched(at: t0)
        let decision = policy.exited(.status(1), at: t0)
        #expect(decision == .giveUp("adapter exited with status 1"))
        let decision2 = policy.exited(.launchFailed("nope"), at: t0)
        #expect(decision2 == .giveUp("could not start perl: nope"))
    }

    @Test func silentChildGivesUpEarly() {
        var policy = AdapterRestartPolicy()
        policy.launched(at: t0)
        let decision = policy.exited(.status(0), at: t0.addingTimeInterval(1))
        #expect(decision == .restart(after: 2))
        policy.launched(at: t0.addingTimeInterval(3))
        let decision2 = policy.exited(.signal(6), at: t0.addingTimeInterval(4))
        #expect(decision2 == .giveUp("adapter produced no output"))
    }
}

@Suite struct MediaSourcePolicyTests {
    private func started(hasAdapter: Bool = true, browserOpen: Bool = true) -> MediaSourcePolicy {
        var policy = MediaSourcePolicy(hasAdapter: hasAdapter)
        policy.start()
        policy.setSystemPlayerRunning(browserOpen)
        return policy
    }

    private func snapshot(playing: Bool) -> NowPlayingSnapshot {
        NowPlayingSnapshot(item: NowPlayingItem(title: "T", artist: "", album: "", duration: nil,
                                                artworkData: nil, bundleIdentifier: "x"),
                           isPlaying: playing, clock: nil)
    }

    @Test func musicAndSpotifyAlwaysRunTheAdapterOnlyWithABrowserOpen() {
        var policy = started(browserOpen: false)
        #expect(policy.runsScriptable && !policy.runsAdapter)
        #expect(policy.status(automationIssue: nil) == .on(web: .standby, automationIssue: nil))

        policy.setSystemPlayerRunning(true)
        #expect(policy.runsScriptable && policy.runsAdapter)
        #expect(policy.status(automationIssue: nil) == .on(web: .listening, automationIssue: nil))

        policy.setSystemPlayerRunning(false)
        #expect(!policy.runsAdapter)
    }

    @Test func webMediaPreferenceAndMissingAdapter() {
        var policy = started()
        policy.setWebMediaEnabled(false)
        #expect(!policy.runsAdapter && !policy.wantsSystemPlayers && policy.runsScriptable)
        #expect(policy.status(automationIssue: nil) == .on(web: .off, automationIssue: nil))

        let bare = started(hasAdapter: false)
        #expect(!bare.runsAdapter && bare.runsScriptable)
        #expect(bare.status(automationIssue: "denied") == .on(web: .notInstalled, automationIssue: "denied"))
    }

    @Test func playingSourceIsShown() {
        let playing = snapshot(playing: true), paused = snapshot(playing: false)
        #expect(MediaSourcePolicy.shown(adapter: paused, scriptable: playing) == .scriptable)
        #expect(MediaSourcePolicy.shown(adapter: playing, scriptable: playing) == .adapter)
        #expect(MediaSourcePolicy.shown(adapter: playing, scriptable: paused) == .adapter)
        #expect(MediaSourcePolicy.shown(adapter: paused, scriptable: paused) == .adapter)
        #expect(MediaSourcePolicy.shown(adapter: nil, scriptable: paused) == .scriptable)
        #expect(MediaSourcePolicy.shown(adapter: nil, scriptable: nil) == nil)
    }

    @Test func giveUpCoolsDownWithDoublingCooldown() {
        var policy = started()
        policy.adapterGaveUp(at: t0)
        #expect(policy.runsScriptable && !policy.runsAdapter)
        #expect(policy.status(automationIssue: nil) == .on(web: .retrying, automationIssue: nil))
        #expect(policy.reprobeAt == t0.addingTimeInterval(300))
        let probes = policy.reprobeIfDue(at: t0.addingTimeInterval(299))
        #expect(!probes)

        let probe = t0.addingTimeInterval(300)
        let probes2 = policy.reprobeIfDue(at: probe)
        #expect(probes2)
        #expect(policy.runsAdapter && policy.runsScriptable)

        policy.adapterGaveUp(at: probe.addingTimeInterval(10))
        #expect(policy.reprobeAt == probe.addingTimeInterval(10 + 600))
        #expect(MediaSourcePolicy.cooldown(afterGiveUps: 10) == MediaSourcePolicy.maxCooldown)
    }

    @Test func longHealthyRunResetsBackoff() {
        var policy = started()
        policy.adapterGaveUp(at: t0)
        _ = policy.reprobeIfDue(at: t0.addingTimeInterval(300))
        policy.adapterBecameHealthy(at: t0.addingTimeInterval(301))
        #expect(policy.reprobeAt == nil)

        let crash = t0.addingTimeInterval(301 + MediaSourcePolicy.healthyRunDuration)
        policy.adapterGaveUp(at: crash)
        #expect(policy.consecutiveGiveUps == 1)
        #expect(policy.reprobeAt == crash.addingTimeInterval(MediaSourcePolicy.baseCooldown))
    }

    @Test func wakeReprobesEarlyButNotInALoop() {
        var policy = started()
        policy.adapterGaveUp(at: t0)
        let probes = policy.resumed(at: t0.addingTimeInterval(60))
        #expect(!probes)
        let probes2 = policy.resumed(at: t0.addingTimeInterval(300))
        #expect(probes2)
        #expect(policy.runsAdapter)
    }

    @Test func staleEventsAreIgnoredAndStopKeepsThePreference() {
        var policy = started(browserOpen: false)
        policy.adapterGaveUp(at: t0)
        #expect(policy.consecutiveGiveUps == 0 && policy.reprobeAt == nil)
        policy.setWebMediaEnabled(false)
        policy.stop()
        #expect(!policy.runsScriptable && !policy.runsAdapter)
        #expect(!policy.webMediaEnabled)
        #expect(policy.status(automationIssue: nil) == .off)
    }
}

@Suite struct SystemPlayersTests {
    @Test func browsersAndVideoAppsButNotScriptablePlayers() {
        #expect(SystemPlayers.contains("com.apple.Safari"))
        #expect(SystemPlayers.contains("com.google.Chrome"))
        #expect(SystemPlayers.contains("com.colliderli.iina"))
        #expect(SystemPlayers.contains("com.apple.Safari.WebApp.1234-ABCD"))
        #expect(!SystemPlayers.contains("com.apple.Music"))
        #expect(!SystemPlayers.contains("com.spotify.client"))
        #expect(!SystemPlayers.contains("com.apple.finder"))
        #expect(!SystemPlayers.contains(nil))
    }
}

@Suite struct AdapterInstallationTests {
    @Test func bundledBuildLooksOnlyInResources() {
        let candidates = AdapterInstallation.candidateDirectories(
            resourceURL: URL(fileURLWithPath: "/Applications/NotchIsland.app/Contents/Resources"),
            executableURL: URL(fileURLWithPath: "/Applications/NotchIsland.app/Contents/MacOS/NotchIsland"),
            isAppBundle: true)
        #expect(candidates.map(\.path) == ["/Applications/NotchIsland.app/Contents/Resources/MediaRemoteAdapter"])
    }

    @Test func unbundledBuildFindsTheProjectVendorFolder() {
        let candidates = AdapterInstallation.candidateDirectories(
            resourceURL: nil,
            executableURL: URL(fileURLWithPath: "/Users/me/proj/.build/arm64-apple-macosx/debug/NotchIsland"),
            isAppBundle: false)
        #expect(candidates.map(\.path).contains("/Users/me/proj/Vendor/MediaRemoteAdapter"))
        let installation = AdapterInstallation(directory: URL(fileURLWithPath: "/x/MediaRemoteAdapter"))
        #expect(installation.scriptURL.path == "/x/MediaRemoteAdapter/mediaremote-adapter.pl")
        #expect(installation.frameworkURL.path == "/x/MediaRemoteAdapter/MediaRemoteAdapter.framework")
    }
}

// MARK: - AppleScript results

@Suite struct AppleScriptParsingTests {
    @Test func numbersInAnyLocale() {
        #expect(AppleScriptNumber.parse("23,410999298096") == 23.410999298096)
        #expect(AppleScriptNumber.parse("23.41") == 23.41)
        #expect(AppleScriptNumber.parse(" 12\n") == 12)
        #expect(AppleScriptNumber.parse("1.234,5") == 1234.5)
        #expect(AppleScriptNumber.parse("1,234.5") == 1234.5)
        #expect(AppleScriptNumber.parse("243\u{00A0}000") == 243_000)
        #expect(AppleScriptNumber.parse("") == nil)
        #expect(AppleScriptNumber.parse("missing value") == nil)
    }

    @Test func descriptorsBecomeSendableValues() {
        let list = NSAppleEventDescriptor.list()
        list.insert(NSAppleEventDescriptor(string: "playing"), at: 1)
        list.insert(NSAppleEventDescriptor(double: 12.5), at: 2)
        list.insert(NSAppleEventDescriptor(typeCode: FourCharCode(fourCC: "msng")), at: 3)
        list.insert(NSAppleEventDescriptor(int32: 7), at: 4)
        list.insert(NSAppleEventDescriptor(boolean: true), at: 5)
        #expect(ScriptValue(list) == .list([.text("playing"), .number(12.5), .missing, .number(7), .bool(true)]))
        #expect(ScriptValue(nil) == .missing)
        let bytes = Data([0xFF, 0xD8, 0xFF])
        let image = NSAppleEventDescriptor(descriptorType: FourCharCode(fourCC: "JPEG"), data: bytes)
        #expect(ScriptValue(image) == .data(bytes))
    }

    @Test func failureCodes() {
        #expect(AppleScriptFailure(code: -1743, message: "") == .notPermitted)
        #expect(AppleScriptFailure(code: -1728, message: "") == .noSuchObject)
        #expect(AppleScriptFailure(code: -1712, message: "") == .timedOut)
        #expect(AppleScriptFailure(code: -600, message: "") == .notRunning)
        #expect(AppleScriptFailure(code: -2741, message: "syntax") == .failed(code: -2741, message: "syntax"))
    }

    @Test func libraryIsFixedGuardedAndTimedOut() {
        for player in ScriptablePlayer.all {
            let source = AppleScriptLibrary.source(for: player)
            for handler in ScriptHandler.allCases {
                #expect(source.contains("on \(handler.rawValue)("))
                #expect(handler.rawValue == handler.rawValue.lowercased())
            }
            let handlerCount = ScriptHandler.allCases.count
            #expect(source.components(separatedBy: "with timeout of 3 seconds").count - 1 == handlerCount)
            #expect(source.components(separatedBy: "if application id \"\(player.bundleID)\" is not running then return").count - 1 == handlerCount)
            #expect(source.contains("set player position to theSeconds"))
            // Never addressed by name, and the position read sits inside `try`.
            #expect(!source.contains("tell application \"\(player.displayName)\""))
            #expect(source.contains("try\n\t\t\t\tset thePosition to player position"))
        }
        #expect(AppleScriptLibrary.source(for: .music).contains("persistent ID of theTrack"))
        #expect(AppleScriptLibrary.source(for: .spotify).contains("artwork url of current track"))
    }

    @Test func fourCharCodes() {
        #expect(FourCharCode(fourCC: "list") == 0x6C69_7374)
        #expect(FourCharCode(fourCC: "----") == 0x2D2D_2D2D)
    }
}

// MARK: - Music / Spotify reports

@Suite struct PlayerReportTests {
    @Test func musicBroadcast() {
        let report = PlayerReport.broadcast([
            "Player State": "Playing", "Name": "Song", "Artist": "Artist", "Album": "Album",
            "Total Time": NSNumber(value: 243_000), "PersistentID": NSNumber(value: Int64(-6_052_837_899_185_946_624)),
        ])
        #expect(report.state == .playing)
        #expect(report.duration == 243)
        #expect(report.position == nil)
        #expect(report.trackID == "AC00000000000000")
    }

    @Test func musicSpacedPersistentIDSpellingIsAccepted() {
        let report = PlayerReport.broadcast(["Player State": "Paused", "Name": "S", "Persistent ID": "ab12"])
        #expect(report.trackID == "AB12")
        #expect(report.state == .paused)
    }

    @Test func spotifyBroadcast() {
        let report = PlayerReport.broadcast([
            "Player State": "Paused", "Name": "Song", "Artist": "A", "Album": "B",
            "Duration": NSNumber(value: 210_500), "Playback Position": NSNumber(value: 42.25),
            "Track ID": "spotify:track:123",
        ])
        #expect(report.duration == 210.5)
        #expect(report.position == 42.25)
        #expect(report.trackID == "spotify:track:123")
        #expect(PlayerReport.broadcast(["Player State": "Stopped"]).state == .stopped)
        #expect(PlayerReport.broadcast([:]).state == .stopped)
    }

    @Test func musicSeed() throws {
        let value = ScriptValue.list([.text("playing"), .number(23.4), .text("Song"), .text("Artist"), .text("Album"),
                                      .number(243.2), .text("ac00000000000000")])
        let report = try #require(PlayerReport.seed(value, player: .music))
        #expect(report.state == .playing)
        #expect(report.position == 23.4)
        #expect(report.duration == 243.2)
        #expect(report.trackID == "AC00000000000000")
    }

    @Test func spotifySeedDurationIsMilliseconds() throws {
        let value = ScriptValue.list([.text("paused"), .text("23,5"), .text("Song"), .text("A"), .text("B"),
                                      .number(210_500), .text("spotify:track:123")])
        let report = try #require(PlayerReport.seed(value, player: .spotify))
        #expect(report.duration == 210.5)
        #expect(report.position == 23.5)
        #expect(report.trackID == "spotify:track:123")
    }

    @Test func seedWithoutPositionOrTrack() throws {
        let stopped = ScriptValue.list([.text("stopped"), .missing, .text(""), .text(""), .text(""), .number(0), .text("")])
        let report = try #require(PlayerReport.seed(stopped, player: .music))
        #expect(report.state == .stopped && report.position == nil && report.duration == nil && report.trackID == nil)
        #expect(PlayerReport.seed(.list([.text("playing")]), player: .music) == nil)
        #expect(PlayerReport.seed(.text("playing"), player: .music) == nil)
    }
}

// MARK: - Which player owns the island

@Suite struct ScriptableStateTests {
    func report(_ state: PlayerReport.State, _ title: String, id: String? = nil, position: TimeInterval? = nil) -> PlayerReport {
        PlayerReport(state: state, title: title, artist: "A", album: "B", duration: 200, position: position, trackID: id)
    }

    @Test func playingPlayerTakesTheIsland() {
        var state = ScriptableState()
        _ = state.ingest(report(.playing, "Music song"), from: .music, at: t0)
        let outcome = state.ingest(report(.playing, "Spotify song"), from: .spotify, at: t0)
        #expect(outcome.changed)
        #expect(state.activeBundleID == "com.spotify.client")
        #expect(state.activeSnapshot?.item.bundleIdentifier == "com.spotify.client")
    }

    @Test func pauseDoesNotDisplaceAPlayingPlayer() {
        var state = ScriptableState()
        _ = state.ingest(report(.playing, "Music song"), from: .music, at: t0)
        let outcome = state.ingest(report(.paused, "Spotify song"), from: .spotify, at: t0)
        #expect(!outcome.changed)
        #expect(state.activeBundleID == "com.apple.Music")
        // Once Music pauses too, the most recent pause wins.
        _ = state.ingest(report(.paused, "Music song"), from: .music, at: t0)
        _ = state.ingest(report(.paused, "Spotify song 2"), from: .spotify, at: t0)
        #expect(state.activeBundleID == "com.spotify.client")
    }

    @Test func emptyTitleIsIgnoredBeforeArbitration() {
        var state = ScriptableState()
        _ = state.ingest(report(.playing, "Music song"), from: .music, at: t0)
        let outcome = state.ingest(report(.playing, ""), from: .spotify, at: t0)
        #expect(outcome == ScriptableState.Outcome())
        #expect(state.activeBundleID == "com.apple.Music")
    }

    @Test func stoppingTheActivePlayerFallsBackAndRequeries() {
        var state = ScriptableState()
        _ = state.ingest(report(.playing, "Spotify song"), from: .spotify, at: t0)
        _ = state.ingest(report(.playing, "Music song"), from: .music, at: t0)
        let outcome = state.ingest(report(.stopped, ""), from: .music, at: t0)
        #expect(outcome.changed)
        #expect(state.activeBundleID == "com.spotify.client")
        #expect(outcome.requery == ["com.spotify.client"])
        let last = state.remove("com.spotify.client")
        #expect(last.changed && state.activeSnapshot == nil)
    }

    @Test func artworkAndGenerationFollowTheTrack() throws {
        var state = ScriptableState()
        let first = state.ingest(report(.playing, "One", id: "1"), from: .music, at: t0)
        #expect(first.newTrack && first.needsPosition)
        let generation = try #require(state.generation(of: "com.apple.Music"))
        let attached = state.attachArtwork(Data([1]), for: "com.apple.Music", generation: generation)
        #expect(attached)

        // Same track (a pause broadcast): artwork kept, position projected, no pull needed.
        let pause = state.ingest(report(.paused, "One", id: "1"), from: .music, at: t0.addingTimeInterval(10))
        #expect(!pause.newTrack && !pause.needsPosition)
        #expect(state.activeSnapshot?.item.artworkData == Data([1]))
        #expect(state.activeSnapshot?.clock?.position(at: t0.addingTimeInterval(99)) == 10)

        // New track: artwork dropped, a stale reply for the old generation is refused.
        _ = state.ingest(report(.playing, "Two", id: "2"), from: .music, at: t0.addingTimeInterval(20))
        #expect(state.activeSnapshot?.item.artworkData == nil)
        let attached2 = state.attachArtwork(Data([9]), for: "com.apple.Music", generation: generation)
        #expect(!attached2)
        let moved = state.updatePosition(150, for: "com.apple.Music", generation: generation, at: t0)
        #expect(!moved)
        let current = try #require(state.generation(of: "com.apple.Music"))
        let moved2 = state.updatePosition(15, for: "com.apple.Music", generation: current, at: t0.addingTimeInterval(21))
        #expect(moved2)
        #expect(state.activeSnapshot?.clock?.elapsed == 15)
    }

    @Test func seedAndBroadcastAgreeOnIdentity() {
        var state = ScriptableState()
        _ = state.ingest(report(.playing, "One", id: "spotify:track:1", position: 30), from: .spotify, at: t0)
        let generation = state.generation(of: "com.spotify.client")
        // A broadcast for the same track, even with a differently formatted ID, is not a new track.
        let broadcast = state.ingest(report(.playing, "One", id: nil, position: 31), from: .spotify, at: t0.addingTimeInterval(1))
        #expect(!broadcast.newTrack)
        #expect(state.generation(of: "com.spotify.client") == generation)
    }

    @Test func optimisticCommandCanBeRolledBack() throws {
        var state = ScriptableState()
        _ = state.ingest(report(.playing, "One", position: 10), from: .music, at: t0)
        let saved = try #require(state.tracks["com.apple.Music"])
        let applied = state.applyOptimistic(.pause, at: t0.addingTimeInterval(5))
        #expect(applied)
        #expect(state.activeSnapshot?.isPlaying == false)
        let optimistic = try #require(state.tracks["com.apple.Music"])
        let restored = state.restore(saved, for: "com.apple.Music", ifUnchangedSince: optimistic)
        #expect(restored)
        #expect(state.activeSnapshot?.isPlaying == true)

        // Not rolled back over a newer report.
        _ = state.applyOptimistic(.pause, at: t0)
        let second = try #require(state.tracks["com.apple.Music"])
        _ = state.ingest(report(.paused, "One"), from: .music, at: t0.addingTimeInterval(1))
        let restored2 = state.restore(saved, for: "com.apple.Music", ifUnchangedSince: second)
        #expect(!restored2)
    }
}

// MARK: - Controller (demo path only: no sources are started)

@Suite struct MediaControllerDemoTests {
    @Test func demoDrivesTheStoreAndClears() async throws {
        let controller = MediaController()
        #expect(controller.item == nil && !controller.isActive)
        #expect(controller.status == .off)

        controller.injectDemo(item(), playing: true)
        #expect(controller.item == item())
        #expect(controller.isPlaying && controller.isActive)
        #expect(controller.clock?.rate == 1)

        controller.send(.togglePlayPause)
        #expect(!controller.isPlaying)
        #expect(controller.isActive)      // paused less than 10 s ago
        #expect(controller.clock?.rate == 0)

        controller.injectDemo(nil, playing: false)
        #expect(controller.item == nil && !controller.isActive && controller.clock == nil)
    }

    @Test func pausedDemoIsVisibleAndStopIsIdempotent() {
        let controller = MediaController()
        controller.injectDemo(item(), playing: false)
        #expect(controller.isActive && !controller.isPlaying)
        controller.stop()
        controller.stop()
        #expect(controller.item == nil && !controller.isActive)
    }

    @Test func artworkIsDecodedOffMain() async throws {
        let controller = MediaController()
        let png = try #require(Self.tinyPNG())
        controller.injectDemo(item(artwork: png), playing: true)
        for _ in 0..<100 where controller.artwork == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(controller.artwork != nil)
    }

    static func tinyPNG() -> Data? {
        let image = NSImage(size: NSSize(width: 4, height: 4), flipped: false) { rect in
            NSColor.systemRed.setFill()
            rect.fill()
            return true
        }
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}

@Suite struct AdapterOrphanTests {
    @Test func onlyOurScriptWithoutAParent() {
        let script = "/Apps/NotchIsland.app/Contents/Resources/MediaRemoteAdapter/mediaremote-adapter.pl"
        let ps = """
          101     1 /usr/bin/perl \(script) /x/MediaRemoteAdapter.framework stream
          102   500 /usr/bin/perl \(script) /x/MediaRemoteAdapter.framework stream
          103     1 /usr/bin/perl /other/tool.pl
          104     1 /usr/bin/perl -e my $pid = fork; -- /usr/bin/perl \(script) stream
        """
        #expect(AdapterOrphans.orphans(in: ps, runningScript: script) == [101, 104])
    }

    @Test func watchdogIsPassedTheAdapterCommand() {
        #expect(MediaRemoteAdapterSource.watchdog.contains("exec { $ARGV[0] } @ARGV"))
    }
}
