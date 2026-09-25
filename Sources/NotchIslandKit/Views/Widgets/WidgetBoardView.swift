import SwiftUI

/// The home page: the user's widgets, each on its own cells of the board grid.
struct WidgetBoardView: View {
    let board: WidgetBoard
    let thumbnails: ThumbnailCache

    var body: some View {
        GeometryReader { proxy in
            let geometry = WidgetBoardGeometry(size: proxy.size, gap: WidgetMetrics.gap)
            ZStack(alignment: .topLeading) {
                ForEach(board.widgets) { widget in
                    let frame = geometry.frame(for: widget.frame)
                    IslandWidgetView(widget: widget, size: frame.size, thumbnails: thumbnails)
                        .offset(x: frame.minX, y: frame.minY)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
    }
}

nonisolated enum WidgetMetrics {
    /// Between two widgets, and the rhythm of the whole board.
    static let gap: CGFloat = 8
    /// Inside a widget's plate.
    static let padding: CGFloat = 6
    static let cornerRadius: CGFloat = 16
    /// Below this inner height a widget draws a single row, with small controls.
    static let singleRowHeight: CGFloat = 44

    /// Inside the widget: tighter without a plate (nothing to keep off the edge) and for Control
    /// Center's controls, whose button should fill a one-cell widget.
    static func padding(for widget: IslandWidget) -> CGFloat {
        if widget.background == .none { return 2 }
        return widget.kind.systemControl != nil ? 4 : padding
    }

    static func cornerRadius(for size: CGSize) -> CGFloat { min(cornerRadius, size.height / 2, size.width / 2) }

    /// One cell wide and tall: drawn as a circle.
    static func isRound(_ widget: IslandWidget) -> Bool { widget.frame.width == 1 && widget.frame.height == 1 }
}

/// Type that grows with the room a widget gives it, times the element's size, within limits — so
/// a label never overflows a small widget and never looks lost in a large one.
nonisolated enum WidgetType {
    static func points(_ room: CGFloat, ratio: CGFloat, min lower: CGFloat, max upper: CGFloat,
                       _ size: ElementSize = .medium) -> CGFloat {
        (min(max(room * ratio, lower), upper) * size.factor).rounded()
    }

    /// An element's size (a type size, or a ring's diameter) where the room may cap it: `design`
    /// is what Medium draws when there is room, `fit` the most the room takes. S, M and L always
    /// differ: with room each is its factor of the design; where the room caps them, Large takes
    /// all of it and Medium and Small a step and two below. (Scaling first and capping after made
    /// Large and Medium the same size — the cap — in most widgets.)
    static func fitted(_ design: CGFloat, fit: CGFloat, _ size: ElementSize, floor lower: CGFloat = 7) -> CGFloat {
        let share: CGFloat = switch size {
        case .small: 0.72
        case .medium: 0.86
        case .large: 1
        }
        // At the floor the steps stay apart too (a little over it rather than all three equal).
        let step: CGFloat = switch size {
        case .small: 0
        case .medium: 0.75
        case .large: 1.5
        }
        let value = min(design * size.factor, max(fit, 0) * share)
        return (max(value, lower + step) * 2).rounded() / 2
    }

    /// The largest type size at which `text` fits `width` on one line (the system font, as the
    /// widgets draw it).
    static func size(fitting text: String, in width: CGFloat, weight: NSFont.Weight = .regular,
                     rounded: Bool = false, monospacedDigits: Bool = false) -> CGFloat {
        guard width.isFinite else { return .greatestFiniteMagnitude }
        guard !text.isEmpty, width > 0 else { return width > 0 ? .greatestFiniteMagnitude : 0 }
        let reference: CGFloat = 100
        var font = monospacedDigits
            ? NSFont.monospacedDigitSystemFont(ofSize: reference, weight: weight)
            : NSFont.systemFont(ofSize: reference, weight: weight)
        if rounded, let descriptor = font.fontDescriptor.withDesign(.rounded) {
            font = NSFont(descriptor: descriptor, size: reference) ?? font
        }
        let measured = (text as NSString).size(withAttributes: [.font: font]).width
        guard measured > 0 else { return .greatestFiniteMagnitude }
        // A hair of slack: SwiftUI's text rounds its width up to whole pixels.
        return reference * width / measured * 0.97
    }

    /// How wide `text` is at a type size.
    static func textWidth(_ text: String, size: CGFloat, weight: NSFont.Weight = .semibold) -> CGFloat {
        let fit = Self.size(fitting: text, in: 100, weight: weight, rounded: true, monospacedDigits: true)
        return fit >= .greatestFiniteMagnitude ? 0 : size * 100 / fit
    }

    /// The largest type size whose lines fit `height`.
    static func size(fittingLines lines: CGFloat = 1, in height: CGFloat) -> CGFloat {
        max(0, height) / (lineHeight * max(lines, 1))
    }

    /// The system font's line height per point of type size.
    static let lineHeight: CGFloat = 1.2

    /// A number inside a ring of `diameter` (a battery's or a level's percentage): `ratio` of the
    /// diameter at Medium, never wider than the ring's inside.
    static func ringText(_ text: String, diameter: CGFloat, ratio: CGFloat, _ size: ElementSize,
                         lines: CGFloat = 2) -> CGFloat {
        let inside = max(0, diameter - 2 * max(3, diameter * 0.1) * 1.4)
        let fit = min(Self.size(fitting: text, in: inside, weight: .semibold, rounded: true, monospacedDigits: true),
                      Self.size(fittingLines: lines, in: inside))
        return fitted(diameter * ratio, fit: fit, size, floor: 6)
    }

    /// The control size for a button element.
    static func controlSize(_ base: ControlSize, _ size: ElementSize) -> ControlSize {
        switch size {
        case .small: Metrics.Control.smaller(base)
        case .medium: base
        case .large: Metrics.Control.larger(base)
        }
    }
}

extension EnvironmentValues {
    /// Drawn as a picture (the widget store, the editor's stage): nothing is read from the system
    /// that could ask for a permission, and switches show as on.
    @Entry var isWidgetPreview = false
}

/// One widget on its background, laid out for exactly `size`. A right-click edits it (Settings ▸
/// Widgets).
struct IslandWidgetView: View {
    let widget: IslandWidget
    let size: CGSize
    let thumbnails: ThumbnailCache

    @Environment(\.controlSize) private var controlSize
    @Environment(\.isWidgetPreview) private var isPreview
    @Environment(AppModel.self) private var model

    var body: some View {
        let padding = WidgetMetrics.padding(for: widget)
        let inner = CGSize(width: max(0, size.width - 2 * padding), height: max(0, size.height - 2 * padding))
        let isSingleRow = inner.height < WidgetMetrics.singleRowHeight
        let accent = accent
        content(inner)
            .frame(width: inner.width, height: inner.height)
            .controlSize(isSingleRow ? .small : Metrics.Control.smaller(controlSize))
            .modifier(OptionalTint(color: accent))
            .padding(padding)
            .frame(width: size.width, height: size.height)
            .background { WidgetBackdrop(widget: widget, size: size, accent: accent) }
            .contextMenu {
                if !isPreview {
                    Button("Edit \(widget.kind.title)…", systemImage: "slider.horizontal.3") { model.editWidget(widget.kind) }
                    Button("Edit Widgets…", systemImage: "square.grid.3x2") { model.showCustomize() }
                }
            }
    }

    static let neutralAccent = Color(white: 0.42)

    /// The widget's own colour; for Now Playing on automatic, the colour of the cover.
    private var accent: Color? {
        if let color = widget.tint.color { return color }
        // The cover's colour only on a coloured or artwork background; on a plate (or none) the
        // controls stay as neutral as the plate: a grey, not the system's blue.
        if widget.kind == .nowPlaying {
            if widget.background == .tinted || widget.background == .artwork {
                if let cover = model.media.artworkColor { return Color(cover) }
            } else {
                return Self.neutralAccent
            }
        }
        return nil
    }

    @ViewBuilder private func content(_ inner: CGSize) -> some View {
        if let control = widget.kind.systemControl {
            ControlWidget(control: control, widget: widget, size: inner)
        } else {
            kindContent(inner)
        }
    }

    @ViewBuilder private func kindContent(_ inner: CGSize) -> some View {
        switch widget.kind {
        case .nowPlaying: NowPlayingWidget(widget: widget, size: inner)
        case .timer: TimerWidget(widget: widget, size: inner)
        case .stopwatch: StopwatchWidget(widget: widget, size: inner)
        case .shelf: ShelfWidget(widget: widget, size: inner, thumbnails: thumbnails)
        case .battery: BatteryWidget(widget: widget, size: inner)
        case .volume: LevelWidget(kind: .volume, widget: widget, size: inner)
        case .brightness: LevelWidget(kind: .brightness, widget: widget, size: inner)
        case .assistant: AssistantWidget(widget: widget, size: inner)
        case .keyboardBrightness: KeyboardWidget(widget: widget, size: inner)
        case .dateTime: DateTimeWidget(widget: widget, size: inner)
        case .systemStats: SystemStatsWidget(widget: widget, size: inner)
        default: EmptyView()
        }
    }
}

/// What the widget sits on: nothing, a faint plate, a plate in its colour, or its blurred cover.
private struct WidgetBackdrop: View {
    let widget: IslandWidget
    let size: CGSize
    let accent: Color?

    @Environment(AppModel.self) private var model

    var body: some View {
        // A one-cell widget is always a circle, whatever the cell's proportions at this island
        // size (a cell a little wider than tall would otherwise make a capsule).
        if WidgetMetrics.isRound(widget) {
            let side = min(size.width, size.height)
            backdrop(size: CGSize(width: side, height: side))
                .frame(width: size.width, height: size.height)
        } else {
            backdrop(size: size)
        }
    }

    @ViewBuilder private func backdrop(size: CGSize) -> some View {
        let radius = WidgetMetrics.isRound(widget) ? size.height / 2 : WidgetMetrics.cornerRadius(for: size)
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        // 0…1 from the widget's setting (plate default 0.4; colour 0.5 → 0.22 at its default 0.5;
        // artwork fully drawn at 1).
        let strength = widget.effectiveBackgroundOpacity
        switch widget.background {
        case .none:
            Color.clear
        case .plate:
            shape.fill(.white.opacity(0.28 * strength))
        case .tinted:
            shape.fill(LinearGradient(
                colors: [(accent ?? .accentColor).opacity(strength), (accent ?? .accentColor).opacity(0.44 * strength)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ))
        case .artwork:
            if let artwork = model.media.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
                    .blur(radius: 22, opaque: true)
                    .overlay(.black.opacity(0.38))
                    .clipShape(shape)
                    .opacity(strength)
            } else {
                // No cover yet: the plate's default look, scaled the same way.
                shape.fill(.white.opacity(0.07 * strength))
            }
        }
    }
}

/// The widget's own accent, when it has one (otherwise the system's).
private struct OptionalTint: ViewModifier {
    let color: Color?

    func body(content: Content) -> some View {
        if let color {
            content.tint(color)
        } else {
            content
        }
    }
}

extension Color {
    init(_ cover: ArtworkColor) {
        self.init(red: cover.red, green: cover.green, blue: cover.blue)
    }
}

extension WidgetTint {
    var color: Color? {
        switch self {
        case .automatic: nil
        case .blue: .blue
        case .purple: .purple
        case .pink: .pink
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .mint: .mint
        case .teal: .teal
        case .gray: .gray
        }
    }
}

extension View {
    /// A widget's two sides swapped (`IslandWidget.mirrored`): the row lays out right to left.
    /// Each side keeps its own direction with `ownDirection()`, so text and sliders read as usual.
    func mirroredSides(_ mirrored: Bool) -> some View {
        environment(\.layoutDirection, mirrored ? .rightToLeft : .leftToRight)
    }

    func ownDirection() -> some View {
        environment(\.layoutDirection, .leftToRight)
    }
}

// MARK: - Now Playing

struct NowPlayingWidget: View {
    let widget: IslandWidget
    let size: CGSize

    @Environment(AppModel.self) private var model

    /// Automatic: one line when the widget is one row tall, the cover beside the text otherwise.
    private var layout: WidgetLayout {
        switch widget.layout {
        case .automatic: size.height < WidgetMetrics.singleRowHeight ? .minimal : .beside
        default: widget.layout
        }
    }

    var body: some View {
        let media = model.media
        Group {
            switch layout {
            case .cover: cover(media)
            case .minimal: minimal(media)
            default: beside(media)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .leading)
        .onAppear { withoutAnimation { media.refreshPosition() } }
    }

    // The cover beside a column of title, artist, progress and controls. The cover is as tall as
    // the widget (its size element scales it down), and gives way when the text would be squeezed.
    private func beside(_ media: MediaController) -> some View {
        let artworkSide = min(size.height * widget.size(of: .artwork).factor.clamped(to: 0.6...1), size.height)
        let showsArtwork = widget.shows(.artwork) && size.width - artworkSide >= 110
        let spacing = size.height >= 90 ? Metrics.Spacing.large : Metrics.Spacing.medium
        return HStack(spacing: spacing) {
            if showsArtwork {
                artwork(media, side: artworkSide)
                    .ownDirection()
            }
            VStack(alignment: .leading, spacing: 0) {
                titles(media.item, room: size.height, compact: size.height < 70)
                Spacer(minLength: Metrics.Spacing.xSmall)
                if widget.shows(.progress), size.height >= 84, let item = media.item {
                    PlaybackScrubber(clock: media.clock, duration: item.duration, isPlaying: media.isPlaying)
                }
                controls(media)
                    .frame(maxWidth: .infinity)
                    .padding(.top, Metrics.Spacing.xSmall)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .ownDirection()
        }
        .mirroredSides(widget.mirrored)
    }

    // The cover fills the widget; the text and controls sit on a dark fade along its bottom.
    private func cover(_ media: MediaController) -> some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if widget.shows(.artwork), let image = media.artwork {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                } else {
                    Rectangle().fill(.tint.opacity(0.35))
                }
            }
            .frame(width: size.width, height: size.height)
            .overlay(LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom))
            .clipShape(.rect(cornerRadius: max(0, WidgetMetrics.cornerRadius - WidgetMetrics.padding), style: .continuous))
            .onTapGesture { media.openPlayerApp() }
            HStack(alignment: .bottom, spacing: Metrics.Spacing.medium) {
                titles(media.item, room: size.height * 0.8, compact: size.height < 90)
                    .frame(maxWidth: .infinity, alignment: .leading)
                controls(media)
            }
            .padding(Metrics.Spacing.medium)
            .mirroredSides(widget.mirrored)
        }
        .environment(\.colorScheme, .dark)
    }

    // One line: a small cover, the title (and artist when there is height), play.
    private func minimal(_ media: MediaController) -> some View {
        HStack(spacing: Metrics.Spacing.medium) {
            if widget.shows(.artwork), size.width >= 150 {
                artwork(media, side: size.height)
                    .ownDirection()
            }
            titles(media.item, room: size.height * 2.4, compact: size.height < 34)
                .frame(maxWidth: .infinity, alignment: .leading)
                .ownDirection()
            controls(media)
                .ownDirection()
        }
        .mirroredSides(widget.mirrored)
    }

    private func artwork(_ media: MediaController, side: CGFloat) -> some View {
        Group {
            if let item = media.item {
                ArtworkView(image: media.artwork, bundleIdentifier: item.bundleIdentifier,
                            minimumRadius: side < 44 ? 6 : Metrics.Expanded.artworkMinimumRadius)
                    .onTapGesture { media.openPlayerApp() }
                    .help("Open the player")
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: side * 0.36))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.white.opacity(0.06), in: .rect(cornerRadius: side < 44 ? 6 : 12))
            }
        }
        .frame(width: side, height: side)
    }

    /// Title over artist, each sized from the room and its element size, one line each (shrinking a
    /// little before it truncates). In a compact spot the artist joins the title's line.
    @ViewBuilder private func titles(_ item: NowPlayingItem?, room: CGFloat, compact: Bool) -> some View {
        let titleSize = WidgetType.points(room, ratio: 0.12, min: 12, max: 20, widget.size(of: .trackInfo))
        let artistSize = WidgetType.points(room, ratio: 0.1, min: 11, max: 16, widget.size(of: .artist))
        let showsTitle = widget.shows(.trackInfo), showsArtist = widget.shows(.artist)
        if compact {
            let titleText = Text(title(item)).font(.system(size: titleSize, weight: .semibold))
            let artistText = Text(subtitle(item)).font(.system(size: artistSize)).foregroundStyle(.secondary)
            // Both on one line when they fit; else the title alone (the artist gives way first).
            ViewThatFits(in: .horizontal) {
                if showsTitle, showsArtist {
                    (titleText + Text("  ") + artistText).lineLimit(1).fixedSize()
                }
                if showsTitle || showsArtist {
                    (showsTitle ? titleText : artistText).lineLimit(1).minimumScaleFactor(0.75)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: Metrics.Spacing.xxSmall) {
                if showsTitle {
                    Text(title(item))
                        .font(.system(size: titleSize, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                if showsArtist {
                    // Nothing playing: the hint may take two lines rather than end in "…".
                    Text(subtitle(item))
                        .font(.system(size: artistSize))
                        .foregroundStyle(.secondary)
                        .lineLimit(item == nil ? 2 : 1)
                        .minimumScaleFactor(0.85)
                        .fixedSize(horizontal: false, vertical: item == nil)
                }
            }
        }
    }

    @ViewBuilder private func controls(_ media: MediaController) -> some View {
        if media.item != nil {
            if widget.shows(.playbackButtons) || widget.shows(.skipButtons) {
                TransportControls(isPlaying: media.isPlaying,
                                  showsPlay: widget.shows(.playbackButtons),
                                  showsSkip: widget.shows(.skipButtons) && size.width >= 170,
                                  glass: { [widget] button in widget.plainButtons ? nil : widget.look(of: button).glass })
                    .controlSize(WidgetType.controlSize(size.height < WidgetMetrics.singleRowHeight ? .small : .regular,
                                                        widget.size(of: .playbackButtons)))
                    .fixedSize()
            }
        } else if size.width >= 150 {
            Button("Open Music", systemImage: "arrow.up.forward.app") { media.openPlayerApp() }
                .islandButton(size.width >= 240 ? .capsule : .circle)
                .fixedSize()
        }
    }

    private func title(_ item: NowPlayingItem?) -> String {
        guard let item else { return String(localized: "Nothing Playing") }
        return item.title.isEmpty ? String(localized: "Unknown Title") : item.title
    }

    private func subtitle(_ item: NowPlayingItem?) -> String {
        guard let item else { return String(localized: "Music you play appears here.") }
        return item.artist.isEmpty ? item.album : item.artist
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}

// MARK: - Timer

/// The iPhone-style timer: a ruler to set the length, one action, and the time in large orange digits.
struct TimerWidget: View {
    let widget: IslandWidget
    let size: CGSize

    @Environment(AppModel.self) private var model
    /// The unit the ruler sets (with Hours or Seconds on): tap a part of the time, or the unit under
    /// the marker, to move on.
    @State private var editing: TimerUnit = .minutes
    /// The button row's actions (Start; Pause, +1 and Cancel): the time gets the rest of the row.
    @State private var actionsWidth: CGFloat = 0

    /// Orange, like the iPhone's timer, unless the widget has its own tint.
    private var accent: Color { widget.tint.color ?? TimerRuler.tint }

    private var draftUnits: TimerDraftUnits {
        TimerDraftUnits(hours: widget.shows(.timerHours), seconds: widget.shows(.timerSeconds))
    }

    var body: some View {
        let timers = model.timers
        // The ruler stays at every island size: a short widget gets a shorter ruler and smaller
        // digits rather than losing it (it was dropped below 62 pt, i.e. at Extra Small).
        let isShort = size.height < 66
        let spacing = isShort ? 3 : Metrics.Spacing.small
        let rulerHeight: CGFloat = ((size.height >= 100 ? 44 : 22) * widget.size(of: .ruler).factor).rounded()
        // Ticks plus the marker under them, cut down to what is left above the button row.
        let rulerSpace = min(rulerHeight + 14, size.height - Self.minimumRowHeight - spacing)
        let isCompactRuler = rulerSpace < 30
        let showsRuler = widget.shows(.ruler) && rulerSpace >= Self.minimumRulerSpace
        let rowHeight = showsRuler ? size.height - rulerSpace - spacing : size.height
        VStack(spacing: spacing) {
            if showsRuler {
                ruler(timers, compact: isCompactRuler)
                    .frame(height: rulerSpace)
            }
            HStack(spacing: Metrics.Spacing.medium) {
                actions(timers)
                    .ownDirection()
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { actionsWidth = $0 }
                Spacer(minLength: 0)
                if widget.shows(.readout) {
                    let points = readoutPoints(timers, rowHeight: rowHeight)
                    // One size for every part of the time. (A shrink-to-fit on the row shrank each
                    // part on its own — a big "0" beside a small ":05:00".) The size is measured to
                    // fit; the smaller ones only catch a measurement that came out short.
                    ViewThatFits(in: .horizontal) {
                        readout(timers, points: points)
                        readout(timers, points: points * 0.85)
                        readout(timers, points: points * 0.7)
                    }
                    .foregroundStyle(accent.opacity(timers.countdown.isPaused ? 0.55 : 1))
                    .ownDirection()
                }
            }
            .frame(height: rowHeight)
            .mirroredSides(widget.mirrored)
        }
        .frame(width: size.width, height: size.height)
        .animation(Motion.content, value: timers.countdown)
        .animation(Motion.content, value: editing)
        .onReceive(NotificationCenter.default.publisher(for: .demoNextTimerUnit)) { _ in
            let units = draftUnits
            guard !units.isMinutesOnly else { return }
            editing = units.next(after: editing)
        }
        // Switching Hours or Seconds off drops what they can no longer show.
        .onChange(of: draftUnits, initial: true) { _, units in
            let normalized = units.draft(timers.draftDuration)
            if normalized != timers.draftDuration { timers.draftDuration = normalized }
            if !units.units.contains(editing) { editing = .minutes }
        }
    }

    @ViewBuilder private func ruler(_ timers: TimerStore, compact: Bool) -> some View {
        let showsLabels = size.height >= 100
        let markerSize: CGFloat = compact ? 6 : 9
        switch timers.countdown {
        case .idle:
            let units = draftUnits
            let unit = units.units.contains(editing) ? editing : .minutes
            let range = units.range(of: unit)
            TimerRuler(
                minutes: Binding(
                    get: { units.value(of: unit, in: timers.draftDuration) },
                    set: { timers.draftDuration = units.duration(setting: unit, to: $0, in: timers.draftDuration) }
                ),
                // Minutes only: 0 stays on the ruler as a landmark, the ruler settles on 1.
                range: units.isMinutesOnly ? 0...range.upperBound : range,
                minimum: range.lowerBound,
                unit: unit,
                // Too short for the unit's name under the marker: tap a part of the time instead.
                nextUnit: units.isMinutesOnly || compact ? nil : { editing = units.next(after: unit) },
                showsLabels: showsLabels,
                tint: accent,
                onInteraction: { model.island.isInteracting = $0 },
                markerSize: markerSize
            )
            // The ruler swaps only its scale per unit (see `TimerRuler`); the marker stays.
            .onChange(of: timers.draftDuration) { model.haptics.play(.tick) }
        case .running(let endDate, _):
            // Re-read once per remaining minute, on the countdown's own minute boundaries.
            let remaining = max(0, endDate.timeIntervalSinceNow)
            let boundary = endDate.addingTimeInterval(-60 * (remaining / 60).rounded(.up))
            TimelineView(.periodic(from: boundary, by: 60)) { context in
                TimerRuler(
                    minutes: .constant(Self.minutesLeft(timers.countdown, at: context.date)),
                    isEditable: false,
                    showsLabels: showsLabels,
                    tint: accent,
                    markerSize: markerSize
                )
            }
        case .paused, .finished:
            TimerRuler(minutes: .constant(Self.minutesLeft(timers.countdown, at: .now)), isEditable: false,
                       showsLabels: showsLabels, tint: accent, markerSize: markerSize)
        }
    }

    /// The time's type size: the row's height sets its design size, and the room beside the
    /// buttons caps it — below that cap, so S, M and L stay apart (`WidgetType.fitted`).
    private func readoutPoints(_ timers: TimerStore, rowHeight: CGFloat) -> CGFloat {
        let design = WidgetType.points(rowHeight, ratio: 0.72, min: 12, max: 44)
        let room = size.width - actionsWidth - Metrics.Spacing.medium
        let fit = min(WidgetType.size(fitting: readoutText(timers), in: room, rounded: true, monospacedDigits: true),
                      WidgetType.size(fittingLines: 1, in: rowHeight))
        return WidgetType.fitted(design, fit: fit, widget.size(of: .readout), floor: 10)
    }

    /// The time as it reads now (a running countdown only gets shorter).
    private func readoutText(_ timers: TimerStore) -> String {
        switch timers.countdown {
        case .idle:
            let units = draftUnits
            if units.isMinutesOnly { return IslandFormat.clock(timers.draftDuration) }
            return units.units.enumerated().map { index, unit in
                let value = units.value(of: unit, in: timers.draftDuration)
                return index == 0 ? "\(value)" : String(format: "%02d", value)
            }.joined(separator: ":")
        default:
            return IslandFormat.clock((timers.countdown.remaining(at: .now) ?? 0).rounded(.up))
        }
    }

    /// The start button and the time need this much height beside a ruler.
    static let minimumRowHeight: CGFloat = 18
    /// Below this the ruler's ticks would be too short to read or grab.
    static let minimumRulerSpace: CGFloat = 18

    private func readout(_ timers: TimerStore, points: CGFloat) -> some View {
        time(timers)
            .font(.system(size: points, weight: .regular, design: .rounded).monospacedDigit())
            .lineLimit(1)
            .fixedSize()
    }

    static func minutesLeft(_ state: CountdownState, at date: Date) -> Int {
        Int(((state.remaining(at: date) ?? 0) / 60).rounded(.up))
    }

    @ViewBuilder private func time(_ timers: TimerStore) -> some View {
        switch timers.countdown {
        case .idle:
            let units = draftUnits
            if units.isMinutesOnly {
                // Follows the ruler exactly, unanimated: a cross-fade per tick smeared the digits.
                Text(IslandFormat.clock(timers.draftDuration))
                    .transaction { $0.animation = nil }
            } else {
                // Each part is tappable: the ruler then sets that unit. The one being set is bright.
                HStack(spacing: 0) {
                    ForEach(Array(units.units.enumerated()), id: \.element) { index, unit in
                        if index > 0 { Text(":").opacity(0.45) }
                        let value = units.value(of: unit, in: timers.draftDuration)
                        Text(index == 0 ? "\(value)" : String(format: "%02d", value))
                            .opacity(unit == editing ? 1 : 0.45)
                            .contentShape(.rect)
                            .onTapGesture { editing = unit }
                            .accessibilityAddTraits(.isButton)
                            .accessibilityLabel(Text("\(value) \(unit.accessibilityTitle)"))
                    }
                }
            }
        default:
            CountdownReadout(state: timers.countdown)
        }
    }

    @ViewBuilder private func actions(_ timers: TimerStore) -> some View {
        let wide = size.width >= 190
        switch timers.countdown {
        case .idle:
            Button {
                timers.start(duration: draftUnits.normalized(timers.draftDuration))
            } label: {
                if wide { Text("Start Timer") } else { Label("Start", systemImage: "play.fill") }
            }
            .timerAction(iconOnly: !wide, tint: accent)
            // 0:00, on the way to another time: nothing to count down.
            .disabled(!draftUnits.canStart(timers.draftDuration))
        case .running, .paused:
            Button {
                timers.countdown.isPaused ? timers.resume() : timers.pause()
            } label: {
                if wide {
                    Text(timers.countdown.isPaused ? "Resume" : "Pause")
                } else {
                    Label(timers.countdown.isPaused ? "Resume" : "Pause",
                          systemImage: timers.countdown.isPaused ? "play.fill" : "pause.fill")
                }
            }
            .timerAction(iconOnly: !wide, tint: accent)
            if widget.shows(.addMinute) {
                Button("+1") { timers.add(seconds: 60) }
                    .islandButton(.circle)
                    .help("Add a minute")
            }
            Button {
                timers.cancel()
            } label: {
                Label("Cancel", systemImage: "xmark")
            }
            .islandButton(.circle)
            .help("Cancel the timer")
        case .finished:
            Button {
                timers.acknowledge()
                model.banners.dismiss(.timerFinished)
            } label: {
                if wide { Text("Done") } else { Label("Done", systemImage: "checkmark") }
            }
            .timerAction(iconOnly: !wide, tint: accent)
            if widget.shows(.addMinute) {
                Button("+1") {
                    timers.add(seconds: 60)
                    model.banners.dismiss(.timerFinished)
                }
                .islandButton(.circle)
                .help("Add a minute")
            }
        }
    }
}

// MARK: - Stopwatch

struct StopwatchWidget: View {
    let widget: IslandWidget
    let size: CGSize

    @Environment(AppModel.self) private var model
    /// The buttons beside the time: it gets the rest of the row.
    @State private var buttonsWidth: CGFloat = 0

    var body: some View {
        let timers = model.timers
        let running = timers.stopwatch.isRunning
        HStack(spacing: Metrics.Spacing.medium) {
            if widget.shows(.readout) {
                StopwatchReadout(state: timers.stopwatch)
                    .font(.system(size: readoutPoints(timers), weight: .regular, design: .rounded).monospacedDigit())
                    .foregroundStyle(running ? .primary : .secondary)
                    .lineLimit(1)
                    // Only for a measurement that came out short: the size is fitted already.
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: widget.mirrored ? .trailing : .leading)
                    .ownDirection()
            } else {
                Spacer(minLength: 0)
            }
            HStack(spacing: Metrics.Spacing.medium) {
                if widget.shows(.resetButton), timers.isStopwatchActive {
                    Button {
                        timers.resetStopwatch()
                    } label: {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                    }
                    .islandButton(.circle)
                    .help("Reset")
                }
                Button {
                    running ? timers.pauseStopwatch() : timers.startStopwatch()
                } label: {
                    Label(running ? "Pause" : "Start", systemImage: running ? "pause.fill" : "play.fill")
                        .contentTransition(.symbolEffect(.replace))
                }
                .islandButton(.circle, prominent: true)
                .help(running ? "Pause" : "Start")
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { buttonsWidth = $0 }
            if !widget.shows(.readout) { Spacer(minLength: 0) }
        }
        .mirroredSides(widget.mirrored)
        .frame(width: size.width, height: size.height)
        .animation(Motion.content, value: timers.stopwatch)
    }

    /// Sized for the widest time it will show before the next redraw of the widget (the digits
    /// tick on their own): "00:00" under an hour, "0:00:00" from the fifty-ninth minute.
    private func readoutPoints(_ timers: TimerStore) -> CGFloat {
        let elapsed = timers.stopwatch.elapsed(at: .now)
        let template = elapsed >= 59 * 60 ? "0:00:00" : "00:00"
        let room = size.width - buttonsWidth - Metrics.Spacing.medium
        let fit = min(WidgetType.size(fitting: template, in: room, rounded: true, monospacedDigits: true),
                      WidgetType.size(fittingLines: 1, in: size.height))
        return WidgetType.fitted(WidgetType.points(size.height, ratio: 0.55, min: 15, max: 40), fit: fit,
                                 widget.size(of: .readout), floor: 11)
    }
}

// MARK: - Shelf

struct ShelfWidget: View {
    let widget: IslandWidget
    let size: CGSize
    let thumbnails: ThumbnailCache

    @Environment(AppModel.self) private var model

    var body: some View {
        let items = model.shelf.items
        let side = (min(size.height - 34, 64) * widget.size(of: .previews).factor).rounded()
        let showsPreviews = widget.shows(.previews) && side >= 22 && !items.isEmpty
        // The row under the previews (or the whole widget): its height and, beside the tray and
        // the chevron, the shortest wording ("Drop", or the count) cap the type.
        let rowHeight = showsPreviews ? max(20, size.height - side - Metrics.Spacing.small) : size.height
        let labelFit = min(WidgetType.size(fittingLines: 1, in: rowHeight),
                           WidgetType.size(fitting: items.isEmpty ? "Drop files" : "\(items.count) items", in: size.width * 0.62, weight: .medium))
        let labelSize = WidgetType.fitted(WidgetType.points(size.height, ratio: 0.3, min: 11, max: 15), fit: labelFit,
                                          widget.size(of: .shelfCount), floor: 9)
        VStack(spacing: Metrics.Spacing.small) {
            if showsPreviews {
                ScrollView(.horizontal) {
                    HStack(spacing: Metrics.Spacing.medium) {
                        ForEach(items) { item in
                            FileTile(item: item, thumbnails: thumbnails,
                                     scale: side / Metrics.Expanded.thumbnailSize, showsName: false)
                        }
                    }
                }
                .scrollIndicators(.never)
                .frame(height: side)
            }
            HStack(spacing: Metrics.Spacing.small) {
                Button {
                    model.island.page = .shelf
                } label: {
                    HStack(spacing: Metrics.Spacing.xSmall) {
                        Image(systemName: items.isEmpty ? "tray" : "tray.full.fill")
                            .foregroundStyle(.secondary)
                        if widget.shows(.shelfCount) {
                            // Shorter wording before smaller type, and nothing rather than "Dro…": the
                            // tray already says what the widget is.
                            ViewThatFits(in: .horizontal) {
                                Text(items.isEmpty ? "Drop files here" : "^[\(items.count) item](inflect: true)")
                                    .fixedSize()
                                Text(items.isEmpty ? "Drop files" : "\(items.count)")
                                    .fixedSize()
                                Text(items.isEmpty ? "Drop" : "\(items.count)")
                                    .fixedSize()
                                Color.clear.frame(width: 0, height: 0)
                            }
                            .foregroundStyle(items.isEmpty ? .secondary : .primary)
                            .contentTransition(.opacity)
                        }
                        Spacer(minLength: 0)
                        if size.width >= 110 {
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.tertiary)
                                .imageScale(.small)
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .font(.system(size: labelSize, weight: .medium))
                .help("Open Shelf")
                if widget.shows(.shelfActions), !items.isEmpty, size.width >= 200 {
                    Button {
                        model.shelf.airDrop()
                    } label: {
                        Label("AirDrop", systemImage: "dot.radiowaves.up.forward")
                    }
                    .islandButton(.circle)
                    .help("Send with AirDrop")
                    Button(role: .destructive) {
                        model.shelf.clear()
                    } label: {
                        Label("Clear", systemImage: "xmark")
                    }
                    .islandButton(.circle)
                    .help("Remove everything from the shelf")
                }
            }
            .frame(maxHeight: showsPreviews ? nil : .infinity)
        }
        .frame(width: size.width, height: size.height)
        .animation(Motion.content, value: items.count)
    }
}

// MARK: - Battery

struct BatteryWidget: View {
    let widget: IslandWidget
    let size: CGSize

    @Environment(AppModel.self) private var model

    /// Automatic: a ring when the widget is about square, the battery when it is wide.
    private var layout: WidgetLayout {
        switch widget.layout {
        case .automatic: size.width < size.height * 1.4 ? .ring : .glyph
        default: widget.layout
        }
    }

    var body: some View {
        let state = model.power.state
        Group {
            if layout == .ring {
                ring(state)
            } else {
                glyph(state)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private func ring(_ state: PowerState) -> some View {
        let side = min(size.width, size.height)
        let diameter = WidgetType.fitted(side, fit: side, widget.size(of: .batteryGlyph), floor: 20)
        let timeSize = WidgetType.fitted(11, fit: WidgetType.size(fittingLines: 1, in: size.height - diameter - Metrics.Spacing.xSmall),
                                         widget.size(of: .timeRemaining), floor: 8)
        return VStack(spacing: Metrics.Spacing.xSmall) {
            BatteryRing(level: state.level, isCharging: state.isCharging, tint: state.tint,
                        showsPercentage: widget.shows(.percentage) && diameter >= 40, diameter: diameter,
                        percentSize: widget.size(of: .percentage))
            if widget.shows(.timeRemaining), size.height - diameter >= 14, let text = remaining(state) {
                Text(text).font(.system(size: timeSize)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            }
        }
    }

    // The battery with its percentage inside; the time left beside it (or under it when the
    // widget is tall). Without the battery element, the percentage alone, large.
    private func glyph(_ state: PowerState) -> some View {
        let tall = size.height >= 70
        let time = widget.shows(.timeRemaining) && (size.width >= 110 || tall) ? remaining(state) : nil
        // Beside the battery (or the percentage), the time left takes what the other leaves.
        let share: CGFloat = time == nil || tall ? 1 : 0.5
        let glyphHeight = WidgetType.fitted(
            WidgetType.points(size.height, ratio: tall ? 0.3 : 0.5, min: 11, max: 34),
            fit: min((size.width - 8) * share / 2.35, size.height * (tall ? 0.5 : 0.8)),
            widget.size(of: .batteryGlyph), floor: 9)
        let percentText = state.hasBattery ? IslandFormat.percent(Double(state.level) / 100) : "—"
        let percentSize = WidgetType.fitted(
            WidgetType.points(size.height, ratio: 0.42, min: 13, max: 34),
            fit: min(WidgetType.size(fitting: "100%", in: (size.width - 8) * share, weight: .semibold, rounded: true, monospacedDigits: true),
                     WidgetType.size(fittingLines: tall && time != nil ? 1.6 : 1, in: size.height)),
            widget.size(of: .percentage), floor: 10)
        let besideWidth = widget.shows(.batteryGlyph) ? glyphHeight * 2.35 : WidgetType.textWidth(percentText, size: percentSize)
        let timeSize = WidgetType.fitted(
            WidgetType.points(size.height, ratio: 0.18, min: 10, max: 15),
            fit: min(WidgetType.size(fitting: time ?? "", in: tall ? size.width - 8 : size.width - besideWidth - Metrics.Spacing.medium - 8),
                     WidgetType.size(fittingLines: 1, in: tall ? size.height * 0.3 : size.height)),
            widget.size(of: .timeRemaining), floor: 8)
        let layout = tall ? AnyLayout(VStackLayout(spacing: Metrics.Spacing.small))
                          : AnyLayout(HStackLayout(spacing: Metrics.Spacing.medium))
        return layout {
            if widget.shows(.batteryGlyph) {
                BatteryGlyph(level: state.level, isCharging: state.isCharging, tint: state.tint,
                             showsPercentage: widget.shows(.percentage), height: glyphHeight)
                    .ownDirection()
            } else if widget.shows(.percentage) {
                Text(percentText)
                    .font(.system(size: percentSize, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(state.tint.style)
                    .contentTransition(.opacity)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            if let text = time {
                Text(text)
                    .font(.system(size: timeSize))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .ownDirection()
            }
        }
        .mirroredSides(widget.mirrored && !tall)
    }

    private func remaining(_ state: PowerState) -> String? {
        if state.isCharging { return String(localized: "Charging") }
        guard let minutes = state.minutesRemaining, minutes > 0 else { return nil }
        let text = Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .narrow))
        return String(localized: "\(text) left")
    }
}

// MARK: - Volume and brightness

struct LevelWidget: View {
    let kind: LevelKind
    let widget: IslandWidget
    let size: CGSize

    @Environment(AppModel.self) private var model

    var body: some View {
        let reading = model.levels.reading(kind)
        if widget.resolvedLevelLayout(size) == .ring {
            LevelRing(value: reading.value, symbol: IslandFormat.levelSymbol(kind, reading: reading),
                      showsValue: widget.shows(.levelValue), size: size,
                      set: { model.levels.set(kind, to: $0) },
                      onInteraction: { model.island.isInteracting = $0 },
                      symbolSize: widget.size(of: .levelIcon), valueSize: widget.size(of: .levelValue))
                .disabled(!reading.isAvailable)
        } else {
            let iconSize = WidgetType.points(size.height, ratio: 0.42, min: 13, max: 22, widget.size(of: .levelIcon))
            HStack(spacing: Metrics.Spacing.medium) {
                if widget.shows(.levelIcon), size.width >= 90 {
                    LevelSymbol(kind: kind, reading: reading)
                        .font(.system(size: iconSize))
                        .frame(width: iconSize * 1.3)
                }
                LevelSlider(kind: kind)
                    .ownDirection()
                if widget.shows(.levelValue), size.width >= 150 {
                    LevelValue(reading: reading)
                        .font(.system(size: WidgetType.points(size.height, ratio: 0.3, min: 11, max: 15,
                                                              widget.size(of: .levelValue))).monospacedDigit())
                        .frame(minWidth: 34, alignment: .trailing)
                        .ownDirection()
                }
            }
            .mirroredSides(widget.mirrored)
            .padding(.horizontal, Metrics.Spacing.xSmall)
            .frame(width: size.width, height: size.height)
        }
    }
}

extension IslandWidget {
    /// Automatic: a ring when the widget is about square, a slider when it is wide.
    func resolvedLevelLayout(_ size: CGSize) -> WidgetLayout {
        switch layout {
        case .automatic: size.width < size.height * 1.6 ? .ring : .slider
        default: layout
        }
    }
}

/// A level as a ring with its symbol inside: drag up or down on it to change the level.
struct LevelRing: View {
    let value: Double
    let symbol: String
    let showsValue: Bool
    let size: CGSize
    let set: (Double) -> Void
    var onInteraction: (Bool) -> Void = { _ in }
    /// The widget's Icon and Value elements.
    var symbolSize: ElementSize = .medium
    var valueSize: ElementSize = .medium

    @State private var dragStart: Double?

    var body: some View {
        let diameter = min(size.width, size.height)
        let line = max(3, diameter * 0.1)
        let showsNumber = showsValue && diameter >= 44
        let valuePoints = WidgetType.ringText("100%", diameter: diameter, ratio: 0.18, valueSize)
        let inside = diameter - 2 * line * 1.4
        let symbolPoints = WidgetType.fitted(diameter * (showsNumber ? 0.24 : 0.34),
                                             fit: showsNumber ? max(6, inside * 0.75 - valuePoints * WidgetType.lineHeight) : inside * 0.8,
                                             symbolSize, floor: 7)
        ZStack {
            Circle().stroke(.white.opacity(0.16), lineWidth: line)
            Circle()
                .trim(from: 0, to: value)
                .stroke(.tint, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Image(systemName: symbol)
                    .font(.system(size: symbolPoints, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                if showsNumber {
                    Text(IslandFormat.percent(value))
                        .font(.system(size: valuePoints, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.secondary)
                        // The ring moves; the number just changes (a cross-fade per step smeared).
                        .transaction { $0.animation = nil }
                }
            }
        }
        .frame(width: diameter, height: diameter)
        .frame(width: size.width, height: size.height)
        .contentShape(.rect)
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { drag in
                    if dragStart == nil {
                        dragStart = value
                        onInteraction(true)
                    }
                    set(((dragStart ?? value) - drag.translation.height / max(diameter * 2, 80)).clamped(to: 0...1))
                }
                .onEnded { _ in
                    dragStart = nil
                    onInteraction(false)
                }
        )
        .accessibilityRepresentation {
            Slider(value: Binding(get: { value }, set: set), in: 0...1)
        }
    }
}

// MARK: - Siri

/// One button: Siri in the notch (the assistant).
struct AssistantWidget: View {
    let widget: IslandWidget
    let size: CGSize

    @Environment(AppModel.self) private var model

    var body: some View {
        let tall = size.height >= 70
        let showsLabel = widget.shows(.assistantLabel)
        let iconSide = tall ? min(size.height * 0.4, 40) : min(size.height * 0.6, 22)
        let labelFit = min(WidgetType.size(fittingLines: 1, in: tall ? size.height - iconSide * 1.2 - Metrics.Spacing.small : size.height),
                           WidgetType.size(fitting: "Siri", in: tall ? size.width - 8 : size.width - iconSide * 1.3 - Metrics.Spacing.small - 8,
                                           weight: .semibold))
        let labelSize = WidgetType.fitted(WidgetType.points(size.height, ratio: tall ? 0.16 : 0.4, min: 11, max: 17), fit: labelFit,
                                          widget.size(of: .assistantLabel), floor: 9)
        Button {
            model.perform(.assistant)
        } label: {
            Group {
                if tall {
                    VStack(spacing: Metrics.Spacing.small) {
                        Image(systemName: "siri").font(.system(size: min(size.height * 0.4, 40)))
                        if showsLabel { Text("Siri").font(.system(size: labelSize, weight: .semibold)) }
                    }
                } else {
                    HStack(spacing: Metrics.Spacing.small) {
                        Image(systemName: "siri").font(.system(size: min(size.height * 0.6, 22)))
                        if showsLabel, size.width >= 70 {
                            Text("Siri").font(.system(size: labelSize, weight: .semibold))
                        }
                    }
                }
            }
            .frame(width: size.width, height: size.height)
            .contentShape(.rect(cornerRadius: WidgetMetrics.cornerRadius))
        }
        .buttonStyle(.plain)
        .foregroundStyle(
            LinearGradient(colors: IslandWidgetKind.assistant.iconColors, startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .help("Siri")
    }
}

/// Picks a label style at run time.
struct AnyLabelStyle: LabelStyle {
    private let make: (Configuration) -> AnyView

    init<S: LabelStyle>(_ style: S) {
        make = { AnyView(Label($0).labelStyle(style)) }
    }

    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}
