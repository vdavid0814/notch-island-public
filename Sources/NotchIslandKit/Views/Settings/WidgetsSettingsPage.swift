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
                        let picked = group.filter { model.widgets.board.contains($0) }
                        if picked.count >= 2 {
                            GroupInspector(ids: picked, selection: $selection, group: $group)
                                .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                                        removal: .opacity))
                        } else if let id = selection, model.widgets.board.contains(id) {
                            WidgetInspector(id: id, selection: $selection, notice: $notice)
                                .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                                        removal: .opacity))
                        } else {
                            WidgetStoreView(add: { add($0, scroller: scroller) },
                                        open: { kind in
                                            if let id = model.widgets.board.first(of: kind)?.id { select(id, scroller: scroller) }
                                        })
                                .transition(.opacity)
                        }
                    }
                    .animation(.spring(duration: 0.35, bounce: 0.12), value: selection)
                    .animation(.spring(duration: 0.35, bounce: 0.12), value: group.count >= 2)
                }
                .padding(.horizontal, 28)
                .padding(.top, 10)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.automatic)
        }
        .onAppear(perform: takeRequestedEdit)
        .onChange(of: model.editingWidget) { takeRequestedEdit() }
        .task(id: notice) {
            guard notice != nil else { return }
            try? await Task.sleep(for: .seconds(4))
            notice = nil
        }
    }

    /// Exactly the area the home page gives its board.
    static func boardSize(_ layout: IslandLayout) -> CGSize {
        let presentation = IslandPresentation.expanded(.home)
        let island = layout.size(for: presentation)
        let split = NotchSplit(layout: layout, presentation: presentation,
                               outerInset: Metrics.Expanded.horizontalInset, clearance: Metrics.notchClearance)
        return CGSize(
            width: island.width - 2 * split.contentInset,
            height: island.height - layout.notch.height - Metrics.Expanded.pageTopInset - Metrics.Expanded.pageBottomInset
        )
    }

    /// "Edit …" from a widget's context menu in the island.
    private func takeRequestedEdit() {
        guard let id = model.editingWidget else { return }
        model.editingWidget = nil
        guard model.widgets.board.contains(id) else { return }
        selection = id
    }

    private func select(_ id: WidgetID, scroller: ScrollViewProxy) {
        selection = id
        withAnimation(.spring(duration: 0.4)) { scroller.scrollTo(StudioAnchor.stage, anchor: .top) }
    }

    private func add(_ kind: IslandWidgetKind, scroller: ScrollViewProxy) {
        var added: WidgetID?
        withAnimation(.spring(duration: 0.35, bounce: 0.2)) { added = model.widgets.add(kind) }
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

/// What the stage's island takes from Settings around it: the widgets picked.
private struct StagePick: Equatable {
    let selection: WidgetID?
    let group: Set<WidgetID>
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

    /// Between the hint and the button and the stage's edges.
    static let controlInset: CGFloat = 12

    var body: some View {
        let layout = model.layout
        let island = layout.size(for: .expanded(.home))
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
            IsolatedHosting(size: island, input: StagePick(selection: selection, group: group)) {
                StageIsland(selection: $selection, group: $group, thumbnails: thumbnails)
                    .environment(model)
                    .environment(\.appearsActive, true)
            }
        }
        .frame(height: layout.notch.height + island.height + 70)
        .frame(maxWidth: .infinity)
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(.white.opacity(0.1))
        }
        .overlay(alignment: .bottom) {
            HStack(spacing: 10) {
                Label(notice ?? (group.count >= 2
                                 ? "\(group.count) widgets picked: change their look together. ⌘-click to add or remove."
                                 : selection == nil
                                 ? "Click a widget to customize it, ⌘-click to pick several. Drag to move, drag a corner to resize."
                                 : "Arrow keys move it one cell. Delete removes it. ⌘-click another to edit both."),
                      systemImage: notice == nil ? "hand.tap.fill" : "exclamationmark.triangle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(notice == nil ? AnyShapeStyle(.white) : AnyShapeStyle(.orange))
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .frame(minHeight: controlHeight)
                    .glassEffect(.regular, in: .capsule)
                Spacer()
                Menu {
                    Picker("Wallpaper", selection: $backdrop) {
                        ForEach(DesktopBackdropStyle.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                    Divider()
                    Button("Reset to Default Widgets", role: .destructive) {
                        selection = nil
                        withAnimation(.spring(duration: 0.35)) { model.widgets.reset() }
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

    @Environment(AppModel.self) private var model

    var body: some View {
        let layout = model.layout
        let presentation = IslandPresentation.expanded(.home)
        let size = layout.size(for: presentation)
        let split = NotchSplit(layout: layout, presentation: presentation,
                               outerInset: Metrics.Expanded.horizontalInset, clearance: Metrics.notchClearance)
        let shape = IslandShape(bottomRadius: layout.bottomRadius(for: presentation),
                                shoulderRadius: layout.shoulderRadius(for: presentation))
        let style = model.effectiveGlassStyle
        GlassEffectContainer {
            VStack(spacing: 0) {
                ExpandedHeader(split: split, height: layout.notch.height)
                    .allowsHitTesting(false)
                    // A picture of the header: its controls' tooltips ("Home"…) must not pop up
                    // over the widgets being arranged under it.
                    .environment(\.showsControlHelp, false)
                    .overlay {
                        // The camera housing.
                        UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8)
                            .fill(.black)
                            .frame(width: layout.notch.width, height: layout.notch.height)
                    }
                BoardEditor(selection: $selection, thumbnails: thumbnails, group: $group)
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
        let widgets = model.widgets.board.widgets.filter { ids.contains($0.id) }
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
                    withAnimation(.spring(duration: 0.3)) { doomed.forEach { model.widgets.remove($0) } }
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
                    LabeledSetting("Colour") {
                        TintSwatches(selection: tints.count == 1 ? tints.first : nil, automaticHint: "Each widget's own") { tint in
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
            for id in ids { model.widgets.update(id, change) }
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
        if let widget = model.widgets.board.widget(id) {
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
                                        withAnimation(Motion.content) { model.widgets.update(id, change) }
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
                withAnimation(.spring(duration: 0.3)) { model.widgets.remove(id) }
            }
            .controlSize(.large)
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
                                withAnimation(Motion.content) { model.widgets.update(id) { $0.layout = layout } }
                            }
                        }
                    }
                }
            }
            LabeledSetting("Colour") {
                TintSwatches(selection: widget.tint, automaticHint: kind == .nowPlaying ? "From the artwork" : "Accent colour") { tint in
                    withAnimation(Motion.content) { model.widgets.update(id) { $0.tint = tint } }
                }
            }
            LabeledSetting("Background") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Background", selection: Binding(get: { widget.background }, set: { background in
                        withAnimation(.spring(duration: 0.4, bounce: 0.18)) {
                            model.widgets.update(id) {
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
                            model.widgets.update(id) { $0.backgroundOpacity = value }
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
                                model.widgets.update(id) { $0.plainButtons = on }
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
                                        model.widgets.update(id) { $0.buttonLooks[button.rawValue] = look }
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
                    withAnimation(Motion.content) { model.widgets.update(id) { $0.mirrored = on } }
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
                .foregroundStyle(on ? .white : SettingsPalette.secondary)
                .frame(width: 26, height: 26)
                .background(on ? AnyShapeStyle(Color.islandAccent.gradient) : AnyShapeStyle(.white.opacity(0.08)),
                            in: .rect(cornerRadius: 7, style: .continuous))
            Text(element.title)
                .foregroundStyle(on ? .primary : SettingsPalette.secondary)
            Spacer(minLength: 8)
            if element.isSizable, on {
                Picker("Size", selection: Binding(get: { widget.size(of: option) }, set: { size in
                    change { $0.sizes[option] = size }
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

    var body: some View {
        let offered = IslandWidgetKind.allCases.filter(\.isOffered)
        let kinds = offered.filter { kind in
            (category == nil || kind.category == category)
                && (search.isEmpty || kind.title.localizedStandardContains(search) || kind.summary.localizedStandardContains(search))
        }
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("All Widgets").font(.title3.weight(.semibold))
                    Text("Built in · \(offered.filter { model.widgets.board.contains($0) }.count) of \(offered.count) on your island")
                        .font(.callout)
                        .foregroundStyle(SettingsPalette.secondary)
                }
                Spacer(minLength: 0)
                NativeSearchField(text: $search, prompt: "Search Widgets")
                    .frame(width: 200)
            }
            Picker("Category", selection: $category) {
                Text("All").tag(WidgetCategory?.none)
                // Only groups with something to offer: kinds still being built stay out of the bar.
                ForEach(WidgetCategory.allCases.filter { group in offered.contains { $0.category == group } }) {
                    Text($0.title).tag(Optional($0))
                }
            }
            .choiceBar()
            .labelsHidden()
            .fixedSize()

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
                GalleryCard(kind: kind, grid: model.widgets.board.grid,
                            order: IslandWidgetKind.allCases.firstIndex(of: kind) ?? 0,
                            isAdded: model.widgets.board.contains(kind),
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
    /// Position in the gallery: previews come in one after another.
    let order: Int
    let isAdded: Bool
    let add: () -> Void
    let open: () -> Void

    @State private var isHovered = false
    /// A live preview is a whole widget (sliders, glass buttons…). Built all at once, sixteen of
    /// them stalled the frame Settings opened in; each now arrives a few frames after the last,
    /// fading in on the render server (`WidgetPreview`).
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
            try? await Task.sleep(for: .milliseconds(60 + 35 * order))
            guard !Task.isCancelled else { return }
            showsPreview = true
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
