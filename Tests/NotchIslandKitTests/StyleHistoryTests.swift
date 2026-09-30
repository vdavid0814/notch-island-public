import Foundation
import Observation
import Testing
@testable import NotchIslandKit

@Suite struct StyleHistoryTests {
    /// A style whose surface opacity is `value`: a step told apart from the others.
    private func style(_ value: Double) -> WidgetStyle {
        var style = WidgetStyle()
        style.surface.artworkDim = value
        return style
    }

    @Test func undoAndRedoWalkTheSnapshots() {
        var history = StyleHistory()
        history.record(style(0), property: \WidgetStyle.surface.artworkDim)
        history.record(style(0.1), property: \WidgetStyle.surface.artworkDim)
        #expect(history.undo(from: style(0.2)) == style(0.1))
        #expect(history.undo(from: style(0.1)) == style(0))
        #expect(history.undo(from: style(0)) == nil)
        #expect(history.redo(from: style(0)) == style(0.1))
        #expect(history.redo(from: style(0.1)) == style(0.2))
        #expect(history.redo(from: style(0.2)) == nil)
    }

    @Test func aDragOfOnePropertyIsOneStep() {
        var history = StyleHistory()
        history.begin()
        for step in 0..<5 { history.record(style(Double(step) / 10), property: \WidgetStyle.surface.artworkDim) }
        history.end()
        #expect(history.undoStack == [style(0)])
        #expect(history.undo(from: style(0.5)) == style(0))
    }

    @Test func onlyConsecutiveEditsOfOnePropertyInAGroupCoalesce() {
        var history = StyleHistory()
        history.begin()
        history.record(style(0), property: \WidgetStyle.surface.artworkDim)
        history.record(style(0.1), property: \WidgetStyle.surface.artworkDim)
        history.record(style(0.2), property: \WidgetStyle.layout.padding)
        history.record(style(0.3), property: \WidgetStyle.surface.artworkDim)
        history.end()
        #expect(history.undoStack == [style(0), style(0.2), style(0.3)])

        // Outside a group, every edit is its own step; a new group starts a new one.
        var plain = StyleHistory()
        plain.record(style(0), property: \WidgetStyle.surface.artworkDim)
        plain.record(style(0.1), property: \WidgetStyle.surface.artworkDim)
        plain.begin()
        plain.record(style(0.2), property: \WidgetStyle.surface.artworkDim)
        plain.end()
        plain.begin()
        plain.record(style(0.3), property: \WidgetStyle.surface.artworkDim)
        plain.end()
        #expect(plain.undoStack.count == 4)
    }

    @Test func aNewEditClearsRedo() {
        var history = StyleHistory()
        history.record(style(0), property: \WidgetStyle.surface.artworkDim)
        _ = history.undo(from: style(0.1))
        #expect(history.canRedo)
        history.record(style(0), property: \WidgetStyle.layout.padding)
        #expect(!history.canRedo)
        #expect(history.redo(from: style(0.2)) == nil)
    }

    @Test func theOldestStepsGoPastTheDepth() {
        var history = StyleHistory(depth: 3)
        for step in 0..<5 { history.record(style(Double(step) / 10), property: \WidgetStyle.surface.artworkDim) }
        #expect(history.undoStack == [style(0.2), style(0.3), style(0.4)])
    }
}

@MainActor @Suite struct EditorSessionTests {
    private func store() -> (WidgetStore, String) {
        let name = "notchisland.tests.\(UUID().uuidString)"
        return (WidgetStore(defaults: UserDefaults(suiteName: name)!), name)
    }

    /// Whether `change` changed the board (observed as a view would).
    private func writes(_ store: WidgetStore, _ change: () -> Void) -> Bool {
        // Observation calls back synchronously, on this thread, during `change`.
        nonisolated(unsafe) var changed = false
        withObservationTracking { _ = store.board } onChange: { changed = true }
        change()
        return changed
    }

    @Test func aBindingWritesTheStoreOncePerCommit() {
        let (store, name) = store()
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }
        let id = WidgetID.legacy(.nowPlaying)
        let session = EditorSession(widget: id, store: store)
        let opacity = session.binding(for: \.surface.artworkDim)

        #expect(writes(store) { opacity.wrappedValue = 0.4 })
        #expect(store.board.widget(id)?.style.surface.artworkDim == 0.4)
        #expect(session.history.undoStack.count == 1)
        // The same value again is no change: nothing written, nothing to undo.
        #expect(!writes(store) { opacity.wrappedValue = 0.4 })
        #expect(session.history.undoStack.count == 1)
        // Reading writes nothing.
        #expect(!writes(store) { _ = opacity.wrappedValue })
    }

    @Test func aDragIsOneUndoStep() {
        let (store, name) = store()
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }
        let id = WidgetID.legacy(.nowPlaying)
        let session = EditorSession(widget: id, store: store)
        let opacity = session.binding(for: \.surface.artworkDim)

        session.beginEdit()
        for step in 1...5 {
            #expect(writes(store) { opacity.wrappedValue = Double(step) / 10 })
        }
        session.endEdit()
        #expect(store.board.widget(id)?.style.surface.artworkDim == 0.5)
        #expect(session.history.undoStack.count == 1)

        session.undo()
        #expect(store.board.widget(id)?.style.surface.artworkDim == nil)
        session.redo()
        #expect(store.board.widget(id)?.style.surface.artworkDim == 0.5)
    }

    /// A value out of range is compared as the store keeps it (clamped): the same clamped value
    /// again is no change, and one undo restores the original.
    @Test func aClampedValueIsOneUndoStep() {
        let (store, name) = store()
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }
        let id = WidgetID.legacy(.nowPlaying)
        let session = EditorSession(widget: id, store: store)
        let opacity = session.binding(for: \.surface.artworkDim)

        opacity.wrappedValue = 1.5
        #expect(!writes(store) { opacity.wrappedValue = 1.5 })
        opacity.wrappedValue = 1.5
        #expect(store.board.widget(id)?.style.surface.artworkDim == 1)
        #expect(session.history.undoStack.count == 1)
        session.undo()
        #expect(store.board.widget(id)?.style.surface.artworkDim == nil)
    }

    /// Undo's availability is told only when it changes: a drag's later steps, merged into its
    /// first, tell nothing.
    @Test func aMergedStepDoesNotNotifyUndoObservers() {
        let (store, name) = store()
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }
        let session = EditorSession(widget: .legacy(.nowPlaying), store: store)
        let opacity = session.binding(for: \.surface.artworkDim)
        nonisolated(unsafe) var notified = 0
        func observe() {
            withObservationTracking { _ = session.canUndo; _ = session.canRedo } onChange: { notified += 1 }
        }

        session.beginEdit()
        observe()
        opacity.wrappedValue = 0.1
        #expect(notified == 1)
        #expect(session.canUndo)
        observe()
        opacity.wrappedValue = 0.2
        opacity.wrappedValue = 0.3
        session.endEdit()
        #expect(notified == 1)
        #expect(session.history.undoStack.count == 1)

        session.undo()
        #expect(notified == 2)
        #expect(!session.canUndo && session.canRedo)
    }
}
