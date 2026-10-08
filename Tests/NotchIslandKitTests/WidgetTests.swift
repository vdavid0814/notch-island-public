import CoreGraphics
import Foundation
import Testing
@testable import NotchIslandKit

/// The standard board's widgets, by their legacy ids.
nonisolated let nowPlayingID = WidgetID.legacy(.nowPlaying)
nonisolated let stopwatchID = WidgetID.legacy(.stopwatch)
nonisolated let volumeID = WidgetID.legacy(.volume)

@Suite struct WidgetBoardTests {
    @Test func standardBoardIsValidAndFull() {
        let board = WidgetBoard.standard
        #expect(board.widgets.map(\.kind) == [.nowPlaying, .dateTime, .wifi, .stopwatch, .volume])
        for widget in board.widgets {
            #expect(board.isFree(widget.frame, for: widget.kind, excluding: widget.id))
        }
        let cells = board.widgets.reduce(0) { $0 + $1.frame.width * $1.frame.height }
        #expect(cells == board.grid.columns * board.grid.rows)
        #expect(board.freeSlot(for: .wifi) == nil)
    }

    @Test func overlappingAndOutOfBoundsFramesAreRefused() {
        var board = WidgetBoard.standard
        let result1 = board.setFrame(GridRect(column: 6, row: 1, width: 5, height: 1), for: stopwatchID)
        #expect(!result1)
        let result2 = board.setFrame(GridRect(column: 8, row: 1, width: 5, height: 1), for: stopwatchID)
        #expect(!result2)
        // Below the minimum size.
        let result3 = board.setFrame(GridRect(column: 7, row: 1, width: 2, height: 1), for: stopwatchID)
        #expect(!result3)
        #expect(board.widget(stopwatchID)?.frame == GridRect(column: 7, row: 1, width: 5, height: 1))
    }

    @Test func addFindsRoomAndShrinksToFit() {
        var board = WidgetBoard.standard
        board.remove(volumeID)
        // The default 3 × 1 fits where the volume was.
        let stats = board.add(.systemStats)
        #expect(stats != nil)
        #expect(board.first(of: .systemStats)?.frame == GridRect(column: 7, row: 2, width: 3, height: 1))
        // Two cells left: room for Wi-Fi's 2 × 1 tile, then the board is full.
        let wifi = board.add(.wifi)
        #expect(wifi != nil && wifi != stats)
        #expect(board.instances(of: .wifi).last?.frame == GridRect(column: 10, row: 2, width: 2, height: 1))
        #expect(board.add(.wifi) == nil)
    }

    @Test func optionsAreLimitedToTheKind() {
        var board = WidgetBoard.standard
        board.setOption(.artwork, true, for: stopwatchID)
        #expect(board.widget(stopwatchID)?.shows(.artwork) == false)
        board.setOption(.resetButton, false, for: stopwatchID)
        #expect(board.widget(stopwatchID)?.shows(.resetButton) == false)
        // Always drawn: no switch.
        board.setOption(.stopwatchButton, false, for: stopwatchID)
        #expect(board.widget(stopwatchID)?.shows(.stopwatchButton) == true)
    }

    @Test func roundTripsAndParksInvalidEntries() throws {
        var board = WidgetBoard.standard
        board.setOption(.skipButtons, false, for: nowPlayingID)
        let data = try JSONEncoder().encode(board)
        #expect(try JSONDecoder().decode(WidgetBoard.self, from: data) == board)

        let broken = """
        {"widgets":[
          {"kind":"stopwatch","frame":{"column":0,"row":0,"width":5,"height":1},"options":["readout","percentage"]},
          {"kind":"volume","frame":{"column":2,"row":0,"width":5,"height":1},"options":[]},
          {"kind":"dateTime","frame":{"column":11,"row":0,"width":3,"height":1},"options":[]},
          {"kind":"stopwatch","frame":{"column":6,"row":1,"width":5,"height":1},"options":[]}
        ]}
        """
        let decoded = try JSONDecoder().decode(WidgetBoard.self, from: Data(broken.utf8))
        // The volume overlaps the stopwatch and the date leaves the board: both parked, not lost.
        // The second stopwatch is a second instance, with an id of its own.
        #expect(decoded.widgets.map(\.kind) == [.stopwatch, .stopwatch])
        #expect(decoded.parked.map(\.kind) == [.volume, .dateTime])
        #expect(decoded.widgets.map(\.id) == [stopwatchID, WidgetID(name: "notchisland.widget.\(stopwatchID).1")])
        #expect(decoded.first(of: .stopwatch)?.options == [.readout])
    }

    @Test func widgetsOfKindsNoLongerBuiltAreKeptAsTheyWere() throws {
        let json = """
        {"version":3,"widgets":[
          {"kind":"photoFrame","frame":{"column":7,"row":0,"width":5,"height":2},"options":["photo"],"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF"},
          {"kind":"wifi","frame":{"column":0,"row":0,"width":2,"height":1},"options":["controlName"],"style":{"surface":{"borderWidth":2}}}
        ]}
        """
        let board = try JSONDecoder().decode(WidgetBoard.self, from: Data(json.utf8))
        #expect(board.widgets.map(\.kind) == [.wifi])
        #expect(board.foreign.count == 1)
        // Written back as read, for a build that knows it.
        let again = try JSONDecoder().decode(WidgetBoard.self, from: JSONEncoder().encode(board))
        #expect(again.foreign == board.foreign)
    }

    /// A widget kept while its kind was gone comes back where it was, with its switches, once the
    /// kind is built again (the timer, after the widgets were cut to their bases).
    @Test func aKindBuiltAgainComesBackFromForeign() throws {
        let json = """
        {"version":3,"widgets":[
          {"kind":"wifi","frame":{"column":0,"row":0,"width":2,"height":1},"options":["controlName"]}
        ],"foreign":[
          {"kind":"timer","frame":{"column":7,"row":0,"width":5,"height":2},"options":["ruler","readout","addMinute"],
           "id":"6F9619FF-8B86-D011-B42D-00C04FC964FF"}
        ]}
        """
        let board = try JSONDecoder().decode(WidgetBoard.self, from: Data(json.utf8))
        #expect(board.widgets.map(\.kind) == [.wifi, .timer])
        #expect(board.foreign.isEmpty)
        let timer = try #require(board.first(of: .timer))
        #expect(timer.frame == GridRect(column: 7, row: 0, width: 5, height: 2))
        #expect(timer.shows(.ruler) && timer.shows(.readout) && timer.shows(.addMinute))
    }

    @Test func centring() {
        #expect(GridRect(column: 4, row: 0, width: 4, height: 1).isHorizontallyCentred(in: .standard))
        #expect(!GridRect(column: 4, row: 0, width: 5, height: 1).isHorizontallyCentred(in: .standard))
        #expect(GridRect(column: 0, row: 1, width: 12, height: 1).isVerticallyCentred(in: .standard))
        let wide = BoardGrid(columns: 16, rows: 4, gap: 8)
        #expect(GridRect(column: 6, row: 1, width: 4, height: 2).isHorizontallyCentred(in: wide))
        #expect(GridRect(column: 6, row: 1, width: 4, height: 2).isVerticallyCentred(in: wide))
    }
}

@Suite struct WidgetBoardGeometryTests {
    // 12 columns of 40 with 8 between; 3 rows of 40 with 8 between.
    let geometry = WidgetBoardGeometry(size: CGSize(width: 12 * 40 + 11 * 8, height: 3 * 40 + 2 * 8), grid: .standard)

    @Test func framesSitOnTheGrid() {
        #expect(geometry.cellWidth == 40 && geometry.cellHeight == 40)
        #expect(geometry.frame(for: GridRect(column: 1, row: 1, width: 2, height: 1))
                == CGRect(x: 48, y: 48, width: 88, height: 40))
    }

    @Test func moveSnapsToTheNearestCellAndStaysInside() {
        let size = GridSize(width: 5, height: 2)
        #expect(geometry.snappedMove(origin: CGPoint(x: 70, y: 20), size: size)
                == GridRect(column: 1, row: 0, width: 5, height: 2))
        #expect(geometry.snappedMove(origin: CGPoint(x: 1000, y: 1000), size: size)
                == GridRect(column: 7, row: 1, width: 5, height: 2))
        #expect(geometry.snappedMove(origin: CGPoint(x: -300, y: -40), size: size)
                == GridRect(column: 0, row: 0, width: 5, height: 2))
    }

    @Test func resizeSnapsEdgesAndRespectsLimits() {
        let start = GridRect(column: 4, row: 0, width: 4, height: 1)
        // Trailing edge dragged about two cells right.
        let wider = geometry.snappedResize(
            frame: CGRect(x: 192, y: 0, width: 4 * 48 - 8 + 100, height: 40),
            from: start, kind: .nowPlaying, movesLeading: false, movesTop: false)
        #expect(wider == GridRect(column: 4, row: 0, width: 6, height: 1))
        // Leading edge dragged far right: held at Now Playing's 3-column minimum.
        let narrow = geometry.snappedResize(
            frame: CGRect(x: 400, y: 0, width: 40, height: 40),
            from: start, kind: .nowPlaying, movesLeading: true, movesTop: false)
        #expect(narrow == GridRect(column: 5, row: 0, width: 3, height: 1))
        // Bottom edge dragged beyond the board.
        let tall = geometry.snappedResize(
            frame: CGRect(x: 192, y: 0, width: 184, height: 900),
            from: start, kind: .nowPlaying, movesLeading: false, movesTop: false)
        #expect(tall == GridRect(column: 4, row: 0, width: 4, height: 3))
    }
}

@Suite struct WidgetElementTests {
    @Test func version1BoardsGainTheNewElements() throws {
        let json = #"{"widgets":[{"kind":"nowPlaying","frame":{"column":0,"row":0,"width":7,"height":3},"options":["artwork","trackInfo"],"showsPlate":false},{"kind":"stopwatch","frame":{"column":7,"row":0,"width":4,"height":1},"options":[]}]}"#
        let board = try JSONDecoder().decode(WidgetBoard.self, from: Data(json.utf8))
        let nowPlaying = try #require(board.first(of: .nowPlaying))
        #expect(nowPlaying.options == [.artwork, .trackInfo, .artist, .playbackButtons])
        #expect(nowPlaying.background == .none)
        #expect(board.first(of: .stopwatch)?.options == [.readout])
    }

    @Test func version2BoardsKeepWhatWasSwitchedOff() throws {
        var board = WidgetBoard.standard
        board.update(nowPlayingID) { widget in
            widget.options.remove(.artist)
            widget.background = .tinted
        }
        let decoded = try JSONDecoder().decode(WidgetBoard.self, from: JSONEncoder().encode(board))
        let nowPlaying = try #require(decoded.widget(nowPlayingID))
        #expect(!nowPlaying.shows(.artist))
        #expect(nowPlaying.background == .tinted)
    }

    @Test func backgroundColourAndOpacityRoundTripWithinRange() throws {
        var board = WidgetBoard.standard
        board.update(nowPlayingID) { widget in
            widget.background = .tinted
            widget.backgroundColor = IslandTheme.RGB(red: 0.2, green: 0.6, blue: 0.9)
            widget.backgroundOpacity = 1.7
        }
        #expect(board.widget(nowPlayingID)?.backgroundOpacity == 1)
        let decoded = try JSONDecoder().decode(WidgetBoard.self, from: JSONEncoder().encode(board))
        let nowPlaying = try #require(decoded.widget(nowPlayingID))
        #expect(nowPlaying.backgroundColor == IslandTheme.RGB(red: 0.2, green: 0.6, blue: 0.9))
        #expect(nowPlaying.effectiveBackgroundOpacity == 1)
        // Unset: each background's own strength.
        #expect(WidgetBoard.standard.widget(stopwatchID)?.effectiveBackgroundOpacity == 0.4)
    }

    /// What earlier versions offered and this one does not (a layout, swapped sides, the artwork or
    /// a gradient behind a widget) is read as the plain widget on a plate.
    @Test func settingsNoLongerOfferedAreDropped() throws {
        let json = #"{"version":3,"widgets":[{"kind":"nowPlaying","frame":{"column":0,"row":0,"width":7,"height":3},"options":["artwork"],"layout":"cover","background":"artwork","mirrored":true},{"kind":"volume","frame":{"column":7,"row":0,"width":5,"height":1},"options":[],"background":"gradient","sizes":{"levelValue":"large"}}]}"#
        let board = try JSONDecoder().decode(WidgetBoard.self, from: Data(json.utf8))
        #expect(board.first(of: .nowPlaying)?.background == .plate)
        #expect(board.first(of: .volume)?.background == .plate)
        let object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(board)) as? [String: Any])
        let widget = try #require((object["widgets"] as? [[String: Any]])?.first)
        #expect(Set(widget.keys) == ["version", "id", "kind", "frame", "options", "background"])
    }

    @Test func sizePresetsRespectTheLimits() {
        for kind in IslandWidgetKind.allCases {
            #expect(!kind.sizePresets.isEmpty)
            for size in kind.sizePresets {
                #expect(WidgetBoard(widgets: []).fits(size, kind))
            }
        }
        #expect(IslandWidgetKind.wifi.sizePresets.contains(GridSize(width: 2, height: 1)))
    }

    @Test func placementPrefersTheCurrentSpotThenTheNearest() throws {
        var board = WidgetBoard.standard
        board.remove(volumeID)
        let stopwatch = board.widget(stopwatchID)!.frame   // 7,1 5×1
        // Taller: 5 × 2 fits in place now that the volume is gone.
        #expect(board.placement(for: .stopwatch, size: GridSize(width: 5, height: 2), near: stopwatch, excluding: stopwatchID)
                == GridRect(column: 7, row: 1, width: 5, height: 2))
        // Wider than the room right of Now Playing: nowhere.
        #expect(board.placement(for: .stopwatch, size: GridSize(width: 6, height: 1), near: stopwatch, excluding: stopwatchID) == nil)
        // A small widget lands next to where it was.
        let added = board.add(.wifi)
        let wifiID = try #require(added)
        let wifi = board.widget(wifiID)!.frame
        #expect(board.placement(for: .wifi, size: GridSize(width: 1, height: 1), near: wifi, excluding: wifiID)?.row == wifi.row)
    }

    @Test func settingsPaneAliases() {
        #expect(IslandSettingsPane.named("appearance") == .general)
        #expect(IslandSettingsPane.named("permissions") == .about)
        #expect(IslandSettingsPane.named("widgets") == .widgets)
        #expect(AppCommand.parse(URL(string: "notchisland://settings/permissions")!) == .showSettingsPane(.about))
    }

    @Test func artworkAccentIsReadable() {
        let black = ArtworkColor(red: 0.02, green: 0.02, blue: 0.03).accent
        #expect(max(black.red, black.green, black.blue) >= 0.7)
        let muddyRed = ArtworkColor(red: 0.3, green: 0.12, blue: 0.1).accent
        #expect(muddyRed.red > muddyRed.green && muddyRed.red >= 0.7)
        let grey = ArtworkColor(red: 0.5, green: 0.5, blue: 0.5).accent
        #expect(abs(grey.red - grey.blue) < 0.01)
    }
}

@Suite struct MoreWidgetsTests {
    @Test func systemLoadReadsFromMach() throws {
        let ticks = try #require(SystemStatsMonitor.cpuTicks())
        #expect(ticks.total >= ticks.busy && ticks.total > 0)
        let memory = try #require(SystemStatsMonitor.memoryUsedBytes())
        #expect(memory > 0 && memory <= ProcessInfo.processInfo.physicalMemory)
    }

    @Test func everyKindHasElementsAndFitsItsBounds() {
        for kind in IslandWidgetKind.allCases {
            // A list's rows are all it has: nothing to switch off.
            #expect(!kind.spec.elements.isEmpty && (!kind.options.isEmpty || kind == .clipboard), "\(kind)")
            #expect(kind.defaultSize.width >= kind.minimumSize.width && kind.defaultSize.width <= kind.maximumSize.width)
            #expect(!kind.summary.isEmpty && kind.title != kind.rawValue)
        }
    }
}
