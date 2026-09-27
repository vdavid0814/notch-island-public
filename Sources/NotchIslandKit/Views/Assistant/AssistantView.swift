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
        let fullRoom: AssistantRoom = assistant.room == .gallery ? .gallery : .list
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
/// pointer's never does, see `AssistantModel.selectionFollowsPointer`).
private struct RowsList: View {
    let assistant: AssistantModel
    @State private var pointer = PointerTracker()

    var body: some View {
        let rows = assistant.rows
        let count = rows.count
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: IslandLayout.assistantRowSpacing) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        RowView(row: row, isSelected: index == assistant.selection)
                            .id(row.id)
                            .contentShape(.rect)
                            .onTapGesture { assistant.perform(row) }
                    }
                }
            }
            .scrollIndicators(.never)
            // Fewer rows than fit: nothing to scroll, so no rubber-band either.
            .scrollBounceBehavior(.basedOnSize)
            .pointerPicks(pointer, assistant: assistant) { point in
                AssistantHitTest.row(atY: point.y, height: IslandLayout.assistantRowHeight,
                                     spacing: IslandLayout.assistantRowSpacing, count: count)
            }
            .onChange(of: assistant.selection) { _, selection in
                // Only a selection the keys moved: one the pointer hovered is already in view.
                guard !assistant.selectionFollowsPointer, rows.indices.contains(selection) else { return }
                proxy.scrollTo(rows[selection].id)
            }
        }
    }
}

/// Every app as an icon with its name, most recently used first, like the system's Applications
/// view; the field filters it.
private struct AppGallery: View {
    let assistant: AssistantModel
    @State private var pointer = PointerTracker()

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
                            GalleryCell(hit: hit, isSelected: index == assistant.selection)
                                .id(row.id)
                                .contentShape(.rect)
                                .onTapGesture { assistant.perform(row) }
                        }
                    }
                }
            }
            .scrollIndicators(.never)
            // Fewer rows than fit: nothing to scroll, so no rubber-band either.
            .scrollBounceBehavior(.basedOnSize)
            .pointerPicks(pointer, assistant: assistant) { [pointer] point in
                AssistantHitTest.cell(at: point, width: pointer.contentWidth, columns: columnCount,
                                      height: IslandLayout.galleryCellHeight,
                                      spacing: IslandLayout.galleryRowSpacing, count: count)
            }
            .onChange(of: assistant.selection) { _, selection in
                // Only a selection the keys moved: one the pointer hovered is already in view.
                guard !assistant.selectionFollowsPointer, rows.indices.contains(selection) else { return }
                proxy.scrollTo(rows[selection].id)
            }
        }
    }
}

/// Where the pointer is over a list or the gallery, kept outside SwiftUI's state: it changes with
/// every move, and nothing is drawn from it (only the selection it picks is).
private final class PointerTracker {
    /// In the scroll view's own coordinates; nil while the pointer is elsewhere.
    var location: CGPoint?
    var contentOffset: CGPoint = .zero
    var contentWidth: CGFloat = 0
}

private extension View {
    /// The row or app under the pointer is selected at every move, worked out from the pointer's
    /// place in the content rather than from each row's own hover (which fired only on entering a
    /// row: none in the gaps between rows, none for a row scrolled under a resting pointer, none
    /// when the pointer moved inside the row the keys had just left). A scroll re-picks too, but
    /// only while the pointer leads the selection, so ↑/↓ scrolling the list never takes it back.
    func pointerPicks(_ tracker: PointerTracker, assistant: AssistantModel,
                      index: @escaping (CGPoint) -> Int?) -> some View {
        let pick = {
            guard let location = tracker.location,
                  let picked = index(CGPoint(x: location.x + tracker.contentOffset.x,
                                             y: location.y + tracker.contentOffset.y)) else { return }
            assistant.select(at: picked)
        }
        return onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let location):
                tracker.location = location
                pick()
            case .ended:
                tracker.location = nil
            }
        }
        .onScrollGeometryChange(for: ScrollGeometry.self, of: { $0 }) { _, geometry in
            tracker.contentOffset = geometry.contentOffset
            tracker.contentWidth = geometry.contentSize.width
            if assistant.selectionFollowsPointer { pick() }
        }
    }
}

/// Which row or app is at a point of the content: rows and cells are laid out at a fixed pitch, and
/// the gap between two belongs half to each, so the pointer is over one wherever it is.
nonisolated enum AssistantHitTest {
    /// A row of a list `height` tall and `spacing` apart, or nil past the last one.
    static func row(atY y: CGFloat, height: CGFloat, spacing: CGFloat, count: Int) -> Int? {
        guard y >= 0 else { return nil }
        let index = Int(((y + spacing / 2) / (height + spacing)).rounded(.down))
        return index < count ? index : nil
    }

    /// A cell of a grid `columns` wide filling `width`, cells `height` tall and `spacing` apart both
    /// ways; nil past the last cell (the last row's empty places included).
    static func cell(at point: CGPoint, width: CGFloat, columns: Int, height: CGFloat, spacing: CGFloat,
                     count: Int) -> Int? {
        guard columns > 0, width > 0, point.x >= 0, point.x < width,
              let row = row(atY: point.y, height: height, spacing: spacing, count: Int.max) else { return nil }
        let cellWidth = (width - CGFloat(columns - 1) * spacing) / CGFloat(columns)
        let column = min(Int(((point.x + spacing / 2) / (cellWidth + spacing)).rounded(.down)), columns - 1)
        let index = row * columns + column
        return index < count ? index : nil
    }
}

private struct GalleryCell: View {
    let hit: AssistantHit
    let isSelected: Bool

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
        .background { SelectionPlate(isSelected: isSelected, cornerRadius: 12) }
    }
}

/// The selected row or app, as the system's Search window marks it: a faint light plate, no
/// colour. It follows the pointer closely: it comes in at once and the one it leaves fades in a
/// tenth of a second (a quarter of a second left a trail of two or three plates behind a moving
/// pointer, and the plate seemed to lag it); only the plate animates, never the row.
///
/// Its corners are concentric with the island's: a row or app next to the island's bottom corners
/// rounds its own bottom corners with them, everywhere else `cornerRadius`.
private struct SelectionPlate: View {
    let isSelected: Bool
    let cornerRadius: CGFloat

    static let opacity: Double = 0.1
    static let appear: Animation = .easeOut(duration: 0.05)
    static let disappear: Animation = .easeOut(duration: 0.1)

    var body: some View {
        ConcentricRectangle(corners: .concentric(minimum: .fixed(cornerRadius)), isUniform: false)
            .fill(Color.white.opacity(isSelected ? Self.opacity : 0))
            .animation(isSelected ? Self.appear : Self.disappear, value: isSelected)
    }
}

/// An icon and a name, nothing else (a suggestion also shows its shortcut, as the system does).
private struct RowView: View {
    let row: AssistantRow
    let isSelected: Bool

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
        .background { SelectionPlate(isSelected: isSelected, cornerRadius: 10) }
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
