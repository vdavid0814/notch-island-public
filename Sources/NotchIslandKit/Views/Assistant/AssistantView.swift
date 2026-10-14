import SwiftUI

/// Siri in the notch, as spare as the system's Search window: the Siri orb in the header band and
/// the field; under it (when the island makes room, see `AssistantRoom`) the suggestions
/// (Applications ⌘1 … Emoji ⌘7), the app gallery, the hits and actions for the query, or Apple
/// Intelligence's answer.
///
/// The view is always laid out at the list's full height and the island's outline clips it, so
/// growing from the field to the list uncovers the rows instead of squeezing them.
///
/// Keys: typing goes to the field; ↑/↓ move the selection (←/→ too in the gallery), Return runs
/// it, ⌘Return asks Apple Intelligence, ⌘1–⌘7 open a suggestion, ⌘C copies a clip or an emoji,
/// ⌘H and ⌘Q hide or quit a running app, ⌘↩ anchors its window under the notch, Delete in an empty field leaves it, Esc steps back (answer → empty field → suggestions → closed). The whole view keeps one
/// identity while it is open (`surfaceKey` "assistant"): a new one would recreate the field and
/// drop its keyboard focus.
struct AssistantView: View {
    @Environment(AppModel.self) private var model
    @FocusState private var isFieldFocused: Bool
    @State private var swipe = AssistantSwipe()

    var body: some View {
        let layout = model.layout
        let assistant = model.assistant
        // Its room's kind (`AssistantModel.room`) without reading the room: that reads the rows, and
        // every keystroke and landing search would build this whole view again, not only the list.
        let isGallery = assistant.category == .applications && assistant.answer == nil
        let showsTiles = assistant.showsSearchTiles
        // Laid out at the largest size of the current kind: the list (a query's with its tiles), or
        // the gallery's window.
        let fullRoom: AssistantRoom = isGallery ? .gallery : showsTiles ? .search(layout.siri.listRows)
            : assistant.answer != nil ? .answer(9999) : .list
        let split = NotchSplit(
            layout: layout,
            presentation: .assistant(fullRoom),
            outerInset: Metrics.Expanded.horizontalInset,
            clearance: Metrics.notchClearance
        )
        let fullHeight = layout.size(for: .assistant(fullRoom)).height
        // The gallery's grid is always as wide as in the gallery's window, also while the island
        // shrinks back to the list around it (it would reflow into the narrower width meanwhile).
        let galleryWidth = layout.size(for: .assistant(.gallery)).width - 2 * NotchSplit(
            layout: layout, presentation: .assistant(.gallery),
            outerInset: Metrics.Expanded.horizontalInset, clearance: Metrics.notchClearance
        ).contentInset
        let below: BelowField = assistant.answer != nil ? .answer : isGallery ? .gallery : !assistant.needsList ? .picks
            : showsTiles ? .search : .rows
        // Below the field nothing shows while the island is only the field (the rows would peek
        // out under it); they fade in with the island's growth.
        let showsBelowField: Bool = if case .assistant(.field) = model.island.presentation { false } else { true }
        VStack(spacing: 0) {
            NotchSplitBand(split: split, height: layout.notch.height) {
                // The Spotlight mark is in the field now (asked for: not twice).
                EmptyView()
            } trailing: {
                EmptyView()
            }

            VStack(spacing: IslandLayout.assistantTopInset) {
                field(assistant)
                Group {
                    if let answer = assistant.answer {
                        AnswerPane(answer: answer)
                    } else if isGallery {
                        AppGallery(assistant: assistant, plateRadius: layout.assistantGalleryPlateRadius)
                            .frame(width: galleryWidth)
                    } else if below == .picks {
                        // Each box's corners concentric with the panel's lower corners.
                        QuickPicks(assistant: assistant,
                                   radius: layout.bottomRadius(for: .assistant(.picks)) - IslandLayout.assistantPicksGap)
                            .padding(.top, IslandLayout.assistantPicksGap - IslandLayout.assistantTopInset)
                            // Out to 2 pt from the panel's sides, past the page's inset (its body starts
                            // `outerInset` outside the content; the shoulders are beyond).
                            .padding(.horizontal, IslandLayout.assistantPicksGap - split.outerInset)
                    } else if below == .search {
                        SearchResults(assistant: assistant, layout: layout,
                                      extraInset: layout.assistantRowInset - Metrics.Expanded.horizontalInset,
                                      tileRadius: layout.bottomRadius(for: .assistant(.picks)) - IslandLayout.assistantPicksGap,
                                      tileOutset: IslandLayout.assistantPicksGap - split.outerInset)
                    } else {
                        RowsList(assistant: assistant,
                                 extraInset: layout.assistantRowInset - Metrics.Expanded.horizontalInset)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                // Into a suggestion the page slides in from the right and the search out to the
                // left; back, the other way (asked for). Each side always leaves and comes back
                // the same way, so no direction has to be remembered.
                .id(assistant.category)
                .transition(assistant.category == nil ? Self.searchSlide : Self.suggestionSlide)
                .animation(Self.slide, value: assistant.category)
                // Their own short cross-fade: the island's spring does not reach in here (the
                // content changes size at once, `IslandContentStack`).
                .animation(Self.swap, value: below)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .opacity(showsBelowField ? 1 : 0)
                .animation(Self.swap, value: showsBelowField)
            }
            .padding(.top, IslandLayout.assistantTopInset)
            .padding(.bottom, Metrics.Expanded.pageBottomInset)
            .padding(.horizontal, split.contentInset)
        }
        .frame(height: fullHeight, alignment: .top)
        .onKeyPress(.upArrow) {
            assistant.moveSelection(by: isGallery ? -assistant.galleryColumns : -1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            assistant.moveSelection(by: isGallery ? assistant.galleryColumns : 1)
            return .handled
        }
        .onKeyPress(.leftArrow) {
            guard isGallery else { return assistant.moveAmongTiles(by: -1) ? .handled : .ignored }
            assistant.moveSelection(by: -1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            guard isGallery else { return assistant.moveAmongTiles(by: 1) ? .handled : .ignored }
            assistant.moveSelection(by: 1)
            return .handled
        }
        .onKeyPress(.return, phases: .down) { press in
            // Plain Return is left to the field (IME commit, then onSubmit).
            guard press.modifiers.contains(.command) else { return .ignored }
            // On a window the user picked, ⌘↩ anchors it under the notch.
            if assistant.anchorSelectedWindow() { return .handled }
            assistant.ask()
            return .handled
        }
        .onKeyPress(keys: Set(AssistantCategory.allCases.map(\.key)), phases: .down) { press in
            guard press.modifiers == .command,
                  let category = AssistantCategory.allCases.first(where: { $0.key == press.key }) else { return .ignored }
            assistant.open(category)
            return .handled
        }
        .onKeyPress(KeyEquivalent("c"), phases: .down) { press in
            guard press.modifiers == .command else { return .ignored }
            return assistant.copySelection() ? .handled : .ignored
        }
        // Quick Look on a file the selection was moved to (Space there, ⌘Y anywhere), and ⌘R to
        // show a file or an app in Finder.
        .onKeyPress(.space, phases: .down) { press in
            guard press.modifiers.isEmpty else { return .ignored }
            return assistant.quickLookSelection() ? .handled : .ignored
        }
        .onKeyPress(KeyEquivalent("y"), phases: .down) { press in
            guard press.modifiers == .command else { return .ignored }
            return assistant.quickLookSelection() ? .handled : .ignored
        }
        .onKeyPress(KeyEquivalent("r"), phases: .down) { press in
            guard press.modifiers == .command else { return .ignored }
            return assistant.revealSelection() ? .handled : .ignored
        }
        .onKeyPress(KeyEquivalent("h"), phases: .down) { press in
            guard press.modifiers == .command else { return .ignored }
            return assistant.hideSelectedApp() ? .handled : .ignored
        }
        .onKeyPress(KeyEquivalent("q"), phases: .down) { press in
            guard press.modifiers == .command else { return .ignored }
            return assistant.quitSelectedApp() ? .handled : .ignored
        }
        .onKeyPress(.delete) {
            assistant.deleteBackwardInEmptyField() ? .handled : .ignored
        }
        .onExitCommand { assistant.escape() }
        // Focus is asked for once the panel is key (the field editor does not take first responder
        // in a window that is not key yet), a turn later, and again whenever the panel becomes key.
        .onAppear {
            focusField()
            // Two fingers to the right: back to the search; to the left: into the last suggestion.
            swipe.start { back in
                withAnimation(Self.slide) { _ = back ? assistant.swipeBack() : assistant.swipeForward() }
            }
        }
        // Its lists, icons and the answer pane go with it: give their memory back.
        .onDisappear {
            swipe.stop()
            MemoryRelief.afterLargeSurfaceClosed()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
            guard note.object is IslandPanel else { return }
            focusField()
        }
    }

    /// What shows under the field.
    private enum BelowField { case rows, gallery, answer, picks, search }

    /// The swap under the field: as short as the content's swap while the island moves.
    static let swap: Animation = .easeOut(duration: 0.18)

    /// Into a suggestion and back out of it.
    static let slide: Animation = .smooth(duration: 0.3)
    static let searchSlide: AnyTransition = .move(edge: .leading).combined(with: .opacity)
    static let suggestionSlide: AnyTransition = .move(edge: .trailing).combined(with: .opacity)

    private func focusField() {
        isFieldFocused = false
        Task { @MainActor in
            await Task.yield()
            isFieldFocused = true
        }
    }

    private func field(_ assistant: AssistantModel) -> some View {
        @Bindable var assistant = assistant
        let isResponding = assistant.answer?.isResponding == true || assistant.isHandingToSiri
        return HStack(spacing: Metrics.Spacing.medium) {
            Group {
                if let category = assistant.category {
                    category.tile
                } else {
                    // NotchIsland's Spotlight mark where the magnifier was, in the field's grey.
                    SpotlightMark()
                        .fill(.secondary)
                        .frame(width: 17, height: 17)
                        .accessibilityLabel("Spotlight")
                }
                // In Clipboard the field shows the copy the selection is on, as Spotlight does.
                TextField(assistant.selectedClip?.preview ?? assistant.category?.title ?? String(localized: "Search or Ask"),
                          text: $assistant.query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($isFieldFocused)
                    .onSubmit { assistant.activateSelection() }
            }
            // Inside Applications, Files or Actions a click on the field goes back to the three
            // suggestions (the query stays), as Esc does. A layer over the field takes the click:
            // the text field itself (AppKit) swallows it before a gesture sees it. Typing still
            // goes to the field, which keeps the keyboard.
            .overlay {
                if assistant.category != nil {
                    Color.clear
                        .contentShape(.rect)
                        .onTapGesture {
                            withAnimation(Motion.content) { assistant.open(nil) }
                            focusField()
                        }
                        .help("Back to Applications, Files and Actions")
                }
            }
            Button {
                AssistantActions.startDictation()
            } label: {
                Image(systemName: "mic.fill")
                    .foregroundStyle(.secondary)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help("Dictation")
        }
        .padding(.horizontal, Metrics.Spacing.large)
        .frame(height: IslandLayout.assistantFieldHeight)
        .background(.white.opacity(0.08), in: Capsule())
        .overlay(alignment: .bottom) {
            // Siri's colours along the field while it answers; nothing otherwise.
            if isResponding {
                AssistantGlow(isFlowing: true)
                    .padding(.horizontal, Metrics.Spacing.xLarge)
                    .offset(y: 2)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: isResponding)
    }
}

extension AssistantCategory {
    var title: String {
        switch self {
        case .applications: String(localized: "Applications")
        case .files: String(localized: "Files")
        case .actions: String(localized: "Actions")
        case .clipboard: String(localized: "Clipboard")
        case .system: String(localized: "System")
        case .windows: String(localized: "Windows")
        case .emoji: String(localized: "Emoji")
        case .people: String(localized: "People & Calendar")
        }
    }

    /// ⌘1–⌘8.
    var key: KeyEquivalent { KeyEquivalent(Character(String(rawValue))) }

    /// The tile at another size (the quick picks').
    func tile(side: CGFloat) -> some View {
        AssistantTile(symbol: tileSymbol, color: tileColor, side: side)
    }

    private var tileSymbol: String {
        switch self {
        case .applications: "square.grid.2x2.fill"
        case .files: "folder.fill"
        case .actions: "bolt.fill"
        case .clipboard: "list.clipboard.fill"
        case .system: "switch.2"
        case .windows: "macwindow.on.rectangle"
        case .emoji: "face.smiling.inverse"
        case .people: "person.2.fill"
        }
    }

    private var tileColor: Color {
        switch self {
        case .applications: .blue
        case .files: .cyan
        case .actions: .orange
        case .clipboard: .gray
        case .system: .indigo
        case .windows: .purple
        case .emoji: .yellow
        case .people: .green
        }
    }

    var tile: some View {
        AssistantTile(symbol: tileSymbol, color: tileColor)
    }
}

/// A symbol on a small coloured tile, the size of an app icon in the list (larger in the quick
/// picks, `side`).
struct AssistantTile: View {
    let symbol: String
    let fill: AnyShapeStyle
    var side: CGFloat = 22

    init(symbol: String, color: Color, side: CGFloat = 22) {
        self.init(symbol: symbol, fill: AnyShapeStyle(color.gradient), side: side)
    }

    init(symbol: String, fill: AnyShapeStyle, side: CGFloat = 22) {
        self.symbol = symbol
        self.fill = fill
        self.side = side
    }

    var body: some View {
        RoundedRectangle(cornerRadius: side * 0.27, style: .continuous)
            .fill(fill)
            .frame(width: side, height: side)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: side * 0.5, weight: .semibold))
                    .foregroundStyle(.white)
            }
    }
}

/// The pointer over Siri: Applications, Files, Actions and Clipboard as large icons side by side,
/// each opening its list as its row in the suggestions would. Each in a box of the same size — the
/// outer ones' sides on the field's, all of them as far above the panel's bottom as that, their
/// corners concentric with the panel's — shown grey under the pointer.
private struct QuickPicks: View {
    let assistant: AssistantModel
    let radius: CGFloat

    var body: some View {
        HStack(spacing: Self.spacing) {
            ForEach(Array(assistant.quickPicks.enumerated()), id: \.element) { index, category in
                QuickPick(category: category, radius: radius,
                          isMarked: assistant.marksSelection && assistant.selection == index) { assistant.open(category) }
            }
        }
        .frame(height: IslandLayout.assistantPicksHeight)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    static let spacing: CGFloat = 4
}

private struct QuickPick: View {
    let category: AssistantCategory
    let radius: CGFloat
    /// Chosen with ↑/↓: shown as under the pointer.
    var isMarked = false
    let open: () -> Void

    var body: some View {
        PickBox(title: category.title, radius: radius, isMarked: isMarked, action: open) {
            category.tile(side: PickBox<EmptyView>.iconSide)
        }
    }
}

/// A query's Ask Apple Intelligence, Search the Web and Ask ChatGPT as large tiles in a row under
/// its rows, in boxes like the quick picks' (asked for: not as rows).
private struct SearchTiles: View {
    let assistant: AssistantModel
    let radius: CGFloat

    var body: some View {
        let rows = assistant.rows
        let tiles = rows.indices.filter { rows[$0].isSearchTile }
        HStack(spacing: QuickPicks.spacing) {
            ForEach(tiles, id: \.self) { index in
                let row = rows[index]
                PickBox(title: Self.title(row), radius: radius,
                        isMarked: assistant.marksSelection && assistant.selection == index) { assistant.perform(row) } icon: {
                    Self.icon(row)
                }
            }
        }
        .frame(height: IslandLayout.assistantPicksHeight)
    }

    /// Siri AI's own icon, the new Siri's (the Siri app's before it), as the
    /// system draws it (asked for: not a symbol). Read once.
    private static let intelligenceIcon: NSImage? = {
        let paths = ["/System/Applications/Siri AI.app", "/System/Applications/Siri.app", "/System/Library/CoreServices/Siri.app"]
        return paths.first { FileManager.default.fileExists(atPath: $0) }.map { NSWorkspace.shared.icon(forFile: $0) }
    }()

    private static func title(_ row: AssistantRow) -> String {
        switch row {
        case .askIntelligence: String(localized: "Use Siri AI")
        case .searchWeb: String(localized: "Search the Web")
        default: String(localized: "Ask ChatGPT")
        }
    }

    @ViewBuilder private static func icon(_ row: AssistantRow) -> some View {
        let side = PickBox<EmptyView>.iconSide
        switch row {
        case .askIntelligence:
            if let icon = intelligenceIcon {
                // An app icon has a margin round its body (a tenth on each side): drawn larger, its
                // body is as large as the other tiles.
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: side * 1.25, height: side * 1.25)
                    .frame(width: side, height: side)
            } else {
                AssistantTile(symbol: "apple.intelligence", fill: AnyShapeStyle(AssistantGlow.gradient), side: side)
            }
        case .searchWeb: AssistantTile(symbol: "safari.fill", color: .blue, side: side)
        default: AssistantTile(symbol: "bubble.left.and.text.bubble.right.fill", color: .green, side: side)
        }
    }
}

/// A query's rows with its tiles under them; the rows scroll past the list's height, the tiles
/// stay (`AssistantRoom.search`).
private struct SearchResults: View {
    let assistant: AssistantModel
    let layout: IslandLayout
    let extraInset: CGFloat
    let tileRadius: CGFloat
    /// Out to 2 pt from the panel's sides, past the page's inset, as the quick picks.
    let tileOutset: CGFloat

    var body: some View {
        let listed = assistant.rows.count { !$0.isSearchTile }
        VStack(spacing: IslandLayout.assistantTilesGap) {
            if listed > 0 {
                RowsList(assistant: assistant, extraInset: extraInset, excludesTiles: true)
                    .frame(height: layout.assistantSearchRowsHeight(min(listed, layout.siri.listRows)))
            }
            SearchTiles(assistant: assistant, radius: tileRadius)
                // With no rows, right under the field, as the quick picks.
                .padding(.top, listed > 0 ? 0 : IslandLayout.assistantPicksGap - IslandLayout.assistantTopInset)
                .padding(.horizontal, tileOutset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// A large icon over its caption in a box, grey under the pointer or when ↑/↓ chose it.
private struct PickBox<Icon: View>: View {
    let title: String
    let radius: CGFloat
    var isMarked = false
    let action: () -> Void
    @ViewBuilder let icon: () -> Icon
    @State private var isHovered = false

    /// The icon as large as the box leaves it beside its caption.
    static var iconSide: CGFloat { 60 }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                icon()
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(isHovered || isMarked ? 1 : 0.8))
                    .lineLimit(1)
            }
            // The caption's line reaches below its letters: a point lower, the icon's top is as far
            // under the field as the letters are above the panel's bottom.
            .offset(y: 1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.white.opacity(isHovered || isMarked ? 0.1 : 0), in: .rect(cornerRadius: radius, style: .continuous))
            .contentShape(.rect(cornerRadius: radius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .accessibilityLabel(title)
    }
}

/// The suggestions, hits and actions; the selected row is tinted, ↑/↓ scroll it into view (the
/// pointer does not move the selection: it only clicks (reported: following it felt slow, v0.4.5).
private struct RowsList: View {
    let assistant: AssistantModel
    /// The rows further in than the field, so their capsules are concentric with the panel's
    /// corners (`IslandLayout.assistantRowInset`).
    let extraInset: CGFloat
    /// A query's Ask / Web / ChatGPT are tiles under the list (`SearchTiles`), not rows in it.
    var excludesTiles = false

    var body: some View {
        let rows = assistant.rows
        let count = rows.count
        let listed = Array(rows.enumerated()).filter { !excludesTiles || !$0.element.isSearchTile }
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: IslandLayout.assistantRowSpacing) {
                    ForEach(listed, id: \.element.id) { index, row in
                        RowView(row: row, isMarked: assistant.marksSelection && index == assistant.selection,
                                state: Self.state(of: row, in: assistant), isConfirming: assistant.confirming == row.id,
                                leadingInset: max(Metrics.Spacing.small, Metrics.Spacing.large - extraInset))
                            .id(row.id)
                            .contentShape(.rect)
                            .onTapGesture { assistant.perform(row) }
                    }
                }
                .padding(.horizontal, extraInset)
                .background {
                    SelectionScroller(assistant: assistant, count: count) {
                        // A tile is not in the list: nothing to scroll to.
                        if !excludesTiles || !rows[$0].isSearchTile { proxy.scrollTo(rows[$0].id) }
                    }
                }
            }
            .scrollIndicators(.never)
            // Fewer rows than fit: nothing to scroll, so no rubber-band either.
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    /// A switch's state as read this opening ("Wi-Fi — On").
    private static func state(of row: AssistantRow, in assistant: AssistantModel) -> Bool? {
        guard case .command(let command) = row else { return nil }
        return assistant.commandStates[command]
    }
}

/// Every app as an icon with its name, most recently used first, like the system's Applications
/// view; the field filters it.
private struct AppGallery: View {
    let assistant: AssistantModel
    let plateRadius: CGFloat

    var body: some View {
        // The user's column count (Settings ▸ Siri ▸ App Gallery); the window widens with it.
        let columnCount = assistant.galleryColumns
        let iconSize = assistant.galleryIconSize
        let columns = Array(repeating: GridItem(.flexible(), spacing: IslandLayout.galleryRowSpacing),
                            count: columnCount)
        let rows = assistant.rows
        let count = rows.count
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, spacing: IslandLayout.galleryRowSpacing) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        if case .hit(let hit) = row {
                            GalleryCell(hit: hit, isMarked: assistant.marksSelection && index == assistant.selection,
                                        plateRadius: plateRadius, iconSize: iconSize)
                                .id(row.id)
                                .contentShape(.rect)
                                .onTapGesture { assistant.perform(row) }
                        }
                    }
                }
                .background { SelectionScroller(assistant: assistant, count: count) { proxy.scrollTo(rows[$0].id) } }
            }
            .scrollIndicators(.never)
            // Fewer rows than fit: nothing to scroll, so no rubber-band either.
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

private struct GalleryCell: View {
    let hit: AssistantHit
    /// The keys moved the selection here (`AssistantModel.marksSelection`).
    var isMarked = false
    var plateRadius: CGFloat = 10
    var iconSize: CGFloat = SiriGalleryIconSize.medium.points
    @State private var icon: NSImage?

    var body: some View {
        VStack(spacing: Metrics.Spacing.xSmall) {
            Group {
                if let icon = icon ?? AssistantIcons.cachedThumbnail(for: hit, points: iconSize) {
                    Image(nsImage: icon)
                } else {
                    // Only a cell without its icon yet asks for it: a gallery of kept icons starts
                    // no task per cell.
                    RoundedRectangle(cornerRadius: iconSize * 0.23, style: .continuous)
                        .fill(.white.opacity(0.08))
                        .padding(4)
                        .task(id: "\(Int(iconSize)) \(hit.url.path)") {
                            icon = await AssistantIcons.thumbnail(for: hit, points: iconSize)
                        }
                }
            }
            .frame(width: iconSize, height: iconSize)
            Text(hit.name)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, Metrics.Spacing.xxSmall)
        // Exactly the height `IslandLayout` sizes the gallery by, so N rows fill it.
        .frame(maxWidth: .infinity, minHeight: IslandLayout.galleryCellHeight(icon: iconSize),
               maxHeight: IslandLayout.galleryCellHeight(icon: iconSize))
        .background { SelectionPlate(isShown: isMarked, shape: .rect(cornerRadius: plateRadius, style: .continuous)) }
    }
}

/// Brings a selection the keys moved into view (`SelectionPlate` marks it then).
private struct SelectionScroller: View {
    let assistant: AssistantModel
    let count: Int
    let scroll: (Int) -> Void

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .onChange(of: assistant.selection) { _, selection in
                guard !assistant.selectionFollowsPointer, selection >= 0, selection < count else { return }
                scroll(selection)
            }
    }
}

/// Where ↑/↓ are: a soft plate in the theme's colour, only after the keys moved the selection.
/// A list row's is a capsule, a gallery cell's rounded concentric with the panel's corners.
private struct SelectionPlate: View {
    let isShown: Bool
    var shape: AnyShape = AnyShape(Capsule())

    init(isShown: Bool, shape: some Shape = Capsule()) {
        self.isShown = isShown
        self.shape = AnyShape(shape)
    }

    var body: some View {
        shape
            .fill(Color.islandAccent.opacity(0.16))
            .opacity(isShown ? 1 : 0)
            .animation(.easeOut(duration: 0.12), value: isShown)
    }
}

/// An icon and a name, nothing else (a suggestion also shows its shortcut, as the system does).
struct RowView: View {
    let row: AssistantRow
    /// The keys moved the selection here (`AssistantModel.marksSelection`).
    var isMarked = false
    /// A switch's On or Off.
    var state: Bool?
    /// Waiting for a second Return (`AssistantModel.confirming`).
    var isConfirming = false
    /// From the capsule's ends to the icon and the shortcut: the icon lines up with the field's
    /// magnifying glass above.
    var leadingInset: CGFloat = Metrics.Spacing.large

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        HStack(spacing: Metrics.Spacing.large) {
            icon
                .frame(width: 22, height: 22)
            Text(title).lineLimit(1)
            Spacer(minLength: 0)
            if case .clip(let item) = row {
                Text("Copied \(item.copied.formatted(date: Calendar.current.isDateInToday(item.copied) ? .omitted : .abbreviated, time: .shortened))")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if case .category(let category) = row {
                Text(verbatim: "⌘\(category.rawValue)")
                    .foregroundStyle(.secondary)
            }
            if let detail {
                Text(detail)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, leadingInset)
        .frame(height: IslandLayout.assistantRowHeight)
        .background { SelectionPlate(isShown: isMarked) }
    }

    @ViewBuilder private var icon: some View {
        switch row {
        case .category(let category):
            category.tile
        case .hit(let hit):
            Image(nsImage: AssistantIcons.icon(for: hit, scale: displayScale))
                .resizable()
                .aspectRatio(contentMode: .fit)
        case .action(.island(let action)):
            AssistantTile(symbol: action.symbol, color: .gray)
        case .action(.shortcut):
            Image(nsImage: AssistantIcons.shortcuts(scale: displayScale))
                .resizable()
                .aspectRatio(contentMode: .fit)
        case .clip:
            Image(systemName: "doc.plaintext").foregroundStyle(.secondary).imageScale(.large)
        case .command(.control(let control)):
            AssistantTile(symbol: control.symbol(on: state ?? true), color: state == false ? .gray : .blue)
        case .command(let command):
            AssistantTile(symbol: command.symbol, color: .gray)
        case .settingsPane:
            Image(nsImage: AssistantIcons.systemSettings(scale: displayScale))
                .resizable()
                .aspectRatio(contentMode: .fit)
        case .window(let window):
            Image(nsImage: AssistantIcons.app(window.appPath, scale: displayScale))
                .resizable()
                .aspectRatio(contentMode: .fit)
        case .emoji(let emoji):
            Text(emoji.character).font(.system(size: 17))
        case .calculation:
            AssistantTile(symbol: "equal", color: .orange)
        case .definition:
            AssistantTile(symbol: "character.book.closed.fill", color: .brown)
        case .contact:
            AssistantTile(symbol: "person.fill", color: .green)
        case .contactAction(let action):
            AssistantTile(symbol: action.symbol, color: action.kind == .copy ? .gray : .green)
        case .event(let event):
            AssistantTile(symbol: "calendar", color: Color(red: event.red, green: event.green, blue: event.blue))
        case .bookmark:
            AssistantTile(symbol: "bookmark.fill", color: .blue)
        case .permission(let permission):
            AssistantTile(symbol: permission.symbol, color: .gray)
        case .openURL:
            AssistantTile(symbol: "globe", color: .blue)
        case .askIntelligence:
            Image(systemName: "apple.intelligence").foregroundStyle(AssistantGlow.gradient).imageScale(.large)
        case .searchWeb:
            Image(systemName: "safari").foregroundStyle(.blue).imageScale(.large)
        case .askChatGPT:
            Image(systemName: "bubble.left.and.text.bubble.right.fill").foregroundStyle(.green).imageScale(.large)
        }
    }

    /// Trailing, in grey: where a pane or a window is.
    private var detail: String? {
        switch row {
        case .settingsPane: String(localized: "System Settings")
        case .window(let window) where window.title != nil: window.appName
        case .definition: String(localized: "Dictionary")
        case .contact(let contact): contact.detail
        case .event(let event): Self.when(event)
        case .bookmark(let bookmark): bookmark.url.host() ?? bookmark.browser
        default: nil
        }
    }

    private var title: String {
        switch row {
        case .category(let category): category.title
        case .hit(let hit): hit.name
        case .action(let action): action.title
        case .clip(let item): item.preview
        case .command(.mac(.emptyTrash)) where isConfirming: String(localized: "Press Return again to empty the Trash")
        case .command(.control(let control)): state.map { "\(control.title) — \(control.status(on: $0))" } ?? control.title
        case .command(let command): state.map { "\(command.title) — \($0 ? String(localized: "On") : String(localized: "Off"))" } ?? command.title
        case .settingsPane(let pane): pane.title
        case .window(let window): window.name
        case .emoji(let emoji): emoji.title
        case .calculation(let calculation): "\(calculation.expression) = \(calculation.result)"
        case .definition(let definition): "\(definition.word) — \(definition.summary)"
        case .contact(let contact): contact.name
        case .contactAction(let action): action.title
        case .event(let event): event.title.isEmpty ? String(localized: "Event") : event.title
        case .bookmark(let bookmark): bookmark.title
        case .permission(let permission): permission.title
        case .openURL(let url): String(localized: "Open \(AssistantURL.display(url))")
        case .askIntelligence: String(localized: "Use Siri AI")
        case .searchWeb: String(localized: "Search the Web")
        case .askChatGPT: String(localized: "Ask ChatGPT")
        }
    }
}

extension RowView {
    /// "Today 14:30", "Tomorrow", "Fri 9:00": when an event starts.
    static func when(_ event: CalendarEvent, now: Date = Date()) -> String {
        let calendar = Calendar.current
        let time = event.isAllDay ? String(localized: "All Day") : event.start.formatted(date: .omitted, time: .shortened)
        if event.start <= now, event.end > now { return String(localized: "Now") }
        if calendar.isDateInToday(event.start) { return event.isAllDay ? String(localized: "Today") : String(localized: "Today \(time)") }
        if calendar.isDateInTomorrow(event.start) { return event.isAllDay ? String(localized: "Tomorrow") : String(localized: "Tomorrow \(time)") }
        let day = event.start.formatted(.dateTime.weekday(.abbreviated).day())
        return event.isAllDay ? day : "\(day) \(time)"
    }
}

/// An answer as it streams in — Apple Intelligence's text, or Siri AI's answer as Siri lays it
/// out (`SiriAnswerView`) — with Copy and the next step as icons under it. As tall as it is
/// (measured, `AssistantModel.answerHeight`), up to the island's most; past that it scrolls. Plain
/// text on purpose: a selectable text would take the keyboard when clicked, and Esc and typing
/// would stop working.
private struct AnswerPane: View {
    let answer: AssistantAnswer

    @Environment(AppModel.self) private var model

    var body: some View {
        let assistant = model.assistant
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(answer.question)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let failure = answer.failure {
                    Text(failure)
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                } else if answer.fromSiri {
                    SiriAnswerView(reply: answer.siri, isResponding: answer.isResponding)
                } else {
                    Text(answer.text)
                        .font(.system(size: 15))
                        .lineSpacing(2.5)
                        .contentTransition(.opacity)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !answer.isResponding {
                    actions(assistant)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { assistant.setAnswerHeight($0) }
        }
        .scrollIndicators(.never)
        // Shorter than its room: nothing to scroll, so no rubber-band either.
        .scrollBounceBehavior(.basedOnSize)
        // From its start, also while it grows (it opened at its end, the question out of sight).
        .defaultScrollAnchor(.top)
        .defaultScrollAnchor(.top, for: .sizeChanges)
    }

    private func actions(_ assistant: AssistantModel) -> some View {
        HStack(spacing: Metrics.Spacing.small) {
            Spacer(minLength: 0)
            Button {
                assistant.copyAnswer()
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .help("Copy")
            .disabled(answer.text.isEmpty)
            if answer.fromSiri {
                Button {
                    assistant.showInSiri()
                } label: {
                    Label("Show in Siri AI", systemImage: "arrow.up.forward.app")
                }
                .help("Show in Siri AI")
            } else if let word = answer.definedWord {
                // A dictionary's entry: the whole of it in Dictionary.
                Button {
                    assistant.openInDictionary(word)
                } label: {
                    Label("Open in Dictionary", systemImage: "character.book.closed")
                }
                .help("Open in Dictionary")
            } else {
                Button {
                    assistant.perform(.askChatGPT)
                } label: {
                    Label("Ask ChatGPT", systemImage: "bubble.left.and.text.bubble.right")
                }
                .help("Ask ChatGPT")
            }
        }
        .islandButton(.circle)
        .controlSize(.small)
    }
}

/// Siri's view built and drawn once, unseen, a while after launch (`AppModel`, after the model's
/// own `prewarm`): what its first opening did for the first time — loading and instantiating the
/// view's types, the text field and its input context, the fonts and symbols it draws — is done
/// ahead, on the efficiency cores, in a window that is never shown. The first opening cost about
/// seven times a later one (Energy Impact ~90 against ~12, measured).
@MainActor enum AssistantRehearsal {
    static func run(model: AppModel) {
        let size = model.layout.size(for: .assistant(.list))
        guard size.width > 0, size.height > 0 else { return }
        MainThrift.lowPower(for: 0.5, unattended: true)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        let host = NSHostingView(rootView: AssistantView()
            .environment(model)
            .environment(\.colorScheme, .dark)
            .environment(\.appearsActive, true)
            .frame(width: size.width, height: size.height, alignment: .top))
        host.sizingOptions = []
        host.frame = CGRect(origin: .zero, size: size)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        host.display()
        // Gone a turn later, with what it built.
        DispatchQueue.main.async {
            window.contentView = nil
            window.close()
        }
    }
}
