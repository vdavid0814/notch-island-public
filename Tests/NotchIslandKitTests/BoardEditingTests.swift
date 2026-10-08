import Foundation
import Testing
@testable import NotchIslandKit

@MainActor @Suite struct BoardEditingTests {
    private func store() -> WidgetStore {
        let defaults = UserDefaults(suiteName: "board-editing-\(UUID().uuidString)")!
        return WidgetStore(defaults: defaults, key: "board", seed: WidgetBoard(widgets: []))
    }

    /// ⌘Z takes the board back a step and ⌘⇧Z forward; a new change ends what could be redone.
    @Test func undoAndRedoStepThroughTheBoard() async throws {
        let store = store()
        #expect(!store.undo())
        let first = try #require(store.add(.wifi))
        try? await Task.sleep(for: .seconds(WidgetStore.coalescing + 0.05))
        let second = try #require(store.add(.volume))
        #expect(store.board.contains(first) && store.board.contains(second))
        #expect(store.undo())
        #expect(store.board.contains(first) && !store.board.contains(second))
        #expect(store.undo())
        #expect(store.board.widgets.isEmpty)
        #expect(store.redo())
        #expect(store.board.contains(first) && !store.board.contains(second))
        store.remove(first)
        #expect(!store.redo())
        #expect(store.undo())
        #expect(store.board.contains(first))
    }

    /// Changes in quick succession (a drag) are one step.
    @Test func aDragIsOneStep() async throws {
        let store = store()
        let id = try #require(store.add(.wifi))
        try? await Task.sleep(for: .seconds(WidgetStore.coalescing + 0.05))
        let start = try #require(store.board.widget(id)).frame
        for column in 1...3 { store.setFrame(GridRect(column: column, row: start.row, width: start.width, height: start.height), for: id) }
        #expect(store.board.widget(id)?.frame.column == 3)
        #expect(store.undo())
        #expect(store.board.widget(id)?.frame == start)
    }

    /// A new widget looks as most of the board's do: their background, its colour and strength.
    @Test func aNewWidgetTakesThePrevailingLook() throws {
        var board = WidgetBoard(widgets: [])
        let a = board.add(.wifi), b = board.add(.volume), c = board.add(.dateTime)
        let ids = try [a, b, c].map { try #require($0) }
        for id in ids.prefix(2) {
            board.update(id) {
                $0.background = .tinted
                $0.backgroundColor = IslandTheme.RGB(red: 1, green: 0, blue: 0)
                $0.backgroundOpacity = 0.3
            }
        }
        board.update(ids[2]) { $0.background = .none }
        let stopwatch = board.add(.stopwatch)
        let added = try #require(stopwatch)
        let widget = try #require(board.widget(added))
        #expect(widget.background == .tinted && widget.backgroundOpacity == 0.3
                && widget.backgroundColor == IslandTheme.RGB(red: 1, green: 0, blue: 0))
    }

    /// Dropped on the board: where it is let go when that is free, else the free place nearest.
    @Test func aDroppedWidgetLandsWhereItIsLetGo() throws {
        var board = WidgetBoard(widgets: [])
        let size = board.grid.defaultSize(for: .wifi)
        let anchor = GridRect(column: 4, row: 1, width: size.width, height: size.height)
        let first = board.add(.wifi, near: anchor)
        let id = try #require(first)
        #expect(board.widget(id)?.frame == anchor)
        let second = board.add(.wifi, near: anchor)
        let next = try #require(second)
        let frame = try #require(board.widget(next)?.frame)
        #expect(frame != anchor && abs(frame.row - anchor.row) <= 1)
    }
}
