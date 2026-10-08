import CoreGraphics
import Foundation
import Testing
@testable import NotchIslandKit

/// Defaults of their own, removed when done.
private func scratchDefaults() -> (UserDefaults, String) {
    let name = "notchisland.tests.\(UUID().uuidString)"
    return (UserDefaults(suiteName: name)!, name)
}

@Suite struct WidgetMigrationTests {
    /// A board as version 1 saved it: no versions, no ids, a plate as a flag.
    static let version1 = #"{"widgets":[{"kind":"nowPlaying","frame":{"column":0,"row":0,"width":7,"height":3},"options":["artwork","trackInfo"],"showsPlate":false},{"kind":"stopwatch","frame":{"column":7,"row":0,"width":4,"height":1},"options":[]}]}"#
    /// A board as version 2 saved it: each widget versioned, one per kind.
    static let version2 = #"{"widgets":[{"version":2,"kind":"stopwatch","frame":{"column":7,"row":1,"width":5,"height":1},"options":["readout","resetButton"],"sizes":{"readout":"large"},"tint":"teal","layout":"automatic","background":"plate","mirrored":true,"plainButtons":true},{"version":2,"kind":"volume","frame":{"column":7,"row":2,"width":5,"height":1},"options":["levelIcon"],"sizes":{},"tint":"automatic","layout":"automatic","background":"none","mirrored":false,"plainButtons":true}]}"#

    @Test func legacyIDsArePinned() {
        // Derived from the kind alone: the same on every Mac, in every build.
        #expect(WidgetID.legacy(.nowPlaying).description == "6AC515A9-7464-8E76-B7ED-78195F55CB25")
        // Version 8 (custom), RFC variant.
        let bytes = WidgetID.legacy(.stopwatch).rawValue.uuid
        #expect(bytes.6 >> 4 == 8 && bytes.8 >> 6 == 0b10)
    }

    @Test func version1BecomesVersion3() throws {
        let board = try JSONDecoder().decode(WidgetBoard.self, from: Data(Self.version1.utf8))
        #expect(board.grid == .standard)
        #expect(board.widgets.map(\.id) == [.legacy(.nowPlaying), .legacy(.stopwatch)])
        #expect(board.widget(.legacy(.nowPlaying))?.options == [.artwork, .trackInfo, .artist, .playbackButtons])
        #expect(board.widget(.legacy(.stopwatch))?.options == [.readout])
        #expect(WidgetMigration.version(of: Data(Self.version1.utf8)) == 1)
    }

    @Test func version2BecomesVersion3AndRoundTrips() throws {
        let board = try JSONDecoder().decode(WidgetBoard.self, from: Data(Self.version2.utf8))
        let stopwatch = try #require(board.widget(.legacy(.stopwatch)))
        #expect(stopwatch.options == [.readout, .resetButton])
        #expect(stopwatch.background == .plate)
        #expect(board.widget(.legacy(.volume))?.background == WidgetBackground.none)
        #expect(WidgetMigration.version(of: Data(Self.version2.utf8)) == 2)

        let data = try JSONEncoder().encode(board)
        #expect(WidgetMigration.version(of: data) == 3)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == ["version", "grid", "widgets", "parked", "foreign"])
        #expect(try JSONDecoder().decode(WidgetBoard.self, from: data) == board)
    }

    @Test func outOfBoundsAndOverlappingWidgetsAreParkedNotDropped() throws {
        let json = #"{"version":3,"grid":{"columns":12,"rows":3,"gap":8},"widgets":[{"kind":"stopwatch","frame":{"column":0,"row":0,"width":5,"height":1},"options":[]},{"kind":"dateTime","frame":{"column":3,"row":0,"width":3,"height":1},"options":[]},{"kind":"wifi","frame":{"column":11,"row":0,"width":2,"height":1},"options":[]}],"parked":[{"kind":"volume","frame":{"column":0,"row":2,"width":5,"height":1},"options":[]}],"foreign":[]}"#
        let board = try JSONDecoder().decode(WidgetBoard.self, from: Data(json.utf8))
        #expect(board.widgets.map(\.kind) == [.stopwatch])
        #expect(board.parked.map(\.kind) == [.dateTime, .wifi, .volume])
        // A round trip keeps them where they are.
        let again = try JSONDecoder().decode(WidgetBoard.self, from: JSONEncoder().encode(board))
        #expect(again == board)
    }

    @Test func foreignKindsAreKeptVerbatim() throws {
        let json = #"{"version":3,"widgets":[{"kind":"hologram","frame":{"column":0,"row":0,"width":2,"height":1},"beam":{"power":7.5,"on":true,"colours":["red",null]}},{"kind":"stopwatch","frame":{"column":7,"row":0,"width":5,"height":1},"options":["readout"]}],"parked":[{"kind":"teleporter","frame":{"column":0,"row":0,"width":1,"height":1}}]}"#
        let board = try JSONDecoder().decode(WidgetBoard.self, from: Data(json.utf8))
        #expect(board.widgets.map(\.kind) == [.stopwatch])
        #expect(board.foreign.count == 2)
        let written = try JSONEncoder().encode(board)
        let reread = try JSONDecoder().decode(WidgetBoard.self, from: written)
        #expect(reread.foreign == board.foreign)
        let hologram = try #require(board.foreign.first)
        guard case .object(let fields) = hologram else { Issue.record("not an object"); return }
        #expect(fields["kind"] == .string("hologram"))
        #expect(fields["beam"] == .object(["power": .number(7.5), "on": .bool(true), "colours": .array([.string("red"), .null])]))
    }

    @Test func foreignKindsThisBuildKnowsComeBack() throws {
        // Written to foreign by an older build; this one knows wifi and dateTime.
        let json = #"{"version":3,"widgets":[{"kind":"stopwatch","frame":{"column":7,"row":0,"width":5,"height":1},"options":[]}],"foreign":[{"kind":"wifi","frame":{"column":0,"row":0,"width":2,"height":1},"options":[]},{"kind":"dateTime","frame":{"column":7,"row":0,"width":3,"height":1},"options":[]},{"kind":"hologram","frame":{"column":0,"row":0,"width":2,"height":1}}]}"#
        let board = try JSONDecoder().decode(WidgetBoard.self, from: Data(json.utf8))
        #expect(board.widgets.map(\.kind) == [.stopwatch, .wifi])
        #expect(board.parked.map(\.kind) == [.dateTime])
        #expect(board.foreign.count == 1)
        guard case .object(let fields) = try #require(board.foreign.first) else { Issue.record("not an object"); return }
        #expect(fields["kind"] == .string("hologram"))
    }

    @Test func repeatedIDsAreRederivedTheSameWayEachTime() throws {
        let id = WidgetID()
        let widgets = (0..<3).map { index in
            IslandWidget(kind: .wifi, frame: GridRect(column: index * 2, row: 0, width: 2, height: 1),
                         options: IslandWidgetKind.wifi.defaultOptions, id: id)
        }
        let board = WidgetBoard(widgets: widgets)
        #expect(Set(board.widgets.map(\.id)).count == 3)
        #expect(board.widgets[0].id == id)
        #expect(board.widgets[1].id == WidgetID(name: "notchisland.widget.\(id).1"))
        #expect(WidgetBoard(widgets: widgets) == board)
    }

    @MainActor @Test func theOldBoardIsBackedUpOnceBeforeTheFirstWrite() throws {
        let (defaults, name) = scratchDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }
        let v2 = Data(Self.version2.utf8)
        defaults.set(v2, forKey: WidgetStore.key)

        let store = WidgetStore(defaults: defaults)
        #expect(store.board.contains(.legacy(.stopwatch)))
        // Reading alone writes nothing.
        #expect(defaults.data(forKey: WidgetMigration.backupKey) == nil)
        store.update(.legacy(.stopwatch)) { $0.background = .tinted }
        #expect(defaults.data(forKey: WidgetStore.key) == v2)   // not yet: the write waits
        store.flush()
        #expect(defaults.data(forKey: WidgetMigration.backupKey) == v2)
        let stored = try #require(defaults.data(forKey: WidgetStore.key))
        #expect(WidgetMigration.version(of: stored) == 3)

        // A later store, a later write: the backup stays the version 2 board.
        let later = WidgetStore(defaults: defaults)
        later.update(.legacy(.stopwatch)) { $0.background = .none }
        later.flush()
        #expect(defaults.data(forKey: WidgetMigration.backupKey) == v2)
        #expect(WidgetStore(defaults: defaults).board.widget(.legacy(.stopwatch))?.background == WidgetBackground.none)
    }

    @MainActor @Test func writesWaitForTheDelayAndFlushWritesAtOnce() async throws {
        let (defaults, name) = scratchDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }
        let store = WidgetStore(defaults: defaults)
        let added = store.add(.wifi)
        #expect(added == nil)   // the standard board is full
        store.remove(.legacy(.volume))
        #expect(defaults.data(forKey: WidgetStore.key) == nil)
        // Written once the delay is over (waited for generously: the tests run side by side).
        for _ in 0..<50 where defaults.data(forKey: WidgetStore.key) == nil {
            try await Task.sleep(for: .milliseconds(100))
        }
        let stored = try #require(defaults.data(forKey: WidgetStore.key))
        #expect(try JSONDecoder().decode(WidgetBoard.self, from: stored) == store.board)
        // Nothing waiting: flush writes nothing.
        defaults.removeObject(forKey: WidgetStore.key)
        store.flush()
        #expect(defaults.data(forKey: WidgetStore.key) == nil)
    }
}

@Suite struct WidgetGridTests {
    /// Any number of columns (the board is centred on the notch either way), within the ranges.
    @Test func gridsAreClamped() {
        let odd = BoardGrid(columns: 13, rows: 19, gap: 30)
        #expect(odd.columns == 13 && odd.rows == BoardGrid.rowRange.upperBound && odd.gap == BoardGrid.gapRange.upperBound)
        let tiny = BoardGrid(columns: 2, rows: 0, gap: 0)
        #expect(tiny.columns == BoardGrid.columnRange.lowerBound && tiny.rows == 1 && tiny.gap == BoardGrid.gapRange.lowerBound)
        let decoded = try? JSONDecoder().decode(BoardGrid.self, from: Data(#"{"columns":"many","rows":4}"#.utf8))
        #expect(decoded == BoardGrid(columns: 12, rows: 4, gap: 8))
    }

    @Test func kindLimitsAreTheReferenceOnTheStandardGrid() {
        for kind in IslandWidgetKind.allCases {
            #expect(BoardGrid.standard.minimum(for: kind) == kind.minimumSize)
            #expect(BoardGrid.standard.maximum(for: kind) == kind.maximumSize)
            #expect(BoardGrid.standard.defaultSize(for: kind) == kind.defaultSize)
        }
    }

    /// More cells are more room, not larger widgets: a kind's least and default size is its
    /// reference size in cells on any grid; its largest grows with the grid, so a widget may still
    /// span it.
    @Test func kindLimitsConvertToOtherGrids() {
        let fine = BoardGrid(columns: 18, rows: 6, gap: 6)
        #expect(fine.minimum(for: .nowPlaying) == IslandWidgetKind.nowPlaying.minimumSize)
        #expect(fine.defaultSize(for: .stopwatch) == IslandWidgetKind.stopwatch.defaultSize)
        #expect(fine.maximum(for: .wifi) == GridSize(width: 6, height: 4))
        let coarse = BoardGrid(columns: 8, rows: 2, gap: 8)
        #expect(coarse.minimum(for: .stopwatch) == IslandWidgetKind.stopwatch.minimumSize)
        #expect(coarse.maximum(for: .wifi) == IslandWidgetKind.wifi.maximumSize)
        for grid in [fine, coarse, BoardGrid(columns: 10, rows: 5, gap: 8)] {
            for kind in IslandWidgetKind.allCases {
                let lower = grid.minimum(for: kind), upper = grid.maximum(for: kind), preferred = grid.defaultSize(for: kind)
                #expect(lower.width >= 1 && lower.height >= 1 && upper.width <= grid.columns && upper.height <= grid.rows)
                #expect(lower.width <= preferred.width && preferred.width <= upper.width)
                #expect(lower.height <= preferred.height && preferred.height <= upper.height)
            }
        }
    }

    @Test func aFinerGridAndBackKeepsEveryFrame() {
        var board = WidgetBoard.standard
        board.setGrid(BoardGrid(columns: 12, rows: 6, gap: 8))
        #expect(board.widget(.legacy(.nowPlaying))?.frame == GridRect(column: 0, row: 0, width: 7, height: 6))
        #expect(board.widget(.legacy(.stopwatch))?.frame == GridRect(column: 7, row: 2, width: 5, height: 2))
        #expect(board.parked.isEmpty)
        board.setGrid(.standard)
        #expect(board == WidgetBoard.standard)
    }

    @Test func sharedEdgesStayShared() {
        var board = WidgetBoard.standard
        board.setGrid(BoardGrid(columns: 10, rows: 3, gap: 8))
        let nowPlaying = board.widget(.legacy(.nowPlaying))!.frame, stopwatch = board.widget(.legacy(.stopwatch))!.frame
        let volume = board.widget(.legacy(.volume))!.frame
        #expect(nowPlaying.maxColumn == stopwatch.column && stopwatch.column == volume.column)
        #expect(stopwatch.maxColumn == 10 && volume.maxColumn == 10 && stopwatch.maxRow == volume.row)
    }

    @Test func aCoarserGridParksWhatCannotFit() {
        // 36 one-cell controls fill the 12 × 3 board; 8 × 3 has room for 24 of them.
        var widgets: [IslandWidget] = []
        for row in 0..<3 {
            for column in 0..<12 {
                widgets.append(IslandWidget(kind: .wifi, frame: GridRect(column: column, row: row, width: 1, height: 1),
                                            options: [], id: WidgetID()))
            }
        }
        var board = WidgetBoard(widgets: widgets)
        #expect(board.widgets.count == 36)
        board.setGrid(BoardGrid(columns: 8, rows: 3, gap: 8))
        #expect(board.widgets.count == 24 && board.parked.count == 12)
        #expect(Set(board.widgets.map(\.id) + board.parked.map(\.id)) == Set(widgets.map(\.id)))
        for widget in board.widgets {
            #expect(board.isFree(widget.frame, for: widget.kind, excluding: widget.id))
        }
        // The board keeps its drawing order.
        let order = widgets.map(\.id).filter { id in board.widgets.contains { $0.id == id } }
        #expect(board.widgets.map(\.id) == order)
    }

    @Test func aShorterGridShrinksBeforeItParks() {
        var board = WidgetBoard.standard
        board.setGrid(BoardGrid(columns: 12, rows: 2, gap: 8))
        // 3 rows → 2: Now Playing 7 × 2, the stopwatch 5 × 1; what no longer fits beside them is parked.
        #expect(board.widget(.legacy(.nowPlaying))?.frame == GridRect(column: 0, row: 0, width: 7, height: 2))
        #expect(board.widget(.legacy(.stopwatch))?.frame.size == GridSize(width: 5, height: 1))
        #expect(board.widgets.count + board.parked.count == 5)
    }
}

@Suite struct WidgetInstanceTests {
    @Test func aKindMayBeOnTheBoardTwice() throws {
        var board = WidgetBoard(widgets: [])
        let firstResult = board.add(.stopwatch)
        let first = try #require(firstResult)
        let secondResult = board.add(.stopwatch)
        let second = try #require(secondResult)
        #expect(first != second && board.instances(of: .stopwatch).count == 2)
        #expect(board.first(of: .stopwatch)?.id == first)
        board.update(second) { $0.background = .tinted }
        #expect(board.widget(first)?.background == .plate && board.widget(second)?.background == .tinted)
        board.remove(first)
        #expect(board.instances(of: .stopwatch).map(\.id) == [second])
    }

    @Test func duplicateCopiesTheLookNearTheOriginal() throws {
        var board = WidgetBoard.standard
        board.remove(.legacy(.volume))
        board.update(.legacy(.stopwatch)) {
            $0.background = .tinted
            $0.options.remove(.resetButton)
        }
        // The only room left is the row under the stopwatch.
        let copyResult = board.duplicate(.legacy(.stopwatch))
        let copy = try #require(copyResult)
        let widget = try #require(board.widget(copy))
        #expect(widget.kind == .stopwatch && widget.background == .tinted && !widget.shows(.resetButton))
        #expect(widget.frame == GridRect(column: 7, row: 2, width: 5, height: 1))
        let another = board.duplicate(.legacy(.stopwatch))
        #expect(another == nil)
    }

    @Test func isFreeExcludesOnlyTheGivenInstance() throws {
        var board = WidgetBoard(widgets: [])
        let firstResult = board.add(.wifi)
        let first = try #require(firstResult)
        let frame = try #require(board.widget(first)?.frame)
        let secondResult = board.add(.wifi)
        let second = try #require(secondResult)
        #expect(board.isFree(frame, for: .wifi, excluding: first))
        #expect(!board.isFree(frame, for: .wifi, excluding: second))
        let moved = board.setFrame(frame, for: second)
        #expect(!moved)
    }

    @Test func routesOpenAKindOrAnInstance() throws {
        #expect(AppCommand.parse(URL(string: "notchisland://widget/stopwatch")!) == .editWidget(.kind(.stopwatch)))
        #expect(AppCommand.parse(URL(string: "notchisland://widget/nowplaying")!) == .editWidget(.kind(.nowPlaying)))
        let id = WidgetID.legacy(.stopwatch)
        #expect(AppCommand.parse(URL(string: "notchisland://widget/\(id)")!) == .editWidget(.instance(id)))
        #expect(AppCommand.parse(URL(string: "notchisland://widget/\(id.description.lowercased())")!) == .editWidget(.instance(id)))
        #expect(AppCommand.parse(URL(string: "notchisland://widget/nothing")!) == nil)
    }
}

@Suite struct WidgetSpecTests {
    @Test func everyKindHasASpec() {
        // The six base widgets first, then every control (as Wi-Fi) and level (as Volume) built on them.
        #expect(Array(IslandWidgetKind.allCases.prefix(6)) == [.wifi, .volume, .dateTime, .stopwatch, .nowPlaying, .systemStats])
        #expect(IslandWidgetKind.allCases.filter { $0.control == nil && $0.level == nil }
            == [.dateTime, .stopwatch, .nowPlaying, .systemStats, .worldClock, .clipboard, .battery, .batteryChart,
                .batteryTime, .batteryHealth, .batteryCycles, .batteryPower, .batteryTemperature, .charger, .batteryLastCharge,
                .uptime, .diskSpace, .timer, .shelf, .analogClock, .monthCalendar, .batteryUsage, .memory])
        // The figures are readouts as World Clock is: its parts, styled as its are.
        for kind in IslandWidgetKind.allCases where kind.isReadout {
            #expect(kind.spec.texts == [.value, .label] && kind.spec.buttons == [.symbol], "\(kind)")
        }
        #expect(IslandWidgetKind.allCases.compactMap(\.systemControl).sorted { $0.rawValue < $1.rawValue }
            == SystemControl.allCases.sorted { $0.rawValue < $1.rawValue })
        #expect(IslandWidgetKind.allCases.compactMap(\.level) == [.volume, .brightness, .keyboard])
        for kind in IslandWidgetKind.allCases {
            let spec = kind.spec
            #expect(!spec.elements.isEmpty && !spec.title.isEmpty && !spec.summary.isEmpty && spec.iconColors.count == 2, "\(kind)")
            #expect(Set(spec.elements.map(\.id)).count == spec.elements.count, "\(kind)")
            #expect(kind.minimumSize.width <= kind.defaultSize.width && kind.defaultSize.width <= kind.maximumSize.width)
            #expect(kind.minimumSize.height <= kind.defaultSize.height && kind.defaultSize.height <= kind.maximumSize.height)
            #expect(kind.maximumSize.width <= 12 && kind.maximumSize.height <= 3)
            // Offered, but a control that does not work on this Mac (True Tone on one without it).
            #expect(kind.isOffered || kind.systemControl.map { !ExtendedControls.isAvailable($0) } == true, "\(kind)")
            if spec.category == .controls { #expect(kind.control != nil) }
        }
        for category in WidgetCategory.allCases {
            #expect(!category.kinds.isEmpty, "\(category)")
        }
    }

    @Test func todaysElementsAreUnchanged() {
        #expect(IslandWidgetKind.nowPlaying.options == [.artwork, .trackInfo, .artist, .progress, .playbackButtons, .skipButtons,
                                                        .seekButtons])
        // Back and forward are there to be switched on, not on in a new widget.
        #expect(IslandWidgetKind.nowPlaying.defaultOptions == Set(IslandWidgetKind.nowPlaying.options).subtracting([.seekButtons]))
        #expect(IslandWidgetKind.stopwatch.defaultOptions == [.readout, .resetButton])
        // Those always drawn (a start button, a slider) have no switch.
        #expect(!IslandWidgetKind.stopwatch.options.contains(.stopwatchButton))
        #expect(!IslandWidgetKind.volume.options.contains(.levelSlider))
        #expect(!IslandWidgetKind.wifi.options.contains(.controlButton))
    }
}

@Suite struct PanelLayoutTests {
    nonisolated static let notches = [CGSize(width: 156, height: 28), CGSize(width: 185, height: 32), CGSize(width: 240, height: 38)]
    nonisolated static let screens = [CGSize.zero, CGSize(width: 1280, height: 800), CGSize(width: 1512, height: 982),
                          CGSize(width: 3456, height: 2234)]

    /// The default panel is 12 × 3 cells of 40 pt, 8 pt apart, at the island's scale, with the
    /// insets round them — within the screen; Siri grows out of the header as wide.
    @Test(arguments: notches, IslandScale.allCases)
    func theDefaultsAreTwelveByThreeCells(notch: CGSize, scale: IslandScale) {
        for screen in Self.screens {
            let layout = IslandLayout(notch: notch, scale: scale, screen: screen)
            let f = scale.factor
            let pitch = (48 * f).rounded()
            let size = layout.size(for: .expanded(.home))
            #expect(size.width == min(12 * pitch - 8 + 36, layout.maximumExpandedSize.width))
            #expect(size.height == notch.height + min(3 * pitch - 8 + 16, layout.maximumExpandedSize.height - notch.height))
            #expect(layout.size(for: .assistant(.list)).width == size.width)
            #expect(layout.replacing(panel: PanelLayout()) == layout)
        }
    }

    @Test func thePanelStaysWithinTheScreen() {
        let notch = CGSize(width: 185, height: 32)
        let huge = IslandLayout(notch: notch, scale: .large, screen: CGSize(width: 1024, height: 640),
                                panel: PanelSettings(cell: 90, gap: 20, columns: 30, rows: 8).layout)
        let size = huge.size(for: .expanded(.home))
        #expect(size.width == 1024 - 2 * IslandLayout.settingsSideMargin)
        #expect(size.height == (0.62 * 640).rounded(.down))
        // Siri as wide as the panel at most, the gallery too.
        #expect(huge.size(for: .assistant(.list)).width == size.width)
        #expect(huge.size(for: .assistant(.gallery)).width == size.width)
    }

    @Test func settingsAreClampedAndTolerant() throws {
        #expect(PanelSettings(cell: 999, gap: -5, columns: 99, rows: 0)
                == PanelSettings(cell: PanelSettings.cellRange.upperBound, gap: PanelSettings.gapRange.lowerBound,
                                 columns: PanelSettings.columnRange.upperBound, rows: PanelSettings.rowRange.lowerBound))
        let decoded = try JSONDecoder().decode(PanelSettings.self, from: Data(#"{"cell":"large","gap":30,"columns":7}"#.utf8))
        #expect(decoded.cell == 40 && decoded.gap == PanelSettings.gapRange.upperBound && decoded.columns == 7 && decoded.rows == 3)
        let empty = try JSONDecoder().decode(PanelSettings.self, from: Data("{}".utf8))
        #expect(empty == PanelSettings() && empty.layout == PanelLayout())
    }

    @MainActor @Test func preferencesKeepThePanel() {
        let (defaults, name) = scratchDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }
        let preferences = Preferences(defaults: defaults)
        #expect(preferences.panel == PanelSettings())
        preferences.panel = PanelSettings(cell: 32, gap: 6, columns: 15, rows: 4)
        #expect(Preferences(defaults: defaults).panel == PanelSettings(cell: 32, gap: 6, columns: 15, rows: 4))
    }
}
