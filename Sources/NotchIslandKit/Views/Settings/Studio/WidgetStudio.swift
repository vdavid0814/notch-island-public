import AppKit
import Observation
import SwiftUI

/// Settings ▸ Widgets' shared state: what the stage edits.
@Observable final class WidgetStudio {
    enum Mode: Hashable, CaseIterable, Identifiable {
        var id: Self { self }

        var title: String {
            switch self {
            case .widgets: String(localized: "Widgets")
            case .topBar: String(localized: "Top Bar")
            case .size: String(localized: "Size")
            }
        }

        /// The board: widgets moved, resized, picked.
        case widgets
        /// The panel's header items.
        case topBar
        /// The panel's size and its grid.
        case size
    }

    var mode: Mode = .widgets
    /// The widget open in Customize, over all of Settings (`WidgetCustomizeView`); nil: none.
    var customizing: WidgetID?
    /// The page whose board the stage shows and edits (`AppModel.editedWidgets`).
    var page: ExpandedPage = .home
    /// The panel as an edge or a slider dragged in Size mode makes it, until the drag ends and it
    /// is stored: the stage draws it, the real panel is not staged again at every step.
    var draft: StudioDraft?
    /// The top bar's item picked in Top Bar mode.
    var headerSelection: HeaderItem?

    /// The mode picked and on its way in (`switchMode`): the picker shows it at once.
    var pendingMode: Mode?
    /// The Widgets page's content under the stage: faded out while the mode switches.
    var contentOpacity: Double = 1
    @ObservationIgnored private var switching: Task<Void, Never>?

    /// To another mode, without a stutter. Building a mode's page and laying Settings out again
    /// takes one frame of ~100 ms whatever is done (measured: ~35 ms the page under the stage, the
    /// rest the stage and the scroll view); a spring over it ran at 30 fps after that frame. So the
    /// picker moves at once, the content fades out, the switch lands while nothing moves (the long
    /// frame is not seen), and the new content fades in: opacity only, no layout, every frame cheap.
    @MainActor func switchMode(to target: Mode) {
        guard target != (pendingMode ?? mode) else { return }
        switching?.cancel()
        guard target != mode else {
            // Back to the mode still shown, before it went.
            pendingMode = nil
            withAnimation(.easeOut(duration: Self.fadeIn)) { contentOpacity = 1 }
            return
        }
        pendingMode = target
        withAnimation(.easeIn(duration: Self.fadeOut)) { contentOpacity = 0 }
        switching = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.fadeOut))
            guard let self, !Task.isCancelled else { return }
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) {
                self.mode = target
                self.pendingMode = nil
            }
            // After the long frame: a fade started before it would be half over when it ends.
            try? await Task.sleep(for: .milliseconds(30))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: Self.fadeIn)) { self.contentOpacity = 1 }
        }
    }

    private static let fadeOut: TimeInterval = 0.12
    private static let fadeIn: TimeInterval = 0.2
}
