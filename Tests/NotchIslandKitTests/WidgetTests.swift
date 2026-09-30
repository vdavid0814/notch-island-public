import CoreGraphics
import Foundation
import Testing
@testable import NotchIslandKit

/// The standard board's widgets, by their legacy ids.
nonisolated let timerID = WidgetID.legacy(.timer)
nonisolated let nowPlayingID = WidgetID.legacy(.nowPlaying)
nonisolated let shelfID = WidgetID.legacy(.shelf)

@Suite struct WidgetBoardTests {
    @Test func standardBoardIsValidAndFull() {
        let board = WidgetBoard.standard
        #expect(board.widgets.map(\.kind) == [.nowPlaying, .timer, .shelf])
        for widget in board.widgets {
            #expect(board.isFree(widget.frame, for: widget.kind, excluding: widget.id))
        }
        let cells = board.widgets.reduce(0) { $0 + $1.frame.width * $1.frame.height }
        #expect(cells == board.grid.columns * board.grid.rows)
        #expect(board.freeSlot(for: .battery) == nil)
    }

    @Test func overlappingAndOutOfBoundsFramesAreRefused() {
        var board = WidgetBoard.standard
        let result1 = board.setFrame(GridRect(column: 6, row: 0, width: 5, height: 2), for: timerID)
        #expect(!result1)
        let result2 = board.setFrame(GridRect(column: 8, row: 0, width: 5, height: 2), for: timerID)
        #expect(!result2)
        // Below the minimum size.
        let result3 = board.setFrame(GridRect(column: 7, row: 0, width: 2, height: 1), for: timerID)
        #expect(!result3)
        #expect(board.widget(timerID)?.frame == GridRect(column: 7, row: 0, width: 5, height: 2))
    }

    @Test func addFindsRoomAndShrinksToFit() {
        var board = WidgetBoard.standard
        board.remove(shelfID)
        // The default 3 × 1 fits where the shelf was.
        let battery = board.add(.battery)
        #expect(battery != nil)
        #expect(board.first(of: .battery)?.frame == GridRect(column: 7, row: 2, width: 3, height: 1))
        // Two cells left: room for a control's 2 × 1 tile, then the board is full.
        let wifi = board.add(.wifi)
        #expect(wifi != nil && wifi != battery)
        #expect(board.first(of: .wifi)?.frame == GridRect(column: 10, row: 2, width: 2, height: 1))
        let bluetooth = board.add(.bluetooth), secondBattery = board.add(.battery)
        #expect(bluetooth == nil)
        #expect(secondBattery == nil)  // a second battery would be welcome, but the board is full
    }

    @Test func optionsAreLimitedToTheKind() {
        var board = WidgetBoard.standard
        board.setOption(.percentage, true, for: timerID)
        #expect(board.widget(timerID)?.shows(.percentage) == false)
        board.setOption(.addMinute, true, for: timerID)
        #expect(board.widget(timerID)?.shows(.addMinute) == true)
        board.setOption(.ruler, false, for: timerID)
        #expect(board.widget(timerID)?.shows(.ruler) == false)
    }

    @Test func roundTripsAndParksInvalidEntries() throws {
        var board = WidgetBoard.standard
        board.setOption(.skipButtons, false, for: nowPlayingID)
        let data = try JSONEncoder().encode(board)
        #expect(try JSONDecoder().decode(WidgetBoard.self, from: data) == board)

        let broken = """
        {"widgets":[
          {"kind":"timer","frame":{"column":0,"row":0,"width":5,"height":2},"options":["ruler","percentage"]},
          {"kind":"shelf","frame":{"column":2,"row":1,"width":5,"height":1},"options":[]},
          {"kind":"battery","frame":{"column":11,"row":0,"width":3,"height":1},"options":[]},
          {"kind":"timer","frame":{"column":6,"row":0,"width":5,"height":2},"options":[]}
        ]}
        """
        let decoded = try JSONDecoder().decode(WidgetBoard.self, from: Data(broken.utf8))
        // The shelf overlaps the timer and the battery leaves the board: both parked, not lost. The
        // second timer is a second instance, with an id of its own.
        #expect(decoded.widgets.map(\.kind) == [.timer, .timer])
        #expect(decoded.parked.map(\.kind) == [.shelf, .battery])
        #expect(decoded.widgets.map(\.id) == [timerID, WidgetID(name: "notchisland.widget.\(timerID).1")])
        #expect(decoded.first(of: .timer)?.options == [.ruler])
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
            from: start, kind: .timer, movesLeading: false, movesTop: false)
        #expect(wider == GridRect(column: 4, row: 0, width: 6, height: 1))
        // Leading edge dragged far right: held at the timer's 3-column minimum.
        let narrow = geometry.snappedResize(
            frame: CGRect(x: 400, y: 0, width: 40, height: 40),
            from: start, kind: .timer, movesLeading: true, movesTop: false)
        #expect(narrow == GridRect(column: 5, row: 0, width: 3, height: 1))
        // Bottom edge dragged beyond the board.
        let tall = geometry.snappedResize(
            frame: CGRect(x: 192, y: 0, width: 184, height: 900),
            from: start, kind: .timer, movesLeading: false, movesTop: false)
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
            widget.sizes[.trackInfo] = .large
            widget.sizes[.artist] = .medium        // medium is the default: not stored
            widget.sizes[.skipButtons] = .small    // not sizable: dropped
            widget.layout = .cover
            widget.background = .artwork
        }
        let decoded = try JSONDecoder().decode(WidgetBoard.self, from: JSONEncoder().encode(board))
        let nowPlaying = try #require(decoded.widget(nowPlayingID))
        #expect(!nowPlaying.shows(.artist))
        #expect(nowPlaying.sizes == [.trackInfo: .large])
        #expect(nowPlaying.layout == .cover && nowPlaying.background == .artwork)
    }

    @Test func layoutsAndBackgroundsAreLimitedToTheKind() {
        var board = WidgetBoard.standard
        board.update(timerID) { widget in
            widget.layout = .cover
            widget.background = .artwork
        }
        #expect(board.widget(timerID)?.layout == .automatic)
        #expect(board.widget(timerID)?.background == .plate)
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
        board.remove(shelfID)
        let timer = board.widget(timerID)!.frame   // 7,0 5×2
        // Taller: 5 × 3 fits in place now that the shelf is gone.
        #expect(board.placement(for: .timer, size: GridSize(width: 5, height: 3), near: timer, excluding: timerID)
                == GridRect(column: 7, row: 0, width: 5, height: 3))
        // Wider than the room right of Now Playing: nowhere.
        #expect(board.placement(for: .timer, size: GridSize(width: 6, height: 2), near: timer, excluding: timerID) == nil)
        // A small widget lands next to where it was.
        let added = board.add(.battery)
        let batteryID = try #require(added)
        let battery = board.widget(batteryID)!.frame
        #expect(board.placement(for: .battery, size: GridSize(width: 1, height: 1), near: battery, excluding: batteryID)?.row
                == battery.row)
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
        let memory = try #require(SystemStatsMonitor.memoryUsed())
        #expect(memory > 0 && memory <= 1)
    }

    @Test func everyNewControlIsAnActionWithSomethingToOpen() {
        let actions: [SystemControl] = [.calculator, .voiceMemos, .screenshot, .notes, .focus, .clock, .home]
        for control in actions {
            #expect(control.isAction)
            #expect(control.actionURL != nil)
        }
        #expect(SystemControl.lockScreen.isAction)
        for kind in IslandWidgetKind.allCases where kind.systemControl != nil {
            #expect(kind.category == .controls && kind.minimumSize == GridSize(width: 1, height: 1))
        }
    }

    @Test func newWidgetsHaveElementsAndFitTheirBounds() {
        for kind in [IslandWidgetKind.dateTime, .systemStats] {
            #expect(!kind.options.isEmpty)
            #expect(kind.defaultSize.width >= kind.minimumSize.width && kind.defaultSize.width <= kind.maximumSize.width)
            #expect(!kind.summary.isEmpty && kind.title != kind.rawValue)
        }
    }
}
