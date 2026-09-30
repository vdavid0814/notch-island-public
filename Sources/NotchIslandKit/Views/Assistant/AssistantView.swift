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

    var body: some View {
        let layout = model.layout
        let assistant = model.assistant
        // Its room's kind (`AssistantModel.room`) without reading the room: that reads the rows, and
        // every keystroke and landing search would build this whole view again, not only the list.
        let isGallery = assistant.category == .applications && assistant.answer == nil
        // Laid out at the largest size of the current kind: the list, or the gallery's window.
        let fullRoom: AssistantRoom = isGallery ? .gallery : .list
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
                        AppGallery(assistant: assistant, plateRadius: layout.assistantGalleryPlateRadius)
                            .frame(width: galleryWidth)
                    } else {
                        RowsList(assistant: assistant,
                                 extraInset: layout.assistantRowInset - Metrics.Expanded.horizontalInset)
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
        case .system: String(localized: "System")
        case .windows: String(localized: "Windows")
        case .emoji: String(localized: "Emoji")
        case .people: String(localized: "People & Calendar")
        }
    }

    /// ⌘1–⌘8.
    var key: KeyEquivalent { KeyEquivalent(Character(String(rawValue))) }

    var tile: some View {
        switch self {
        case .applications: AssistantTile(symbol: "square.grid.2x2.fill", color: .blue)
        case .files: AssistantTile(symbol: "folder.fill", color: .cyan)
        case .actions: AssistantTile(symbol: "bolt.fill", color: .orange)
        case .clipboard: AssistantTile(symbol: "list.clipboard.fill", color: .gray)
        case .system: AssistantTile(symbol: "switch.2", color: .indigo)
        case .windows: AssistantTile(symbol: "macwindow.on.rectangle", color: .purple)
        case .emoji: AssistantTile(symbol: "face.smiling.inverse", color: .yellow)
        case .people: AssistantTile(symbol: "person.2.fill", color: .green)
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
    /// The rows further in than the field, so their capsules are concentric with the panel's
    /// corners (`IslandLayout.assistantRowInset`).
    let extraInset: CGFloat

    var body: some View {
        let rows = assistant.rows
        let count = rows.count
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: IslandLayout.assistantRowSpacing) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        RowView(row: row, isMarked: assistant.marksSelection && index == assistant.selection,
                                state: Self.state(of: row, in: assistant), isConfirming: assistant.confirming == row.id,
                                leadingInset: max(Metrics.Spacing.small, Metrics.Spacing.large - extraInset))
                            .id(row.id)
                            .contentShape(.rect)
                            .onTapGesture { assistant.perform(row) }
                    }
                }
                .padding(.horizontal, extraInset)
                .background { SelectionScroller(assistant: assistant, count: count) { proxy.scrollTo(rows[$0].id) } }
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
                                        plateRadius: plateRadius)
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

    static let iconSize: CGFloat = AssistantIcons.galleryIconSize
    @State private var icon: NSImage?

    var body: some View {
        VStack(spacing: Metrics.Spacing.xSmall) {
            Group {
                if let icon = icon ?? AssistantIcons.cachedThumbnail(for: hit) {
                    Image(nsImage: icon)
                } else {
                    // Only a cell without its icon yet asks for it: a gallery of kept icons starts
                    // no task per cell.
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(.white.opacity(0.08))
                        .padding(4)
                        .task(id: hit.url) {
                            icon = await AssistantIcons.thumbnail(for: hit, points: Self.iconSize)
                        }
                }
            }
            .frame(width: Self.iconSize, height: Self.iconSize)
            Text(hit.name)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, Metrics.Spacing.xxSmall)
        // Exactly the height `IslandLayout` sizes the gallery by, so N rows fill it.
        .frame(maxWidth: .infinity, minHeight: IslandLayout.galleryCellHeight, maxHeight: IslandLayout.galleryCellHeight)
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
        case .askIntelligence: String(localized: "Ask Apple Intelligence")
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
                    if let word = answer.definedWord {
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
    }
}
