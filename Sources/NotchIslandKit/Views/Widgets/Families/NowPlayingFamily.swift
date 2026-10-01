import SwiftUI

/// The Now Playing family (`NowPlayingSpecs`): each kind to its view, a kind not built yet to its placeholder.
struct NowPlayingFamily: View, WidgetFamilyElements {
    let widget: IslandWidget
    let size: CGSize

    var body: some View {
        switch widget.kind {
        case .nowPlaying: NowPlayingWidget(widget: widget, size: size)
        default: WidgetPlaceholder(kind: widget.kind, size: size)
        }
    }

    func demands(_ input: PlanInput) -> [ElementDemand] {
        input.demands(types: [.trackInfo: NowPlayingWidget.titleType.at(20), .artist: NowPlayingWidget.artistType.at(16)])
    }

    func element(_ id: ElementID) -> NowPlayingElement { NowPlayingElement(widget: widget, id: id) }
}

/// One element of Now Playing on its own (a custom layout), at the size the layout plans.
struct NowPlayingElement: View {
    let widget: IslandWidget
    let id: ElementID

    @Environment(\.widgetPlan) private var plan
    @Environment(\.widgetStyle) private var style
    @Environment(\.widgetCorners) private var corners
    @Environment(\.widgetArtworkColor) private var artwork
    @Environment(AppModel.self) private var model

    var body: some View {
        let media = model.media
        let planned = plan?.elements[id]
        let room = planned?.size ?? CGSize(width: 60, height: 20)
        let alignment = style.element(id)?.text.alignment?.frameAlignment ?? .leading
        switch id {
        case .artwork:
            // The whole rectangle, the cover filling it (cropped to it like a photo): its frame is the picture.
            NowPlayingArtwork(size: room)
        case .trackInfo:
            let titleType = NowPlayingWidget.titleType.at(planned?.points ?? 14)
            Group {
                if widget.shows(.artist), plan?.elements[.artist] == nil, let artistPoints = style.element(.artist)?.text.points {
                    // The artist not placed on its own: on the title's line, as the one-line layout draws them —
                    // no larger than the title the line is planned for (larger, it ran out of its frame).
                    let artistType = NowPlayingWidget.artistType.at(min(CGFloat(artistPoints), titleType.points))
                    (Text.widgetRun(NowPlayingWidget.title(media.item), .trackInfo, titleType, style: style, artwork: artwork) + Text("  ")
                        + Text.widgetRun(NowPlayingWidget.subtitle(media.item), .artist, artistType, color: AnyShapeStyle(.secondary),
                                         style: style, artwork: artwork))
                        .lineLimit(1)
                } else {
                    Text(NowPlayingWidget.title(media.item))
                        .widgetText(.trackInfo, titleType, in: style)
                        .lineLimit(style.element(.trackInfo)?.text.lineLimit ?? 1)
                }
            }
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
        case .artist:
            Text(NowPlayingWidget.subtitle(media.item))
                .widgetText(.artist, NowPlayingWidget.artistType.at(planned?.points ?? 12), in: style)
                .foregroundStyle(.secondary)
                .lineLimit(style.element(.artist)?.text.lineLimit ?? 1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
        case .progress:
            if let item = media.item {
                PlaybackScrubber(clock: media.clock, duration: item.duration, isPlaying: media.isPlaying)
                    .controlSize(room.height >= 40 ? .large : .regular)
            }
        case .playbackButtons:
            if media.item == nil {
                // Nothing playing: the player's app, a click away (where play will be).
                NowPlayingOpenPlayer(capsule: room.width >= room.height * 2.5)
                    .controlSize(style.controlSize(.playbackButtons, height: room.height))
            } else {
                TransportControls(isPlaying: media.isPlaying, showsPlay: true, showsSkip: false,
                                  looks: widget.plainButtons ? nil : widget.buttonLooks)
                    // Play is drawn a size up from its row (`TransportControls`).
                    .controlSize(style.element(.playbackButtons)?.button.size.map { Metrics.Control.smaller($0.controlSize) }
                                 ?? Metrics.Control.smaller(.fitting(height: room.height)))
            }
        case .seekBack, .seekForward:
            if media.item != nil {
                TransportSeek(forward: id == .seekForward, seconds: style.element(id)?.button.seconds ?? ButtonSpec.standardSeconds)
                    .controlSize(style.controlSize(id, height: room.height))
            }
        case .skipButtons.part("previous"), .skipButtons.part("next"):
            if media.item != nil {
                TransportSkip(forward: id == .skipButtons.part("next"), looks: widget.plainButtons ? nil : widget.buttonLooks)
                    .controlSize(style.controlSize(id, height: room.height))
            }
        default:
            EmptyView()
        }
    }
}

struct NowPlayingWidget: View {
    let widget: IslandWidget
    let size: CGSize

    @Environment(\.widgetFrameProbe) private var probe
    @Environment(AppModel.self) private var model
    @Environment(\.widgetCorners) private var corners
    @Environment(\.widgetRenderMode) private var renderMode
    @Environment(\.widgetStyle) private var style
    @Environment(\.widgetArtworkColor) private var artworkColor

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
        .whileShown { if renderMode == .live { withoutAnimation { media.refreshPosition() } } }
    }

    // The cover beside a column of title, artist, progress and controls. The cover is as tall as
    // the widget (its size element scales it down), and gives way when the text would be squeezed.
    private func beside(_ media: MediaController) -> some View {
        // Large: the cover runs out to the widget's edges, in its corners (it cannot be taller than
        // the widget inside the padding).
        let bleeds = widget.size(of: .artwork) == .large
        let padding = WidgetMetrics.padding(for: widget)
        let artworkSide = bleeds ? size.height + 2 * padding : min(size.height * widget.size(of: .artwork).factor.clamped(to: 0.6...1), size.height)
        let showsArtwork = widget.shows(.artwork) && size.width - (bleeds ? size.height : artworkSide) >= 110
        let spacing = size.height >= 90 ? Metrics.Spacing.large : Metrics.Spacing.medium
        return HStack(spacing: spacing) {
            if showsArtwork {
                artwork(media, side: artworkSide)
                    .modifier(EdgeBleed(isOn: bleeds, padding: padding, outer: corners.outer))
                    .ownDirection()
            }
            VStack(alignment: .leading, spacing: 0) {
                titles(media.item, room: size.height, compact: size.height < 70, textRoom: besideTextRoom(media))
                Spacer(minLength: Metrics.Spacing.xSmall)
                if widget.shows(.progress), size.height >= 84, let item = media.item {
                    PlaybackScrubber(clock: media.clock, duration: item.duration, isPlaying: media.isPlaying)
                        .environment(\.lineScale, widget.size(of: .progress).factor)
                        .editorElement(.progress, in: probe)
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
            // Concentric with the widget, inside its real padding.
            .clipShape(corners: corners.inner)
            .widgetImage(.artwork, in: style)
            .editorElement(.artwork, in: probe)
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
        NowPlayingArtwork(side: side)
            .frame(width: side, height: side)
            .editorElement(.artwork, in: probe)
    }

    /// The height the title and the artist share beside the cover: what the progress line and the
    /// buttons under them leave (about their heights at the column's control size).
    private func besideTextRoom(_ media: MediaController) -> CGFloat {
        var reserved = Metrics.Spacing.xSmall
        if widget.shows(.progress), size.height >= 84, media.item != nil { reserved += 31 }
        if media.item != nil, widget.shows(.playbackButtons) || widget.shows(.skipButtons) { reserved += 26 + Metrics.Spacing.xSmall }
        return max(size.height - reserved, 0)
    }

    /// The title's type (semibold) and the artist's, at a size set where they are drawn.
    static let titleType = TypeSpec(points: 14, weight: .semibold)
    static let artistType = TypeSpec(points: 12)

    /// Title over artist, each sized from the room and its element size, one line each (shrinking a
    /// little before it truncates). In a compact spot the artist joins the title's line. A fixed
    /// size (the style's) is drawn as set, never taller than the line the room gives it.
    /// `textRoom`: the height title and artist share one over the other, where sizes of their own
    /// would together run past it (each up to its line, a 96 pt title pushed the buttons out).
    @ViewBuilder private func titles(_ item: NowPlayingItem?, room: CGFloat, compact: Bool, textRoom: CGFloat? = nil) -> some View {
        let lineFit = WidgetType.size(fittingLines: 1, in: compact ? size.height : room * 0.4)
        let showsTitle = widget.shows(.trackInfo), showsArtist = widget.shows(.artist)
        let (titlePoints, artistPoints) = shared(
            title: style.textPoints(.trackInfo, auto: WidgetType.points(room, ratio: 0.12, min: 12, max: 20, widget.size(of: .trackInfo)),
                                    fit: lineFit),
            artist: style.textPoints(.artist, auto: WidgetType.points(room, ratio: 0.1, min: 11, max: 16, widget.size(of: .artist)),
                                     fit: lineFit),
            in: compact ? nil : textRoom, both: showsTitle && showsArtist)
        let titleType = Self.titleType.at(titlePoints)
        let artistType = Self.artistType.at(artistPoints)
        if compact {
            // Both on one line when they fit, each a run in its own type; else the title alone (the
            // artist gives way first).
            // Each wording tagged where it is drawn: only the one that fits is.
            let titleDrawn = WidgetFrameProbe.Drawn.text(style.drawnType(.trackInfo, titleType), lines: 1, fit: lineFit)
            ViewThatFits(in: .horizontal) {
                if showsTitle, showsArtist {
                    (Text.widgetRun(title(item), .trackInfo, titleType, style: style, artwork: artworkColor) + Text("  ")
                        + Text.widgetRun(subtitle(item), .artist, artistType, color: AnyShapeStyle(.secondary),
                                         style: style, artwork: artworkColor))
                        .lineLimit(1).fixedSize()
                        .editorElement(.trackInfo, in: probe, drawn: titleDrawn, companion: (.artist, style.drawnType(.artist, artistType)))
                }
                if showsTitle {
                    Text(title(item)).widgetText(.trackInfo, titleType, in: style).lineLimit(1).minimumScaleFactor(0.75)
                        .editorElement(.trackInfo, in: probe, drawn: titleDrawn)
                } else if showsArtist {
                    Text(subtitle(item)).widgetText(.artist, artistType, in: style).foregroundStyle(.secondary)
                        .lineLimit(1).minimumScaleFactor(0.75)
                        .editorElement(.artist, in: probe, drawn: .text(style.drawnType(.artist, artistType), lines: 1, fit: lineFit))
                }
            }
        } else {
            VStack(alignment: .leading, spacing: Metrics.Spacing.xxSmall) {
                if showsTitle {
                    Text(title(item))
                        .widgetText(.trackInfo, titleType, in: style)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .editorElement(.trackInfo, in: probe, drawn: .text(style.drawnType(.trackInfo, titleType), lines: 1, fit: lineFit))
                }
                if showsArtist {
                    // Nothing playing: the hint may take two lines rather than end in "…".
                    Text(subtitle(item))
                        .widgetText(.artist, artistType, in: style)
                        .foregroundStyle(.secondary)
                        .lineLimit(item == nil ? 2 : 1)
                        .minimumScaleFactor(0.85)
                        .fixedSize(horizontal: false, vertical: item == nil)
                        .editorElement(.artist, in: probe, drawn: .text(style.drawnType(.artist, artistType), lines: item == nil ? 2 : 1,
                                                                        fit: lineFit))
                }
            }
        }
    }

    @ViewBuilder private func controls(_ media: MediaController) -> some View {
        if media.item != nil {
            if widget.shows(.playbackButtons) || widget.shows(.skipButtons) || seek(.seekBack) != nil || seek(.seekForward) != nil {
                TransportControls(isPlaying: media.isPlaying,
                                  showsPlay: widget.shows(.playbackButtons),
                                  showsSkip: widget.shows(.skipButtons) && size.width >= 170,
                                  looks: widget.plainButtons ? nil : widget.buttonLooks,
                                  playSize: widget.size(of: .playbackButtons), skipSize: widget.size(of: .skipButtons),
                                  seekBack: seek(.seekBack), seekForward: seek(.seekForward))
                    .controlSize(size.height < WidgetMetrics.singleRowHeight ? .small : .regular)
                    // Its own height; across, the room it is given (titled buttons that do not fit it
                    // show their symbols alone, `TransportControls`).
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else if size.width >= 150 {
            NowPlayingOpenPlayer(capsule: size.width >= 240)
                .buttonElement(.playbackButtons, in: probe)
        }
    }

    /// A seek button as the row offers it: switched on (the row drops it where it has no room).
    private func seek(_ id: ElementID) -> TransportSeek.Setting? {
        guard widget.shows(id) else { return nil }
        return TransportSeek.Setting(seconds: style.element(id)?.button.seconds ?? ButtonSpec.standardSeconds, size: widget.size(of: id))
    }

    /// Title and artist sizes of their own (the style's) scaled down together to `room`, one over
    /// the other; the kind's own sizes as they are.
    private func shared(title: CGFloat, artist: CGFloat, in room: CGFloat?, both: Bool) -> (CGFloat, CGFloat) {
        guard let room, style.isFixed(.trackInfo) || style.isFixed(.artist) else { return (title, artist) }
        let titleHeight = TextFit.frameHeight(points: title, lines: 1, spec: Self.titleType.at(title))
        let artistHeight = both ? TextFit.frameHeight(points: artist, lines: 1, spec: Self.artistType.at(artist)) : 0
        let total = titleHeight + artistHeight + (both ? Metrics.Spacing.xxSmall : 0)
        guard total > room, total > 0 else { return (title, artist) }
        let factor = max(room - (both ? Metrics.Spacing.xxSmall : 0), 0) / (titleHeight + artistHeight)
        return (max((title * factor * 4).rounded(.down) / 4, TextFit.minimumPoints),
                max((artist * factor * 4).rounded(.down) / 4, TextFit.minimumPoints))
    }

    private func title(_ item: NowPlayingItem?) -> String { Self.title(item) }

    private func subtitle(_ item: NowPlayingItem?) -> String { Self.subtitle(item) }

    static func title(_ item: NowPlayingItem?) -> String {
        guard let item else { return String(localized: "Nothing Playing") }
        return item.title.isEmpty ? String(localized: "Unknown Title") : item.title
    }

    static func subtitle(_ item: NowPlayingItem?) -> String {
        guard let item else { return String(localized: "Music you play appears here.") }
        return item.artist.isEmpty ? item.album : item.artist
    }
}

/// The cover (tap: open the player), or a note while nothing plays; in the element's look.
struct NowPlayingArtwork: View {
    /// Square in the kind's stacks; in a custom layout, the element's rectangle.
    let size: CGSize

    init(side: CGFloat) { size = CGSize(width: side, height: side) }

    init(size: CGSize) { self.size = size }

    private var side: CGFloat { min(size.width, size.height) }

    @Environment(\.widgetStyle) private var style
    @Environment(AppModel.self) private var model

    var body: some View {
        let media = model.media
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
        .frame(width: size.width, height: size.height)
        // Concentric with the widget already, wherever it sits (`ArtworkView`'s own shape).
        .widgetImage(.artwork, in: style)
    }
}

/// The cover run out over the widget's padding to its top, bottom and leading edges, its leading
/// corners the widget's own.
private struct EdgeBleed: ViewModifier {
    let isOn: Bool
    let padding: CGFloat
    let outer: RectangleCornerRadii

    func body(content: Content) -> some View {
        if isOn {
            content
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: outer.topLeading, bottomLeadingRadius: outer.bottomLeading,
                                                  bottomTrailingRadius: 0, topTrailingRadius: 0, style: .continuous))
                .padding(.vertical, -padding)
                .padding(.leading, -padding)
        } else {
            content
        }
    }
}

/// Clipped to a custom layout's corners for the picture, where it has them.
struct OptionalCornerClip: ViewModifier {
    let corners: RectangleCornerRadii?

    func body(content: Content) -> some View {
        if let corners { content.clipShape(corners: corners) } else { content }
    }
}

/// Nothing playing: opens the player's app.
struct NowPlayingOpenPlayer: View {
    let capsule: Bool

    @Environment(\.widgetStyle) private var style
    @Environment(AppModel.self) private var model

    var body: some View {
        Button("Open Music", systemImage: "arrow.up.forward.app") { model.media.openPlayerApp() }
            .widgetButton(.playbackButtons, in: style)
            .islandButton(capsule ? .capsule : .circle)
            .fixedSize()
    }
}
