import SwiftUI

extension EnvironmentValues {
    /// Drawn as a picture (the widget store, the editor's stage): nothing is read from the system
    /// that could ask for a permission, and switches show as on.
    @Entry var isWidgetPreview = false
    /// A moment the widgets show in place of their ticking clock (the snapshots); nil is now.
    @Entry var widgetDate: Date?
}

/// One widget on its background, laid out for exactly `size`. A right-click edits it (Settings ▸
/// Widgets).
///
/// Its style is resolved here, once per body evaluation, and handed to its elements with its
/// corners (`\.widgetStyle`, `\.widgetCorners`): both are equatable, so an evaluation that
/// changes neither re-renders nothing below. Its surface is handed them as values.
struct IslandWidgetView: View {
    /// As given; drawn as `drawn` (a custom layout's unlocked sizes in its style).
    let given: IslandWidget
    let size: CGSize
    let thumbnails: ThumbnailCache

    @Environment(\.controlSize) private var controlSize
    @Environment(\.isWidgetPreview) private var isPreview
    @Environment(\.widgetBoard) private var board
    @Environment(\.widgetRenderMode) private var renderMode
    @Environment(AppModel.self) private var model

    init(widget: IslandWidget, size: CGSize, thumbnails: ThumbnailCache) {
        given = widget
        self.size = size
        self.thumbnails = thumbnails
    }

    var body: some View {
        let padding = WidgetMetrics.padding(for: given)
        let inner = CGSize(width: max(0, size.width - 2 * padding), height: max(0, size.height - 2 * padding))
        // In a custom layout, with the sizes its elements were unlocked at (`drawn(in:scale:)`).
        let widget = given.drawn(in: inner, scale: model.layout.scale.factor)
        let isSingleRow = inner.height < WidgetMetrics.singleRowHeight
        let accent = accent(widget)
        let style = ResolvedWidgetStyle.resolve(widget.style)
        let corners = WidgetCorners(outer: Self.outerCorners(widget, size: size, board: board), padding: padding)
        let artwork = style.usesArtwork ? model.media.artworkColor.map { Color($0) } : nil
        scaled(widget, inner)
            // Its glass controls take a new accent only as they are made: made again for one.
            .id(widget.tint)
            .frame(width: inner.width, height: inner.height)
            .controlSize(isSingleRow ? .small : Metrics.Control.smaller(controlSize))
            .modifier(OptionalTint(color: accent))
            .padding(padding)
            .frame(width: size.width, height: size.height)
            .canvasPicture(renderMode == .canvas)
            .background {
                WidgetSurface(widget: widget, size: size, accent: accent, style: style, corners: corners, artworkColor: artwork)
            }
            .environment(\.widgetStyle, style)
            .environment(\.widgetCorners, corners)
            .environment(\.widgetArtworkColor, artwork)
            .behaviour(of: widget)
            .contextMenu {
                if !isPreview, renderMode == .live {
                    Button("Customize \(widget.kind.title)…", systemImage: "paintbrush") { model.customizeWidget(widget.id) }
                    Button("Edit \(widget.kind.title)…", systemImage: "slider.horizontal.3") { model.editWidget(widget.id) }
                    Button("Duplicate", systemImage: "plus.square.on.square") {
                        if (model.boards.store(containing: widget.id) ?? model.widgets).duplicate(widget.id) == nil { NSSound.beep() }
                    }
                    Button("Edit Widgets…", systemImage: "square.grid.3x2") { model.showCustomize() }
                }
            }
    }

    static let neutralAccent = Color(white: 0.42)

    /// The widget's own colour; for Now Playing on automatic, the colour of the cover.
    private func accent(_ widget: IslandWidget) -> Color? {
        if let color = widget.tint.color { return color }
        // The cover's colour only on a coloured, gradient or artwork background; on a plate (or
        // none) the controls stay as neutral as the plate: a grey, not the system's blue.
        if widget.kind == .nowPlaying {
            if [.tinted, .gradient, .artwork].contains(widget.background) {
                if let cover = model.media.artworkColor { return Color(cover) }
            } else {
                return Self.neutralAccent
            }
        }
        return nil
    }

    /// On the panel's board, concentric with the panel where the widget sits in its bottom corner;
    /// elsewhere (a picture in Settings) the standard corners; the style's radius when it sets one.
    /// The background is drawn in them, and what sits in its corners is concentric with them.
    static func outerCorners(_ widget: IslandWidget, size: CGSize, board: WidgetBoardShape?) -> RectangleCornerRadii {
        let square = WidgetMetrics.isRound(widget) ? CGSize(width: min(size.width, size.height), height: min(size.width, size.height)) : size
        return ConcentricGeometry.outer(for: widget.frame, grid: board?.grid ?? .standard, size: square,
                                        boardCorner: board?.cornerRadius ?? WidgetMetrics.cornerRadius,
                                        custom: widget.style.surface.cornerRadius.map { CGFloat($0) })
    }

    /// Laid out smaller or larger and drawn at the widget's size (the style's content scale), the
    /// way the editor's canvas magnifies the island: every element keeps its proportions. A custom
    /// layout scales its elements itself (`ResolvedArrangement`).
    @ViewBuilder private func scaled(_ widget: IslandWidget, _ inner: CGSize) -> some View {
        if let scale = widget.style.layout.contentScale.map({ CGFloat($0) }), scale != 1, widget.style.layout.arrangement == nil {
            let room = CGSize(width: inner.width / scale, height: inner.height / scale)
            content(widget, room)
                .frame(width: room.width, height: room.height)
                .scaleEffect(scale)
        } else {
            content(widget, inner)
        }
    }

    /// Each family routes its own kinds (`Views/Widgets/Families/`), so a kind is added there.
    @ViewBuilder private func content(_ widget: IslandWidget, _ inner: CGSize) -> some View {
        switch widget.kind.spec.family {
        case .nowPlaying: arranged(widget, NowPlayingFamily(widget: widget, size: inner), inner)
        case .timers: arranged(widget, TimerFamily(widget: widget, size: inner), inner)
        case .levels: arranged(widget, LevelFamily(widget: widget, size: inner), inner)
        case .battery: arranged(widget, BatteryFamily(widget: widget, size: inner), inner)
        case .controls: arranged(widget, ControlFamily(widget: widget, size: inner), inner)
        case .time: arranged(widget, TimeFamily(widget: widget, size: inner), inner)
        case .system: arranged(widget, SystemFamily(widget: widget, size: inner), inner)
        case .tools: arranged(widget, ToolFamily(widget: widget, size: inner, thumbnails: thumbnails), inner)
        case .airPods: arranged(widget, AirPodsFamily(widget: widget, size: inner), inner)
        }
    }

    /// A family that draws its elements one by one (`WidgetFamilyElements`) may be laid out freely
    /// (`ArrangedFamily`); any other draws its own stacks. Chosen by type, when the view is built.
    private func arranged<Family: View>(_ widget: IslandWidget, _ family: Family, _ inner: CGSize) -> Family { family }

    private func arranged<Family: View & WidgetFamilyElements>(_ widget: IslandWidget, _ family: Family, _ inner: CGSize) -> ArrangedFamily<Family> {
        ArrangedFamily(family: family, widget: widget, size: inner)
    }
}

extension View {
    /// On the editor's canvas: a picture — nothing read from the system, and nothing in it answers a
    /// click, so no click there sets the volume or sends a command — and the space its elements'
    /// frames are measured in (`WidgetFrameProbe`). On the island, the view itself.
    @ViewBuilder func canvasPicture(_ isCanvas: Bool) -> some View {
        if isCanvas {
            environment(\.isWidgetPreview, true)
                .allowsHitTesting(false)
                .coordinateSpace(.named(WidgetFrameProbe.space))
        } else {
            self
        }
    }
}

extension View {
    /// The widget's behaviour (its tap, haptic, dimming) where its style sets any; else the view itself.
    @ViewBuilder func behaviour(of widget: IslandWidget) -> some View {
        if widget.style.behaviour == BehaviourStyle() {
            self
        } else {
            modifier(WidgetBehaviourModifier(widget: widget))
        }
    }
}

/// The widget's own accent, when it has one (otherwise the system's).
struct OptionalTint: ViewModifier {
    let color: Color?

    func body(content: Content) -> some View {
        if let color {
            content.tint(color)
        } else {
            content
        }
    }
}
