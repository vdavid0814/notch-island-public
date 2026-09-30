import AppKit
import Observation
import SwiftUI

/// One widget's Customize editor: what is picked and hovered, the size the canvas shows, and the
/// undo history of the widget's look — its style and the settings it had before styles (tint,
/// background, layout, elements, sizes). Every control binds through `binding(for:)` or
/// `widgetBinding(for:)`.
@Observable final class EditorSession {
    /// The size the canvas shows the widget at.
    enum CanvasSize: Hashable {
        /// Its size on the board.
        case onIsland
        /// One of the kind's `sizePresets`.
        case preset(GridSize)
    }

    let widgetID: WidgetID
    /// The elements picked on the canvas or in the outline; empty is the widget itself.
    var selection: Set<ElementID> = []
    var hover: ElementID?
    var canvasSize: CanvasSize = .onIsland
    /// Held down: the canvas shows the kind's own look.
    var comparing = false
    /// The custom layout while a drag changes it; the drag's end writes it. Never stored.
    var layoutDraft: LayoutDraft?
    /// What the canvas draws the widget with, and how it unlocks it: set by the canvas as it lays
    /// the widget out (only when its size, padding or scale changes).
    var canvasContext: CanvasContext?
    /// The guides a drag draws now, and whether its landing place is refused.
    var layoutGuides: [SnapGuide] = []
    var isLayoutRefused = false
    /// What the canvas measured last (`WidgetFrameProbe`): each element's frame in the widget and
    /// the size it was drawn at, and the widget's size there. Published only when it changes.
    private(set) var frames: [ElementID: CGRect] = [:]
    private(set) var drawn: [ElementID: WidgetFrameProbe.Drawn] = [:]
    /// Where each text element's letters are on the canvas (`WidgetFrameProbe.inks`).
    private(set) var inks: [ElementID: TextLetters] = [:]
    private(set) var canvasWidgetSize: CGSize = .zero
    /// Not observed: a drag's merged steps change it at every tick. `canUndo` and `canRedo` tell
    /// only when they flip.
    @ObservationIgnored private(set) var history = EditHistory<IslandWidget>()
    private(set) var canUndo = false
    private(set) var canRedo = false

    @ObservationIgnored private let store: WidgetStore
    /// What each element drawn at a size of its own draws on the canvas (`ElementFit`): the outline
    /// and resizing follow it. `fitsVersion` changes with it, so what reads it is drawn again.
    @ObservationIgnored private(set) var fits = ElementFitStore()
    private(set) var fitsVersion = 0

    init(widget: WidgetID, store: WidgetStore) {
        widgetID = widget
        self.store = store
        fits = ElementFitStore { [weak self] in
            Task { @MainActor in self?.fitsVersion &+= 1 }
        }
    }

    /// The widget as stored; nil once it is gone (removed elsewhere).
    var widget: IslandWidget? { store.board.widget(widgetID) }

    /// The widget's style as stored (the kind's own look once the widget is gone).
    var style: WidgetStyle { widget?.style ?? WidgetStyle() }

    /// The one element picked, if exactly one is.
    var selectedElement: ElementID? { selection.count == 1 ? selection.first : nil }

    // MARK: Editing

    /// One property of the style: each change is written to the store once and recorded for undo
    /// (a drag's changes as one step, between `beginEdit` and `endEdit`).
    func binding<Value: Equatable>(for keyPath: WritableKeyPath<WidgetStyle, Value>) -> Binding<Value> {
        Binding { self.style[keyPath: keyPath] } set: { self.set(keyPath, to: $0) }
    }

    /// One of the widget's own settings (its tint, background, layout, an element's size…).
    func widgetBinding<Value: Equatable>(for keyPath: WritableKeyPath<IslandWidget, Value>, fallback: Value) -> Binding<Value> {
        Binding { self.widget?[keyPath: keyPath] ?? fallback } set: { value in
            self.change(keyPath) { $0[keyPath: keyPath] = value }
        }
    }

    /// A change is compared as the store keeps it (clamped to its range, dropped where the kind
    /// lacks it): one that comes out the same is no change.
    func set<Value: Equatable>(_ keyPath: WritableKeyPath<WidgetStyle, Value>, to value: Value) {
        change((\IslandWidget.style).appending(path: keyPath)) { $0.style[keyPath: keyPath] = value }
    }

    /// Any change of the widget's look, recorded for undo as a change of `property`.
    func change(_ property: AnyKeyPath, _ edit: (inout IslandWidget) -> Void) {
        guard let before = widget else { return }
        var after = before
        edit(&after)
        after.id = before.id
        after.kind = before.kind
        after.frame = before.frame
        after.sanitize()
        guard after != before else { return }
        history.record(before, property: property)
        publishAvailability()
        store.update(widgetID) { $0 = after }
    }

    /// A drag starts: its changes of one property become one undo step.
    func beginEdit() { history.begin() }

    func endEdit() { history.end() }

    func undo() {
        guard let current = widget, let previous = history.undo(from: current) else { return }
        restore(previous)
    }

    func redo() {
        guard let current = widget, let next = history.redo(from: current) else { return }
        restore(next)
    }

    private func restore(_ snapshot: IslandWidget) {
        publishAvailability()
        store.update(widgetID) { widget in
            let frame = widget.frame
            widget = snapshot
            widget.frame = frame
        }
    }

    private func publishAvailability() {
        if canUndo != history.canUndo { canUndo = history.canUndo }
        if canRedo != history.canRedo { canRedo = history.canRedo }
    }

    /// The canvas measured the widget again.
    func measured(frames: [ElementID: CGRect], drawn: [ElementID: WidgetFrameProbe.Drawn], inks: [ElementID: TextLetters] = [:],
                  size: CGSize) {
        if frames != self.frames { self.frames = frames }
        if drawn != self.drawn { self.drawn = drawn }
        if inks != self.inks { self.inks = inks }
        if size != canvasWidgetSize { canvasWidgetSize = size }
    }

    /// One cell larger on the board, wider first, then taller, where there is room: for a size the
    /// room caps ("Make Room"). False when no larger size fits.
    @discardableResult
    func makeRoom() -> Bool {
        guard let widget else { return false }
        let board = store.board
        let upper = board.grid.maximum(for: widget.kind)
        for size in [GridSize(width: widget.frame.width + 1, height: widget.frame.height),
                     GridSize(width: widget.frame.width, height: widget.frame.height + 1),
                     GridSize(width: widget.frame.width + 1, height: widget.frame.height + 1)]
        where size.width <= upper.width && size.height <= upper.height {
            if let rect = board.placement(for: widget.kind, size: size, near: widget.frame, excluding: widget.id),
               store.setFrame(rect, for: widget.id) {
                return true
            }
        }
        NSSound.beep()
        return false
    }

    // MARK: Resetting

    /// The element back to the kind's own look (its style, its S/M/L size).
    func resetElement(_ id: ElementID) {
        change(\IslandWidget.style.elements) { widget in
            widget.style.elements[id] = nil
            widget.sizes[id] = nil
        }
    }

    /// The whole widget back to the kind's own look; where it is and what it shows stay.
    func resetWidget() {
        change(\IslandWidget.self) { widget in
            let options = widget.options
            let config = widget.config
            widget = IslandWidget(kind: widget.kind, frame: widget.frame, options: options, id: widget.id)
            widget.config = config
        }
    }

    // MARK: Copy and paste

    /// The pasteboard type of a copied style (Copy Style / Paste Style, ⌥⌘C / ⌥⌘V).
    nonisolated static let pasteboardType = NSPasteboard.PasteboardType("com.davidvarga.notchisland.widget-style")

    /// Copies the widget's style, each element's under its role, for another widget to take.
    func copyStyle() {
        guard let widget, let data = try? JSONEncoder().encode(CopiedStyle(widget)) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(data, forType: Self.pasteboardType)
    }

    var canPasteStyle: Bool { NSPasteboard.general.availableType(from: [Self.pasteboardType]) != nil }

    /// Takes a copied style: the widget's own parts as they were, each element's by its role (a
    /// title's type goes to this kind's first text, and so on), what this kind lacks left out.
    func pasteStyle() {
        guard let data = NSPasteboard.general.data(forType: Self.pasteboardType),
              let copied = try? JSONDecoder().decode(CopiedStyle.self, from: data) else { return }
        change(\IslandWidget.style) { copied.apply(to: &$0) }
    }
}

/// A widget's look as copied: its own parts, and each element's style under its role, in order.
nonisolated struct CopiedStyle: Codable, Sendable {
    var tint: WidgetTint
    var background: WidgetBackground
    var backgroundOpacity: Double?
    var surface: SurfaceStyle
    var behaviour: BehaviourStyle
    var format: FormatStyle
    var padding: Double?
    var spacing: Double?
    /// Per role, the elements' styles in the order the kind draws them.
    var roles: [String: [ElementStyle]]

    init(_ widget: IslandWidget) {
        tint = widget.tint
        background = widget.background
        backgroundOpacity = widget.backgroundOpacity
        surface = widget.style.surface
        behaviour = widget.style.behaviour
        format = widget.style.format
        padding = widget.style.layout.padding
        spacing = widget.style.layout.spacing
        var roles: [String: [ElementStyle]] = [:]
        for element in widget.kind.spec.elements {
            roles[element.role.rawValue, default: []].append(widget.style.elements[element.id] ?? ElementStyle())
        }
        self.roles = roles
    }

    func apply(to widget: inout IslandWidget) {
        widget.tint = tint
        if widget.kind.backgrounds.contains(background) {
            widget.background = background
            widget.backgroundOpacity = backgroundOpacity
        }
        widget.style.surface = surface
        widget.style.behaviour = behaviour
        widget.style.format = format
        widget.style.layout.padding = padding
        widget.style.layout.spacing = spacing
        var next: [String: Int] = [:]
        for element in widget.kind.spec.elements {
            let role = element.role.rawValue
            let index = next[role, default: 0]
            next[role] = index + 1
            guard let styles = roles[role], index < styles.count else { continue }
            let style = styles[index]
            widget.style.elements[element.id] = style == ElementStyle() ? nil : style
        }
    }
}
