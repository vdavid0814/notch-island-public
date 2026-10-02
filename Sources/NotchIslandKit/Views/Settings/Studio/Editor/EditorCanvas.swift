import AppKit
import SwiftUI

/// The Customize editor's canvas: the widget laid out exactly as the island lays it out, magnified,
/// on a slab of the island over the wallpaper; its elements picked with a click (a ring round the
/// one picked, a finer one round the one under the pointer).
struct EditorCanvas: View {
    let session: EditorSession
    let close: () -> Void

    @Environment(AppModel.self) private var model
    @AppStorage(DesktopBackdropStyle.key) private var backdrop: DesktopBackdropStyle = DesktopBackdropStyle.defaultStyle

    var body: some View {
        VStack(spacing: 0) {
            CanvasToolbar(session: session, close: close)
            GeometryReader { proxy in
                if let widget = session.widget {
                    let geometry = CanvasGeometry(area: proxy.size, widget: widget, canvasSize: session.canvasSize, layout: model.layout,
                                                  grid: model.editedWidgets.board.grid)
                    ZStack(alignment: .topLeading) {
                        DesktopBackdrop(style: backdrop)
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .allowsHitTesting(false)
                        // A piece of the island around the widget.
                        RoundedRectangle(cornerRadius: geometry.slabRadius, style: .continuous)
                            .fill(.black)
                            .overlay {
                                RoundedRectangle(cornerRadius: geometry.slabRadius, style: .continuous).strokeBorder(.white.opacity(0.08))
                            }
                            .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
                            .frame(width: geometry.slab.width, height: geometry.slab.height)
                            .offset(x: geometry.slab.minX, y: geometry.slab.minY)
                            .allowsHitTesting(false)
                        // In a graph of its own: an edit redraws the widget, never the panes around it.
                        IsolatedHosting(size: geometry.scaledWidget.size,
                                        input: CanvasInput(id: widget.id, size: geometry.widgetSize, frame: geometry.widgetFrame,
                                                           zoom: geometry.zoom, comparing: session.comparing)) {
                            CanvasWidget(session: session, size: geometry.widgetSize, frame: geometry.widgetFrame, zoom: geometry.zoom,
                                         comparing: session.comparing, board: model.editedWidgets.board.grid)
                                .environment(model)
                        }
                        .frame(width: geometry.scaledWidget.width, height: geometry.scaledWidget.height)
                        .offset(x: geometry.scaledWidget.minX, y: geometry.scaledWidget.minY)
                        .allowsHitTesting(false)
                        ElementLayoutEditor(session: session, geometry: geometry)
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                    .clipped()
                    .overlay(alignment: .bottom) {
                        CanvasLayoutBar(session: session)
                            .padding(.bottom, 10)
                    }
                }
            }
        }
    }
}

/// Where the widget is drawn on the canvas.
struct CanvasGeometry: Equatable {
    /// The widget's size on the island (or the preset looked at), in points.
    let widgetSize: CGSize
    /// Its cells as drawn: its place on the board, or a preset's at the board's corner.
    let widgetFrame: GridRect
    let zoom: CGFloat
    /// The magnified widget, in the canvas.
    let scaledWidget: CGRect
    let slab: CGRect
    let slabRadius: CGFloat

    /// Around the slab.
    static let margin: CGFloat = 36
    static let maximumZoom: CGFloat = 3

    init(area: CGSize, widget: IslandWidget, canvasSize: EditorSession.CanvasSize, layout: IslandLayout, grid: BoardGrid) {
        let board = WidgetBoardGeometry(size: WidgetsSettingsPage.boardSize(layout), grid: grid)
        let frame: GridRect = switch canvasSize {
        case .onIsland: widget.frame
        case .preset(let size): GridRect(column: 0, row: 0, width: min(size.width, grid.columns), height: min(size.height, grid.rows))
        }
        widgetFrame = frame
        widgetSize = board.frame(for: frame).size
        let room = CGSize(width: max(area.width - 2 * Self.margin - 32, 40), height: max(area.height - 2 * Self.margin - 32, 40))
        let zoom = min(Self.maximumZoom, room.width / max(widgetSize.width, 1), room.height / max(widgetSize.height, 1))
        // Whole device pixels at the magnified size, so the widget's edges stay crisp.
        self.zoom = max(zoom, 0.5)
        let scaled = CGSize(width: (widgetSize.width * self.zoom).rounded(), height: (widgetSize.height * self.zoom).rounded())
        scaledWidget = CGRect(x: ((area.width - scaled.width) / 2).rounded(), y: ((area.height - scaled.height) / 2).rounded(),
                              width: scaled.width, height: scaled.height)
        slab = scaledWidget.insetBy(dx: -16, dy: -16)
        slabRadius = WidgetMetrics.cornerRadius * self.zoom + 16
    }

    /// A point on the canvas in the widget's own space (unmagnified).
    func widgetPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - scaledWidget.minX) / zoom, y: (point.y - scaledWidget.minY) / zoom)
    }

    /// A rectangle of the widget on the canvas.
    func canvasRect(_ rect: CGRect) -> CGRect {
        CGRect(x: scaledWidget.minX + rect.minX * zoom, y: scaledWidget.minY + rect.minY * zoom,
               width: rect.width * zoom, height: rect.height * zoom)
    }
}

/// All the canvas's own graph takes from outside: ids and geometry (the widget's look is read from
/// the store inside it, so every edit redraws it).
private struct CanvasInput: Equatable {
    let id: WidgetID
    let size: CGSize
    let frame: GridRect
    let zoom: CGFloat
    let comparing: Bool
}

/// The widget on the canvas: the island's own layout, drawn as a picture and measured.
struct CanvasWidget: View {
    let session: EditorSession
    let size: CGSize
    let frame: GridRect
    let zoom: CGFloat
    let comparing: Bool
    let board: BoardGrid

    @Environment(AppModel.self) private var model
    @Environment(\.displayScale) private var displayScale
    @State private var probe = WidgetFrameProbe()
    @State private var thumbnails = ThumbnailCache()
    @State private var publisher = MeasurePublisher()

    var body: some View {
        if let widget = model.editedWidgets.board.widget(session.widgetID) {
            let shown = Self.drawn(widget, frame: frame, comparing: comparing, draft: session.layoutDraft)
            let context = context(shown)
            // While the widget flies in or out, the flier stands in for it (`SettingsSurfaceView`).
            let isFlying = model.studio.customizing == widget.id && model.studio.phase != .open
            IslandWidgetView(widget: shown, size: size, thumbnails: thumbnails)
                .frame(width: size.width, height: size.height)
                .environment(\.widgetRenderMode, .canvas)
                .environment(\.widgetFrameProbe, probe)
                .environment(\.elementFitStore, session.fits)
                .environment(\.widgetReadsLive, true)
                .environment(\.widgetBoard, WidgetBoardShape(grid: board, cornerRadius: ConcentricGeometry.boardCornerRadius(model.layout)))
                .controlSize(Metrics.controlSize(forScale: model.layout.factor))
                .environment(\.colorScheme, .dark)
                .scaleEffect(zoom, anchor: .topLeading)
                .frame(width: size.width * zoom, height: size.height * zoom, alignment: .topLeading)
                .opacity(isFlying ? 0 : 1)
                .background { StudioPhaseReporter(probe: model.studio.probe, phase: model.studio.phase, report: \.canvasReport) }
                .onAppear {
                    session.canvasContext = context
                    publisher.connect(probe: probe, session: session, size: size)
                }
                .onChange(of: size) { publisher.connect(probe: probe, session: session, size: size) }
                .onChange(of: ContextKey(size: context.size, padding: context.padding, scale: context.scale), initial: true) {
                    session.canvasContext = context
                }
        }
    }
}

extension CanvasWidget {
    /// The widget as the canvas draws it: at the cells looked at, in its kind's own look while compared.
    static func drawn(_ widget: IslandWidget, frame: GridRect, comparing: Bool, draft: LayoutDraft? = nil) -> IslandWidget {
        var drawn = comparing ? IslandWidget(kind: widget.kind, frame: frame, options: widget.options, id: widget.id) : widget
        drawn.frame = frame
        // The layout a drag is changing, before it is stored.
        if !comparing, let draft {
            drawn.style = draft.resolvedStyle
            for id in draft.layout.items.map(\.id) where widget.kind.options.contains(id) { drawn.options.insert(id) }
        }
        return drawn
    }

    /// What the session lays the widget out with: its size here, its padding, the island's scale,
    /// and the widget as its stacks draw it now.
    fileprivate func context(_ widget: IslandWidget) -> CanvasContext {
        let padding = WidgetMetrics.padding(for: widget)
        let scale = model.layout.factor
        let contentScale = CGFloat(widget.style.layout.contentScale ?? 1)
        return CanvasContext(size: size, padding: padding, scale: scale, displayScale: displayScale) { [weak probe, size, displayScale] in
            probe?.unlock(size: size, padding: padding, scale: scale, displayScale: displayScale, contentScale: contentScale)
        }
    }

    fileprivate struct ContextKey: Equatable {
        var size: CGSize
        var padding: CGFloat
        var scale: CGFloat
    }
}

/// Hands what the probe measured to the session, once per run of layout rather than per element.
@MainActor private final class MeasurePublisher {
    private var isScheduled = false

    func connect(probe: WidgetFrameProbe, session: EditorSession, size: CGSize) {
        probe.onChange = { [weak self, weak probe, weak session] in
            guard let self, !self.isScheduled else { return }
            self.isScheduled = true
            DispatchQueue.main.async {
                self.isScheduled = false
                guard let probe, let session else { return }
                session.measured(frames: probe.frames, drawn: probe.drawn, inks: probe.inks, size: size)
            }
        }
        session.measured(frames: probe.frames, drawn: probe.drawn, inks: probe.inks, size: size)
    }
}

/// ‹ Widgets · the widget's name · the size it is looked at · Compare · Undo, Redo · Done.
private struct CanvasToolbar: View {
    let session: EditorSession
    let close: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: close) {
                Label("Widgets", systemImage: "chevron.left")
            }
            .help("Back to all widgets (esc)")
            if let widget = session.widget {
                Text(widget.kind.title)
                    .font(.headline)
                    .lineLimit(1)
                Picker("Size", selection: Binding(get: { session.canvasSize }, set: { size in
                    withAnimation(Motion.content) { session.canvasSize = size }
                })) {
                    Text("On Island (\(widget.frame.width) × \(widget.frame.height))").tag(EditorSession.CanvasSize.onIsland)
                    Divider()
                    ForEach(widget.kind.sizePresets, id: \.self) { size in
                        Text("\(size.width) × \(size.height)").tag(EditorSession.CanvasSize.preset(size))
                    }
                }
                .labelsHidden()
                .fixedSize()
                .help("The size the widget is shown at while you edit it")
            }
            Spacer(minLength: 8)
            CompareButton(session: session)
            ControlGroup {
                Button { session.undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                    .disabled(!session.canUndo)
                    .keyboardShortcut("z", modifiers: .command)
                    .help("Undo (⌘Z)")
                Button { session.redo() } label: { Label("Redo", systemImage: "arrow.uturn.forward") }
                    .disabled(!session.canRedo)
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .help("Redo (⇧⌘Z)")
            }
            .fixedSize()
            Button("Done", action: close)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .controlSize(.regular)
        .padding(.horizontal, 14)
        .frame(height: CustomizeLayout.toolbarHeight)
    }
}

/// Held down: the widget in its kind's own look, to compare with.
private struct CompareButton: View {
    let session: EditorSession
    @State private var isPressed = false

    var body: some View {
        Label("Compare", systemImage: "square.split.2x1")
            .labelStyle(.iconOnly)
            .frame(width: 28, height: 22)
            .background(isPressed ? Color.islandAccent.opacity(0.3) : .white.opacity(0.08), in: .rect(cornerRadius: 6, style: .continuous))
            .contentShape(.rect)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isPressed else { return }
                    isPressed = true
                    session.comparing = true
                }
                .onEnded { _ in
                    isPressed = false
                    session.comparing = false
                })
            .help("Hold to see the widget's own look (or hold M)")
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Compare with the widget's own look")
    }
}
