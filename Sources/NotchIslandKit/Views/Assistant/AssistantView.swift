import SwiftUI

/// Siri in the notch, as spare as the system's Search window: the Siri orb in the header band and
/// the field; under it (when the island makes room, see `AssistantRoom`) the suggestions
/// (Applications ⌘1, Files ⌘2, Actions ⌘3), the app gallery, the hits and actions for the query, or
/// Apple Intelligence's answer.
///
/// The view is always laid out at the list's full height and the island's outline clips it, so
/// growing from the field to the list uncovers the rows instead of squeezing them.
///
/// Keys: typing goes to the field; ↑/↓ move the selection (←/→ too in the gallery), Return runs
/// it, ⌘Return asks Apple Intelligence, ⌘1–⌘3 open a suggestion, Delete in an empty field leaves
/// it, Esc steps back (answer → empty field → suggestions → closed). The whole view keeps one
/// identity while it is open (`surfaceKey` "assistant"): a new one would recreate the field and
/// drop its keyboard focus.
struct AssistantView: View {
    @Environment(AppModel.self) private var model
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        let layout = model.layout
        let assistant = model.assistant
        // Laid out at the largest size of the current kind: the list, or the gallery's window.
        let fullRoom: AssistantRoom = assistant.room.isGallery ? .gallery : .list
        let split = NotchSplit(
            layout: layout,
            presentation: .assistant(fullRoom),
            outerInset: Metrics.Expanded.horizontalInset,
            clearance: Metrics.notchClearance
        )
        let fullHeight = layout.size(for: .assistant(fullRoom)).height
        let isGallery = assistant.category == .applications && assistant.answer == nil
        // The gallery's grid is always as wide as in the gallery's window, also while the island
        // shrinks back to the list around it (it would reflow into the narrower width meanwhile).
        let galleryWidth = layout.size(for: .assistant(.gallery)).width - 2 * NotchSplit(
            layout: layout, presentation: .assistant(.gallery),
            outerInset: Metrics.Expanded.horizontalInset, clearance: Metrics.notchClearance
        ).contentInset
        let below: BelowField = assistant.answer != nil ? .answer : isGallery ? .gallery : .rows
        // Below the field nothing shows while the island is only the field (the rows would peek
        // out under it); they fade in with the island's growth.
        let showsBelowField: Bool = if case .assistant(.field) = model.island.presentation { false } else { true }
        VStack(spacing: 0) {
            NotchSplitBand(split: split, height: layout.notch.height) {
                Image(systemName: "siri")
                    .foregroundStyle(AssistantGlow.gradient)
                    .imageScale(.large)
                    .accessibilityLabel("Siri")
            } trailing: {
                EmptyView()
            }

            VStack(spacing: IslandLayout.assistantTopInset) {
                field(assistant)
                Group {
                    if let answer = assistant.answer {
                        AnswerPane(answer: answer)
                    } else if isGallery {
                        AppGallery(assistant: assistant)
                            .frame(width: galleryWidth)
                    } else {
                        RowsList(assistant: assistant)
                    }
                }
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
            guard isGallery else { return .ignored }
            assistant.moveSelection(by: -1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            guard isGallery else { return .ignored }
            assistant.moveSelection(by: 1)
            return .handled
        }
        .onKeyPress(.return, phases: .down) { press in
            // Plain Return is left to the field (IME commit, then onSubmit).
            guard press.modifiers.contains(.command) else { return .ignored }
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
            return assistant.copySelectedClip() ? .handled : .ignored
        }
        .onKeyPress(.delete) {
            assistant.deleteBackwardInEmptyField() ? .handled : .ignored
        }
        .onExitCommand { assistant.escape() }
        // Focus is asked for once the panel is key (the field editor does not take first responder
        // in a window that is not key yet), a turn later, and again whenever the panel becomes key.
        .onAppear { focusField() }
        // Its lists, icons and the answer pane go with it: give their memory back.
        .onDisappear { MemoryRelief.afterLargeSurfaceClosed() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
            guard note.object is IslandPanel else { return }
            focusField()
        }
    }

    /// What shows under the field.
    private enum BelowField { case rows, gallery, answer }

    /// The swap under the field: as short as the content's swap while the island moves.
    static let swap: Animation = .easeOut(duration: 0.18)

    private func focusField() {
        isFieldFocused = false
        Task { @MainActor in
            await Task.yield()
            isFieldFocused = true
        }
    }

    private func field(_ assistant: AssistantModel) -> some View {
        @Bindable var assistant = assistant
        let isResponding = assistant.answer?.isResponding == true
        return HStack(spacing: Metrics.Spacing.medium) {
            Group {
                if let category = assistant.category {
                    category.tile
                } else {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
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
        }
    }

    /// ⌘1–⌘4.
    var key: KeyEquivalent { KeyEquivalent(Character(String(rawValue))) }

    var tile: some View {
        switch self {
        case .applications: AssistantTile(symbol: "square.grid.2x2.fill", color: .blue)
        case .files: AssistantTile(symbol: "folder.fill", color: .cyan)
        case .actions: AssistantTile(symbol: "bolt.fill", color: .orange)
        case .clipboard: AssistantTile(symbol: "list.clipboard.fill", color: .gray)
        }
    }
}

/// A symbol on a small coloured tile, the size of an app icon in the list.
struct AssistantTile: View {
    let symbol: String
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(color.gradient)
            .frame(width: 22, height: 22)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
            }
    }
}

/// The suggestions, hits and actions; the selected row is tinted, ↑/↓ scroll it into view (the
/// pointer does not move the selection: it only clicks (reported: following it felt slow, v0.4.5).
private struct RowsList: View {
    let assistant: AssistantModel

    var body: some View {
        let rows = assistant.rows
        let count = rows.count
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: IslandLayout.assistantRowSpacing) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        RowView(row: row, isMarked: assistant.marksSelection && index == assistant.selection)
                            .id(row.id)
                            .contentShape(.rect)
                            .onTapGesture { assistant.perform(row) }
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

/// Every app as an icon with its name, most recently used first, like the system's Applications
/// view; the field filters it.
private struct AppGallery: View {
    let assistant: AssistantModel

    var body: some View {
        // The user's column count (Settings ▸ Siri ▸ App Gallery); the window widens with it.
        let columnCount = assistant.galleryColumns
        let columns = Array(repeating: GridItem(.flexible(), spacing: IslandLayout.galleryRowSpacing),
                            count: columnCount)
        let rows = assistant.rows
        let count = rows.count
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, spacing: IslandLayout.galleryRowSpacing) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        if case .hit(let hit) = row {
                            GalleryCell(hit: hit, isMarked: assistant.marksSelection && index == assistant.selection)
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

    static let iconSize: CGFloat = AssistantIcons.galleryIconSize
    @State private var icon: NSImage?

    var body: some View {
        VStack(spacing: Metrics.Spacing.xSmall) {
            Group {
                if let icon = icon ?? AssistantIcons.cachedThumbnail(for: hit) {
                    Image(nsImage: icon)
                } else {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(.white.opacity(0.08))
                        .padding(4)
                }
            }
            .frame(width: Self.iconSize, height: Self.iconSize)
            .task(id: hit.url) {
                guard AssistantIcons.cachedThumbnail(for: hit) == nil else { return }
                icon = await AssistantIcons.thumbnail(for: hit, points: Self.iconSize)
            }
            Text(hit.name)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, Metrics.Spacing.xxSmall)
        // Exactly the height `IslandLayout` sizes the gallery by, so N rows fill it.
        .frame(maxWidth: .infinity, minHeight: IslandLayout.galleryCellHeight, maxHeight: IslandLayout.galleryCellHeight)
        .background { SelectionPlate(isShown: isMarked) }
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
private struct SelectionPlate: View {
    let isShown: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.islandAccent.opacity(0.16))
            .opacity(isShown ? 1 : 0)
            .animation(.easeOut(duration: 0.12), value: isShown)
    }
}

/// An icon and a name, nothing else (a suggestion also shows its shortcut, as the system does).
private struct RowView: View {
    let row: AssistantRow
    /// The keys moved the selection here (`AssistantModel.marksSelection`).
    var isMarked = false

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
        }
        .padding(.horizontal, Metrics.Spacing.large)
        .frame(height: IslandLayout.assistantRowHeight)
        .background { SelectionPlate(isShown: isMarked) }
    }

    @ViewBuilder private var icon: some View {
        switch row {
        case .category(let category):
            category.tile
        case .hit(let hit):
            Image(nsImage: AssistantIcons.icon(for: hit))
                .resizable()
                .aspectRatio(contentMode: .fit)
        case .action(.island(let action)):
            AssistantTile(symbol: action.symbol, color: .gray)
        case .action(.shortcut):
            Image(nsImage: AssistantIcons.shortcuts)
                .resizable()
                .aspectRatio(contentMode: .fit)
        case .clip:
            Image(systemName: "doc.plaintext").foregroundStyle(.secondary).imageScale(.large)
        case .calculation:
            AssistantTile(symbol: "equal", color: .orange)
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

    private var title: String {
        switch row {
        case .category(let category): category.title
        case .hit(let hit): hit.name
        case .action(let action): action.title
        case .clip(let item): item.preview
        case .calculation(let calculation): "\(calculation.expression) = \(calculation.result)"
        case .openURL(let url): String(localized: "Open \(AssistantURL.display(url))")
        case .askIntelligence: String(localized: "Ask Apple Intelligence")
        case .searchWeb: String(localized: "Search the Web")
        case .askChatGPT: String(localized: "Ask ChatGPT")
        }
    }
}

/// Apple Intelligence's answer as it streams in, with Copy and ChatGPT as icons. Plain text on
/// purpose: a selectable text would take the keyboard when clicked, and Esc and typing would stop
/// working.
private struct AnswerPane: View {
    let answer: AssistantAnswer

    @Environment(AppModel.self) private var model

    var body: some View {
        let assistant = model.assistant
        VStack(alignment: .leading, spacing: Metrics.Spacing.medium) {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.Spacing.small) {
                    Text(answer.question)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(answer.failure ?? answer.text)
                        .foregroundStyle(answer.failure == nil ? .primary : .secondary)
                        .contentTransition(.opacity)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.never)
            // Fewer rows than fit: nothing to scroll, so no rubber-band either.
            .scrollBounceBehavior(.basedOnSize)
            if !answer.isResponding {
                HStack(spacing: Metrics.Spacing.small) {
                    Spacer(minLength: 0)
                    Button {
                        assistant.copyAnswer()
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .help("Copy")
                    .disabled(answer.text.isEmpty)
                    Button {
                        assistant.perform(.askChatGPT)
                    } label: {
                        Label("Ask ChatGPT", systemImage: "bubble.left.and.text.bubble.right")
                    }
                    .help("Ask ChatGPT")
                }
                .islandButton(.circle)
                .controlSize(.small)
            }
        }
    }
}
