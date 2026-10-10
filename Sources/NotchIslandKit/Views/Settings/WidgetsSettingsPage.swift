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
    @AppStorage(DesktopBackdropStyle.key) private var backdrop: DesktopBackdropStyle = DesktopBackdropStyle.defaultStyle
    /// Letting go of the picks once the page has gone (`pickResetDelay`).
    @State private var pendingReset: Timer?

    var body: some View {
        ScrollViewReader { scroller in
            ScrollView {
                VStack(alignment: .leading, spacing: Self.spacing) {
                    StudioStage(selection: $selection, group: $group, backdrop: $backdrop, notice: notice,
                                fillHeight: model.studio.mode == .size
                                    ? viewportHeight - Self.topInset - Self.spacing - inspectorHeight - bottomInset : 0)
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
                        TopBarInspector()
                            .deckSlot(.topBar, shown: shown)
                        VStack(alignment: .leading, spacing: 16) {
                            SizeInspector()
                            ParkedTray()
                        }
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { inspectorHeight = $0 }
                        .deckSlot(.size, shown: shown)
                        VStack(alignment: .leading, spacing: 22) {
                            ParkedTray()
                            WidgetStoreView(isShown: shown == .gallery, add: { add($0, scroller: scroller) },
                                            open: { kind in
                                                if let id = model.editedWidgets.board.first(of: kind)?.id { select(id, scroller: scroller) }
                                            })
                                // Unseen, it is not gone over at all: every change to a widget (a
                                // drag in Customize) would run its fifty cards' bodies otherwise.
                                .equatable()
                        }
                        .deckSlot(.gallery, shown: shown)
                        VStack(alignment: .leading, spacing: 0) {
                            if mode != .widgets {
                                EmptyView()
                            } else if picked.count >= 2 {
                                GroupInspector(ids: picked, selection: $selection, group: $group)
                                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                                            removal: .opacity))
                            } else if let id = selection, model.editedWidgets.board.contains(id) {
                                WidgetInspector(id: id, selection: $selection, notice: $notice)
                                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                                            removal: .opacity))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .deckSlot(.inspector, shown: shown)
                    }
                    .animation(.spring(duration: 0.35, bounce: 0.12), value: selection)
                    .animation(.spring(duration: 0.35, bounce: 0.12), value: group.count >= 2)
                    // Faded out while the stage switches modes (`WidgetStudio.switchMode`).
                    .opacity(model.studio.contentOpacity)
                }
                .padding(.horizontal, 28)
                .padding(.top, Self.topInset)
                .padding(.bottom, bottomInset)
                // A row added or taken away while sizing grows the stage: what is under it glides.
                .animation(.spring(duration: 0.3, bounce: 0.05), value: model.studio.draft?.panel.rows)
            }
            .scrollIndicators(.automatic)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewportHeight = $0 }
            // Size mode's ready-made sizes: out of their button, over the Size cards and buttons.
            .overlayPreferenceValue(ReadyMadeAnchors.self, alignment: .topLeading) { anchors in
                GeometryReader { proxy in
                    if model.studio.mode == .size, let area = anchors[.area], let button = anchors[.button] {
                        ReadyMadeBox(button: proxy[button], area: proxy[area])
                    }
                }
            }
        }
        .background { BoardUndoKeys(selection: $selection, group: $group) }
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
    /// Under the page: in Size mode its controls end where the sidebar does.
    private var bottomInset: CGFloat { model.studio.mode == .size ? IslandSettingsView.sidebarGap : 28 }
    private static let spacing: CGFloat = 22

    /// Exactly the area the home page gives its board.
    static func boardSize(_ layout: IslandLayout) -> CGSize { BoardSizing.board(layout) }

    private func left() {
        model.studio.draft = nil
        model.studio.headerSelection = nil
        model.studio.sizeEntry = nil
        model.studio.closeReadyMade()
        model.studio.showsNotchStyles = false
    }

    /// Size mode entered, or shown again: what Reset Size goes back to is what it finds now.
    private func noteSizeEntry() {
        model.studio.sizeEntry = model.studio.mode == .size ? model.sizeSnapshot() : nil
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

/// ⌘Z and ⌘⇧Z on the page: the board edited (its widgets added, moved, resized, restyled, taken
/// away) back a step and forward again. Only while the page is the one shown and Customize is not
/// open over it (its own undo is the widget's).
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
    /// One of `ModeDeck`'s: seen and used only while it is the one shown, fading as it comes and goes.
    func deckSlot(_ slot: ModeDeck.Slot, shown: ModeDeck.Slot) -> some View {
        opacity(slot == shown ? 1 : 0)
            .animation(.easeOut(duration: 0.18), value: slot == shown)
            .allowsHitTesting(slot == shown)
            .accessibilityHidden(slot != shown)
    }
}

private struct BoardUndoKeys: View {
    @Binding var selection: WidgetID?
    @Binding var group: Set<WidgetID>

    @Environment(AppModel.self) private var model
    @Environment(\.settingsPageVisit) private var visit

    var body: some View {
        let store = model.editedWidgets
        let isActive = (visit?.isShown ?? true) && model.studio.customizing == nil && model.studio.mode != .topBar
        ZStack {
            Button("Undo") { step { store.undo() } }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!isActive || store.undoStack.isEmpty)
            Button("Redo") { step { store.redo() } }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!isActive || store.redoStack.isEmpty)
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func step(_ change: () -> Bool) {
        var changed = false
        withAnimation(.spring(duration: 0.32, bounce: 0.18)) { changed = change() }
        guard changed else { return NSSound.beep() }
        // A pick on a widget that is gone ends.
        let board = model.editedWidgets.board
        if let id = selection, !board.contains(id) { selection = nil }
        group = group.filter { board.contains($0) }
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
    /// The round Stage button's height: the hint's capsule is made as tall, and the stage's lower
    /// corners concentric with both.
    @State private var controlHeight: CGFloat = 28
    /// The stage's own width: an island wider than it is shown smaller, whole.
    @State private var stageWidth: CGFloat = 0
    /// How much smaller the island was shown when sizing began: kept until it ends, so the island
    /// stays put while cells are added (the stage grows under it) instead of shrinking away.
    @State private var sizingFit: CGFloat?
    /// The stage's height as drawn, following the one it should have: into Size mode it unfolds
    /// down to the controls at the window's bottom, and folds back up out of it.
    @State private var shownHeight: CGFloat?
    /// The mode the height was last set for, and until when a change of height is the mode's
    /// (unfolding) rather than a row's.
    @State private var heightMode: WidgetStudio.Mode?
    @State private var unfoldsUntil: TimeInterval = 0

    /// The stage unfolding into Size mode's room, and folding back.
    static let unfold: Animation = .spring(duration: 0.55, bounce: 0.12)

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
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: 18,
            bottomLeadingRadius: controlHeight / 2 + Self.controlInset,
            bottomTrailingRadius: controlHeight / 2 + Self.controlInset,
            topTrailingRadius: 18,
            style: .continuous
        )
        let height = max((layout.notch.height + box.height + Self.badgeRoom + 56).rounded(), fillHeight.rounded())
        ZStack(alignment: .top) {
            DesktopBackdrop(style: backdrop)
                .contentShape(.rect)
                .onTapGesture {
                    selection = nil
                    group = []
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
        .frame(height: shownHeight ?? height)
        .onAppear { heightMode = mode }
        .onChange(of: height) { _, new in
            // Into Size mode or out of it (its room measured a moment later is part of it): the
            // stage unfolds down to the controls, or folds back up. A row added while sizing:
            // as the island grows.
            let now = ProcessInfo.processInfo.systemUptime
            if heightMode != mode {
                unfoldsUntil = now + 0.8
                heightMode = mode
            }
            withAnimation(now < unfoldsUntil ? Self.unfold : .spring(duration: 0.3, bounce: 0.05)) { shownHeight = new }
        }
        // Grown or shrunk by a row while sizing: what is under the stage glides with it.
        .animation(.spring(duration: 0.3, bounce: 0.05), value: box.height)
        .onChange(of: model.studio.draft != nil) { _, isSizing in sizingFit = isSizing ? shown : nil }
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { stageWidth = $0 }
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(.white.opacity(0.1))
        }
        .overlay(alignment: .bottom) {
            HStack(spacing: 10) {
                // Which page's board the stage edits (the top bar is every page's).
                if mode != .topBar {
                    StudioPageBar {
                        selection = nil
                        group = []
                    }
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
                .help("What the stage edits")
                Menu {
                    Picker("Wallpaper", selection: $backdrop) {
                        ForEach(DesktopBackdropStyle.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                    Divider()
                    Button("Reset to Default Widgets", role: .destructive) {
                        selection = nil
                        withAnimation(.spring(duration: 0.35)) { model.editedWidgets.reset() }
                    }
                } label: {
                    Label("Stage", systemImage: "ellipsis")
                }
                .menuStyle(.button)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .labelStyle(.iconOnly)
                .menuIndicator(.hidden)
                .fixedSize()
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { controlHeight = $0 }
                .help("Wallpaper and reset")
            }
            .padding(Self.controlInset)
            .environment(\.colorScheme, .dark)
        }
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
                BoardEditor(selection: $selection, group: $group, showsGrid: mode == .size)
                    // Only the Widgets mode arranges them.
                    .allowsHitTesting(mode == .widgets)
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
                    get: { backgrounds.count == 1 ? backgrounds.first : nil },
                    set: { (new: WidgetBackground?) in
                        guard let new else { return }
                        withAnimation(.spring(duration: 0.4, bounce: 0.18)) { apply { $0.background = new } }
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
                        Picker("Background", selection: Binding(get: { widget.background }, set: { background in
                            withAnimation(.spring(duration: 0.4, bounce: 0.18)) { model.editedWidgets.update(id) { $0.background = background } }
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
private struct WidgetStoreView: View, Equatable {
    /// Unseen before and after: the same, whatever else it was given (its closures never compare).
    nonisolated static func == (old: WidgetStoreView, new: WidgetStoreView) -> Bool { !old.isShown && !new.isShown }

    /// False while it is kept unseen (a widget is picked, another mode): it stands still then — the
    /// board is not read, so moving a widget on the stage does not go over its cards.
    var isShown = true
    let add: (IslandWidgetKind) -> Void
    let open: (IslandWidgetKind) -> Void

    @Environment(AppModel.self) private var model
    @State private var category: WidgetCategory?
    @State private var search = ""

    /// The search field's width, at the row's right end.
    static let searchWidth: CGFloat = 220
    /// Between the categories and the search.
    static let barGap: CGFloat = 24
    /// The categories' widest: beyond it the segments would only grow apart.
    static let categoryBarMaximum: CGFloat = 760
    /// The row's width: the categories take what the search leaves them.
    @State private var rowWidth: CGFloat = 0
    /// The board as it was when last shown: what the cards say while unseen.
    @State private var seen = SeenBoard()

    private final class SeenBoard {
        var board: WidgetBoard?
    }

    /// The board the cards read: the edited one while shown, the last one seen otherwise.
    private var board: WidgetBoard {
        if isShown || seen.board == nil { seen.board = model.editedWidgets.board }
        return seen.board ?? model.editedWidgets.board
    }

    private func matches(_ kind: IslandWidgetKind) -> Bool {
        search.isEmpty || kind.title.localizedStandardContains(search) || kind.summary.localizedStandardContains(search)
    }

    var body: some View {
        let board = board
        let offered = IslandWidgetKind.allCases.filter(\.isOffered)
        let kinds = offered.filter { kind in (category == nil || kind.category == category) && matches(kind) }
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
                    category = nil
                    search = ""
                }
            })

            if kinds.isEmpty {
                ContentUnavailableView.search(text: search)
                    .frame(maxWidth: .infinity, minHeight: 140)
            }
            // One group per category, each kept whichever is picked: a category picked folds the
            // others away (their cards and previews stay built), so it is there at once and All
            // comes back at once — only what a search leaves out is taken away.
            VStack(alignment: .leading, spacing: 0) {
                ForEach(WidgetCategory.allCases) { group in
                    let inGroup = group.kinds.filter { $0.isOffered && matches($0) }
                    let folded = inGroup.isEmpty || (category != nil && category != group)
                    VStack(alignment: .leading, spacing: 8) {
                        // Its name over it among all the others; alone, the bar says which it is.
                        if category == nil, search.isEmpty {
                            Label(group.title, systemImage: group.systemImage)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(SettingsPalette.secondary)
                        }
                        grid(inGroup, board: board)
                    }
                    .padding(.top, category == nil && search.isEmpty ? 18 : 14)
                    .opacity(folded ? 0 : 1)
                    .animation(.easeOut(duration: 0.22), value: folded)
                    .frame(height: folded ? 0 : nil, alignment: .top)
                    .clipped()
                    .allowsHitTesting(!folded)
                    .accessibilityHidden(folded)
                }
            }
            .padding(.top, -14)
        }
    }

    private func grid(_ kinds: [IslandWidgetKind], board: WidgetBoard) -> some View {
        GalleryGrid(minimum: 200, maximum: 300, spacing: 12) {
            ForEach(kinds) { kind in
                GalleryCard(kind: kind, grid: board.grid,
                            isAdded: board.contains(kind),
                            add: { add(kind) }, open: { open(kind) })
            }
        }
    }
}

/// A widget in the gallery, on one even card (no bands or seams): its live preview in a dark
/// rounded well, then its icon, name and the quiet Add / Edit, and two lines on what it shows.
private struct GalleryCard: View {
    let kind: IslandWidgetKind
    let grid: BoardGrid
    let isAdded: Bool
    let add: () -> Void
    let open: () -> Void

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
    private static var nextTurn = ContinuousClock.now

    static func turn() async {
        let now = ContinuousClock.now
        let slot = max(now, nextTurn)
        nextTurn = slot + (SettingsPresence.shared.isShown ? spacing : unseenSpacing)
        if slot > now { try? await Task.sleep(until: slot, tolerance: .milliseconds(2)) }
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
