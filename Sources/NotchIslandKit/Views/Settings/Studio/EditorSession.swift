import Observation
import SwiftUI

/// One widget's Customize editor: what is picked and hovered, the size the canvas shows, and the
/// style's undo history. Every style control binds through `binding(for:)`.
@Observable final class EditorSession {
    /// The size the canvas shows the widget at.
    enum CanvasSize: Hashable {
        /// Its size on the board.
        case onIsland
        /// One of the kind's `sizePresets`.
        case preset(GridSize)
    }

    let widgetID: WidgetID
    var selection: Set<ElementID> = []
    var hover: ElementID?
    var canvasSize: CanvasSize = .onIsland
    /// Held down: the canvas shows the kind's own look.
    var comparing = false
    /// The custom layout while a drag changes it; the drag's end writes it. Never stored.
    var layoutDraft: CustomLayout?
    /// Not observed: a drag's merged steps change it at every tick. `canUndo` and `canRedo` tell
    /// only when they flip.
    @ObservationIgnored private(set) var history = StyleHistory()
    private(set) var canUndo = false
    private(set) var canRedo = false

    @ObservationIgnored private let store: WidgetStore

    init(widget: WidgetID, store: WidgetStore) {
        widgetID = widget
        self.store = store
    }

    /// The widget's style as stored (the kind's own look once the widget is gone).
    var style: WidgetStyle { store.board.widget(widgetID)?.style ?? WidgetStyle() }

    /// One property of the style: each change is written to the store once and recorded for undo
    /// (a drag's changes as one step, between `beginEdit` and `endEdit`).
    func binding<Value: Equatable>(for keyPath: WritableKeyPath<WidgetStyle, Value>) -> Binding<Value> {
        Binding { self.style[keyPath: keyPath] } set: { self.set(keyPath, to: $0) }
    }

    /// A change is compared as the store keeps it (clamped to its range, dropped where the kind
    /// lacks it): one that comes out the same is no change.
    func set<Value: Equatable>(_ keyPath: WritableKeyPath<WidgetStyle, Value>, to value: Value) {
        guard let widget = store.board.widget(widgetID) else { return }
        var after = widget.style
        after[keyPath: keyPath] = value
        after.sanitize(for: widget.kind)
        guard after != widget.style else { return }
        history.record(widget.style, property: keyPath)
        publishAvailability()
        store.update(widgetID) { $0.style = after }
    }

    /// A drag starts: its changes of one property become one undo step.
    func beginEdit() { history.begin() }

    func endEdit() { history.end() }

    func undo() {
        if let previous = history.undo(from: style) { restore(previous) }
    }

    func redo() {
        if let next = history.redo(from: style) { restore(next) }
    }

    private func restore(_ style: WidgetStyle) {
        publishAvailability()
        store.update(widgetID) { $0.style = style }
    }

    private func publishAvailability() {
        if canUndo != history.canUndo { canUndo = history.canUndo }
        if canRedo != history.canRedo { canRedo = history.canRedo }
    }
}
