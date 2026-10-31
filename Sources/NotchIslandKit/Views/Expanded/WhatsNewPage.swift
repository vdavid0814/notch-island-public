import SwiftUI

/// What the version that runs brought (`ReleaseNotes.current`), in the notch after an update, as high
/// as its rows want (`IslandLayout.size(for:)`), on the island's own surface, in the look of How
/// NotchIsland Works (`InfoPageShell`): by topic as a release's notes are, full rows of three cards.
/// Opened from Settings (`AppModel.openWhatsNewFromSettings`), two fingers lead back there.
/// Written with the `whats-new` skill at each release. Kept open until Done (or a click elsewhere).
struct WhatsNewPage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.isIslandPanelHidden) private var isPanelHidden
    /// From Settings the cards come in as How NotchIsland Works's do (`AppInfoMenu`).
    @State private var contentIn = true
    @State private var swipe = AssistantSwipe()

    private var isFromSettings: Bool { model.settingsInfo == .whatsNew }

    var body: some View {
        WhatsNewContent(solidGround: false) { model.controller.collapse() }
            .opacity(contentIn ? 1 : 0)
            .offset(y: contentIn ? 0 : -10)
            .onChange(of: isFromSettings, initial: true) { _, fromSettings in
                // Two fingers go back to Settings and forward again only if it came from there.
                if fromSettings {
                    swipe.start { [weak model] back in model?.swipeSettings(back: back) }
                    contentIn = false
                    withAnimation(.spring(duration: 0.45, bounce: 0.1).delay(0.1)) { contentIn = true }
                } else {
                    swipe.stop()
                    contentIn = true
                }
            }
            .onChange(of: isPanelHidden) { _, hidden in
                // Closed: whatever comes next is no longer a step from Settings.
                if hidden, isFromSettings { model.settingsHistory.withoutRecording { model.settingsInfo = nil } }
                if !hidden { model.whatsNewSection = ReleaseNotes.current.sections.first ?? .new }
            }
            .onDisappear { swipe.stop() }
    }
}

/// The topics and their cards.
struct WhatsNewContent: View {
    var solidGround = true
    let close: () -> Void

    @Environment(AppModel.self) private var model

    var body: some View {
        let notes = ReleaseNotes.current
        InfoPageShell(topics: notes.sections, title: \.title, label: "What's new in NotchIsland \(notes.version)",
                      solidGround: solidGround, scrolls: false, picked: { section in
            // The window unfolds and folds to the topic's rows, as Widgets' stage does for Size.
            withAnimation(.spring(StudioStageSpring.unfold)) { model.whatsNewSection = section }
        }, close: close) { section in
            Topic(notes: notes, section: section)
        }
    }
}

/// A topic's rows, all as high: every tab looks the same, whatever its cards say.
private struct Topic: View {
    let notes: ReleaseNotes
    let section: ReleaseNotes.Section

    var body: some View {
        let stats = section == .performance ? notes.stats : []
        VStack(spacing: InfoRow<EmptyView>.spacing) {
            if !stats.isEmpty {
                InfoRow {
                    ForEach(stats) { stat in
                        InfoStat(title: stat.title, symbol: stat.symbol, tint: stat.tint, value: stat.value, detail: stat.detail)
                            .infoColumns()
                    }
                }
            }
            InfoCardGrid(cards: notes.items(section), columns: notes.columns(section))
        }
        .environment(\.infoRowHeight, ReleaseNotes.rowHeight)
        // From the same top on every tab.
        .frame(height: ReleaseNotes.cardsHeight(rows: notes.rows(section)), alignment: .top)
    }
}
