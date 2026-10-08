import SwiftUI

/// One widget on its background, laid out for exactly `size`. A right-click edits it (Settings ▸
/// Widgets).
struct IslandWidgetView: View {
    let widget: IslandWidget
    let size: CGSize

    @Environment(\.controlSize) private var controlSize
    @Environment(\.isWidgetPreview) private var isPreview
    @Environment(\.widgetBoard) private var board
    @Environment(\.widgetRenderMode) private var renderMode
    @Environment(\.drawsWidgetSurface) private var drawsSurface
    @Environment(\.widgetLayerPass) private var layerPass
    @Environment(AppModel.self) private var model

    var body: some View {
        let padding = WidgetMetrics.padding(for: widget)
        let inner = CGSize(width: max(0, size.width - 2 * padding), height: max(0, size.height - 2 * padding))
        let accent = accent
        let corners = Self.outerCorners(widget, size: size, board: board)
        content(inner)
            .frame(width: inner.width, height: inner.height)
            .overlay {
                if !widget.figures.isEmpty { WidgetFiguresLayer(widget: Self.adapted(widget, size: size)) }
            }
            .controlSize(inner.height < WidgetMetrics.singleRowHeight ? .small : Metrics.Control.smaller(controlSize))
            .modifier(OptionalTint(color: accent))
            .padding(padding)
            .frame(width: size.width, height: size.height)
            .environment(\.widgetShape, WidgetShape(size: size, corners: corners))
            .coordinateSpace(.named(WidgetShape.space))
            .canvasPicture(renderMode == .canvas)
            .background {
                if drawsSurface, layerPass != .overlay { WidgetSurface(widget: widget, size: size, accent: accent, corners: corners) }
            }
            .contextMenu {
                if !isPreview, renderMode == .live {
                    Button("Edit \(widget.kind.title)…", systemImage: "slider.horizontal.3") { model.editWidget(widget.id) }
                    Button("Duplicate", systemImage: "plus.square.on.square") {
                        if (model.boards.store(containing: widget.id) ?? model.widgets).duplicate(widget.id) == nil { NSSound.beep() }
                    }
                    Button("Edit Widgets…", systemImage: "square.grid.3x2") { model.showCustomize() }
                }
            }
    }

    static let neutralAccent = Color(white: 0.42)

    /// The system's accent; for Now Playing, the colour of the cover on a coloured background, and
    /// on a plate (or none) a grey as neutral as the plate.
    private var accent: Color? {
        guard widget.kind == .nowPlaying else { return nil }
        guard widget.background == .tinted else { return Self.neutralAccent }
        return model.media.artworkColor.map { Color($0) }
    }

    /// On the panel's board, concentric with the panel where the widget sits in its bottom corner;
    /// elsewhere (a picture in Settings) the standard corners.
    static func outerCorners(_ widget: IslandWidget, size: CGSize, board: WidgetBoardShape?) -> RectangleCornerRadii {
        let square = WidgetMetrics.isRound(widget) ? CGSize(width: min(size.width, size.height), height: min(size.width, size.height)) : size
        return ConcentricGeometry.outer(for: widget.frame, grid: board?.grid ?? .standard, size: square,
                                        boardCorner: board?.cornerRadius ?? WidgetMetrics.cornerRadius)
    }

    /// `widget` with its pictures where their fit puts them (`ImageLook.Fit`), drawn `size` large:
    /// the scale and offset that grow them to its edges or over all of it. As stored where they keep
    /// their own size.
    /// Adapted first to `size` where Customize placed its parts at another (`adapted(to:size:)`).
    static func resolved(_ widget: IslandWidget, size: CGSize) -> IslandWidget {
        var widget = adapted(widget, size: size)
        // One cell that is its one part: that part where the widget puts it, as large as it makes it.
        if widget.isOneElement {
            widget.offsets = [:]
            widget.scales = [:]
        }
        guard widget.imageLooks.values.contains(where: { $0.fit != .own }) else { return widget }
        let padding = WidgetMetrics.padding(for: widget)
        let inner = CGSize(width: max(0, size.width - 2 * padding), height: max(0, size.height - 2 * padding))
        switch widget.kind {
        case .nowPlaying: return NowPlayingWidget.placingArtwork(widget, inner: inner, padding: padding)
        default: return widget
        }
    }

    /// `widget`, drawn `size` large, with its parts as Customize placed them at its design size
    /// taken along to this one (`IslandWidget.adapted(keepsPlacement:)`): kept where both sizes
    /// are laid out alike, left to the layout where not.
    static func adapted(_ widget: IslandWidget, size: CGSize) -> IslandWidget {
        let design = widget.effectiveDesignSize
        guard design != widget.frame.size, design.width > 0, design.height > 0,
              widget.frame.width > 0, widget.frame.height > 0 else { return widget }
        let padding = WidgetMetrics.padding(for: widget)
        // The design size in points, from this one (cell for cell).
        let inner = CGSize(width: max(0, size.width - 2 * padding), height: max(0, size.height - 2 * padding))
        let designInner = CGSize(width: max(0, size.width * CGFloat(design.width) / CGFloat(widget.frame.width) - 2 * padding),
                                 height: max(0, size.height * CGFloat(design.height) / CGFloat(widget.frame.height) - 2 * padding))
        var designed = widget
        designed.frame.width = design.width
        designed.frame.height = design.height
        let sameLayout = layout(of: widget, inner: inner) == layout(of: designed, inner: designInner)
        var textWidth: Double?
        if widget.kind == .nowPlaying {
            let now = NowPlayingWidget.textColumnWidth(widget, inner: inner)
            let then = NowPlayingWidget.textColumnWidth(widget, inner: designInner)
            if then > 0 { textWidth = Double(now / then) }
        }
        return widget.adapted(keepsPlacement: sameLayout, textWidth: textWidth)
    }

    /// Which of its layouts a widget uses at its size (`inner`, inside its padding): Now Playing's
    /// row or its column; a control's lone button, its wide tile or its tall one; a level's slider
    /// or ring; the battery's ring, its row or its column; a readout's, the clock's and the
    /// system's row or column. Where two sizes differ in it, parts moved at one are not taken along.
    static func layout(of widget: IslandWidget, inner: CGSize) -> Int {
        if widget.kind.control != nil {
            let label = widget.shows(.controlName) || widget.shows(.controlStatus)
            guard label, ControlWidget.hasTileRoom(widget, inner: inner) else { return 0 }
            return inner.height >= ControlWidget.tallTileHeight && inner.width < inner.height * 1.6 ? 1 : 2
        }
        if widget.kind.level != nil { return LevelWidget.isRing(inner) ? 0 : 1 }
        if widget.kind.isReadout { return ReadingWidget.isTall(inner) ? 0 : 1 }
        switch widget.kind {
        case .nowPlaying: return inner.height < WidgetMetrics.singleRowHeight ? 0 : 1
        case .battery: return BatteryWidget.isRing(inner) ? 0 : BatteryWidget.isTall(inner) ? 1 : 2
        case .dateTime: return DateTimeWidget.isTall(inner) ? 0 : 1
        case .systemStats: return inner.height >= 56 ? 0 : inner.width >= 200 ? 1 : 2
        case .timer: return TimerWidget.showsRuler(widget, inner: inner) ? 0 : 1
        case .shelf: return ShelfWidget.hasPreviewRoom(inner: inner) ? 0 : 1
        case .analogClock:
            return switch ClockFaceWidget.captionPlace(widget, inner: inner) {
            case .under: 0
            case .beside: 1
            case .none: 2
            }
        case .monthCalendar: return MonthCalendarWidget.hasTitleRoom(inner: inner) ? 0 : 1
        default: return 0
        }
    }

    /// Whether `element` has room at this size: one switched on that has none is not drawn
    /// (Customize shows it off then).
    static func hasRoom(for element: ElementID, in widget: IslandWidget, size: CGSize) -> Bool {
        let padding = WidgetMetrics.padding(for: widget)
        let inner = CGSize(width: max(0, size.width - 2 * padding), height: max(0, size.height - 2 * padding))
        switch widget.kind {
        case .nowPlaying:
            if element == .seekButtons {
                var shown = widget
                shown.options.insert(.seekButtons)
                return NowPlayingWidget.controlRow(shown, inner: inner).showsSeek
            }
            return NowPlayingWidget.hasRoom(for: element, inner: inner)
        case .timer: return element != .ruler || TimerWidget.rulerSpace(inner: inner) > 0
        case .shelf:
            if element == .previews { return ShelfWidget.hasPreviewRoom(inner: inner) }
            return element != .shelfActions || ShelfWidget.hasActionRoom(inner: inner)
        case .analogClock:
            if element != .label { return true }
            var shown = widget
            shown.options.insert(.label)
            return ClockFaceWidget.captionPlace(shown, inner: inner) != .none
        case .monthCalendar:
            guard element == .label else { return true }
            var shown = widget
            shown.options.insert(.label)
            return MonthCalendarWidget.showsTitle(shown, inner: inner)
        default:
            if widget.kind.control != nil { return ControlWidget.hasRoom(for: element, in: widget, inner: inner) }
            if widget.kind.level != nil { return LevelWidget.hasRoom(for: element, inner: inner) }
            return true
        }
    }

    @ViewBuilder private func content(_ inner: CGSize) -> some View {
        switch widget.kind {
        case .dateTime: DateTimeWidget(widget: Self.resolved(widget, size: size), size: inner)
        case .stopwatch: StopwatchWidget(widget: Self.resolved(widget, size: size), size: inner)
        case .nowPlaying:
            NowPlayingWidget(widget: Self.resolved(widget, size: size), size: inner,
                             outline: WidgetShape(size: size, corners: Self.outerCorners(widget, size: size, board: board)))
        case .systemStats: SystemStatsWidget(widget: Self.resolved(widget, size: size), size: inner)
        case .worldClock: WorldClockWidget(widget: Self.resolved(widget, size: size), size: inner)
        case .clipboard: ClipboardWidget(widget: Self.resolved(widget, size: size), size: inner)
        case .battery: BatteryWidget(widget: Self.resolved(widget, size: size), size: inner)
        case .batteryChart: BatteryChartWidget(widget: Self.resolved(widget, size: size), size: inner)
        case .batteryTime, .batteryHealth, .batteryCycles, .batteryPower, .batteryTemperature, .charger, .batteryLastCharge:
            BatteryFigureWidget(widget: Self.resolved(widget, size: size), size: inner)
        case .uptime: UptimeWidget(widget: Self.resolved(widget, size: size), size: inner)
        case .timer: TimerWidget(widget: Self.resolved(widget, size: size), size: inner)
        case .shelf: ShelfWidget(widget: Self.resolved(widget, size: size), size: inner)
        case .analogClock: ClockFaceWidget(widget: Self.resolved(widget, size: size), size: inner)
        case .monthCalendar: MonthCalendarWidget(widget: Self.resolved(widget, size: size), size: inner)
        case .batteryUsage: DailyUsageWidget(widget: Self.resolved(widget, size: size), size: inner)
        case .diskSpace: DiskSpaceWidget(widget: Self.resolved(widget, size: size), size: inner)
        case .memory: MemoryWidget(widget: Self.resolved(widget, size: size), size: inner)
        default:
            if let control = widget.kind.control {
                ControlWidget(control: control, widget: Self.resolved(widget, size: size), size: inner)
            } else if let level = widget.kind.level {
                LevelWidget(level: level, widget: Self.resolved(widget, size: size), size: inner)
            }
        }
    }
}
