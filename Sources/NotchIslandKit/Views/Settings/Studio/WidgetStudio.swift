import AppKit
import Observation

/// Settings ▸ Widgets' shared state: what the stage edits, and the one widget open in Customize.
@Observable final class WidgetStudio {
    enum Mode: Hashable, CaseIterable {
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
    /// The widget whose Customize editor is open or on its way (nil: the stage).
    var customizing: WidgetID?
    var phase: Phase = .idle

    /// Frames and views for the transition, written from layout callbacks.
    @ObservationIgnored let probe = StudioProbe()
}

/// Where the transition flies from and to, in the Settings surface's coordinates (top-left origin),
/// and who flies it. Plain storage, not observed: writing it must never re-render anything.
final class StudioProbe {
    /// Each widget's frame on the stage.
    var sourceFrames: [WidgetID: CGRect] = [:]
    /// The editor's canvas, where the widget lands.
    var canvasFrame: CGRect = .null
    weak var stageView: NSView?
    weak var canvasView: NSView?
    /// nil (nothing happens) until the Settings surface installs its coordinator.
    weak var driver: (any CustomizeDriving)?
}

/// Flies a widget from the stage into its Customize editor and back.
protocol CustomizeDriving: AnyObject {
    func open(_ id: WidgetID, animated: Bool)
    /// Back to the stage, the widget flying home.
    func close()
    /// Everything removed at once (Settings closing mid-flight).
    func cancel()
}
