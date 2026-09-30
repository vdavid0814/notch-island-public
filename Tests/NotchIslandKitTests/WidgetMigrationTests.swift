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
    static let version2 = #"{"widgets":[{"version":2,"kind":"timer","frame":{"column":7,"row":0,"width":5,"height":2},"options":["ruler","readout","timerSeconds"],"sizes":{"readout":"large"},"tint":"teal","layout":"automatic","background":"plate","mirrored":true,"plainButtons":true},{"version":2,"kind":"shelf","frame":{"column":7,"row":2,"width":5,"height":1},"options":["previews"],"sizes":{},"tint":"automatic","layout":"automatic","background":"none","mirrored":false,"plainButtons":true}]}"#

    @Test func legacyIDsArePinned() {
        // Derived from the kind alone: the same on every Mac, in every build.
        #expect(WidgetID.legacy(.timer).description == "931627B4-3044-8766-A985-844E4BD29D04")
        #expect(WidgetID.legacy(.nowPlaying).description == "6AC515A9-7464-8E76-B7ED-78195F55CB25")
        // Version 8 (custom), RFC variant.
        let bytes = WidgetID.legacy(.timer).rawValue.uuid
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
        let timer = try #require(board.widget(.legacy(.timer)))
        #expect(timer.options == [.ruler, .readout, .timerSeconds])
        #expect(timer.sizes == [.readout: .large] && timer.tint == .teal && timer.mirrored)
        #expect(board.widget(.legacy(.shelf))?.background == WidgetBackground.none)
        #expect(WidgetMigration.version(of: Data(Self.version2.utf8)) == 2)

        let data = try JSONEncoder().encode(board)
        #expect(WidgetMigration.version(of: data) == 3)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == ["version", "grid", "widgets", "parked", "foreign"])
        #expect(try JSONDecoder().decode(WidgetBoard.self, from: data) == board)
    }

    @Test func outOfBoundsAndOverlappingWidgetsAreParkedNotDropped() throws {
        let json = #"{"version":3,"grid":{"columns":12,"rows":3,"gap":8},"widgets":[{"kind":"timer","frame":{"column":0,"row":0,"width":5,"height":2},"options":[]},{"kind":"battery","frame":{"column":3,"row":1,"width":3,"height":1},"options":[]},{"kind":"wifi","frame":{"column":11,"row":0,"width":2,"height":1},"options":[]}],"parked":[{"kind":"shelf","frame":{"column":0,"row":2,"width":5,"height":1},"options":[]}],"foreign":[]}"#
        let board = try JSONDecoder().decode(WidgetBoard.self, from: Data(json.utf8))
        #expect(board.widgets.map(\.kind) == [.timer])
        #expect(board.parked.map(\.kind) == [.battery, .wifi, .shelf])
        // A round trip keeps them where they are.
        let again = try JSONDecoder().decode(WidgetBoard.self, from: JSONEncoder().encode(board))
        #expect(again == board)
    }

    @Test func foreignKindsAreKeptVerbatim() throws {
        let json = #"{"version":3,"widgets":[{"kind":"hologram","frame":{"column":0,"row":0,"width":2,"height":1},"beam":{"power":7.5,"on":true,"colours":["red",null]}},{"kind":"timer","frame":{"column":7,"row":0,"width":5,"height":2},"options":["ruler"]}],"parked":[{"kind":"teleporter","frame":{"column":0,"row":0,"width":1,"height":1}}]}"#
        let board = try JSONDecoder().decode(WidgetBoard.self, from: Data(json.utf8))
        #expect(board.widgets.map(\.kind) == [.timer])
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
        // Written to foreign by an older build; this one knows wifi and battery.
        let json = #"{"version":3,"widgets":[{"kind":"timer","frame":{"column":7,"row":0,"width":5,"height":2},"options":[]}],"foreign":[{"kind":"wifi","frame":{"column":0,"row":0,"width":2,"height":1},"options":[]},{"kind":"battery","frame":{"column":7,"row":0,"width":3,"height":1},"options":[]},{"kind":"hologram","frame":{"column":0,"row":0,"width":2,"height":1}}]}"#
        let board = try JSONDecoder().decode(WidgetBoard.self, from: Data(json.utf8))
        #expect(board.widgets.map(\.kind) == [.timer, .wifi])
        #expect(board.parked.map(\.kind) == [.battery])
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
        #expect(store.board.contains(.legacy(.timer)))
        // Reading alone writes nothing.
        #expect(defaults.data(forKey: WidgetMigration.backupKey) == nil)
        store.update(.legacy(.timer)) { $0.tint = .pink }
        #expect(defaults.data(forKey: WidgetStore.key) == v2)   // not yet: the write waits
        store.flush()
        #expect(defaults.data(forKey: WidgetMigration.backupKey) == v2)
        let stored = try #require(defaults.data(forKey: WidgetStore.key))
        #expect(WidgetMigration.version(of: stored) == 3)

        // A later store, a later write: the backup stays the version 2 board.
        let later = WidgetStore(defaults: defaults)
        later.update(.legacy(.timer)) { $0.tint = .red }
        later.flush()
        #expect(defaults.data(forKey: WidgetMigration.backupKey) == v2)
        #expect(WidgetStore(defaults: defaults).board.widget(.legacy(.timer))?.tint == .red)
    }

    @MainActor @Test func writesWaitForTheDelayAndFlushWritesAtOnce() async throws {
        let (defaults, name) = scratchDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }
        let store = WidgetStore(defaults: defaults)
        let added = store.add(.battery)
        #expect(added == nil)   // the standard board is full
        store.remove(.legacy(.shelf))
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
    @Test func gridsAreClampedAndEven() {
        let odd = BoardGrid(columns: 13, rows: 9, gap: 30)
        #expect(odd.columns == 12 && odd.rows == 6 && odd.gap == 14)
        let tiny = BoardGrid(columns: 2, rows: 0, gap: 0)
        #expect(tiny.columns == 8 && tiny.rows == 2 && tiny.gap == 4)
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

    @Test func kindLimitsConvertToOtherGrids() {
        let fine = BoardGrid(columns: 24, rows: 6, gap: 6)
        #expect(fine.minimum(for: .nowPlaying) == GridSize(width: 6, height: 2))
        #expect(fine.maximum(for: .wifi) == GridSize(width: 8, height: 4))
        let coarse = BoardGrid(columns: 8, rows: 2, gap: 8)
        // 3 × 1 → 2 × 1 (rounded up), never below a cell; 4 × 2 → 2 × 1 (rounded down).
        #expect(coarse.minimum(for: .timer) == GridSize(width: 2, height: 1))
        #expect(coarse.maximum(for: .wifi) == GridSize(width: 2, height: 1))
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
        board.setGrid(BoardGrid(columns: 24, rows: 6, gap: 8))
        #expect(board.widget(.legacy(.nowPlaying))?.frame == GridRect(column: 0, row: 0, width: 14, height: 6))
        #expect(board.widget(.legacy(.timer))?.frame == GridRect(column: 14, row: 0, width: 10, height: 4))
        #expect(board.parked.isEmpty)
        board.setGrid(.standard)
        #expect(board == WidgetBoard.standard)
    }

    @Test func sharedEdgesStayShared() {
        var board = WidgetBoard.standard
        board.setGrid(BoardGrid(columns: 10, rows: 3, gap: 8))
        let nowPlaying = board.widget(.legacy(.nowPlaying))!.frame, timer = board.widget(.legacy(.timer))!.frame
        let shelf = board.widget(.legacy(.shelf))!.frame
        #expect(nowPlaying.maxColumn == timer.column && timer.column == shelf.column)
        #expect(timer.maxColumn == 10 && shelf.maxColumn == 10 && timer.maxRow == shelf.row)
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
        // 3 rows → 2: Now Playing 7 × 2, the timer 5 × 1 (round(2 · 2 / 3) = 1), the shelf under it.
        #expect(board.widget(.legacy(.nowPlaying))?.frame == GridRect(column: 0, row: 0, width: 7, height: 2))
        #expect(board.widget(.legacy(.timer))?.frame.size == GridSize(width: 5, height: 1))
        #expect(board.widgets.count + board.parked.count == 3)
    }
}

@Suite struct WidgetInstanceTests {
    @Test func aKindMayBeOnTheBoardTwice() throws {
        var board = WidgetBoard(widgets: [])
        let firstResult = board.add(.timer)
        let first = try #require(firstResult)
        let secondResult = board.add(.timer)
        let second = try #require(secondResult)
        #expect(first != second && board.instances(of: .timer).count == 2)
        #expect(board.first(of: .timer)?.id == first)
        board.update(second) { $0.tint = .green }
        #expect(board.widget(first)?.tint == .automatic && board.widget(second)?.tint == .green)
        board.remove(first)
        #expect(board.instances(of: .timer).map(\.id) == [second])
    }

    @Test func duplicateCopiesTheLookNearTheOriginal() throws {
        var board = WidgetBoard.standard
        board.remove(.legacy(.shelf))
        board.update(.legacy(.timer)) {
            $0.tint = .mint
            $0.style.format.showsSeconds = true
        }
        // The only room left is the row under the timer: a 5 × 1 copy (shrunk from 5 × 2).
        let copyResult = board.duplicate(.legacy(.timer))
        let copy = try #require(copyResult)
        let widget = try #require(board.widget(copy))
        #expect(widget.kind == .timer && widget.tint == .mint && widget.style.format.showsSeconds == true)
        #expect(widget.frame == GridRect(column: 7, row: 2, width: 5, height: 1))
        let another = board.duplicate(.legacy(.timer))
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

    @Test func reservedKindsAreNeverPlaced() {
        var board = WidgetBoard(widgets: [])
        for kind in IslandWidgetKind.allCases where !kind.spec.isImplemented {
            let added = board.add(kind)
            #expect(added == nil)
            #expect(!kind.isOffered)
        }
        #expect(board.widgets.isEmpty)
    }

    @Test func routesOpenAKindOrAnInstance() throws {
        #expect(AppCommand.parse(URL(string: "notchisland://widget/timer")!) == .editWidget(.kind(.timer)))
        #expect(AppCommand.parse(URL(string: "notchisland://widget/nowplaying")!) == .editWidget(.kind(.nowPlaying)))
        let id = WidgetID.legacy(.timer)
        #expect(AppCommand.parse(URL(string: "notchisland://widget/\(id)")!) == .editWidget(.instance(id)))
        #expect(AppCommand.parse(URL(string: "notchisland://widget/\(id.description.lowercased())")!) == .editWidget(.instance(id)))
        #expect(AppCommand.parse(URL(string: "notchisland://widget/nothing")!) == nil)
    }
}

@Suite struct WidgetSpecTests {
    @Test func everyKindHasASpecFromItsFamily() {
        #expect(IslandWidgetKind.allCases.count == 57)
        #expect(IslandWidgetKind.allCases.filter { !$0.spec.isImplemented }.count == 31)
        for family in WidgetFamily.allCases {
            for (kind, spec) in family.specs { #expect(spec.family == family, "\(kind)") }
        }
        for kind in IslandWidgetKind.allCases {
            let spec = kind.spec
            #expect(!spec.elements.isEmpty && !spec.title.isEmpty && !spec.summary.isEmpty && spec.iconColors.count == 2, "\(kind)")
            #expect(Set(spec.elements.map(\.id)).count == spec.elements.count, "\(kind)")
            #expect(kind.minimumSize.width <= kind.defaultSize.width && kind.defaultSize.width <= kind.maximumSize.width)
            #expect(kind.minimumSize.height <= kind.defaultSize.height && kind.defaultSize.height <= kind.maximumSize.height)
            #expect(kind.maximumSize.width <= 12 && kind.maximumSize.height <= 3)
            if spec.category == .controls { #expect(kind.systemControl != nil && spec.family == .controls) }
        }
    }

    @Test func theGalleryOffersTodaysKinds() {
        #expect(IslandWidgetKind.allCases.filter(\.isOffered).count == 26)
        for category in WidgetCategory.allCases {
            #expect(category.kinds.contains { $0.isOffered }, "\(category)")
        }
    }

    @Test func todaysElementsAreUnchanged() {
        #expect(IslandWidgetKind.nowPlaying.options == [.artwork, .trackInfo, .artist, .progress, .playbackButtons, .skipButtons])
        #expect(IslandWidgetKind.timer.defaultOptions == [.ruler, .readout])
        #expect(IslandWidgetKind.stopwatch.defaultOptions == [.readout, .resetButton])
        let sizable = IslandWidgetKind.allCases.flatMap { $0.spec.elements.filter { !$0.isSizable }.map(\.id) }
        #expect(Set(sizable) == [.progress, .skipButtons, .addMinute, .timerSeconds, .timerHours, .resetButton, .shelfActions])
        #expect(IslandWidgetKind.nowPlaying.spec.element(.skipButtons)?.parts == [ElementID(rawValue: "skipButtons.previous"),
                                                                                ElementID(rawValue: "skipButtons.next")])
    }

    @Test func extendedControlsAreStubsUntilBuilt() {
        let extended: [SystemControl] = [.soundOutput, .outputMute, .trueTone, .stageManager, .lowPowerMode, .screenMirroring,
                                         .missionControl, .showDesktop, .appsLauncher, .characterViewer, .displaySleep]
        for control in extended {
            #expect(!control.title.isEmpty && control.title != control.rawValue)
            #expect(!ExtendedControls.isOn(control))
        }
    }
}

@Suite struct PanelLayoutTests {
    nonisolated static let notches = [CGSize(width: 156, height: 28), CGSize(width: 185, height: 32), CGSize(width: 240, height: 38)]
    nonisolated static let screens = [CGSize.zero, CGSize(width: 1280, height: 800), CGSize(width: 1512, height: 982),
                          CGSize(width: 3456, height: 2234)]

    /// With the default panel settings every size is exactly what it was before they existed.
    @Test(arguments: notches, IslandScale.allCases)
    func defaultsChangeNothing(notch: CGSize, scale: IslandScale) {
        for screen in Self.screens {
            let layout = IslandLayout(notch: notch, scale: scale, screen: screen)
            let f = scale.factor
            let base = max(notch.width + 380, 600)
            #expect(layout.size(for: .expanded(.home))
                    == CGSize(width: (base * f).rounded(), height: notch.height + (160 * f).rounded()))
            #expect(layout.size(for: .assistant(.list)).width == (base * f).rounded())
            #expect(layout.replacing(panel: PanelLayout()) == layout)
        }
    }

    @Test func thePanelGrowsWithinTheScreen() {
        let notch = CGSize(width: 185, height: 32), screen = CGSize(width: 1512, height: 982)
        let wide = IslandLayout(notch: notch, scale: .standard, screen: screen,
                                panel: PanelSettings(widthFactor: 1.2, boardHeightFactor: 1.5).layout)
        #expect(wide.size(for: .expanded(.home)) == CGSize(width: 720, height: 32 + 240))
        // Siri grows out of the header as wide, times its own factor.
        #expect(wide.size(for: .assistant(.list)).width == 720)
        let huge = IslandLayout(notch: notch, scale: .large, screen: CGSize(width: 1024, height: 640),
                                panel: PanelSettings(widthFactor: 1.6, boardHeightFactor: 2.2).layout)
        let size = huge.size(for: .expanded(.home))
        #expect(size.width == 1024 - 2 * IslandLayout.settingsSideMargin)
        #expect(size.height == 32 + (0.62 * 640 - 32).rounded(.down))
        // Siri as wide as the panel at most, the gallery too.
        #expect(huge.size(for: .assistant(.list)).width == size.width)
        #expect(huge.size(for: .assistant(.gallery)).width == size.width)
    }

    @Test func settingsAreClampedAndTolerant() throws {
        #expect(PanelSettings(widthFactor: 9, boardHeightFactor: 0) == PanelSettings(widthFactor: 1.6, boardHeightFactor: 0.8))
        let decoded = try JSONDecoder().decode(PanelSettings.self, from: Data(#"{"widthFactor":"wide","boardHeightFactor":3}"#.utf8))
        #expect(decoded.widthFactor == 1 && decoded.boardHeightFactor == 2.2)
        let empty = try JSONDecoder().decode(PanelSettings.self, from: Data("{}".utf8))
        #expect(empty == PanelSettings() && empty.layout == PanelLayout())
    }

    @MainActor @Test func preferencesKeepThePanel() {
        let (defaults, name) = scratchDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }
        let preferences = Preferences(defaults: defaults)
        #expect(preferences.panel == PanelSettings())
        preferences.panel = PanelSettings(widthFactor: 1.3, boardHeightFactor: 1.1)
        #expect(Preferences(defaults: defaults).panel == PanelSettings(widthFactor: 1.3, boardHeightFactor: 1.1))
    }
}

@Suite struct WidgetStyleModelTests {
    static func styled() -> WidgetStyle {
        var style = WidgetStyle()
        var title = ElementStyle()
        title.text.points = 18
        title.text.weight = .bold
        title.text.labelOverride = "Now"
        title.colors[.primary] = .rgb(IslandTheme.RGB(red: 1, green: 0.5, blue: 0), alpha: 0.8)
        style.elements[.trackInfo] = title
        var cover = ElementStyle()
        cover.image.corners = .custom(12)
        cover.image.placement = .trailing
        style.elements[.artwork] = cover
        style.surface.fill = .named(.purple)
        style.surface.borderWidth = 1
        style.layout.alignment = .bottomLeading
        style.layout.order = [.artwork, .trackInfo]
        style.behaviour.tap = .url("https://example.com")
        style.format.clock24Hour = true
        return style
    }

    @Test func styleAndConfigRoundTrip() throws {
        let style = Self.styled()
        #expect(try JSONDecoder().decode(WidgetStyle.self, from: JSONEncoder().encode(style)) == style)
        var config = WidgetConfig()
        config.timeZone = "Europe/Budapest"
        config.apps = ["/Applications/Safari.app"]
        config.count = 3
        config.date = Date(timeIntervalSinceReferenceDate: 800_000_000)
        #expect(try JSONDecoder().decode(WidgetConfig.self, from: JSONEncoder().encode(config)) == config)
        // An empty style and config are not written at all.
        let plain = IslandWidget(kind: .timer, frame: GridRect(column: 0, row: 0, width: 5, height: 2), options: [.readout])
        let object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(plain)) as? [String: Any])
        #expect(object["style"] == nil)
        #expect(object["config"] == nil)
        #expect(object["id"] as? String == plain.id.description, "\(object)")
        // A config cleared away from its kind's default stays cleared.
        var cleared = IslandWidget(kind: .clipboard, frame: GridRect(column: 0, row: 0, width: 4, height: 2), options: [])
        #expect(cleared.config.count == 3)
        cleared.config = WidgetConfig()
        #expect(try JSONDecoder().decode(IslandWidget.self, from: JSONEncoder().encode(cleared)).config == WidgetConfig())
    }

    @Test func decodingIsLossyFieldByField() throws {
        let json = #"{"elements":{"trackInfo":{"text":{"weight":"bold","size":{"huge":{}},"lineLimit":"two"},"colors":{"primary":{"theme":{}},"glow":{"accent":{}}}},"artist":"nonsense"},"surface":{"borderWidth":"thick","artworkDim":0.5},"layout":{"order":["artwork",7,"trackInfo"]},"format":{"percentDecimals":1}}"#
        let style = try JSONDecoder().decode(WidgetStyle.self, from: Data(json.utf8))
        let title = try #require(style.elements[.trackInfo])
        #expect(title.text.weight == .bold && title.text.points == nil && title.text.lineLimit == nil)
        #expect(title.colors == [.primary: .theme])
        #expect(style.elements[.artist] == nil)
        #expect(style.surface.borderWidth == nil && style.surface.artworkDim == 0.5)
        #expect(style.layout.order == [.artwork, .trackInfo])
        #expect(style.format.percentDecimals == 1)
        let config = try JSONDecoder().decode(WidgetConfig.self, from: Data(#"{"count":"lots","label":"Tokyo","apps":["a",3]}"#.utf8))
        #expect(config.count == nil && config.label == "Tokyo" && config.apps == ["a"])
    }

    @Test func sanitizeClampsAndDropsWhatTheKindLacks() {
        var style = Self.styled()
        style.elements[.ruler] = ElementStyle()                         // empty: dropped
        var stray = ElementStyle()
        stray.text.italic = true
        style.elements[.percentage] = stray                              // Now Playing has no percentage
        style.elements[.trackInfo]?.text.points = 400
        style.elements[.trackInfo]?.text.lineLimit = 9
        style.elements[.trackInfo]?.text.labelOverride = "   "
        style.elements[.trackInfo]?.colors[.primary] = .rgb(IslandTheme.RGB(red: 2, green: -1, blue: 0.5), alpha: 3)
        style.layout.order = [.percentage, .artwork, .artwork]
        style.layout.contentScale = 4
        style.behaviour.tap = .shortcut("")
        style.format.percentDecimals = 7
        style.sanitize(for: .nowPlaying)
        #expect(Set(style.elements.keys) == [.trackInfo, .artwork])
        let text = style.elements[.trackInfo]!.text
        #expect(text.points == 96 && text.lineLimit == 3 && text.labelOverride == nil)
        #expect(style.elements[.trackInfo]!.colors[.primary] == .rgb(IslandTheme.RGB(red: 1, green: 0, blue: 0.5), alpha: 1))
        #expect(style.layout.order == [.artwork] && style.layout.contentScale == 1.5)
        #expect(style.behaviour.tap == .standard && style.format.percentDecimals == 2)

        var config = WidgetConfig()
        config.timeZone = "Mars/Olympus"
        config.count = 40
        config.label = "  Tokyo  "
        config.apps = (0..<12).map { "/Applications/\($0).app" }
        config.sanitize()
        #expect(config.timeZone == nil && config.count == 8 && config.label == "Tokyo" && config.apps?.count == 8)
    }

    @Test func aBoardSanitizesItsWidgetsStyles() throws {
        var board = WidgetBoard.standard
        board.update(.legacy(.timer)) { widget in
            var style = ElementStyle()
            style.line.thickness = 99
            widget.style.elements[.ruler] = style
            widget.style.elements[.artwork] = style
        }
        let timer = try #require(board.widget(.legacy(.timer)))
        #expect(Set(timer.style.elements.keys) == [.ruler] && timer.style.elements[.ruler]?.line.thickness == 16)
    }
}

@Suite struct ElementLayoutModelTests {
    static let wide = LayoutClass(height: .medium, aspect: .wide)

    static func layout() -> CustomLayout {
        let label = ElementID.custom(UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        return CustomLayout(
            authoredSize: CGSize(width: 320, height: 120), grid: InnerGrid(columns: 12, rows: 4),
            items: [
                ElementFrame(id: .artwork, rect: UnitRect(x: 0, y: 0, width: 0.4, height: 1), pinX: .leading, keepsAspect: true),
                ElementFrame(id: .trackInfo, rect: UnitRect(x: 0.45, y: 0.1, width: 0.55, height: 0.3)),
                ElementFrame(id: ElementID.skipButtons.part("next"), rect: UnitRect(x: 0.8, y: 0.7, width: 0.2, height: 0.3),
                             pinX: .trailing, pinY: .trailing),
                ElementFrame(id: label, rect: UnitRect(x: 0.45, y: 0.45, width: 0.3, height: 0.2), locked: true),
            ],
            parked: [.progress],
            decorations: [label: .label("Live")]
        )
    }

    @Test func roundTripsInsideAStyle() throws {
        var style = WidgetStyle()
        style.layout.arrangement = .custom(CustomLayouts(authored: Self.wide,
                                                         variants: [Self.wide: .custom(Self.layout()),
                                                                    LayoutClass(height: .short, aspect: .wide): .automatic]))
        let data = try JSONEncoder().encode(style)
        #expect(try JSONDecoder().decode(WidgetStyle.self, from: data) == style)
        // Size classes are keys of their own ("medium-wide").
        #expect(String(decoding: data, as: UTF8.self).contains("\"medium-wide\""))
        #expect(LayoutClass(name: "tall-narrow") == LayoutClass(height: .tall, aspect: .narrow))
        #expect(LayoutClass(name: "huge-wide") == nil)
    }

    @Test func decodingDropsOnlyWhatIsBroken() throws {
        let json = #"{"authoredSize":[300,100],"grid":{"columns":99,"rows":0},"items":[{"id":"artwork","rect":{"x":0,"y":0,"width":0.5,"height":1},"pinX":"sideways"},{"id":"trackInfo"}],"parked":["progress"],"decorations":{"custom.A":{"shape":{"_0":"circle"}},"custom.B":{"sparkle":{}}}}"#
        let layout = try JSONDecoder().decode(CustomLayout.self, from: Data(json.utf8))
        #expect(layout.grid == InnerGrid(columns: 24, rows: 1))
        #expect(layout.items.map(\.id) == [.artwork] && layout.items[0].pinX == .scale)
        #expect(layout.decorations == [ElementID(rawValue: "custom.A"): .shape(.circle)])
    }

    /// The padding a layout was drawn with is kept with it; one saved before it was recorded takes
    /// the kind's standard padding when sanitized.
    @Test func theAuthoredPaddingIsKeptOrTakesTheKindsStandard() throws {
        var layout = Self.layout()
        layout.authoredPadding = 9
        #expect(try JSONDecoder().decode(CustomLayout.self, from: JSONEncoder().encode(layout)).authoredPadding == 9)
        let json = #"{"authoredSize":[300,100],"authoredPadding":"wide","items":[]}"#
        let unrecorded = try JSONDecoder().decode(CustomLayout.self, from: Data(json.utf8))
        #expect(unrecorded.authoredPadding == nil)
        for (kind, padding) in [(IslandWidgetKind.nowPlaying, WidgetMetrics.padding), (.wifi, 4)] {
            var arrangement = ElementArrangement.custom(CustomLayouts(authored: Self.wide, variants: [Self.wide: .custom(unrecorded)]))
            arrangement.sanitize(for: kind)
            guard case .custom(let layouts) = arrangement, case .custom(let sanitized) = layouts.variants[Self.wide] else {
                Issue.record("\(kind): the layout was dropped")
                continue
            }
            #expect(sanitized.authoredPadding == padding, "\(kind)")
        }
    }

    @Test func sanitizeKeepsTheLayoutValidForTheKind() {
        var layout = Self.layout()
        let decoration = layout.items[3].id
        layout.items += [
            ElementFrame(id: .trackInfo, rect: UnitRect(x: 0, y: 0, width: 1, height: 1)),        // a second title
            ElementFrame(id: .percentage, rect: UnitRect(x: 0, y: 0, width: 0.2, height: 0.2)),   // not Now Playing's
            ElementFrame(id: .custom(), rect: UnitRect(x: 0, y: 0, width: 0.2, height: 0.2)),     // no decoration
        ]
        layout.items[1].rect = UnitRect(x: 0.9, y: -0.5, width: 0.5, height: 0.001)
        layout.parked.append(.artwork)                                                          // placed already
        layout.decorations[ElementID(rawValue: "notCustom")] = .symbol("star")
        layout.sanitize(for: IslandWidgetKind.nowPlaying.spec, standardPadding: WidgetMetrics.padding)

        #expect(layout.items.map(\.id) == [.artwork, .trackInfo, ElementID.skipButtons.part("next"), decoration])
        #expect(layout.items[1].rect == UnitRect(x: 0.5, y: 0, width: 0.5, height: UnitRect.minimumSide))
        // Every element of the kind is placed or parked; skip counts as placed through its part.
        #expect(layout.parked == [.progress, .artist, .playbackButtons])
        #expect(Array(layout.decorations.keys) == [decoration])
    }

    @Test func kindsWithoutCustomLayoutsLoseThem() {
        var style = WidgetStyle()
        style.layout.arrangement = .custom(CustomLayouts(authored: Self.wide, variants: [Self.wide: .custom(Self.layout())]))
        var siri = style
        siri.sanitize(for: .assistant)
        #expect(siri.layout.arrangement == nil)
        // A decoration's style survives with its layout, and goes with it.
        let decoration = Self.layout().items[3].id
        var labelStyle = ElementStyle()
        labelStyle.text.italic = true
        style.elements[decoration] = labelStyle
        var kept = style
        kept.sanitize(for: .nowPlaying)
        #expect(kept.elements[decoration] != nil)
        style.sanitize(for: .assistant)
        #expect(style.elements[decoration] == nil)
    }
}
