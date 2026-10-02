import AppKit
import SwiftUI

/// Settings ▸ Widgets: a live stage over the gallery of built-in widgets.
///
/// - **Stage**: a Mac desktop (the default macOS wallpaper, or the user's own) with its menu bar,
///   and the open island hanging from the notch at its real size. The widgets are arranged right
///   there — drag to move, drag a corner to resize, everything snaps to the grid.
/// - **Inspector** (a widget is selected): the widget's own system — its size as presets, its
///   layout, colour and background, and every element inside it, each with its own switch and
///   size.
/// - **Gallery** (nothing selected): every built-in widget as a compact card with a live preview,
///   grouped by category. Nothing is downloaded or bought: Add puts the widget on the island and
///   selects it, Edit selects one that is already there.
struct WidgetsSettingsPage: View {
    @Environment(AppModel.self) private var model
    @State private var selection: WidgetID?
    /// Two or more widgets picked with ⌘-click: edited together.
    @State private var group: Set<WidgetID> = []
    @State private var thumbnails = ThumbnailCache()
    @State private var notice: String?
    @AppStorage(DesktopBackdropStyle.key) private var backdrop: DesktopBackdropStyle = DesktopBackdropStyle.defaultStyle

    var body: some View {
        ScrollViewReader { scroller in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    StudioStage(selection: $selection, group: $group, thumbnails: thumbnails, backdrop: $backdrop, notice: notice)
                        .id(StudioAnchor.stage)
                    Group {
                        let picked = group.filter { model.editedWidgets.board.contains($0) }
                        if model.studio.mode == .topBar {
                            TopBarInspector()
                                .transition(.opacity)
                        } else if model.studio.mode == .size {
                            VStack(alignment: .leading, spacing: 16) {
                                SizeInspector()
                                ParkedTray()
                            }
                            .transition(.opacity)
                        } else if picked.count >= 2 {
                            GroupInspector(ids: picked, selection: $selection, group: $group)
                                .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                                        removal: .opacity))
                        } else if let id = selection, model.editedWidgets.board.contains(id) {
                            WidgetInspector(id: id, selection: $selection, notice: $notice)
                                .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                                        removal: .opacity))
                        } else {
                            VStack(alignment: .leading, spacing: 22) {
                                ParkedTray()
                                WidgetStoreView(add: { add($0, scroller: scroller) },
                                                open: { kind in
                                                    if let id = model.editedWidgets.board.first(of: kind)?.id { select(id, scroller: scroller) }
                                                })
                            }
                            .transition(.opacity)
                        }
                    }
                    .animation(.spring(duration: 0.35, bounce: 0.12), value: selection)
                    .animation(.spring(duration: 0.35, bounce: 0.12), value: group.count >= 2)
                    // Faded out while the stage switches modes (`WidgetStudio.switchMode`).
                    .opacity(model.studio.contentOpacity)
                }
                .padding(.horizontal, 28)
                .padding(.top, 10)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.automatic)
            .onChange(of: model.studio.stageScrollRequest) {
                withAnimation(.easeInOut(duration: SettingsSurfaceView.stageScroll)) { scroller.scrollTo(StudioAnchor.stage, anchor: .top) }
            }
        }
        .onAppear(perform: takeRequestedEdit)
        .onChange(of: model.editingWidget) { takeRequestedEdit() }
        .onChange(of: model.studio.mode) { _, mode in
            // Each mode's own picks and drafts end with it.
            if mode != .widgets {
                selection = nil
                group = []
            }
            if mode != .topBar { model.studio.headerSelection = nil }
            if mode != .size { model.studio.draft = nil }
        }
        .onDisappear(perform: left)
        // Kept between visits (`SettingsPageDeck`): left as a page that goes, and shown again as
        // a new one, with nothing picked.
        .onSettingsPageVisit(shown: takeRequestedEdit, hidden: {
            left()
            var quiet = Transaction()
            quiet.disablesAnimations = true
            withTransaction(quiet) {
                selection = nil
                group = []
                notice = nil
            }
        })
        .task(id: notice) {
            guard notice != nil else { return }
            try? await Task.sleep(for: .seconds(4))
            notice = nil
        }
    }

    /// Exactly the area the home page gives its board.
    static func boardSize(_ layout: IslandLayout) -> CGSize { BoardSizing.board(layout) }

    private func left() {
        model.studio.draft = nil
        model.studio.headerSelection = nil
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
    let thumbnails: ThumbnailCache
    @Binding var backdrop: DesktopBackdropStyle
    let notice: String?

    @Environment(AppModel.self) private var model
    /// The round Stage button's height: the hint's capsule is made as tall, and the stage's lower
    /// corners concentric with both.
    @State private var controlHeight: CGFloat = 28
    /// The stage's own width: an island wider than it is shown smaller, whole.
    @State private var stageWidth: CGFloat = 0

    /// Between the hint and the button and the stage's edges.
    static let controlInset: CGFloat = 12
    /// Beside an island shown smaller to fit.
    static let sideInset: CGFloat = 16

    /// Size mode's room: the panel as it is, with room to drag its edges out a good way — no more
    /// than the largest it may be made on this screen. Only as large as that, so the stage stays
    /// short and the controls under it in sight; it is the stored panel's (not the one being
    /// dragged), so a drag lays out nothing around the stage, and the room grows after it.
    static func sizeRoom(_ layout: IslandLayout) -> CGSize {
        let island = layout.size(for: .expanded(.home))
        let largest = layout.replacing(panel: PanelLayout(widthFactor: PanelSettings.widthRange.upperBound,
                                                          boardHeightFactor: PanelSettings.boardHeightRange.upperBound))
            .size(for: .expanded(.home))
        return CGSize(width: min(largest.width, (island.width * 1.3).rounded()),
                      height: min(largest.height, island.height + max(64, (island.height * 0.35).rounded())))
    }

    var body: some View {
        let layout = model.layout
        let island = layout.size(for: .expanded(.home))
        let mode = model.studio.mode
        // In Size mode the island's room is the largest it may get, fixed: dragging its edges
        // lays out nothing around the stage.
        let room = mode == .size ? Self.sizeRoom(layout) : island
        let fit = stageWidth > 0 ? min(1, (stageWidth - 2 * Self.sideInset) / room.width) : 1
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: 18,
            bottomLeadingRadius: controlHeight / 2 + Self.controlInset,
            bottomTrailingRadius: controlHeight / 2 + Self.controlInset,
            topTrailingRadius: 18,
            style: .continuous
        )
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
            // observed inside, and the thumbnails' cache is the same object throughout.
            // Shown smaller inside its own graph, not by scaling the host: AppKit hit-tests a
            // scaled view where it was laid out, and clicks near the island's edges missed.
            IsolatedHosting(size: CGSize(width: (room.width * fit).rounded(), height: (room.height * fit).rounded()),
                            input: StagePick(selection: selection, group: group, mode: mode, room: room, fit: fit)) {
                StageIsland(selection: $selection, group: $group, thumbnails: thumbnails, room: room, fit: fit)
                    .environment(model)
                    .environment(\.appearsActive, true)
            }
        }
        .frame(height: (layout.notch.height + room.height * fit + (mode == .size ? 86 : 70)).rounded())
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
    let thumbnails: ThumbnailCache
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
                            .allowsHitTesting(false)
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
                BoardEditor(selection: $selection, thumbnails: thumbnails, group: $group, showsGrid: mode == .size)
                    // Only the Widgets mode arranges them.
                    .allowsHitTesting(mode == .widgets)
                    .opacity(mode == .topBar ? 0.4 : 1)
                    .padding(.top, Metrics.Expanded.pageTopInset)
                    .padding(.bottom, Metrics.Expanded.pageBottomInset)
                    .padding(.horizontal, split.contentInset)
            }
            .frame(width: size.width, height: size.height)
            .controlSize(Metrics.controlSize(forScale: layout.scale.factor))
            .islandSurfaceShade(style, solidDepth: layout.notch.height, in: shape)
            .islandGlass(in: shape)
        }
        .environment(\.islandGlassStyle, style)
        .environment(\.colorScheme, .dark)
        .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
        .frame(width: room.width, height: room.height, alignment: .top)
        .background { StageRoomAnchor(probe: model.studio.probe, scale: fit) }
        .overlay {
            if mode == .size { SizeStageOverlay(island: size, room: room, base: base) }
        }
        .scaleEffect(fit, anchor: .top)
        .frame(width: (room.width * fit).rounded(), height: (room.height * fit).rounded(), alignment: .top)
    }
}

// MARK: - Group inspector

/// Two or more widgets picked with ⌘-click: the look they can share — colour, background and its
/// strength — set on all of them at once. A setting the widgets differ in shows nothing marked
/// until it is chosen.
private struct GroupInspector: View {
    let ids: Set<WidgetID>
    @Binding var selection: WidgetID?
    @Binding var group: Set<WidgetID>

    @Environment(AppModel.self) private var model

    var body: some View {
        let widgets = model.editedWidgets.board.widgets.filter { ids.contains($0.id) }
        let tints = Set(widgets.map(\.tint))
        let backgrounds = Set(widgets.map(\.background))
        // Only backgrounds every picked widget offers (Artwork is Now Playing's own); one chosen in
        // Customize (a gradient, a picture) only while every picked widget has it.
        let offered = WidgetBackground.allCases.filter { background in
            (!background.needsCustomize || backgrounds == [background]) && widgets.allSatisfy { $0.kind.backgrounds.contains(background) }
        }
        let strengths = widgets.filter { $0.background.hasOpacity }.map(\.effectiveBackgroundOpacity)
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
            StudioCard("Look", subtitle: "Applies to every picked widget.") {
                VStack(alignment: .leading, spacing: 14) {
                    LabeledSetting("Accent Colour") {
                        TintWell(selection: tints.count == 1 ? tints.first : nil, automaticHint: "each widget's own") { tint in
                            apply { $0.tint = tint }
                        }
                    }
                    LabeledSetting("Background") {
                        VStack(alignment: .leading, spacing: 10) {
                            Picker("Background", selection: Binding(
                                get: { backgrounds.count == 1 ? backgrounds.first : nil },
                                set: { (new: WidgetBackground?) in
                                    guard let new else { return }
                                    withAnimation(.spring(duration: 0.4, bounce: 0.18)) {
                                        apply {
                                            $0.background = new
                                            $0.backgroundOpacity = nil
                                        }
                                    }
                                }
                            )) {
                                ForEach(offered) { Text($0.title).tag(Optional($0)) }
                            }
                            .choiceBar()
                            .labelsHidden()
                            .fixedSize()
                            if !strengths.isEmpty {
                                BackgroundOpacitySlider(value: strengths.reduce(0, +) / Double(strengths.count)) { value in
                                    apply { if $0.background.hasOpacity { $0.backgroundOpacity = value } }
                                }
                                .transition(.opacity.combined(with: .offset(y: -8)))
                            }
                        }
                    }
                }
            }
        }
    }

    private func apply(_ change: (inout IslandWidget) -> Void) {
        withAnimation(Motion.content) {
            for id in ids { model.editedWidgets.update(id, change) }
        }
    }
}

// MARK: - Inspector

/// One widget's own system: size, look, and each element inside it.
private struct WidgetInspector: View {
    let id: WidgetID
    @Binding var selection: WidgetID?
    @Binding var notice: String?

    @Environment(AppModel.self) private var model

    var body: some View {
        if let widget = model.editedWidgets.board.widget(id) {
            let kind = widget.kind
            VStack(alignment: .leading, spacing: 16) {
                header(widget)
                HStack(alignment: .top, spacing: 16) {
                    // Size and place are set on the stage itself (drag, corner handles, arrow keys).
                    StudioCard("Look") { lookCard(widget) }
                        .frame(maxWidth: .infinity)
                    if !kind.options.isEmpty {
                        StudioCard("Elements", subtitle: "What the widget shows, and how large.") {
                            VStack(spacing: 0) {
                                ForEach(Array(kind.spec.elements.enumerated()), id: \.element.id) { index, element in
                                    if index > 0 { Divider().opacity(0.5) }
                                    ElementRow(element: element, widget: widget) { change in
                                        withAnimation(Motion.content) { model.editedWidgets.update(id, change) }
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private func header(_ widget: IslandWidget) -> some View {
        let kind = widget.kind
        return HStack(spacing: 14) {
            WidgetIcon(kind: kind, side: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.title).font(.system(size: 20, weight: .bold))
                Text("\(kind.category.title) · \(widget.frame.width) × \(widget.frame.height)")
                    .font(.callout)
                    .foregroundStyle(SettingsPalette.secondary)
            }
            Spacer()
            Button("Remove", systemImage: "minus.circle", role: .destructive) {
                selection = nil
                withAnimation(.spring(duration: 0.3)) { model.editedWidgets.remove(id) }
            }
            .controlSize(.large)
            Button("Customize…", systemImage: "paintbrush") { model.studio.probe.driver?.open(id, animated: true) }
                .controlSize(.large)
                .help("Every look of the widget and of each element in it")
            Button("Done") { selection = nil }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: Look

    private func lookCard(_ widget: IslandWidget) -> some View {
        let kind = widget.kind
        return VStack(alignment: .leading, spacing: 14) {
            if !kind.layouts.isEmpty {
                LabeledSetting("Layout") {
                    HStack(spacing: 8) {
                        ForEach(kind.layouts) { layout in
                            LayoutOption(layout: layout, isSelected: widget.layout == layout) {
                                withAnimation(Motion.content) { model.editedWidgets.update(id) { $0.layout = layout } }
                            }
                        }
                    }
                }
            }
            LabeledSetting("Accent Colour") {
                TintWell(selection: widget.tint, automaticHint: kind == .nowPlaying ? "from the artwork" : "the system's accent",
                         purpose: kind.accentPurpose) { tint in
                    withAnimation(Motion.content) { model.editedWidgets.update(id) { $0.tint = tint } }
                }
            }
            LabeledSetting("Background") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Background", selection: Binding(get: { widget.background }, set: { background in
                        withAnimation(.spring(duration: 0.4, bounce: 0.18)) {
                            model.editedWidgets.update(id) {
                                $0.background = background
                                $0.backgroundOpacity = nil
                            }
                        }
                    })) {
                        ForEach(kind.backgrounds.filter { !$0.needsCustomize || $0 == widget.background }) { Text($0.title).tag($0) }
                    }
                    .choiceBar()
                    .labelsHidden()
                    .fixedSize()
                    // Plate, Colour and Artwork have a strength; it slides out under the picker.
                    if widget.background.hasOpacity {
                        BackgroundOpacitySlider(value: widget.effectiveBackgroundOpacity) { value in
                            model.editedWidgets.update(id) { $0.backgroundOpacity = value }
                        }
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(y: -8)).combined(with: .scale(scale: 0.97, anchor: .topLeading)),
                            removal: .opacity
                        ))
                    }
                }
            }
            if kind == .nowPlaying {
                LabeledSetting("Buttons") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(isOn: Binding(get: { widget.plainButtons }, set: { on in
                            withAnimation(.spring(duration: 0.4, bounce: 0.18)) {
                                model.editedWidgets.update(id) { $0.plainButtons = on }
                            }
                        })) {
                            Text("Colourless buttons")
                            Text("All three in the plain glass, like the plate.")
                                .foregroundStyle(SettingsPalette.secondary)
                        }
                        .toggleStyle(.switch)
                        .tint(Color.islandControlAccent)
                        if !widget.plainButtons {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(TransportButton.allCases) { button in
                                    ButtonLookRow(button: button, look: widget.look(of: button)) { look in
                                        model.editedWidgets.update(id) { $0.buttonLooks[button.rawValue] = look }
                                    }
                                }
                            }
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .offset(y: -8)).combined(with: .scale(scale: 0.97, anchor: .topLeading)),
                                removal: .opacity
                            ))
                        }
                    }
                }
            }
            if kind.canMirror {
                Toggle(isOn: Binding(get: { widget.mirrored }, set: { on in
                    withAnimation(Motion.content) { model.editedWidgets.update(id) { $0.mirrored = on } }
                })) {
                    Text("Swap sides")
                    Text(kind == .nowPlaying ? "Artwork on the right." : "The two halves change places.")
                        .foregroundStyle(SettingsPalette.secondary)
                }
                .toggleStyle(.switch)
                .tint(Color.islandControlAccent)
            }
        }
    }
}

/// One element of a widget: its switch, and its size while it is shown.
private struct ElementRow: View {
    let element: ElementSpec
    let widget: IslandWidget
    let change: ((inout IslandWidget) -> Void) -> Void

    var body: some View {
        let option = element.id
        let on = widget.shows(option)
        HStack(spacing: 10) {
            Image(systemName: element.symbol)
                .font(.system(size: 12, weight: .semibold))
                // On the accent, the colour that reads on it (black on the white theme's).
                .foregroundStyle(on ? Color.onIslandAccent : SettingsPalette.secondary)
                .frame(width: 26, height: 26)
                .background(on ? AnyShapeStyle(Color.islandAccent.gradient) : AnyShapeStyle(.white.opacity(0.08)),
                            in: .rect(cornerRadius: 7, style: .continuous))
            Text(element.title)
                .foregroundStyle(on ? .primary : SettingsPalette.secondary)
            Spacer(minLength: 8)
            if element.isSizable, on {
                Picker("Size", selection: Binding(get: { widget.size(of: option) }, set: { size in
                    change { widget in
                        // Laid out freely, its size is its rectangle: that grows or shrinks.
                        let factor = Double(size.factor / widget.size(of: option).factor)
                        LayoutEdit.scale(option, by: factor, in: &widget.style.layout.arrangement)
                        widget.sizes[option] = size
                    }
                })) {
                    ForEach(ElementSize.allCases) { size in
                        Text(size.title).tag(size).help(size.accessibilityTitle)
                    }
                }
                .choiceBar()
                .labelsHidden()
                .fixedSize()
                .controlSize(.small)
                .transition(.opacity)
            }
            Toggle(element.title, isOn: Binding(get: { on }, set: { new in
                change { widget in
                    if new { widget.options.insert(option) } else { widget.options.remove(option) }
                    // Laid out freely: on the widget or in its tray with it.
                    LayoutEdit.setShown(option, new, role: element.role, parts: element.parts, in: &widget.style.layout.arrangement)
                }
            }))
            .toggleStyle(.switch)
            .tint(Color.islandControlAccent)
            .labelsHidden()
            .controlSize(.small)
        }
        .padding(.vertical, 7)
    }
}

// MARK: - Gallery

/// Every built-in widget, grouped by category: compact cards with a live preview, a name, one line
/// on what it shows, and Add (or a check and Edit once it is on the island). Worded and weighted as
/// what it is — widgets that come with the app and only need adding — not as a store.
private struct WidgetStoreView: View {
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

    var body: some View {
        let offered = IslandWidgetKind.allCases.filter(\.isOffered)
        let kinds = offered.filter { kind in
            (category == nil || kind.category == category)
                && (search.isEmpty || kind.title.localizedStandardContains(search) || kind.summary.localizedStandardContains(search))
        }
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("All Widgets").font(.title3.weight(.semibold))
                Text("Built in · \(offered.filter { model.editedWidgets.board.contains($0) }.count) of \(offered.count) on your island")
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
            } else if category == nil, search.isEmpty {
                // Everything: one titled group per category.
                ForEach(WidgetCategory.allCases) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Label(group.title, systemImage: group.systemImage)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(SettingsPalette.secondary)
                        grid(group.kinds.filter(\.isOffered))
                    }
                    .padding(.top, 4)
                }
            } else {
                grid(kinds)
            }
        }
    }

    private func grid(_ kinds: [IslandWidgetKind]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 300), spacing: 12)], spacing: 12) {
            ForEach(kinds) { kind in
                GalleryCard(kind: kind, grid: model.editedWidgets.board.grid,
                            isAdded: model.editedWidgets.board.contains(kind),
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
                    // A long name (Screen Mirroring, Battery Health) a little smaller rather than cut.
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
        .help(kind.summary)
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
    private static var nextTurn = ContinuousClock.now

    static func turn() async {
        let now = ContinuousClock.now
        let slot = max(now, nextTurn)
        nextTurn = slot + spacing
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
    @State private var thumbnails = ThumbnailCache()

    /// As long as the SwiftUI fade it replaces.
    static let fadeIn: TimeInterval = 0.2

    var body: some View {
        let geometry = WidgetBoardGeometry(size: WidgetsSettingsPage.boardSize(model.layout), grid: grid)
        let cells = grid.defaultSize(for: kind)
        let rect = GridRect(column: 0, row: 0, width: cells.width, height: cells.height)
        let size = geometry.frame(for: rect).size
        let scale = min(1, maxSize.width / size.width, maxSize.height / size.height)
        IsolatedFillHosting(input: PreviewInput(kind: kind, rect: rect, size: size, scale: scale), fadeIn: Self.fadeIn, isPicture: true) {
            IslandWidgetView(widget: IslandWidget(kind: kind, frame: rect, options: kind.defaultOptions),
                             size: size, thumbnails: thumbnails)
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
        case .system: "sun.max.fill"
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

/// A view filling the stage's room (top-left origin): the room's place in AppKit, and the scale
/// the stage shows it at (about its top centre), for the Customize transition.
private struct StageRoomAnchor: NSViewRepresentable {
    let probe: StudioProbe
    let scale: CGFloat

    func makeNSView(context: Context) -> RoomView {
        let view = RoomView()
        probe.roomView = view
        probe.roomScale = scale
        return view
    }

    func updateNSView(_ view: RoomView, context: Context) {
        probe.roomView = view
        probe.roomScale = scale
    }

    final class RoomView: NSView {
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
