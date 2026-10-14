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
    var customizing: WidgetID? {
        didSet { if customizing != oldValue { onCustomizingChange?(oldValue) } }
    }
    /// Customize opened or closed (the widget it had open before): Settings' history records it.
    @ObservationIgnored var onCustomizingChange: ((WidgetID?) -> Void)?
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

    /// The stage's height as drawn (it unfolds into Size mode's room and folds back, `StudioStage`),
    /// and the height its place in the page has: the same, but for an unfolding, when the place
    /// takes its new height at once and what is under the stage is shifted by the difference
    /// (`stageLag`) — so the page is laid out once, not at every frame of the spring.
    var stageShown: CGFloat?
    var stagePlace: CGFloat?
    /// How far above its place what is under the stage is drawn (negative: above).
    var stageLag: CGFloat { (stageShown ?? 0) - (stagePlace ?? stageShown ?? 0) }
    /// The stage's place as laid out (its height in the page): Top Bar's page takes the room under it.
    var stageMeasuredHeight: CGFloat = 0
    /// The stage's own height and the room Size mode gives it, as the page last worked them out:
    /// what the stage's height will be in a mode, known before the mode is set (`switchMode`).
    @ObservationIgnored var stageOwnHeight: CGFloat?
    @ObservationIgnored var stageSizeRoom: CGFloat?

    func stageHeight(in mode: Mode) -> CGFloat? {
        guard let own = stageOwnHeight else { return nil }
        return mode == .size ? max(own, (stageSizeRoom ?? 0).rounded()) : own
    }

    /// The mode picked and on its way in (`switchMode`): the picker shows it at once.
    var pendingMode: Mode?
    @ObservationIgnored private var switching: Task<Void, Never>?
    @ObservationIgnored private let modeSlide = GlassSlide()

    /// To another mode, without a stutter. Building a mode's page and laying Settings out again
    /// takes one frame of ~100 ms whatever is done (measured: ~35 ms the page under the stage, the
    /// rest the stage and the scroll view); a spring over it ran at 30 fps after that frame. So the
    /// picker moves at once, the content fades out, the switch lands while nothing moves (the long
    /// frame is not seen), and the new content fades in: opacity only, no layout, every frame cheap.
    @MainActor func switchMode(to target: Mode) {
        guard target != (pendingMode ?? mode) else { return }
        switching?.cancel()
        modeSlide.cancel()
        guard target != mode else {
            // Back to the mode still shown, before it went.
            pendingMode = nil
            DeckFade.fade(out: false, duration: Self.fadeIn)
            return
        }
        pendingMode = target
        DeckFade.fade(out: true, duration: Self.fadeOut)
        // Once the mode bar's glass has slid to its segment (`GlassSlide`), the content faded out.
        modeSlide.afterSettling(minimum: Self.fadeOut) { [weak self] in
            guard let self else { return }
            var instant = Transaction()
            instant.disablesAnimations = true
            // The stage's place takes the mode's height in the same layout as the mode's content
            // (`StudioStage` unfolds into it): set a turn later, when the stage's height is seen
            // to have changed, the page was laid out twice (~55 ms more on a performance core).
            let place = target != .topBar && self.stageShown != nil
                && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? self.stageHeight(in: target) : nil
            // The gallery follows the stage's foot along its spring (`GlidingHostingView`).
            if let place, let was = self.stagePlace, was != place { GalleryGlide.nextSpring = StudioStageSpring.unfold }
            withTransaction(instant) {
                self.mode = target
                self.pendingMode = nil
                if let place, self.stagePlace != nil { self.stagePlace = place }
            }
            // After the long frame: a fade started before it would be half over when it ends.
            self.switching = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(30))
                guard let self, !Task.isCancelled else { return }
                DeckFade.fade(out: false, duration: Self.fadeIn)
            }
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

    /// The page picked and on its way in (`switchPage`): the pickers show it at once.
    var pendingPage: ExpandedPage?
    /// The page the page bar's buttons are for, while a switch lands: the old one, so they change
    /// once the long turn of the switch is over and animate whole (`StudioPageBar`).
    var barPage: ExpandedPage?
    /// The page whose board is going while the shown one's comes (`StageIsland`), and how far the
    /// one has gone into the other (0–1).
    var outgoingPage: ExpandedPage?
    var boardBlend: Double = 1
    /// How opaque the going board was as it began to go.
    var outgoingFrom: Double = 1
    /// When the last fade began (`shownBlend`).
    @ObservationIgnored private var blendStarted: TimeInterval?
    /// Switches landed so far: a fade is only its own switch's to start and end.
    @ObservationIgnored private var landings = 0

    /// How far the shown board has faded in, as drawn now: the ease-in-out of `boardCrossfade`.
    private var shownBlend: Double {
        guard outgoingPage != nil else { return 1 }
        guard let started = blendStarted, boardBlend >= 1 else { return 0 }
        let t = min(1, max(0, (ProcessInfo.processInfo.systemUptime - started) / Self.boardCrossfade))
        return t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
    }
    @ObservationIgnored private var pageSwitching: Task<Void, Never>?
    /// The switch, held until the page bar's glass has slid to its segment (`GlassSlide`).
    @ObservationIgnored private let pageSlide = GlassSlide()

    /// To another page's board, without a stutter. The page bar's glass slides to its segment
    /// on the app's main thread, and the switch (another board on the stage, the gallery's Add and
    /// Edit, ~60–80 ms in one turn) stopped it for frames — the bar hitched on every pressed click.
    /// So the pickers move at once, the board shown stays while the glass slides (faded out then,
    /// the island stood empty for most of half a second, and empty all along under quick clicks),
    /// the switch lands once nothing moves, and the old board fades into the new one — both kept
    /// built, opacity only.
    @MainActor func switchPage(to target: ExpandedPage) {
        guard target != (pendingPage ?? page) else { return }
        pageSlide.cancel()
        // A fade still going (quick clicks) goes on as it was; the next one starts from where it is.
        guard target != page else {
            // Back to the page still shown, before it went.
            pendingPage = nil
            if page == .shelf { ShelfCardFade.fade(out: false, duration: Self.fadeIn) }
            return
        }
        pendingPage = target
        if page == .shelf { ShelfCardFade.fade(out: true, duration: Self.pageFadeOut) }
        pageSlide.afterSettling { [weak self] in
            guard let self else { return }
            var instant = Transaction()
            instant.disablesAnimations = true
            // What the shelf's card coming or going moves under it glides there, from where it
            // is before the switch (`GlidingHostingView`).
            GalleryGlide.arm()
            // The board going is as opaque as it is now: under quick clicks, part-way into a fade.
            let shown = self.shownBlend
            withTransaction(instant) {
                // The page bar's buttons stay the old page's in this long turn (`barPage`), and the
                // old board stays as it is, the new one built unseen under it.
                self.barPage = self.page
                // The board going is the one seen: if the last one never began to come, the one
                // before it is still the one going.
                if self.outgoingPage == nil || self.boardBlend > 0 {
                    self.outgoingPage = self.page
                    self.outgoingFrom = shown
                }
                self.boardBlend = 0
                self.page = target
                self.pendingPage = nil
            }
            // The shelf's card comes with the shelf's board (it goes while the glass slides).
            if target == .shelf { ShelfCardFade.fade(out: false, duration: Self.fadeIn) }
            self.landings += 1
            let landing = self.landings
            // Once the new board is drawn (the long turn and two shorter ones after it, ~150 ms):
            // started sooner, the old board faded while the new one was not there yet.
            self.pageSwitching = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(80))
                // A later switch has landed meanwhile: its own fade takes over.
                guard let self, !Task.isCancelled, self.landings == landing else { return }
                withAnimation(.easeInOut(duration: Self.boardCrossfade)) { self.boardBlend = 1 }
                self.blendStarted = ProcessInfo.processInfo.systemUptime
                self.barPage = nil
                // The old board let go once the bar's buttons have flowed into place: its teardown
                // (up to ~150 ms the first time) would stop them.
                try? await Task.sleep(for: .seconds(0.7))
                guard !Task.isCancelled, self.landings == landing else { return }
                var instant = Transaction()
                instant.disablesAnimations = true
                withTransaction(instant) { self.outgoingPage = nil }
            }
        }
    }

    /// Set at once, with no fade (a page removed, a widget opened on another page): whatever
    /// switch was on its way ends.
    @MainActor func showPage(_ target: ExpandedPage) {
        pageSwitching?.cancel()
        pageSlide.cancel()
        barPage = nil
        pendingPage = nil
        outgoingPage = nil
        boardBlend = 1
        outgoingFrom = 1
        page = target
    }

    private static let fadeOut: TimeInterval = 0.12
    private static let fadeIn: TimeInterval = 0.2
    /// The shelf's card fading out, while the page bar's glass slides.
    private static let pageFadeOut: TimeInterval = 0.14
    /// One page's board into another's.
    private static let boardCrossfade: TimeInterval = 0.28
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
