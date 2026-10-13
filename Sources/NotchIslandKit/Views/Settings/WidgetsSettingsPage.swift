import AppKit
import SwiftUI

/// Settings ▸ Widgets: a live stage over the gallery of built-in widgets.
///
/// - **Stage**: a Mac desktop (the default macOS wallpaper, or the user's own) with its menu bar,
///   and the open island hanging from the notch at its real size. The widgets are arranged right
///   there — drag to move, drag a corner to resize, everything snaps to the grid.
/// - **Inspector** (a widget is selected): its background, and a tile for each element inside it
///   that switches it on or off.
/// - **Gallery** (nothing selected): every built-in widget as a compact card with a live preview,
///   grouped by category. Nothing is downloaded or bought: Add puts the widget on the island and
///   selects it, Edit selects one that is already there.
struct WidgetsSettingsPage: View {
    @Environment(AppModel.self) private var model
    @State private var selection: WidgetID?
    /// Two or more widgets picked with ⌘-click: edited together.
    @State private var group: Set<WidgetID> = []
    @State private var notice: String?
    /// The scroll view's height, and the Size mode's controls': in Size mode the stage takes the
    /// room they leave, so the controls sit at the window's bottom.
    @State private var viewportHeight: CGFloat = 0
    @State private var inspectorHeight: CGFloat = 0
    /// The gallery's own height, as its graph lays it out (`GalleryHost`).
    @State private var galleryHeight: CGFloat = 400
    @Environment(\.settingsPageVisit) private var visit
    /// Handed to the inspector's own graph (`InspectorLayer`).
    @Environment(\.self) private var environment
    @AppStorage(DesktopBackdropStyle.key) private var backdrop: DesktopBackdropStyle = DesktopBackdropStyle.defaultStyle
    /// Letting go of the picks once the page has gone (`pickResetDelay`).
    @State private var pendingReset: Timer?

    var body: some View {
        ScrollViewReader { scroller in
            ScrollView {
                VStack(alignment: .leading, spacing: Self.spacing) {
                    // The room Size mode gives the stage, known in every mode (`WidgetStudio.stageHeight`).
                    // (No inset at the page's foot in Size mode: `bottomInset`.)
                    let sizeRoom = viewportHeight - Self.topInset - Self.spacing - inspectorHeight
                    let _ = model.studio.stageSizeRoom = sizeRoom
                    StudioStage(selection: $selection, group: $group, backdrop: $backdrop, notice: notice,
                                fillHeight: model.studio.mode == .size ? sizeRoom : 0)
                        // For Top Bar's page alone (`TopBarSlot`): kept as the page's own state, every
                        // change of it had the whole page worked out again, a turn after each switch.
                        .onGeometryChange(for: CGFloat.self) { $0.size.height.rounded() } action: { model.studio.stageMeasuredHeight = $0 }
                        .id(StudioAnchor.stage)
                    // Every mode's content is built once and kept (`ModeDeck`): another mode, a widget
                    // picked or let go, is one of them shown instead of another — nothing is built
                    // again (building the gallery's cards, or Size's controls the first time, was the
                    // long frame each switch began with).
                    let picked = group.filter { model.editedWidgets.board.contains($0) }
                    let mode = model.studio.mode
                    let inspects = mode == .widgets && (picked.count >= 2 || selection.map { model.editedWidgets.board.contains($0) } == true)
                    let shown: ModeDeck.Slot = mode == .topBar ? .topBar : mode == .size ? .size : inspects ? .inspector : .gallery
                    ModeDeck(shown: shown) {
                        // Each mode's content in a layer of its own, faded out and in on the render
                        // server as the mode switches (`DeckFade`): faded by SwiftUI, every frame of
                        // it drew the content again (9–14 ms a frame into Size mode, measured).
                        // As tall as the room under the stage: its Reset is level with the sidebar's foot.
                        MeasuredHosting(input: TopBarSlot.Input(room: viewportHeight - Self.topInset - Self.spacing - bottomInset,
                                                                isShown: shown == .topBar),
                                        made: DeckFade.register) { input in
                            TopBarSlot(room: input.room, isShown: input.isShown)
                                .environment(\.self, environment)
                        }
                        .deckSlot(.topBar, shown: shown)
                        MeasuredHosting(input: true, made: DeckFade.register, measured: { inspectorHeight = $0 }) { _ in
                            VStack(alignment: .leading, spacing: 16) {
                                SizeInspector()
                                ParkedTray()
                            }
                            // Its ready-made sizes: out of their button, over the Size cards and buttons.
                            .overlayPreferenceValue(ReadyMadeAnchors.self, alignment: .topLeading) { anchors in
                                ReadyMadeOverlay(anchors: anchors)
                            }
                            .environment(\.self, environment)
                        }
                        .modifier(UnderStage())
                        .deckSlot(.size, shown: shown)
                        VStack(alignment: .leading, spacing: 22) {
                            // The shelf's card, in a layer of its own faded in and out on the render
                            // server (`ShelfCardFade`). Always there, measured, and only as tall as it
                            // is on the shelf's page: built as the shelf came, it was measured a turn
                            // later — the gallery under it jumped instead of gliding, and the card
                            // was half faded in before it had its height.
                            let isShelf = model.studio.page == .shelf
                            MeasuredHosting(input: true, made: { view in
                                ShelfCardFade.made(view, isShown: isShelf)
                                DeckFade.register(view)
                            }) { _ in
                                StudioCard("Shelf", subtitle: "Files dropped on the notch wait on this page. It has no widgets to arrange; General switches it on and off.") {
                                    EmptyView()
                                }
                                .environment(\.colorScheme, .dark)
                            }
                            .frame(height: isShelf ? nil : 0, alignment: .top)
                            // No gap for it either while it is not there.
                            .padding(.bottom, isShelf ? 0 : -22)
                            .allowsHitTesting(isShelf)
                            .accessibilityHidden(!isShelf)
                            .modifier(UnderStage())
                            ParkedTray()
                                .modifier(UnderStage())
                            // In a view graph of its own (`GalleryHost`): kept built while another
                            // mode or a picked widget is shown, but out of this page's graph.
                            GalleryHost(isShown: shown == .gallery, isShelf: model.studio.page == .shelf, height: galleryHeight,
                                        board: model.editedWidgets.board, model: model, visit: visit,
                                        add: { add($0, scroller: scroller) },
                                        open: { kind in
                                            if let id = model.editedWidgets.board.first(of: kind)?.id { select(id, scroller: scroller) }
                                        },
                                        measured: { height in if galleryHeight != height { galleryHeight = height } })
                        }
                        .deckSlot(.gallery, shown: shown)
                        // The picked widget's inspector in a layer of its own, coming up into place on
                        // the render server as a widget is picked (`InspectorLayer`). Moved in by
                        // SwiftUI, the whole page was laid out at every frame of the spring.
                        let inspected = Self.inspected(mode: mode, picked: picked, selection: selection,
                                                       board: model.editedWidgets.board)
                        MeasuredHosting(input: inspected, made: InspectorLayer.made,
                                        changing: { old, new, view in
                                            if !new.isEmpty, new != old { InspectorLayer.rise(view) }
                                        }) { inspected in
                            Group {
                                if inspected.count >= 2 {
                                    GroupInspector(ids: Set(inspected), selection: $selection, group: $group)
                                } else if let id = inspected.first {
                                    WidgetInspector(id: id, selection: $selection, notice: $notice)
                                }
                            }
                            .environment(\.self, environment)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .deckSlot(.inspector, shown: shown)
                    }
                }
                // As wide as the pages' room: that is a box beside the sidebar's, as far from the
                // island's side and its foot as the sidebar is (`SettingsSurfaceView`).
                .padding(.top, Self.topInset)
                .padding(.bottom, bottomInset)
                // A row added or taken away while sizing grows the stage: what is under it glides.
                .animation(.spring(duration: 0.3, bounce: 0.05), value: model.studio.draft?.panel.rows)
            }
            // Its scroller stands out in the gap beside the room (`SettingsEdgeScroller`): the
            // room's own ran over the cards at its edge.
            .scrollIndicators(.hidden)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewportHeight = $0 }
        }
        .background { StudioUndoKeys(selection: $selection, group: $group) }
        .onAppear {
            takeRequestedEdit()
            if model.studio.sizeEntry == nil { noteSizeEntry() }
        }
        .onChange(of: model.editingWidget) { takeRequestedEdit() }
        // Another page's board (from either picker): the picks on the old one end.
        .onChange(of: model.studio.page) {
            selection = nil
            group = []
        }
        .onChange(of: model.studio.mode) { _, mode in
            // Each mode's own picks and drafts end with it.
            if mode != .widgets {
                selection = nil
                group = []
            }
            if mode != .topBar { model.studio.headerSelection = nil }
            if mode != .size {
                model.studio.draft = nil
                model.studio.closeReadyMade()
            }
            noteSizeEntry()
        }
        .onDisappear(perform: left)
        // Kept between visits (`SettingsPageDeck`): left as a page that goes, and shown again as
        // a new one, with nothing picked.
        .onSettingsPageVisit(shown: {
            // Shown again before the picks were let go: let go now, before it is drawn.
            if let reset = pendingReset {
                reset.invalidate()
                pendingReset = nil
                forgetPicks()
            }
            takeRequestedEdit()
            noteSizeEntry()
        }, hidden: {
            left()
            // Nothing picked when it is shown again — but let go a moment later, unseen, on the
            // efficiency cores: with a widget picked, the gallery comes back in its place (54 cards
            // and their previews built again), which in the close's own turn was most of closing
            // Settings (~1 s of CPU, Energy Impact ~1600–1900, measured). A run-loop timer, so the
            // lowered priority holds for its turn.
            pendingReset?.invalidate()
            pendingReset = nil
            guard selection != nil || !group.isEmpty || notice != nil else { return }
            let reset = Timer(timeInterval: Self.pickResetDelay, repeats: false) { _ in
                MainActor.assumeIsolated {
                    pendingReset = nil
                    MainThrift.lowPower(for: 1.5)
                    forgetPicks()
                }
            }
            RunLoop.main.add(reset, forMode: .common)
            pendingReset = reset
        })
        .task(id: notice) {
            guard notice != nil else { return }
            try? await Task.sleep(for: .seconds(4))
            notice = nil
        }
    }

    /// After the page has gone (Settings' close takes ~0.4 s).
    private static let pickResetDelay: TimeInterval = 1

    private func forgetPicks() {
        var quiet = Transaction()
        quiet.disablesAnimations = true
        withTransaction(quiet) {
            selection = nil
            group = []
            notice = nil
        }
    }

    private static let topInset: CGFloat = 10
    /// Under the page: in Size and Top Bar mode its controls end where the pages' room does,
    /// level with the sidebar's foot.
    private var bottomInset: CGFloat { model.studio.mode == .widgets ? 28 : 0 }
    private static let spacing: CGFloat = 22

    /// What the inspector shows: the picked widgets (two or more), the selected one, or none.
    static func inspected(mode: WidgetStudio.Mode, picked: Set<WidgetID>, selection: WidgetID?, board: WidgetBoard) -> [WidgetID] {
        guard mode == .widgets else { return [] }
        if picked.count >= 2 { return picked.sorted { $0.rawValue.uuidString < $1.rawValue.uuidString } }
        guard let selection, board.contains(selection) else { return [] }
        return [selection]
    }

    /// Exactly the area the home page gives its board.
    static func boardSize(_ layout: IslandLayout) -> CGSize { BoardSizing.board(layout) }

    private func left() {
        model.studio.draft = nil
        model.studio.headerPicks = []
        model.studio.headerHistory.clear()
        model.studio.sizeHistory.clear()
        model.studio.sizeSeen = nil
        model.studio.sizeEntry = nil
        model.studio.closeReadyMade()
        model.studio.showsNotchStyles = false
    }

    /// Size mode entered, or shown again: what Reset Size goes back to is what it finds now.
    private func noteSizeEntry() {
        let studio = model.studio
        studio.sizeEntry = studio.mode == .size ? model.sizeSnapshot() : nil
        // Each mode's steps back are its own: they end with it (a step back in Size puts every
        // board back as it was, and must not take what Widgets mode did since with it).
        studio.sizeSeen = studio.sizeEntry
        if studio.mode != .size { studio.sizeHistory.clear() }
        if studio.mode != .topBar { studio.headerHistory.clear() }
    }

    /// "Edit …" from a widget's context menu in the island.
    private func takeRequestedEdit() {
        guard let id = model.editingWidget else { return }
        model.editingWidget = nil
        guard model.editedWidgets.board.contains(id) else { return }
        model.studio.mode = .widgets
        selection = id
    }

    private func select(_ id: WidgetID, scroller: ScrollViewProxy) {
        selection = id
        withAnimation(.spring(duration: 0.4)) { scroller.scrollTo(StudioAnchor.stage, anchor: .top) }
    }

    private func add(_ kind: IslandWidgetKind, scroller: ScrollViewProxy) {
        var added: WidgetID?
        withAnimation(.spring(duration: 0.35, bounce: 0.2)) { added = model.editedWidgets.add(kind) }
        if let added {
            select(added, scroller: scroller)
        } else {
            NSSound.beep()
            notice = "No room for \(kind.title). Make a widget smaller or remove one first."
            withAnimation(.spring(duration: 0.4)) { scroller.scrollTo(StudioAnchor.stage, anchor: .top) }
        }
    }
}

private enum StudioAnchor: Hashable { case stage }

/// The Widgets page's content under the stage: every mode's, built once and kept, one shown. As
/// large as the one shown; the others are laid out at its width, unseen and untouchable, so showing
/// one costs no building and no first layout.
private struct ModeDeck: Layout {
    enum Slot: Int { case topBar, size, gallery, inspector }

    var shown: Slot

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.indices.contains(shown.rawValue) else { return .zero }
        return subviews[shown.rawValue].sizeThatFits(proposal)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            subview.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(width: bounds.width, height: nil))
        }
    }
}

private extension View {
    /// One of `ModeDeck`'s: seen and used only while it is the one shown. What fades as it comes is
    /// faded on the render server (the inspector's, the gallery's layers; a mode's content with
    /// `WidgetStudio.contentOpacity`): faded here, the page was drawn again at every frame.
    func deckSlot(_ slot: ModeDeck.Slot, shown: ModeDeck.Slot) -> some View {
        opacity(slot == shown ? 1 : 0)
            .allowsHitTesting(slot == shown)
            .accessibilityHidden(slot != shown)
    }
}

/// The widget gallery in a view graph of its own, as tall as its content.
///
/// Kept built while it is not shown — another mode, or a widget picked — so coming back to it builds
/// nothing. Kept in the page's own graph it made every update of the page go over its fifty cards
/// and their previews: a pointer's move while something was dragged on the page took 5.6 ms of the
/// main thread with it there and 2.1 without (measured). In its own graph, hidden while unseen, the
/// page's updates pass it by; its content is handed to it again only when what it shows changes —
/// the board its cards tell of (which are on the island), and only while it is the one shown. Told
/// at every coming and going that it was seen or unseen, its fifty-five cards were gone over each
/// time: ~50–60 ms of a performance core in the turn after every switch of mode and every widget
/// picked or let go (measured with `NI_TRACE`).
private struct GalleryHost: NSViewRepresentable {
    let isShown: Bool
    /// The shelf's page: nothing is added to it — faint, and not to be clicked.
    let isShelf: Bool
    let height: CGFloat
    /// The edited board, as the cards show it (read by the page, not by the gallery's own graph).
    let board: WidgetBoard
    let model: AppModel
    let visit: SettingsPageVisit?
    let add: (IslandWidgetKind) -> Void
    let open: (IslandWidgetKind) -> Void
    /// Its content's height, as laid out.
    let measured: (CGFloat) -> Void

    /// What the gallery's content was last built from.
    fileprivate struct Input: Equatable {
        var board: WidgetBoard
        var isShelf: Bool
    }

    @MainActor final class Coordinator {
        fileprivate var input: Input?
        var add: (IslandWidgetKind) -> Void = { _ in }
        var open: (IslandWidgetKind) -> Void = { _ in }
        var measured: (CGFloat) -> Void = { _ in }
        weak var view: GlidingHostingView?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> GlidingHostingView {
        follow(context.coordinator)
        context.coordinator.input = Input(board: board, isShelf: isShelf)
        let view = GlidingHostingView(rootView: root(context.coordinator))
        // Its size comes from here: its width the page's, its height the one it measured.
        view.sizingOptions = []
        view.safeAreaRegions = []
        // Laid out the first time even unseen (the page is built before it is first shown).
        view.forcesLayout = true
        view.isHidden = !isShown
        // Faint on the shelf's page (dimmed on the render server as the page switches).
        view.alphaValue = isShelf ? Self.shelfAlpha : 1
        context.coordinator.view = view
        GalleryGlide.view = view
        DeckFade.register(view)
        return view
    }

    func updateNSView(_ view: GlidingHostingView, context: Context) {
        follow(context.coordinator)
        if view.isHidden == isShown {
            view.isHidden = !isShown
            // Back from a picked widget: in again on the render server.
            if isShown, view.window != nil { view.fadeInOnRenderServer(duration: 0.2) }
        }
        // Unseen, it stands still: moving a widget on the stage does not go over its cards. It
        // catches up when it is shown again, if anything it shows has changed.
        guard isShown else { return }
        let input = Input(board: board, isShelf: isShelf)
        guard context.coordinator.input != input else { return }
        if context.coordinator.input?.isShelf != isShelf {
            PerfTrace.mark("gallery dims \(isShelf)")
            NSAnimationContext.runAnimationGroup { animation in
                animation.duration = 0.25
                animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
                view.animator().alphaValue = isShelf ? Self.shelfAlpha : 1
            }
        }
        context.coordinator.input = input
        view.rootView = root(context.coordinator)
    }

    static let shelfAlpha: CGFloat = 0.35

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: GlidingHostingView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 600, height: max(height, 1))
    }

    /// What the gallery calls back is the page's as it stands now, whichever content it was built with.
    private func follow(_ coordinator: Coordinator) {
        coordinator.add = add
        coordinator.open = open
        coordinator.measured = measured
    }

    private func root(_ coordinator: Coordinator) -> AnyView {
        AnyView(
            WidgetStoreView(board: board, add: { coordinator.add($0) }, open: { coordinator.open($0) })
                .allowsHitTesting(!isShelf)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height.rounded(.up) } action: { height in
                    coordinator.view?.forcesLayout = false
                    coordinator.measured(height)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .environment(model)
                .environment(\.colorScheme, .dark)
                .environment(\.appearsActive, true)
                .environment(\.settingsPageVisit, visit)
                .toggleStyle(.islandSwitch)
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
        )
    }
}

/// ⌘Z and ⌘⇧Z on the page, in each of the stage's modes: in Widgets the board edited (its widgets
/// added, moved, resized, restyled, taken away) back a step and forward again; in Top Bar the bar
/// (an item moved, added, taken out, a page moved, a colour set); in Size the panel, its ready-made
/// size and every widget where it was. Only while the page is the one shown and Customize is not
/// open over it (its own undo is the widget's).
private struct StudioUndoKeys: View {
    @Binding var selection: WidgetID?
    @Binding var group: Set<WidgetID>

    @Environment(AppModel.self) private var model
    @Environment(\.settingsPageVisit) private var visit

    /// What Size mode stores, without the boards (they change with it).
    private struct SizeKey: Equatable {
        let panel: PanelSettings
        let scale: IslandScale
    }

    var body: some View {
        let store = model.editedWidgets
        let studio = model.studio
        let mode = studio.mode
        let isActive = (visit?.isShown ?? true) && studio.customizing == nil
        let canUndo = mode == .widgets ? !store.undoStack.isEmpty : mode == .topBar ? studio.headerHistory.canUndo : studio.sizeHistory.canUndo
        let canRedo = mode == .widgets ? !store.redoStack.isEmpty : mode == .topBar ? studio.headerHistory.canRedo : studio.sizeHistory.canRedo
        ZStack {
            Button("Undo") { step(back: true) }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!isActive || !canUndo)
            Button("Redo") { step(back: false) }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!isActive || !canRedo)
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        // Top Bar mode: every change of the bar — an item moved, added, taken out, a colour — is
        // a step to go back.
        .onChange(of: model.preferences.header) { old, new in
            if mode == .topBar { studio.headerHistory.note(from: old, to: new) }
        }
        // Size mode: the panel or the ready-made size stored (a slider or an edge let go).
        .onChange(of: SizeKey(panel: model.preferences.panel, scale: model.preferences.scale)) {
            guard mode == .size else { return }
            let now = model.sizeSnapshot()
            if let seen = studio.sizeSeen { studio.sizeHistory.note(from: seen, to: now) }
            studio.sizeSeen = now
        }
    }

    private func step(back: Bool) {
        let studio = model.studio
        switch studio.mode {
        case .widgets:
            let store = model.editedWidgets
            var changed = false
            withAnimation(.spring(duration: 0.32, bounce: 0.18)) { changed = back ? store.undo() : store.redo() }
            guard changed else { return NSSound.beep() }
            // A pick on a widget that is gone ends.
            let board = store.board
            if let id = selection, !board.contains(id) { selection = nil }
            group = group.filter { board.contains($0) }
        case .topBar:
            let current = model.preferences.header
            guard let other = back ? studio.headerHistory.undo(from: current) : studio.headerHistory.redo(from: current) else {
                return NSSound.beep()
            }
            withAnimation(TopBarInspector.settle) { model.preferences.header = other }
        case .size:
            let current = model.sizeSnapshot()
            guard let other = back ? studio.sizeHistory.undo(from: current) : studio.sizeHistory.redo(from: current) else {
                return NSSound.beep()
            }
            withAnimation(.spring(duration: 0.32, bounce: 0.1)) {
                studio.draft = nil
                model.restoreSize(other)
            }
            // What it is now is where the next change starts from, not a step of its own.
            studio.sizeSeen = model.sizeSnapshot()
        }
    }
}

/// What the stage's island takes from Settings around it: the widgets picked, and what the stage
/// edits.
private struct StagePick: Equatable {
    let selection: WidgetID?
    let group: Set<WidgetID>
    let mode: WidgetStudio.Mode
    /// The room the island is drawn in (in Size mode, the largest it may get).
    let room: CGSize
    /// How much smaller the room is shown (an island wider than the stage).
    let fit: CGFloat
}

// MARK: - Stage

/// The desktop with the island open under the notch, at real size.
private struct StudioStage: View {
    @Binding var selection: WidgetID?
    @Binding var group: Set<WidgetID>
    @Binding var backdrop: DesktopBackdropStyle
    let notice: String?
    /// As tall as this at the least (Size mode: the room its controls leave), the desktop
    /// reaching down under the island.
    var fillHeight: CGFloat = 0

    @Environment(AppModel.self) private var model
    /// Handed to the stage's own graphs (`StageSurface`).
    @Environment(\.self) private var environment
    /// The mode bar's height: the hint's capsule is made as tall, and the stage's lower corners
    /// concentric with both.
    @State private var controlHeight: CGFloat = 28
    /// Top Bar mode's hint, closed with its cross: it stays away.
    @AppStorage("ni2.studio.topBarHintHidden") private var hidesTopBarHint = false
    /// The stage's own width: an island wider than it is shown smaller, whole.
    @State private var stageWidth: CGFloat = 0
    /// How much smaller the island was shown when sizing began: kept until it ends, so the island
    /// stays put while cells are added (the stage grows under it) instead of shrinking away.
    @State private var sizingFit: CGFloat?
    /// The stage's height as drawn, following the one it should have: into Size mode it unfolds
    /// down to the controls at the window's bottom, and folds back up out of it.
    /// The mode the height was last set for, and until when a change of height is the mode's
    /// (unfolding) rather than a row's.
    @State private var heightMode: WidgetStudio.Mode?
    @State private var unfoldsUntil: TimeInterval = 0

    /// The stage unfolding into Size mode's room, and folding back.
    static let unfoldSpring = StudioStageSpring.unfold
    static let unfold: Animation = .spring(unfoldSpring)

    /// Between the hint and the button and the stage's edges.
    static let controlInset: CGFloat = 12
    /// Beside an island shown smaller to fit.
    static let sideInset: CGFloat = 16

    /// Under the island in the stage's picture, for the Size mode's lower handle (every mode has
    /// it, so the picture is the same size in all three).
    static let badgeRoom: CGFloat = 28

    var body: some View {
        let layout = model.layout
        let island = layout.size(for: .expanded(.home))
        let mode = model.studio.mode
        // The picture is as large as the island stored, in every mode. While the panel is sized
        // the island keeps its scale and stays where it is: rows grow downwards, the stage with
        // them, and columns out to the sides — nothing shrinks away and jumps back.
        let drawn = mode == .size
            ? (model.studio.draft.map { layout.replacing(panel: $0.panel.layout) } ?? layout).size(for: .expanded(.home)) : island
        let room = CGSize(width: max(island.width, drawn.width), height: max(island.height, drawn.height))
        let shown = stageWidth > 0 ? min(1, (stageWidth - 2 * Self.sideInset) / island.width) : 1
        let fit = sizingFit ?? shown
        // As wide as the stage — never wider: a draft wider than it is cut at its sides, and the
        // stage keeps its own width (measured from its frame, a wider box widened it for good) —
        // and as tall as the island drawn.
        let box = CGSize(width: stageWidth > 0 ? stageWidth : (room.width * fit).rounded(), height: (room.height * fit).rounded())
        let ownHeight = (layout.notch.height + box.height + Self.badgeRoom + 56).rounded()
        let height = max(ownHeight, fillHeight.rounded())
        // For `WidgetStudio.stageHeight(in:)` (not observed: nothing is drawn from it).
        let _ = model.studio.stageOwnHeight = ownHeight
        // Its desktop, outline and bar as layers the render server moves into Size mode and back
        // out of it (`StageSurface`).
        StageSurface(mode: mode, topRadius: 18, bottomRadius: controlHeight / 2 + Self.controlInset,
                     spring: Self.unfoldSpring, model: model) {
            ZStack(alignment: .top) {
                DesktopBackdrop(style: backdrop)
                    .contentShape(.rect)
                    .onTapGesture {
                        selection = nil
                        group = []
                    }
                    // The stage's own choices, on a right click of its desktop.
                    .contextMenu {
                        Picker("Wallpaper", selection: $backdrop) {
                            ForEach(DesktopBackdropStyle.offered) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.inline)
                        Divider()
                        Button("Reset to Default Widgets", role: .destructive) {
                            selection = nil
                            withAnimation(.spring(duration: 0.35)) { model.editedWidgets.reset() }
                        }
                    }
                PreviewMenuBar(height: layout.notch.height, notchWidth: island.width, darkText: backdrop.prefersDarkMenuBar,
                               backing: backdrop.menuBarBacking)
                    .allowsHitTesting(false)
                // In a graph of its own: the live widgets on it (clocks, readings) keep ticking, and
                // each tick would otherwise update all of Settings (`IsolatedHosting`). Handed over
                // again only when the picked widgets change: the model (the board, the layout) is
                // observed inside.
                // Shown smaller inside its own graph, not by scaling the host: AppKit hit-tests a
                // scaled view where it was laid out, and clicks near the island's edges missed.
                IsolatedHosting(size: CGSize(width: box.width, height: box.height + Self.badgeRoom),
                                input: StagePick(selection: selection, group: group, mode: mode, room: room, fit: fit),
                                pausesWithSettings: true) {
                    StageIsland(selection: $selection, group: $group, room: room, fit: fit)
                        .frame(width: box.width, height: box.height + Self.badgeRoom, alignment: .top)
                        .environment(model)
                        .environment(\.appearsActive, true)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } bar: {
                HStack(spacing: 10) {
                    // Which page's board the stage edits (the top bar is every page's).
                    if mode != .topBar {
                        StudioPageBar {
                            selection = nil
                            group = []
                        }
                    }
                    if mode == .topBar, !hidesTopBarHint {
                        // On glass, as the notices are; its cross closes it for good.
                        HStack(spacing: 8) {
                            Text("Drag and drop icons to edit")
                                .font(.callout.weight(.medium))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Button {
                                withAnimation(.easeOut(duration: 0.2)) { hidesTopBarHint = true }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.85))
                                    .frame(width: 18, height: 18)
                                    .background(.white.opacity(0.16), in: .circle)
                                    .contentShape(.circle)
                            }
                            .buttonStyle(.plain)
                            .help("Hide this")
                            .accessibilityLabel("Hide the hint")
                        }
                        .padding(.leading, 12)
                        .padding(.trailing, 5)
                        .frame(minHeight: controlHeight)
                        .glassEffect(.regular, in: .capsule)
                        .layoutPriority(-1)
                        .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .leading)))
                    }
                    // What went wrong, for a moment (no room, a widget set aside): nothing otherwise.
                    if let notice {
                        Label(notice, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                            .frame(minHeight: controlHeight)
                            .glassEffect(.regular, in: .capsule)
                            .layoutPriority(-1)
                    }
                    Spacer(minLength: 0)
                    // What the stage edits: the widgets, the top bar, or the panel's size and grid.
                    Picker("Edit", selection: Binding(get: { model.studio.pendingMode ?? model.studio.mode },
                                                      set: { model.studio.switchMode(to: $0) })) {
                        ForEach(WidgetStudio.Mode.allCases) { Text($0.title).tag($0) }
                    }
                    .choiceBar()
                    .labelsHidden()
                    .fixedSize()
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { controlHeight = $0 }
                }
                .padding(Self.controlInset)
                .environment(\.colorScheme, .dark)
        }
        .modifier(StageDrawnHeight(own: height))
        .onAppear {
            heightMode = mode
            // A stage built anew starts at its own height.
            model.studio.stageShown = nil
            model.studio.stagePlace = nil
        }
        .onChange(of: height) { old, new in
            // Into Size mode or out of it (its room measured a moment later is part of it): the
            // stage unfolds down to the controls, or folds back up. A row added while sizing:
            // as the island grows.
            let now = ProcessInfo.processInfo.systemUptime
            if heightMode != mode {
                unfoldsUntil = now + StageSurface<EmptyView, EmptyView>.unfoldWindow
                heightMode = mode
            }
            let studio = model.studio
            guard now < unfoldsUntil, mode != .topBar, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
                // The stage and its place together, as one: the page laid out at every frame. A row
                // added while sizing — and Top Bar's page, which is as tall as the room under the
                // stage and so follows every frame of it.
                withAnimation(now < unfoldsUntil ? Self.unfold : .spring(duration: 0.3, bounce: 0.05)) {
                    studio.stageShown = new
                    studio.stagePlace = new
                }
                return
            }
            // Unfolding or folding: the stage and its place take the new height at once, in one
            // layout of the page, and the render server moves the stage's foot there
            // (`StageSurface`) and the gallery after it (`GalleryGlide`). Laid out at every frame,
            // the page took 30–100 ms a frame, all of the spring on a performance core: 2.1–3.1 J
            // for a switch into Size mode or out of it (measured by real clicks,
            // `Scripts/perf/studio.py`).
            let lift = (studio.stagePlace ?? old) - new
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) {
                studio.stageShown = new
                studio.stagePlace = new
            }
            // The gallery follows the stage's foot along the same spring (`GlidingHostingView`).
            if lift != 0 { GalleryGlide.nextSpring = Self.unfoldSpring }
        }
        // Grown or shrunk by a row while sizing: what is under the stage glides with it.
        .animation(.spring(duration: 0.3, bounce: 0.05), value: box.height)
        .onChange(of: model.studio.draft != nil) { _, isSizing in sizingFit = isSizing ? shown : nil }
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { stageWidth = $0 }
        .modifier(StagePlace())
    }
}

/// The stage's height as drawn (`WidgetStudio.stageShown`), and its place in the page
/// (`stagePlace`), the picture hanging from its top. Views of their own: the stage's whole body
/// would otherwise be worked out again whenever either changes (a second ~55 ms turn at the start
/// of every unfolding, measured).
private struct StageDrawnHeight: ViewModifier {
    let own: CGFloat
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        content.frame(height: model.studio.stageShown ?? own)
    }
}

/// Size mode's ready-made sizes, over the Size cards (`ReadyMadeAnchors`).
private struct ReadyMadeOverlay: View {
    let anchors: [ReadyMadeAnchors.Part: Anchor<CGRect>]
    @Environment(AppModel.self) private var model

    var body: some View {
        GeometryReader { proxy in
            if model.studio.mode == .size, let area = anchors[.area], let button = anchors[.button] {
                ReadyMadeBox(button: proxy[button], area: proxy[area])
            }
        }
    }
}

/// What lies under the stage, each in a layer of its own (the gallery, the inspector, Size's and Top
/// Bar's content, the shelf's card): faded out and in on the render server as the stage's mode
/// switches (`WidgetStudio.switchMode`), with nothing drawn by the app at any frame of it.
@MainActor enum DeckFade {
    private final class Weak { weak var view: NSView?; init(_ view: NSView) { self.view = view } }
    private static var views: [Weak] = []
    private static let key = "deckFade"

    static func register(_ view: NSView) {
        views.removeAll { $0.view == nil || $0.view === view }
        views.append(Weak(view))
    }

    static func fade(out: Bool, duration: TimeInterval) {
        for view in views.compactMap(\.view) {
            guard let layer = view.layer else { continue }
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = layer.animation(forKey: key) != nil ? layer.presentation()?.opacity : (out ? layer.opacity : 0)
            fade.toValue = out ? 0 : layer.opacity
            fade.duration = duration
            fade.timingFunction = CAMediaTimingFunction(name: out ? .easeIn : .easeOut)
            // Out: held there until it comes back in.
            fade.fillMode = .forwards
            fade.isRemovedOnCompletion = !out
            layer.add(fade, forKey: key)
        }
    }
}

/// The picked widget's inspector, in a layer of its own (`MeasuredHosting`): it comes up a little
/// into place and fades in on the render server as a widget is picked.
@MainActor enum InspectorLayer {
    private(set) static weak var view: NSView?

    static func made(_ view: NSView) {
        self.view = view
        DeckFade.register(view)
    }

    static func rise(_ view: NSView) {
        guard let layer = view.layer, view.window != nil, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.22
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(fade, forKey: "inspectorFade")
        let rise = CASpringAnimation(keyPath: "sublayerTransform.translation.y")
        let flipped = layer.isGeometryFlipped || layer.contentsAreFlipped()
        rise.fromValue = flipped ? 28 : -28
        rise.toValue = 0
        rise.mass = 1
        rise.stiffness = 240
        rise.damping = 26
        rise.duration = rise.settlingDuration
        layer.add(rise, forKey: "inspectorRise")
    }

    /// `change` made at once, the inspector as it was drawn fading out over it: its controls come,
    /// go and move with no layout at every frame. The picture is taken of what is on screen of it.
    static func crossfade(_ change: () -> Void) {
        guard let view, let layer = view.layer, view.window != nil, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              case let seen = view.visibleRect, seen.width > 0, seen.height > 0,
              let picture = view.bitmapImageRepForCachingDisplay(in: seen) else { return change() }
        view.cacheDisplay(in: seen, to: picture)
        let cover = CALayer()
        cover.contents = picture.cgImage
        cover.contentsGravity = .resize
        // A view's own layer lays its sublayers out in the view's coordinates (AppKit flips its
        // geometry with the view's).
        cover.frame = seen
        cover.zPosition = 1000
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.addSublayer(cover)
        CATransaction.commit()
        change()
        CATransaction.begin()
        CATransaction.setCompletionBlock { cover.removeFromSuperlayer() }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.duration = 0.24
        fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        cover.opacity = 0
        cover.add(fade, forKey: "crossfade")
        CATransaction.commit()
    }
}

/// The shelf's card under the stage, faded in as it appears and out as the shelf is left, on the
/// render server: faded by SwiftUI, every frame of it worked out the Widgets page again (~11 ms).
@MainActor enum ShelfCardFade {
    private static weak var view: NSView?
    private static let key = "shelfCardFade"

    /// What is wrong with the card for the page shown, once things have settled (`demo/studiostress`).
    static func problems(isShelf: Bool) -> [String] {
        guard let view else { return ["no card"] }
        var problems: [String] = []
        let drawn = CGFloat(view.layer?.presentation()?.opacity ?? Float(view.alphaValue))
        if abs(drawn - (isShelf ? 1 : 0)) > 0.01 { problems.append(String(format: "card drawn %.2f", drawn)) }
        if abs(view.alphaValue - (isShelf ? 1 : 0)) > 0.01 { problems.append(String(format: "card alpha %.2f", view.alphaValue)) }
        if isShelf != (view.frame.height > 2) { problems.append(String(format: "card height %.0f", view.frame.height)) }
        return problems
    }

    /// For `demo/studiostate`.
    static var describe: String {
        guard let view else { return "card none" }
        return String(format: "card alpha %.2f shown %.2f height %.0f", view.alphaValue, view.layer?.presentation()?.opacity ?? -1, view.frame.height)
    }

    static func made(_ view: NSView, isShown: Bool) {
        self.view = view
        view.wantsLayer = true
        view.alphaValue = isShown ? 1 : 0
    }

    /// In (the shelf's page shown) or out, from where it is drawn now.
    static func fade(out: Bool, duration: TimeInterval) {
        guard let view, let layer = view.layer else { return }
        let from = layer.presentation()?.opacity ?? layer.opacity
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        view.alphaValue = out ? 0 : 1
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = from
        fade.toValue = out ? 0 : 1
        fade.duration = duration
        fade.timingFunction = CAMediaTimingFunction(name: out ? .easeIn : .easeOut)
        layer.add(fade, forKey: key)
        CATransaction.commit()
    }
}

/// The boards on the stage: the shown page's, and while it comes, the one going.
enum StageBoards {
    static func pages(current: ExpandedPage, outgoing: ExpandedPage?) -> [ExpandedPage] {
        guard let outgoing, outgoing != current else { return [current] }
        return [outgoing, current]
    }
}

/// A board on the stage, going or coming as the page switches (`WidgetStudio.boardBlend`). A view of
/// its own: read in `StageIsland`, every frame of the fade worked out the whole island again.
private struct BoardBlend: ViewModifier {
    let isOutgoing: Bool
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        let studio = model.studio
        let blend = studio.outgoingPage == nil ? 1 : studio.boardBlend
        content.opacity(isOutgoing ? studio.outgoingFrom * (1 - blend) : blend)
    }
}

private struct StagePlace: ViewModifier {
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        content.frame(height: model.studio.stagePlace, alignment: .top)
    }
}

/// Top Bar's page, as tall as the room under the stage: its Reset is level with the sidebar's foot.
/// It follows the stage's height only while it is the page shown; kept unseen it stays as tall as
/// it last was, so the stage unfolding into Size mode or folding back does not lay it out again.
private struct TopBarSlot: View {
    /// The page's room less the stage: the viewport without the insets and the gap.
    let room: CGFloat
    let isShown: Bool

    struct Input: Equatable {
        let room: CGFloat
        let isShown: Bool
    }

    @Environment(AppModel.self) private var model
    @State private var kept = Kept()

    private final class Kept {
        var height: CGFloat?
    }

    var body: some View {
        TopBarInspector(height: height)
    }

    private var height: CGFloat {
        // Read only while shown (or never yet): unseen, a change of the stage's height is not
        // this view's to follow.
        if isShown || kept.height == nil {
            kept.height = max(room - model.studio.stageMeasuredHeight, TopBarInspector.minimumHeight)
        }
        return kept.height ?? TopBarInspector.minimumHeight
    }
}

/// What lies under the stage, drawn under the stage's foot as it is drawn: while the stage unfolds
/// its place in the page already has the new height (`WidgetStudio.stageLag`). In a view of its
/// own, so only this follows the two heights.
private struct UnderStage: ViewModifier {
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        content.offset(y: model.studio.stageLag)
    }
}

/// The gallery following the stage's foot on the render server: it lies where the page's one
/// layout put it, and its layer shifts what it shows (`sublayerTransform`) from where it was drawn
/// along the stage's own spring. Moved by SwiftUI its fifty-five cards — each preview a hosting
/// view of its own — were told their place had changed at every frame, and the pointer's place
/// over them asked for again (80–165 ms a frame as the stage folded back, measured).
@MainActor enum GalleryGlide {
    static weak var view: NSView?
    private static let key = "galleryGlide"
    /// Down for the shelf's card or a parked widget's tray, or back up.
    static let pageSpring = Spring(duration: 0.4, bounce: 0.08)
    /// The spring of the next move only (the stage's unfolding, `StudioStage`).
    static var nextSpring: Spring? {
        didSet { if nextSpring != nil { arm() } }
    }
    /// Until when a move of the gallery glides: only the moves a page switch or the stage's
    /// unfolding makes. Any other (a mode's content shown, a widget picked or let go, the page laid
    /// out) is where it lands at once, as before.
    private(set) static var armedUntil: TimeInterval = 0

    static func arm(for seconds: TimeInterval = 0.4) {
        armedUntil = ProcessInfo.processInfo.systemUptime + seconds
        // Glided from where it is now: its place, as last seen, may be from a layout long ago.
        (view as? GlidingHostingView)?.notePlace()
    }

    /// What is wrong with the gallery once things have settled (`demo/studiostress`): drawn where it lies.
    static var problems: [String] {
        guard let layer = view?.layer else { return [] }
        let shift = (layer.presentation() ?? layer).sublayerTransform.m42
        return abs(shift) > 0.5 ? [String(format: "gallery shifted %.0f", shift)] : []
    }

    /// For `demo/studiostate`.
    static var describe: String {
        guard let view, let window = view.window else { return "gallery none" }
        let drawn = view.layer?.presentation()?.sublayerTransform.m42 ?? 0
        return String(format: "gallery y %.0f shift %.0f alpha %.2f", view.convert(view.bounds, to: nil).maxY - window.frame.height, drawn, view.alphaValue)
    }

    /// Drawn `distance` points lower than where it now lies (higher, if negative) — on top of any
    /// glide still going — and gliding from there into place, in the same commit as its move.
    static func glide(_ view: NSView, by distance: CGFloat) {
        guard let layer = view.layer else { return }
        let spring = nextSpring ?? pageSpring
        nextSpring = nil
        // Down the screen is down the layer when its geometry is flipped, up otherwise.
        let flipped = layer.isGeometryFlipped || layer.contentsAreFlipped()
        // Where it is drawn now, down the screen from where it lies: as the render server shows it,
        // or — another move in this same turn — where the last glide set out from (the server has
        // not seen that one yet: two opposite moves of one layout cancel out).
        let now = CACurrentMediaTime()
        let shown = layer.presentation()?.sublayerTransform.m42 ?? layer.sublayerTransform.m42
        let drawn = now - lastGlide.at < 0.004 ? lastGlide.from : (flipped ? shown : -shown)
        let from = drawn + distance
        lastGlide = (from, now)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.removeAnimation(forKey: key)
        layer.sublayerTransform = CATransform3DIdentity
        if abs(from) > 0.5 {
            let animation = CASpringAnimation(keyPath: "sublayerTransform")
            animation.mass = spring.mass
            animation.stiffness = spring.stiffness
            animation.damping = spring.damping
            animation.duration = animation.settlingDuration
            animation.fromValue = NSValue(caTransform3D: CATransform3DMakeTranslation(0, flipped ? from : -from, 0))
            animation.toValue = NSValue(caTransform3D: CATransform3DIdentity)
            layer.add(animation, forKey: key)
        }
        CATransaction.commit()
    }

    /// The last glide: how far down the screen it set out from, and when.
    private static var lastGlide: (from: CGFloat, at: CFTimeInterval) = (0, 0)
}

/// The stage unfolding into Size mode's room, and folding back (`StudioStage`).
enum StudioStageSpring {
    static let unfold = Spring(duration: 0.55, bounce: 0.12)
}

/// The gallery's host: moved in the page (the shelf's card above it coming or going, a parked
/// widget's tray, the stage folding back), it glides to its new place on the render server from
/// where it was drawn — the moment its frame changes, so the glide and the move are one commit.
/// Started from SwiftUI's report of the move, the glide sometimes ran a turn before the view
/// moved: it glided where it was and then jumped (quick page switches, recorded).
final class GlidingHostingView: DeferringHostingView<AnyView> {
    /// SwiftUI moves the views around this one, not this one: their moves are watched.
    private var watched: [NSObjectProtocol] = []
    /// Where it lay in the page's content (`place`), last seen.
    private var lastPlace: CGFloat?

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        watched.forEach(NotificationCenter.default.removeObserver)
        watched = []
        lastPlace = nil
        var ancestor = superview
        for _ in 0..<3 {
            guard let view = ancestor else { break }
            view.postsFrameChangedNotifications = true
            watched.append(NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: view,
                                                                  queue: nil) { [weak self] _ in
                MainActor.assumeIsolated { self?.followPlace() }
            })
            ancestor = view.superview
        }
    }

    override func setFrameOrigin(_ newOrigin: NSPoint) {
        super.setFrameOrigin(newOrigin)
        followPlace()
    }

    /// Its top in the scrolled content (down the page: larger), whatever is scrolled.
    private var place: CGFloat? {
        guard let reference = enclosingScrollView?.documentView ?? window?.contentView else { return nil }
        let rect = convert(bounds, to: reference)
        return reference.isFlipped ? rect.minY : reference.bounds.height - rect.maxY
    }

    // Hidden (another mode, a widget picked), it is not where it is seen: where it comes back is
    // where it lies, not a glide from where it was last seen (Size → Widgets: 816 pt, from above).
    override func viewDidHide() {
        super.viewDidHide()
        lastPlace = nil
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        lastPlace = nil
    }

    /// Where it lies now, as what a coming move is glided from (`GalleryGlide.arm`).
    func notePlace() {
        lastPlace = isHiddenOrHasHiddenAncestor ? nil : place
    }

    private func followPlace() {
        guard !isHiddenOrHasHiddenAncestor else { lastPlace = nil; return }
        guard let now = place else { return }
        defer { lastPlace = now }
        guard let last = lastPlace else { return }
        let down = now - last
        guard abs(down) > 0.5, ProcessInfo.processInfo.systemUptime < GalleryGlide.armedUntil,
              bounds.width > 0, let window, window.isVisible, !isHiddenOrHasHiddenAncestor,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        PerfTrace.mark(String(format: "gallery glides %.0f", down))
        // Drawn where it was (that much higher), then gliding down into place — or up.
        GalleryGlide.glide(self, by: -down)
    }
}

/// The open island exactly as the notch shows it, with the editable board for its home page.
private struct StageIsland: View {
    @Binding var selection: WidgetID?
    @Binding var group: Set<WidgetID>
    /// The room it is drawn in, hanging from its top: its own size, or in Size mode the largest it
    /// may get.
    let room: CGSize
    /// How much smaller the stage shows the room.
    let fit: CGFloat

    @Environment(AppModel.self) private var model

    var body: some View {
        let _ = ProcessInfo.processInfo.environment["NI_EXP_LAYOUTLOG"] == "1" ? Self._printChanges() : ()
        let mode = model.studio.mode
        let base = model.layout
        // Size mode: as the edge being dragged makes it, before that is stored.
        let layout = mode == .size ? (model.studio.draft.map { base.replacing(panel: $0.panel.layout) } ?? base) : base
        let presentation = IslandPresentation.expanded(.home)
        let size = layout.size(for: presentation)
        let split = NotchSplit(layout: layout, presentation: presentation,
                               outerInset: Metrics.Expanded.horizontalInset, clearance: Metrics.notchClearance)
        let shape = IslandShape(bottomRadius: layout.bottomRadius(for: presentation),
                                shoulderRadius: layout.shoulderRadius(for: presentation))
        let style = model.effectiveGlassStyle
        GlassEffectContainer {
            VStack(spacing: 0) {
                Group {
                    if mode == .topBar {
                        HeaderStageEditor(split: split, height: layout.notch.height)
                    } else {
                        ExpandedHeader(split: split, height: layout.notch.height)
                            // Only its page picker works: it picks the page the stage edits, as
                            // the picker under the stage does; the rest is a picture.
                            .environment(\.headerPicksStudioPage, true)
                            // A picture of the header: its controls' tooltips ("Home"…) must not pop
                            // up over the widgets being arranged under it.
                            .environment(\.showsControlHelp, false)
                            .environment(\.isHeaderPicture, true)
                    }
                }
                    .overlay {
                        // The camera housing.
                        UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8)
                            .fill(.black)
                            .frame(width: layout.notch.width, height: layout.notch.height)
                    }
                ZStack {
                    // The page's board — and, as another page's comes, the one going, faded into
                    // each other (`WidgetStudio.switchPage`): the going one kept as it was built.
                    let current = model.studio.page
                    ForEach(StageBoards.pages(current: current, outgoing: model.studio.outgoingPage), id: \.self) { shown in
                        let isCurrent = shown == current
                        Group {
                            if shown == .shelf, mode == .widgets {
                                // The shelf has no widgets: as it is while empty.
                                IslandEmptyState(title: "Drop Files Here", systemImage: "tray.and.arrow.down",
                                                 message: "Files you drop on the notch wait here until you drag them out.")
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            } else {
                                BoardEditor(selection: isCurrent ? $selection : .constant(nil),
                                            group: isCurrent ? $group : .constant([]),
                                            showsGrid: mode == .size,
                                            store: isCurrent ? nil : model.boards.store(for: shown == .shelf ? .home : shown))
                            }
                        }
                        // Only the Widgets mode arranges them, and only the shown page's.
                        .allowsHitTesting(mode == .widgets && isCurrent)
                        .modifier(BoardBlend(isOutgoing: !isCurrent))
                    }
                }
                    .opacity(mode == .topBar ? 0.4 : 1)
                    .padding(layout.boardInset)
                    .padding(.top, Metrics.Expanded.pageTopInset)
                    .padding(.bottom, Metrics.Expanded.pageBottomInset)
                    .padding(.horizontal, split.contentInset)
            }
            .frame(width: size.width, height: size.height)
            .controlSize(Metrics.controlSize(forScale: layout.factor))
            .islandSurfaceShade(style, solidDepth: layout.notch.height, in: shape)
            .islandGlass(in: shape)
        }
        .environment(\.islandGlassStyle, style)
        .environment(\.colorScheme, .dark)
        .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
        .frame(width: room.width, height: room.height, alignment: .top)
        .overlay {
            if mode == .size { SizeStageOverlay(island: size, room: room, base: base, fit: fit) }
        }
        .scaleEffect(fit, anchor: .top)
        .frame(width: (room.width * fit).rounded(), height: (room.height * fit).rounded(), alignment: .top)
        // A column or row added or taken away while sizing grows in or out (the cells, the widgets
        // moved for a column at the side dragged, the handles): no jump from one size to the next.
        .animation(.spring(duration: 0.28, bounce: 0.1), value: layout.panel)
    }
}

// MARK: - Group inspector

/// Two or more widgets picked with ⌘-click: the background, set on all of them at once — with the
/// same one, its strength and its colour too, shown as the first of them has them. A setting the
/// widgets differ in shows nothing marked until it is chosen.
private struct GroupInspector: View {
    let ids: Set<WidgetID>
    @Binding var selection: WidgetID?
    @Binding var group: Set<WidgetID>

    @Environment(AppModel.self) private var model
    @State private var isMixing = false
    @State private var pendingBackground: WidgetBackground?
    @State private var backgroundSlide = GlassSlide()

    var body: some View {
        let widgets = model.editedWidgets.board.widgets.filter { ids.contains($0.id) }
        let backgrounds = Set(widgets.map(\.background))
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                HStack(spacing: -10) {
                    ForEach(widgets.prefix(5)) { widget in
                        WidgetIcon(kind: widget.kind, side: 40)
                            .overlay { RoundedRectangle(cornerRadius: 10.4, style: .continuous).strokeBorder(SettingsPalette.window, lineWidth: 2) }
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(widgets.count) Widgets").font(.system(size: 20, weight: .bold))
                    Text(widgets.map(\.kind.title).joined(separator: ", "))
                        .font(.callout)
                        .foregroundStyle(SettingsPalette.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button("Remove All", systemImage: "minus.circle", role: .destructive) {
                    let doomed = ids
                    group = []
                    selection = nil
                    withAnimation(.spring(duration: 0.3)) { doomed.forEach { model.editedWidgets.remove($0) } }
                }
                .controlSize(.large)
                Button("Done") {
                    group = []
                    selection = nil
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
            StudioCard("Background", subtitle: "Applies to every picked widget.") {
                Picker("Background", selection: Binding(
                    get: { pendingBackground ?? (backgrounds.count == 1 ? backgrounds.first : nil) },
                    set: { (new: WidgetBackground?) in
                        guard let new else { return }
                        // As the single widget's (`WidgetInspector`): once the glass has slid there.
                        pendingBackground = new
                        backgroundSlide.afterSettling {
                            InspectorLayer.crossfade {
                                apply { $0.background = new }
                                pendingBackground = nil
                            }
                        }
                    }
                )) {
                    ForEach(WidgetBackground.allCases) { Text($0.title).tag(Optional($0)) }
                }
                .choiceBar()
                .labelsHidden()
                .fixedSize()
                // All on the same plate or colour: how strong, and which colour, for all of them.
                if backgrounds.count == 1, backgrounds.first != WidgetBackground.none, let first = widgets.first {
                    BackgroundSettings(widget: first, isMixing: $isMixing) { change in apply(change) }
                        .transition(.opacity)
                }
            }
            .animation(.spring(duration: 0.35, bounce: 0.12), value: backgrounds)
            .animation(.spring(duration: 0.35, bounce: 0.12), value: isMixing)
        }
    }

    private func apply(_ change: (inout IslandWidget) -> Void) {
        withAnimation(Motion.content) {
            for id in ids { model.editedWidgets.update(id, change) }
        }
    }
}

// MARK: - Inspector

/// One widget's own settings, in one card: its background as a bar across the card (with its
/// strength, and the Colour background's colour, under it), and its elements as a row of equal
/// tiles under that — a tile lit while its element shows, a click switches
/// it. Size and place are set on the stage itself (drag, corner handles, arrow keys).
private struct WidgetInspector: View {
    let id: WidgetID
    @Binding var selection: WidgetID?
    @Binding var notice: String?

    @Environment(AppModel.self) private var model
    /// The card's inside: the bar and the tiles are made exactly as wide.
    @State private var width: CGFloat = 0
    /// The colour mixer open under the Colour background's settings.
    @State private var isMixing = false
    /// The background picked, until its bar's glass has slid there.
    @State private var pendingBackground: WidgetBackground?
    @State private var backgroundSlide = GlassSlide()

    static let inset: CGFloat = 20
    static let spacing: CGFloat = 10
    /// Narrower tiles go onto two rows.
    static let tileMinimum: CGFloat = 104

    var body: some View {
        if let widget = model.editedWidgets.board.widget(id) {
            VStack(alignment: .leading, spacing: 16) {
                header(widget)
                VStack(alignment: .leading, spacing: 18) {
                    section("Background") {
                        // Shown at once; set once the bar's glass has slid there (`GlassSlide`), the
                        // inspector's new rows crossfaded in on the render server (`InspectorLayer`).
                        Picker("Background", selection: Binding(get: { pendingBackground ?? widget.background }, set: { background in
                            pendingBackground = background
                            backgroundSlide.afterSettling {
                                InspectorLayer.crossfade {
                                    model.editedWidgets.update(id) { $0.background = background }
                                    pendingBackground = nil
                                }
                            }
                        })) {
                            ForEach(WidgetBackground.allCases) { Text($0.title).tag($0) }
                        }
                        .choiceBar(width: width > 0 ? width : nil)
                        .labelsHidden()
                        .fixedSize()
                        if widget.background != .none {
                            BackgroundSettings(widget: widget, isMixing: $isMixing) { change in
                                model.editedWidgets.update(id, change)
                            }
                            .transition(.opacity.combined(with: .offset(y: -6)))
                        }
                    }
                    .animation(.spring(duration: 0.35, bounce: 0.12), value: widget.background)
                    .animation(.spring(duration: 0.35, bounce: 0.12), value: isMixing)
                    let switchable = widget.kind.spec.elements.filter { !$0.isRequired }
                    if !switchable.isEmpty {
                        Divider().opacity(0.5)
                        section("Elements", note: alwaysShown(widget.kind)) { tiles(switchable, widget) }
                    }
                }
                .padding(Self.inset)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { ($0.size.width - 2 * Self.inset).rounded(.down) } action: { width = $0 }
                .background(SettingsPalette.card, in: .rect(cornerRadius: SettingsForm.cardRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: SettingsForm.cardRadius, style: .continuous).strokeBorder(SettingsPalette.cardStroke)
                }
            }
        }
    }

    private func section<Content: View>(_ title: String, note: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline)
                Spacer(minLength: 12)
                if let note {
                    Text(note).font(.caption).foregroundStyle(SettingsPalette.secondary)
                }
            }
            content()
        }
    }

    /// What it shows always, beside what can be switched ("Always shown: Slider").
    private func alwaysShown(_ kind: IslandWidgetKind) -> String? {
        // Clipboard's copies are its rows (Settings ▸ Rows), not parts to list.
        let always = kind.spec.elements.filter { $0.isRequired && $0.id.clipRow == nil }.map(\.title)
        return always.isEmpty ? nil : "Always shown: \(ListFormatter.localizedString(byJoining: always))"
    }

    /// One row of equal tiles; where they would be too narrow, two rows of equal tiles.
    private func tiles(_ elements: [ElementSpec], _ widget: IslandWidget) -> some View {
        let fitsOneRow = width <= 0 || (width - CGFloat(elements.count - 1) * Self.spacing) / CGFloat(elements.count) >= Self.tileMinimum
        let columns = fitsOneRow ? elements.count : (elements.count + 1) / 2
        let rows = stride(from: 0, to: elements.count, by: columns).map { Array(elements[$0..<min($0 + columns, elements.count)]) }
        // A part with no room at this size is not drawn: its tile is off, and says why.
        let size = WidgetBoardGeometry(size: WidgetsSettingsPage.boardSize(model.layout), grid: model.editedWidgets.board.grid).laidSize(for: widget.frame)
        return VStack(spacing: Self.spacing) {
            ForEach(rows.indices, id: \.self) { row in
                HStack(spacing: Self.spacing) {
                    ForEach(rows[row], id: \.id) { element in
                        let hasRoom = IslandWidgetView.hasRoom(for: element.id, in: widget, size: size)
                        ElementTile(element: element, isOn: hasRoom && widget.shows(element.id), hasRoom: hasRoom) { on in
                            withAnimation(Motion.content) { model.editedWidgets.setOption(element.id, on, for: id) }
                        }
                    }
                    // A shorter last row keeps the tiles' width.
                    ForEach(0..<(columns - rows[row].count), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity, maxHeight: 1) }
                }
            }
        }
    }

    /// The icon's side: as tall as the buttons beside it, Remove and Done over Customize.
    static let headerHeight: CGFloat = 56
    /// The name and the line under it grow with the icon (20 and 12 pt beside the 52 pt icon of the
    /// other pages' headers), so the three keep their proportions.
    static var headerScale: CGFloat { headerHeight / 52 }

    /// The widget's icon and name; on the right Remove and Done, level with the icon's top, and
    /// Customize under them, as wide as the two and level with the icon's bottom.
    private func header(_ widget: IslandWidget) -> some View {
        let kind = widget.kind
        return HStack(spacing: 14) {
            WidgetIcon(kind: kind, side: Self.headerHeight)
            VStack(alignment: .leading, spacing: 2 * Self.headerScale) {
                Text(kind.title).font(.system(size: (20 * Self.headerScale).rounded(), weight: .bold))
                Text("\(kind.category.title) · \(widget.frame.width) × \(widget.frame.height)")
                    .font(.system(size: (12 * Self.headerScale).rounded()))
                    .foregroundStyle(SettingsPalette.secondary)
            }
            Spacer()
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Button("Remove", systemImage: "minus.circle", role: .destructive) {
                        selection = nil
                        withAnimation(.spring(duration: 0.3)) { model.editedWidgets.remove(id) }
                    }
                    Button("Done") { selection = nil }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
                Spacer(minLength: 0)
                Button { model.studio.customizing = id } label: {
                    Label("Customize…", systemImage: "paintbrush").frame(maxWidth: .infinity)
                }
                .help("The widget large, with everything it can be set to beside it")
            }
            .fixedSize(horizontal: true, vertical: false)
            .frame(height: Self.headerHeight)
        }
    }

}

/// The plate's strength; the Colour background's colour and strength, side by side, the colour
/// mixed in the mixer that opens under them.
struct BackgroundSettings: View {
    let widget: IslandWidget
    /// One under the other (a narrow panel), not side by side.
    var stacked = false
    @Binding var isMixing: Bool
    let change: ((inout IslandWidget) -> Void) -> Void

    @Environment(AppModel.self) private var model

    var body: some View {
        let colours = widget.background == .tinted
        VStack(alignment: .leading, spacing: 12) {
            if stacked {
                if colours { colour }
                opacity
            } else {
                HStack(spacing: 24) {
                    if colours {
                        colour.frame(maxWidth: .infinity)
                    }
                    opacity.frame(maxWidth: .infinity)
                }
            }
            if colours, isMixing {
                ColorMixer(rgb: Binding(get: { widget.backgroundColor ?? model.preferences.theme.rgb },
                                        set: { rgb in change { $0.backgroundColor = rgb } }), compact: stacked)
                    .padding(stacked ? 12 : 18)
                    .frame(maxWidth: .infinity)
                    .background(Color.white.opacity(0.04), in: .rect(cornerRadius: 16, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1) }
                    .transition(.scale(scale: 0.9, anchor: .top).combined(with: .opacity))
            }
        }
        .onChange(of: colours) { if !colours { isMixing = false } }
    }

    /// The colour: its swatch and name, back to automatic, and the mixer.
    private var colour: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(widget.backgroundColor?.color ?? .islandAccent)
                .overlay { Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1) }
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text("Colour").font(.callout)
                Text(widget.backgroundColor?.hex ?? (widget.kind == .nowPlaying ? "Automatic — the artwork's" : "Automatic — the theme's"))
                    .font(.caption)
                    .foregroundStyle(SettingsPalette.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if widget.backgroundColor != nil {
                Button("Automatic") {
                    withAnimation(Motion.content) { change { $0.backgroundColor = nil } }
                }
                .controlSize(.small)
            }
            Button {
                isMixing.toggle()
            } label: {
                Label(isMixing ? "Done" : "Mix", systemImage: isMixing ? "checkmark" : "paintpalette.fill")
            }
            .controlSize(.small)
        }
    }

    /// The strength, 0–100 %, snapped to whole percents so a slow drag does not rewrite the board for
    /// every pixel.
    private var opacity: some View {
        let value = widget.effectiveBackgroundOpacity
        return HStack(spacing: 10) {
            Text("Opacity").font(.callout)
            Slider(value: Binding(get: { value }, set: { new in
                let snapped = (new * 100).rounded() / 100
                if snapped != value { change { $0.backgroundOpacity = snapped } }
            }), in: 0...1) {
                Text("Opacity")
            }
            .labelsHidden()
            .tint(Color.islandAccent)
            ReservedWidthText(value.formatted(.percent.precision(.fractionLength(0))),
                              fitting: [Double(1).formatted(.percent.precision(.fractionLength(0)))])
                .foregroundStyle(SettingsPalette.secondary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Background opacity")
    }
}

/// One element of a widget as a tile: its symbol over its name, lit in the theme's colour while the
/// element shows. A click switches it.
private struct ElementTile: View {
    let element: ElementSpec
    let isOn: Bool
    /// False: the widget is too small to draw it (it comes back where there is room).
    var hasRoom = true
    let set: (Bool) -> Void

    @State private var isHovered = false

    var body: some View {
        Button { set(!isOn) } label: {
            VStack(spacing: 7) {
                Image(systemName: element.symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .frame(height: 22)
                Text(element.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if !hasRoom {
                    Text("No room at this size")
                        .font(.caption2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .opacity(hasRoom ? 1 : 0.55)
            .foregroundStyle(isOn ? AnyShapeStyle(.primary) : AnyShapeStyle(SettingsPalette.secondary))
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 74)
            .background(isOn ? Color.islandAccent.opacity(0.2) : .white.opacity(isHovered ? 0.07 : 0.04),
                        in: .rect(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isOn ? Color.islandAccent : .white.opacity(0.06), lineWidth: isOn ? 1.5 : 1)
            }
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(!hasRoom)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .help(!hasRoom ? "Make the widget larger to show it" : isOn ? "Shown: click to hide" : "Hidden: click to show")
        .accessibilityRepresentation {
            Toggle(element.title, isOn: Binding(get: { isOn }, set: set))
        }
    }
}

// MARK: - Gallery

/// Every built-in widget, grouped by category: compact cards with a live preview, a name, one line
/// on what it shows, and Add (or a check and Edit once it is on the island). Worded and weighted as
/// what it is — widgets that come with the app and only need adding — not as a store.
private struct WidgetStoreView: View {
    /// The board the cards read, handed in (`GalleryHost`): not read from the model here, so the
    /// gallery stands still while it is kept unseen (a widget picked, another mode) and moving a
    /// widget on the stage does not go over its cards.
    let board: WidgetBoard
    let add: (IslandWidgetKind) -> Void
    let open: (IslandWidgetKind) -> Void

    @Environment(AppModel.self) private var model
    @State private var category: WidgetCategory?
    /// The category the cards show: the picked one, once its bar's glass has slid there
    /// (`GalleryCards.Switch`).
    @State private var shownCategory: WidgetCategory?
    @State private var cardsSwitch = GalleryCards.Switch()
    @State private var search = ""

    /// The search field's width, at the row's right end.
    static let searchWidth: CGFloat = 220
    /// Between the categories and the search.
    static let barGap: CGFloat = 24
    /// The categories' widest: beyond it the segments would only grow apart.
    static let categoryBarMaximum: CGFloat = 760
    /// The row's width: the categories take what the search leaves them.
    @State private var rowWidth: CGFloat = 0
    private func matches(_ kind: IslandWidgetKind) -> Bool {
        search.isEmpty || kind.title.localizedStandardContains(search) || kind.summary.localizedStandardContains(search)
    }

    var body: some View {
        let offered = IslandWidgetKind.allCases.filter(\.isOffered)
        let kinds = offered.filter { kind in (shownCategory == nil || kind.category == shownCategory) && matches(kind) }
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("All Widgets").font(.title3.weight(.semibold))
                Text("Built in · \(offered.filter { board.contains($0) }.count) of \(offered.count) on your island")
                    .font(.callout)
                    .foregroundStyle(SettingsPalette.secondary)
            }
            // The categories and the search in one line, each as near its side of the panel: the
            // categories from the left edge up to the search, the search at the right end.
            HStack(alignment: .center, spacing: 0) {
                Picker("Category", selection: $category) {
                    Text("All").tag(WidgetCategory?.none)
                    // Only groups with something to offer: kinds still being built stay out of the bar.
                    ForEach(WidgetCategory.allCases.filter { group in offered.contains { $0.category == group } }) {
                        Text($0.title).tag(Optional($0))
                    }
                }
                .choiceBar(width: rowWidth > 0 ? min(rowWidth - Self.searchWidth - Self.barGap, Self.categoryBarMaximum) : nil)
                .labelsHidden()
                .fixedSize()
                Spacer(minLength: Self.barGap)
                NativeSearchField(text: $search, prompt: "Search Widgets")
                    .frame(minWidth: 160, maxWidth: Self.searchWidth)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width.rounded() } action: { rowWidth = $0 }
            .onSettingsPageVisit(shown: {}, hidden: {
                var quiet = Transaction()
                quiet.disablesAnimations = true
                withTransaction(quiet) {
                    cardsSwitch.cancel()
                    category = nil
                    shownCategory = nil
                    search = ""
                }
            })
            .onChange(of: category) { _, picked in
                guard picked != shownCategory || cardsSwitch.isRunning else { return }
                cardsSwitch.start {
                    // Back to the one shown before it went: nothing to lay out, only to fade in.
                    guard shownCategory != picked else { return cardsSwitch.fadeIn() }
                    var instant = Transaction()
                    instant.disablesAnimations = true
                    withTransaction(instant) { shownCategory = picked }
                }
            }

            if kinds.isEmpty {
                ContentUnavailableView.search(text: search)
                    .frame(maxWidth: .infinity, minHeight: 140)
            }
            // The cards in a layer of their own: another category is crossfaded on the render
            // server (`GalleryCards.crossfade`), the cards laid out once. Folded and unfolded by
            // SwiftUI, the groups slid in from below over several uneven frames (asked about).
            MeasuredHosting(input: GalleryCards.Input(board: board, category: shownCategory, search: search),
                            made: { cardsSwitch.view = $0 },
                            changing: { old, new, view in
                                if old.category != new.category { cardsSwitch.fadeIn() }
                            }) { input in
                GalleryCards(input: input, add: add, open: open)
                    .environment(model)
                    .environment(\.colorScheme, .dark)
                    .environment(\.appearsActive, true)
                    .toggleStyle(.islandSwitch)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
            }
            .padding(.top, -14)
        }
    }
}

/// The gallery's cards, one group per category, each kept whichever is picked: a category picked
/// folds the others away (their cards and previews stay built), so it is there at once and All
/// comes back at once — only what a search leaves out is taken away.
private struct GalleryCards: View {
    struct Input: Equatable {
        let board: WidgetBoard
        let category: WidgetCategory?
        let search: String
    }

    let input: Input
    let add: (IslandWidgetKind) -> Void
    let open: (IslandWidgetKind) -> Void

    private func matches(_ kind: IslandWidgetKind) -> Bool {
        input.search.isEmpty || kind.title.localizedStandardContains(input.search) || kind.summary.localizedStandardContains(input.search)
    }

    var body: some View {
        let category = input.category
        VStack(alignment: .leading, spacing: 0) {
            ForEach(WidgetCategory.allCases) { group in
                let inGroup = group.kinds.filter { $0.isOffered && matches($0) }
                let folded = inGroup.isEmpty || (category != nil && category != group)
                VStack(alignment: .leading, spacing: 8) {
                    // Its name over it among all the others; alone, the bar says which it is.
                    if category == nil, input.search.isEmpty {
                        Label(group.title, systemImage: group.systemImage)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(SettingsPalette.secondary)
                    }
                    grid(inGroup)
                }
                .padding(.top, category == nil && input.search.isEmpty ? 18 : 14)
                .opacity(folded ? 0 : 1)
                .frame(height: folded ? 0 : nil, alignment: .top)
                .clipped()
                .allowsHitTesting(!folded)
                .accessibilityHidden(folded)
            }
        }
    }

    private func grid(_ kinds: [IslandWidgetKind]) -> some View {
        GalleryGrid(minimum: 200, maximum: 300, spacing: 12) {
            ForEach(kinds) { kind in
                GalleryCard(kind: kind, grid: input.board.grid,
                            isAdded: input.board.contains(kind),
                            add: { add(kind) }, open: { open(kind) })
                    // Another page's board: only the cards whose Add or Edit changes are worked
                    // out again. Its new closures alone had all 55 (and their buttons) updated,
                    // half of the ~80 ms a page switch stopped the page bar's slide for.
                    .equatable()
            }
        }
    }

    /// Another category, without a stutter and on the render server. The category bar's glass
    /// slides on the main thread, and laying out the other cards (~50–80 ms) stopped it;
    /// a crossfade from the old cards to the new (`CATransition`) drew the old ones from the
    /// wrong end once the gallery's height changed. So: the cards fade out while the glass slides,
    /// the other category is laid out while none are seen, and its cards fade in, coming up a
    /// little into place.
    @MainActor final class Switch {
        weak var view: NSView?
        private let slide = GlassSlide()
        var isRunning: Bool { slide.isWaiting }

        func start(_ land: @escaping @MainActor () -> Void) {
            slide.cancel()
            guard let layer = view?.layer, view?.window != nil, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
                land()
                return
            }
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = layer.presentation()?.opacity ?? 1
            fade.toValue = 0
            fade.duration = Self.fadeOut
            fade.timingFunction = CAMediaTimingFunction(name: .easeIn)
            fade.fillMode = .forwards
            fade.isRemovedOnCompletion = false
            layer.removeAnimation(forKey: Self.riseKey)
            layer.add(fade, forKey: Self.fadeKey)
            // Laid out once the category bar's glass has slid to its segment (`GlassSlide`).
            slide.afterSettling(minimum: Self.fadeOut, land)
        }

        /// The new cards in: called as they are handed to their graph, so it starts in the commit
        /// they are drawn in.
        func fadeIn() {
            guard let layer = view?.layer else { return }
            guard layer.animation(forKey: Self.fadeKey) != nil else { return }
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            fade.duration = 0.24
            fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(fade, forKey: Self.fadeKey)
            let rise = CASpringAnimation(keyPath: "sublayerTransform.translation.y")
            let flipped = layer.isGeometryFlipped || layer.contentsAreFlipped()
            rise.fromValue = flipped ? 12 : -12
            rise.toValue = 0
            rise.mass = 1
            rise.stiffness = 220
            rise.damping = 28
            rise.duration = rise.settlingDuration
            layer.add(rise, forKey: Self.riseKey)
        }

        func cancel() {
            slide.cancel()
            view?.layer?.removeAnimation(forKey: Self.fadeKey)
            view?.layer?.removeAnimation(forKey: Self.riseKey)
        }

        private static let fadeKey = "categoryFade"
        private static let riseKey = "categoryRise"
        /// The fade out, as the page bar's (`WidgetStudio.switchPage`).
        private static let fadeOut: TimeInterval = 0.14
    }
}

/// A widget in the gallery, on one even card (no bands or seams): its live preview in a dark
/// rounded well, then its icon, name and the quiet Add / Edit, and two lines on what it shows.
private struct GalleryCard: View, Equatable {
    let kind: IslandWidgetKind
    let grid: BoardGrid
    let isAdded: Bool
    /// What it calls goes on through the gallery's coordinator (`GalleryHost`), whichever page
    /// the card was last worked out for: they are left out of its equality.
    let add: () -> Void
    let open: () -> Void

    nonisolated static func == (a: Self, b: Self) -> Bool {
        a.kind == b.kind && a.grid == b.grid && a.isAdded == b.isAdded
    }

    @Environment(AppModel.self) private var model
    @State private var isHovered = false
    /// A live preview is a whole widget (sliders, glass buttons…). Built all at once, sixteen of
    /// them stalled the frame Settings opened in; each now arrives a frame after the last
    /// (`GalleryPreviewQueue`), fading in on the render server (`WidgetPreview`).
    @State private var showsPreview = false

    /// The preview's well, and how far in it sits: the card's corners are concentric with it.
    static let wellRadius: CGFloat = 9
    static let inset: CGFloat = 10
    static let radius = wellRadius + inset

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ZStack {
                if showsPreview {
                    WidgetPreview(kind: kind, grid: grid, maxSize: CGSize(width: 176, height: 60))
                }
            }
                .frame(maxWidth: .infinity)
                .frame(height: 78)
                .background(.black.opacity(0.32), in: .rect(cornerRadius: Self.wellRadius, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if isAdded {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.white, .green)
                            .padding(6)
                            .help("On your island")
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            HStack(spacing: 8) {
                WidgetIcon(kind: kind, side: 22)
                Text(kind.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                    // A long name a little smaller rather than cut.
                    .minimumScaleFactor(0.72)
                Spacer(minLength: 4)
                AddWidgetButton(isAdded: isAdded, add: add, open: open)
            }
            Text(kind.summary)
                .font(.caption)
                .foregroundStyle(SettingsPalette.secondary)
                .lineLimit(2, reservesSpace: true)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Self.inset)
        .background(SettingsPalette.card, in: .rect(cornerRadius: Self.radius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
                .strokeBorder(isHovered ? .white.opacity(0.14) : SettingsPalette.cardStroke)
        }
        // No tooltip of its summary: the card shows it, and the gallery's tooltips stayed where their
        // card had been once it scrolled (another card's summary over this one).
        // Dragged up onto the stage's island: put where it is let go (`GalleryDrop`).
        .onDrag {
            model.studio.draggedKind = kind
            return NSItemProvider(object: GalleryDrop.payload(kind) as NSString)
        } preview: {
            WidgetPreview(kind: kind, grid: grid, maxSize: CGSize(width: 176, height: 60))
        }
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .animation(.spring(duration: 0.3), value: isAdded)
        .task {
            guard !showsPreview else { return }
            await GalleryPreviewQueue.turn()
            guard !Task.isCancelled else { return }
            showsPreview = true
        }
    }
}

/// Hands the gallery's previews their turn to be built: one a frame, in the order their cards
/// appeared. They waited 60 ms plus 35 ms per place in the whole gallery, so the cards further down
/// stayed empty for up to two seconds after they scrolled into view (asked about: "the pictures
/// load slowly"); a card that appears alone now gets its preview at once.
@MainActor enum GalleryPreviewQueue {
    /// Between two previews: one display frame.
    static let spacing: Duration = .milliseconds(16)
    /// While Settings is closed (the gallery coming back unseen after a widget was picked): short
    /// turns far apart, each on the efficiency cores, instead of a second of them back to back.
    static let unseenSpacing: Duration = .milliseconds(120)

    /// The cards waiting for their turn, first come first served, handed it by one pump. Each card
    /// slept until a slot it took as it appeared: those taken while Settings was built ahead,
    /// unseen, stayed 120 ms apart after it opened, and the gallery's first cards were still empty
    /// seconds later (seen, Oct 13 2026). The pump's pace follows whether Settings is shown now.
    private static var waiting: [CheckedContinuation<Void, Never>] = []
    private static var pump: Task<Void, Never>?
    private static var lastTurn = ContinuousClock.now - .seconds(1)

    private static var pace: Duration { SettingsPresence.shared.isShown ? spacing : unseenSpacing }

    static func turn() async {
        // A card that appears alone gets its preview at once.
        if waiting.isEmpty, ContinuousClock.now - lastTurn >= pace {
            lastTurn = .now
            return
        }
        await withCheckedContinuation { continuation in
            waiting.append(continuation)
            startPump()
        }
    }

    private static func startPump() {
        guard pump == nil else { return }
        pump = Task { @MainActor in
            while !waiting.isEmpty {
                let next = lastTurn + pace
                if next > .now { try? await Task.sleep(until: next, tolerance: .milliseconds(2)) }
                lastTurn = .now
                if !waiting.isEmpty { waiting.removeFirst().resume() }
            }
            pump = nil
        }
    }
}

/// The system's small buttons, kept quiet: Add (bordered) puts a built-in widget on the island;
/// once it is there, Edit (plain) selects it for customizing.
private struct AddWidgetButton: View {
    let isAdded: Bool
    let add: () -> Void
    let open: () -> Void

    var body: some View {
        Group {
            if isAdded {
                Button("Edit", action: open)
                    .buttonStyle(.borderless)
                    .foregroundStyle(SettingsPalette.secondary)
                    .help("Customize it on the island")
            } else {
                Button("Add", systemImage: "plus", action: add)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .help("Add it to the island")
            }
        }
        .controlSize(.small)
        .fixedSize()
    }
}

/// A live picture of the widget at its default size on the island's grid, scaled down to fit.
///
/// In a graph of its own that fades in on the render server as it appears: a fade driven by
/// SwiftUI in the gallery's graph updated and redrew all of Settings at every frame, and the
/// sixteen staggered previews kept it redrawing for most of a second. The nested graph gets what
/// the gallery's gave it (`GalleryPreviewStyle`), and fills the well to centre the picture in it
/// exactly where the gallery did (a host only the picture's size sat on whole pixels, which moved
/// the picture by a fraction of one).
struct WidgetPreview: View {
    let kind: IslandWidgetKind
    /// The board's, passed in: read here, every board change would redraw every preview.
    let grid: BoardGrid
    let maxSize: CGSize

    @Environment(AppModel.self) private var model

    /// As long as the SwiftUI fade it replaces.
    static let fadeIn: TimeInterval = 0.2

    var body: some View {
        let geometry = WidgetBoardGeometry(size: WidgetsSettingsPage.boardSize(model.layout), grid: grid)
        let cells = grid.defaultSize(for: kind)
        let rect = GridRect(column: 0, row: 0, width: cells.width, height: cells.height)
        let size = geometry.frame(for: rect).size
        let scale = min(1, maxSize.width / size.width, maxSize.height / size.height)
        IsolatedFillHosting(input: PreviewInput(kind: kind, rect: rect, size: size, scale: scale), fadeIn: Self.fadeIn, isPicture: true,
                            pausesWithSettings: true) {
            IslandWidgetView(widget: IslandWidget(kind: kind, frame: rect, options: kind.defaultOptions), size: size)
                .environment(\.isWidgetPreview, true)
                .environment(\.colorScheme, .dark)
                .allowsHitTesting(false)
                .frame(width: size.width, height: size.height)
                .scaleEffect(scale)
                .frame(width: size.width * scale, height: size.height * scale)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .modifier(GalleryPreviewStyle())
                .environment(model)
        }
        .accessibilityHidden(true)
    }

    /// All the nested graph takes from here.
    struct PreviewInput: Equatable {
        let kind: IslandWidgetKind
        let rect: GridRect
        let size: CGSize
        let scale: CGFloat
    }
}

/// What a preview drew with in the gallery's own graph, which the nested one does not inherit:
/// Settings' control styles (`SettingsDetail`) and its active appearance (`IslandSettingsView`).
struct GalleryPreviewStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .toggleStyle(.islandSwitch)
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .environment(\.appearsActive, true)
    }
}

extension WidgetCategory {
    var systemImage: String {
        switch self {
        case .media: "music.note"
        case .time: "timer"
        case .controls: "switch.2"
        case .battery: "battery.75percent"
        case .system: "cpu"
        case .tools: "wrench.and.screwdriver.fill"
        }
    }
}

/// The system's own search field (`NSSearchField`): the capsule with the magnifier and the clear
/// button, exactly as in Finder or System Settings.
struct NativeSearchField: NSViewRepresentable {
    @Binding var text: String
    var prompt: String

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = prompt
        field.sendsSearchStringImmediately = true
        field.delegate = context.coordinator
        field.controlSize = .large
        // No blue ring while typing: drawn outside the field, it stood out past the gallery's
        // right edge and was cut there (asked for).
        field.focusRingType = .none
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.text = $text
        if field.stringValue != text { field.stringValue = text }
        field.placeholderString = prompt
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>

        init(text: Binding<String>) { self.text = text }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}

