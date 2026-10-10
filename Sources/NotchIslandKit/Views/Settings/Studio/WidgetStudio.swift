import AppKit
import Observation
import SwiftUI

/// Settings ▸ Widgets' shared state: what the stage edits.
@Observable final class WidgetStudio {
    enum Mode: Hashable, CaseIterable, Identifiable {
        var id: Self { self }

        var title: String {
            switch self {
            case .widgets: String(localized: "Widgets")
            case .topBar: String(localized: "Top Bar")
            case .size: String(localized: "Size")
            }
        }

        /// The board: widgets moved, resized, picked.
        case widgets
        /// The panel's header items.
        case topBar
        /// The panel's size and its grid.
        case size
    }

    var mode: Mode = .widgets
    /// The widget open in Customize, over all of Settings (`WidgetCustomizeView`); nil: none.
    var customizing: WidgetID?
    /// The page whose board the stage shows and edits (`AppModel.editedWidgets`).
    var page: ExpandedPage = .home
    /// The panel as an edge or a slider dragged in Size mode makes it, until the drag ends and it
    /// is stored: the stage draws it, the real panel is not staged again at every step.
    var draft: StudioDraft?
    /// What Size mode found when it was entered (`SizeSnapshot`); nil outside it.
    var sizeEntry: SizeSnapshot?
    /// Size mode's ready-made sizes are open (`ReadyMadeBox`), and what is on them in.
    var showsReadyMade = false
    var readyMadeContentIn = false
    /// The saved notch styles are open beside the page's title (`NotchStylesMenu`), and where.
    var showsNotchStyles = false
    var notchStylesFrame: CGRect = .zero
    /// What is picked of the top bar in Top Bar mode: its buttons and the picker's pages, one by a
    /// click, more with ⌘-click. Button Colour sets the colour of these (of everything, with none).
    var headerPicks: Set<HeaderPart> = []
    /// The one button picked, where it is the only pick (the stage's arrow keys and Delete move
    /// and remove it).
    var headerSelection: HeaderItem? {
        get {
            if headerPicks.count == 1, case .item(let item)? = headerPicks.first { return item }
            return nil
        }
        set { headerPicks = newValue.map { [.item($0)] } ?? [] }
    }

    /// A click on `part`: it alone is picked — let go again, if it was the only one; with ⌘, it
    /// joins the picks or leaves them.
    func pick(_ part: HeaderPart, adding: Bool) {
        if adding {
            headerPicks.formSymmetricDifference([part])
        } else {
            headerPicks = headerPicks == [part] ? [] : [part]
        }
    }

    /// Top Bar mode's steps back (⌘Z) and forward again (⌘⇧Z), and Size mode's.
    var headerHistory = EditHistory<HeaderLayout>()
    var sizeHistory = EditHistory<SizeSnapshot>()
    /// Size mode's panel and boards as last seen: what a change of them is a step back to.
    @ObservationIgnored var sizeSeen: SizeSnapshot?
    /// The kind being dragged out of the gallery, for the stage to show where it would land.
    @ObservationIgnored var draggedKind: IslandWidgetKind?

    /// The mode picked and on its way in (`switchMode`): the picker shows it at once.
    var pendingMode: Mode?
    /// The Widgets page's content under the stage: faded out while the mode switches.
    var contentOpacity: Double = 1
    @ObservationIgnored private var switching: Task<Void, Never>?

    /// To another mode, without a stutter. Building a mode's page and laying Settings out again
    /// takes one frame of ~100 ms whatever is done (measured: ~35 ms the page under the stage, the
    /// rest the stage and the scroll view); a spring over it ran at 30 fps after that frame. So the
    /// picker moves at once, the content fades out, the switch lands while nothing moves (the long
    /// frame is not seen), and the new content fades in: opacity only, no layout, every frame cheap.
    @MainActor func switchMode(to target: Mode) {
        guard target != (pendingMode ?? mode) else { return }
        switching?.cancel()
        guard target != mode else {
            // Back to the mode still shown, before it went.
            pendingMode = nil
            withAnimation(.easeOut(duration: Self.fadeIn)) { contentOpacity = 1 }
            return
        }
        pendingMode = target
        withAnimation(.easeIn(duration: Self.fadeOut)) { contentOpacity = 0 }
        switching = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.fadeOut))
            guard let self, !Task.isCancelled else { return }
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) {
                self.mode = target
                self.pendingMode = nil
            }
            // After the long frame: a fade started before it would be half over when it ends.
            try? await Task.sleep(for: .milliseconds(30))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: Self.fadeIn)) { self.contentOpacity = 1 }
        }
    }

    /// The ready-made sizes opened or closed as Customize's Open Widgets is (`WidgetVersionsMenu`),
    /// a fifth faster (asked for): the box unfolds out of the button, then what is on it comes in;
    /// that goes first on the way back.
    @MainActor func toggleReadyMade() {
        let pace = 0.8
        if showsReadyMade {
            withAnimation(.easeIn(duration: 0.12 * pace)) { readyMadeContentIn = false }
            withAnimation(.spring(duration: 0.38 * pace, bounce: 0.08).delay(0.06 * pace)) { showsReadyMade = false }
        } else {
            withAnimation(.spring(duration: 0.55 * pace, bounce: 0.22)) { showsReadyMade = true }
            withAnimation(.spring(duration: 0.45 * pace, bounce: 0.1).delay(0.1 * pace)) { readyMadeContentIn = true }
        }
    }

    /// Closed at once (another mode, the page left).
    @MainActor func closeReadyMade() {
        showsReadyMade = false
        readyMadeContentIn = false
    }

    private static let fadeOut: TimeInterval = 0.12
    private static let fadeIn: TimeInterval = 0.2
}

/// What something was before each change of it, the latest last, and the changes undone: ⌘Z and ⌘⇧Z
/// for what has no history of its own (the top bar, the panel's size). Changes close together — a
/// drag, a colour mixed — are one step.
struct EditHistory<Value: Equatable> {
    private(set) var undoStack: [Value] = []
    private(set) var redoStack: [Value] = []
    private var lastChange: TimeInterval = 0
    /// Being put back by `undo` or `redo`: the change that makes is no step.
    private var restored: Value?

    static var coalescing: TimeInterval { 0.6 }
    static var limit: Int { 60 }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    /// It has changed from `old` to `new`.
    mutating func note(from old: Value, to new: Value, at now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard old != new else { return }
        if restored == new {
            restored = nil
            return
        }
        restored = nil
        defer { lastChange = now }
        redoStack.removeAll()
        if now - lastChange < Self.coalescing, !undoStack.isEmpty { return }
        undoStack.append(old)
        if undoStack.count > Self.limit { undoStack.removeFirst() }
    }

    /// What it was before the last change, `current` kept to make that again; nil with none.
    mutating func undo(from current: Value) -> Value? {
        guard let previous = undoStack.popLast() else { return nil }
        redoStack.append(current)
        restored = previous
        lastChange = 0
        return previous
    }

    mutating func redo(from current: Value) -> Value? {
        guard let next = redoStack.popLast() else { return nil }
        undoStack.append(current)
        restored = next
        lastChange = 0
        return next
    }

    mutating func clear() {
        self = EditHistory()
    }
}
