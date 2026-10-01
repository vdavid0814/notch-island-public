import AppKit
import SwiftUI

/// One widget's Customize editor, in Settings' page area under the header band: the outline where
/// the sidebar was (so the pane seems to stay while its content changes), the canvas in the middle
/// and the inspector on the right. Every look of the widget and of each element in it is set here;
/// every change is one undo step and redraws the canvas at once.
///
/// Laid out by `CustomizeLayout`, the same frames the transition flies the widget into.
struct CustomizeEditor: View {
    let widgetID: WidgetID
    let placement: SettingsPlacement
    let close: () -> Void

    @Environment(AppModel.self) private var model
    @State private var session: EditorSession?
    @FocusState private var isFocused: Bool

    var body: some View {
        GeometryReader { proxy in
            let layout = CustomizeLayout(size: proxy.size, placement: placement)
            if let session {
                ZStack(alignment: .topLeading) {
                    OutlinePane(session: session)
                        .frame(width: layout.outline.width, height: layout.outline.height)
                        .settingsPanel(in: layout.paneShape(leading: true))
                        .offset(x: layout.outline.minX, y: layout.outline.minY)
                    EditorCanvas(session: session, close: close)
                        .frame(width: layout.canvasPane.width, height: layout.canvasPane.height)
                        .clipShape(.rect(cornerRadius: 16, style: .continuous))
                        .offset(x: layout.canvasPane.minX, y: layout.canvasPane.minY)
                    InspectorPane(session: session, isNarrow: layout.isNarrow)
                        // Its switches are Settings' own, the small ones of its form.
                        .environment(\.isSettingsForm, true)
                        .frame(width: layout.inspector.width, height: layout.inspector.height)
                        .settingsPanel(in: layout.paneShape(leading: false))
                        .offset(x: layout.inspector.minX, y: layout.inspector.minY)
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                .focusable()
                .focusEffectDisabled()
                .focused($isFocused)
                .onAppear {
                    isFocused = true
                    model.studio.session = session
                }
                .onExitCommand {
                    // Esc steps back: from an element to the widget, from the widget to the stage.
                    if session.selection.isEmpty { close() } else { session.selection = [] }
                }
                // The grid inside the widget: arrows move the picked elements a point, ⇧ a cell;
                // Delete takes them off the widget; ⌘D copies what the user added.
                .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
                    guard session.layoutState.isCustom, !session.selection.isEmpty, let layout = session.drawnLayout,
                          let context = session.canvasContext else { return .ignored }
                    let cell = CGSize(width: context.size.width / CGFloat(layout.grid.columns), height: context.size.height / CGFloat(layout.grid.rows))
                    let step = press.modifiers.contains(.shift) ? cell : CGSize(width: 1, height: 1)
                    switch press.key {
                    case .leftArrow: session.nudge(dx: -step.width, dy: 0)
                    case .rightArrow: session.nudge(dx: step.width, dy: 0)
                    case .upArrow: session.nudge(dx: 0, dy: -step.height)
                    default: session.nudge(dx: 0, dy: step.height)
                    }
                    return .handled
                }
                .onDeleteCommand {
                    guard session.layoutState.isCustom, !session.selection.isEmpty else { return }
                    withAnimation(Motion.content) { session.hideSelection() }
                }
                .background {
                    Button("Duplicate") { withAnimation(Motion.content) { session.duplicateSelection() } }
                        .keyboardShortcut("d", modifiers: .command)
                        .opacity(0)
                        .accessibilityHidden(true)
                }
                .onKeyPress(keys: ["m"], phases: [.down, .up]) { press in
                    session.comparing = press.phase == .down
                    return .handled
                }
            }
        }
        .onAppear {
            if session == nil { session = EditorSession(widget: widgetID, store: model.editedWidgets) }
        }
        .onChange(of: model.editedWidgets.board.contains(widgetID)) { _, exists in
            // Removed elsewhere (the island's context menu): nothing left to edit.
            if !exists { close() }
        }
    }
}

/// Where the editor's panes are, in Settings' page area (the surface under the header band). Pure:
/// the transition reads the canvas's frame from here before the editor exists.
nonisolated struct CustomizeLayout: Equatable, Sendable {
    let size: CGSize
    let placement: SettingsPlacement
    let outline: CGRect
    let canvasPane: CGRect
    let inspector: CGRect
    /// The editor at its narrowest (Settings at its minimum width): the panes a little narrower.
    let isNarrow: Bool

    /// The canvas's toolbar.
    static let toolbarHeight: CGFloat = 48
    /// Between the panes.
    static let gap: CGFloat = 8

    init(size: CGSize, placement: SettingsPlacement) {
        self.size = size
        self.placement = placement
        isNarrow = size.width < 1000
        let top: CGFloat = 4
        let height = max(size.height - top - placement.gap, 0)
        let outlineWidth = isNarrow ? 180 : SettingsPlacement.sidebarWidth
        let inspectorWidth = isNarrow ? InspectorLayout.narrowWidth : InspectorLayout.width
        outline = CGRect(x: placement.leading, y: top, width: outlineWidth, height: height)
        inspector = CGRect(x: size.width - placement.leading - inspectorWidth, y: top, width: inspectorWidth, height: height)
        canvasPane = CGRect(x: outline.maxX + Self.gap, y: top, width: max(inspector.minX - Self.gap - outline.maxX - Self.gap, 0),
                            height: height)
    }

    /// The canvas under its toolbar, where the widget is drawn.
    var canvasArea: CGRect {
        CGRect(x: canvasPane.minX, y: canvasPane.minY + Self.toolbarHeight, width: canvasPane.width,
               height: max(canvasPane.height - Self.toolbarHeight, 0))
    }

    /// A pane's corners: at the island's corner concentric with it, 16 elsewhere.
    func paneShape(leading: Bool) -> UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: leading ? placement.outerRadius : 16,
                               bottomTrailingRadius: leading ? 16 : placement.outerRadius, topTrailingRadius: 16, style: .continuous)
    }
}
