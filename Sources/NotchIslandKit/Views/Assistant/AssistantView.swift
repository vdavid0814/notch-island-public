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
        let split = NotchSplit(
            layout: layout,
            presentation: .assistant(.list),
            outerInset: Metrics.Expanded.horizontalInset,
            clearance: Metrics.notchClearance
        )
        let fullHeight = layout.size(for: .assistant(.list)).height
        let isGallery = assistant.category == .applications && assistant.answer == nil
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
                    } else {
                        RowsList(assistant: assistant)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .opacity(showsBelowField ? 1 : 0)
            }
            .padding(.top, IslandLayout.assistantTopInset)
            .padding(.bottom, Metrics.Expanded.pageBottomInset)
            .padding(.horizontal, split.contentInset)
        }
        .frame(height: fullHeight, alignment: .top)
        .onKeyPress(.upArrow) {
            assistant.moveSelection(by: isGallery ? -AssistantModel.galleryColumns : -1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            assistant.moveSelection(by: isGallery ? AssistantModel.galleryColumns : 1)
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
        .onKeyPress(.delete) {
            assistant.deleteBackwardInEmptyField() ? .handled : .ignored
        }
        .onExitCommand { assistant.escape() }
        // Focus is asked for once the panel is key (the field editor does not take first responder
        // in a window that is not key yet), a turn later, and again whenever the panel becomes key.
        .onAppear { focusField() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
            guard note.object is IslandPanel else { return }
            focusField()
        }
    }

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
            if let category = assistant.category {
                category.tile
            } else {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
            }
            TextField(assistant.category?.title ?? String(localized: "Search or Ask"), text: $assistant.query)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($isFieldFocused)
                .onSubmit { assistant.activateSelection() }
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
        }
    }

    /// ⌘1, ⌘2, ⌘3.
    var key: KeyEquivalent { KeyEquivalent(Character(String(rawValue))) }

    var tile: some View {
        switch self {
        case .applications: AssistantTile(symbol: "square.grid.2x2.fill", color: .blue)
        case .files: AssistantTile(symbol: "folder.fill", color: .cyan)
        case .actions: AssistantTile(symbol: "bolt.fill", color: .orange)
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

/// The suggestions, hits and actions; the selected row is tinted, ↑/↓ scroll it into view.
private struct RowsList: View {
    let assistant: AssistantModel

    var body: some View {
        let rows = assistant.rows
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: IslandLayout.assistantRowSpacing) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        RowView(row: row, isSelected: index == assistant.selection)
                            .id(row.id)
                            .contentShape(.rect)
                            .onTapGesture { assistant.perform(row) }
                            .onHover { inside in if inside { assistant.select(row) } }
                    }
                }
            }
            .scrollIndicators(.never)
            .onChange(of: assistant.selection) { _, selection in
                guard rows.indices.contains(selection) else { return }
                proxy.scrollTo(rows[selection].id)
            }
        }
    }
}

/// Every app as an icon with its name, most recently used first, like the system's Applications
/// view; the field filters it.
private struct AppGallery: View {
    let assistant: AssistantModel

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: Metrics.Spacing.xSmall),
        count: AssistantModel.galleryColumns
    )

    var body: some View {
        let rows = assistant.rows
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, spacing: Metrics.Spacing.xSmall) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        if case .hit(let hit) = row {
                            GalleryCell(hit: hit, isSelected: index == assistant.selection)
                                .id(row.id)
                                .contentShape(.rect)
                                .onTapGesture { assistant.perform(row) }
                                .onHover { inside in if inside { assistant.select(row) } }
                        }
                    }
                }
            }
            .scrollIndicators(.never)
            .onChange(of: assistant.selection) { _, selection in
                guard rows.indices.contains(selection) else { return }
                proxy.scrollTo(rows[selection].id)
            }
        }
    }
}

private struct GalleryCell: View {
    let hit: AssistantHit
    let isSelected: Bool

    var body: some View {
        VStack(spacing: Metrics.Spacing.xSmall) {
            Image(nsImage: AssistantIcons.icon(for: hit))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 44, height: 44)
            Text(hit.name)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.vertical, Metrics.Spacing.small)
        .padding(.horizontal, Metrics.Spacing.xxSmall)
        .frame(maxWidth: .infinity)
        .background(isSelected ? Color.accentColor.opacity(0.35) : .clear, in: .rect(cornerRadius: 12, style: .continuous))
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
            if case .category(let category) = row {
                Text(verbatim: "⌘\(category.rawValue)")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, Metrics.Spacing.large)
        .frame(height: IslandLayout.assistantRowHeight)
        .background(isSelected ? Color.accentColor.opacity(0.35) : .clear, in: .rect(cornerRadius: 10, style: .continuous))
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
                .buttonStyle(.islandGlass(.circle))
                .controlSize(.small)
            }
        }
    }
}
