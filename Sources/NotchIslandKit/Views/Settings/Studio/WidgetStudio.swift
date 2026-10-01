import AppKit
import Observation
import SwiftUI

/// Settings ▸ Widgets' shared state: what the stage edits, and the one widget open in Customize.
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

    /// Where Customize is: the widget flying into the editor, the editor shown, flying back.
    enum Phase: Hashable {
        case idle, opening, open, closing
    }

    var mode: Mode = .widgets
    /// The page whose board the stage shows and edits (`AppModel.editedWidgets`).
    var page: ExpandedPage = .home
    /// The open Customize editor's session (for `demo/select`).
    @ObservationIgnored weak var session: EditorSession?
    /// The widget whose Customize editor is open or on its way (nil: the stage).
    var customizing: WidgetID?
    var phase: Phase = .idle
    /// The panel as an edge or a slider dragged in Size mode makes it, until the drag ends and it
    /// is stored: the stage draws it, the real panel is not staged again at every step.
    var draft: StudioDraft?
    /// The top bar's item picked in Top Bar mode.
    var headerSelection: HeaderItem?
    /// Raised to have the Widgets page scroll its stage into view (a widget about to fly from it).
    var stageScrollRequest = 0

    /// The mode picked and on its way in (`switchMode`): the picker shows it at once.
    var pendingMode: Mode?
    /// The Widgets page's content under the stage: faded out while the mode switches.
    var contentOpacity: Double = 1
    @ObservationIgnored private var switching: Task<Void, Never>?

    /// Frames and views for the transition, written from layout callbacks.
    @ObservationIgnored let probe = StudioProbe()

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

/// Where the transition flies from, and who flies it. Plain storage, not observed: writing it must
/// never re-render anything.
final class StudioProbe {
    /// The stage's board: where each widget is drawn on it (`sourceFrame`).
    var boardGeometry: WidgetBoardGeometry?
    /// A view laid over the stage's board, top-left origin: the board's space in AppKit.
    weak var stageView: NSView?
    /// A view filling the stage's room, and the scale the stage shows the room at about its top
    /// centre (an island wider than the stage is shown smaller): AppKit knows nothing of it.
    weak var roomView: NSView?
    var roomScale: CGFloat = 1
    /// nil (nothing happens) until the Settings surface installs its coordinator.
    weak var driver: (any CustomizeDriving)?
    /// Called once, by the stage (the canvas), as it takes a change of `phase` in: the widget it
    /// hides or shows with it and what is done here reach the screen in one frame, so the flier
    /// and the widget it stands for are never both seen, nor neither.
    var stageReport: (() -> Void)?
    var canvasReport: (() -> Void)?

    /// A widget's frame on the stage, in `stageView`.
    func sourceFrame(_ frame: GridRect) -> CGRect? { boardGeometry?.frame(for: frame) }
}

/// Tells the transition that the stage or the canvas has taken the studio's phase in: its
/// `updateNSView` runs in the update that hides or shows the widget there.
struct StudioPhaseReporter: NSViewRepresentable {
    let probe: StudioProbe
    let phase: WidgetStudio.Phase
    let report: ReferenceWritableKeyPath<StudioProbe, (() -> Void)?>

    func makeNSView(context: Context) -> NSView {
        context.coordinator.phase = phase
        return PassiveView()
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard context.coordinator.phase != phase else { return }
        context.coordinator.phase = phase
        let work = probe[keyPath: report]
        probe[keyPath: report] = nil
        work?()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var phase: WidgetStudio.Phase?
    }

    private final class PassiveView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

/// Flies a widget from the stage into its Customize editor and back.
protocol CustomizeDriving: AnyObject {
    func open(_ id: WidgetID, animated: Bool)
    /// Back to the stage, the widget flying home.
    func close()
    /// Everything removed at once (Settings closing mid-flight).
    func cancel()
}
