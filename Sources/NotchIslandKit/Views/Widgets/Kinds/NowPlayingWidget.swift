import SwiftUI

/// Now Playing:
///
/// - **One row tall**: one line — a small cover, the title (and artist when there is room), the
///   buttons.
/// - **Taller**: the cover beside a column of title, artist, progress and buttons.
///
/// Every part can be moved in Customize (`movableElement`): it is drawn that far from its place,
/// the others stay where they are.
struct NowPlayingWidget: View {
    let widget: IslandWidget
    let size: CGSize
    /// The whole widget's outline (its padding included): a cover grown to its edges or over it is
    /// cut to it.
    var outline: WidgetShape?

    @Environment(AppModel.self) private var model
    @Environment(\.widgetRenderMode) private var renderMode
    @Environment(\.isElementEditing) private var isEditing

    var body: some View {
        let media = model.media
        // In the editor, a track even while none plays: every part is there to be moved.
        let item = media.item ?? (isEditing ? Self.sample : nil)
        Group {
            if size.height < WidgetMetrics.singleRowHeight {
                minimal(media, item)
            } else {
                beside(media, item)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .leading)
        .whileShown { if renderMode == .live { withoutAnimation { media.refreshPosition() } } }
    }

    // The cover as tall as the widget, giving way when the text would be squeezed (it needs 110 pt).
    private func beside(_ media: MediaController, _ item: NowPlayingItem?) -> some View {
        HStack(spacing: size.height >= 90 ? Metrics.Spacing.large : Metrics.Spacing.medium) {
            if widget.shows(.artwork), Self.hasRoom(for: .artwork, inner: size) {
                artwork
            }
            VStack(alignment: .leading, spacing: 0) {
                titles(item, room: size.height, oneLine: size.height < 70)
                    .elementGroup(Self.titleParts, of: widget)
                Spacer(minLength: Metrics.Spacing.xSmall)
                // The progress line from 84 pt.
                if widget.shows(.progress), Self.hasRoom(for: .progress, inner: size), let item {
                    let line = widget.progressLook(of: .progress)
                    PlaybackScrubber(clock: media.clock, duration: item.duration, isPlaying: media.isPlaying, look: line,
                                     elapsedStyle: widget.textStyles[.elapsedTime], remainingStyle: widget.textStyles[.remainingTime])
                        .movableElement(.progress, of: widget)
                }
                controls(media, item)
                    .frame(maxWidth: .infinity)
                    .padding(.top, Metrics.Spacing.xSmall)
                    .elementGroup(Self.buttonParts, of: widget)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .elementGroup(Self.titleParts + [.progress] + Self.buttonParts, of: widget)
        }
    }

    /// The cover as tall as the widget's inside, sized, moved and as see-through as Customize set it;
    /// grown to the edges or over the widget, cut to its outline.
    private var artwork: some View {
        let look = widget.imageLook(of: .artwork)
        let padding = WidgetMetrics.padding(for: widget)
        let reaches = look.fit != .own || Self.artworkReachesPast(widget, inner: size, padding: padding)
        return NowPlayingArtwork(side: size.height, isGrown: reaches)
            .opacity(look.opacity)
            .movableElement(.artwork, of: widget)
            // The cover is laid out at the inside's corner, `padding` in from the widget's.
            .clipped(to: reaches ? outline : nil, from: CGPoint(x: -padding, y: -padding))
    }

    /// Whether the cover, sized and moved, reaches past the widget's edges (one grown over it and
    /// then moved by hand, at its own size since): cut to the widget's outline then, and only then.
    static func artworkReachesPast(_ widget: IslandWidget, inner: CGSize, padding: CGFloat) -> Bool {
        let scale = widget.scale(of: .artwork), offset = widget.offset(of: .artwork)
        // From its layout box at the inside's corner (`ElementScale.applied`), then moved.
        let drawn = CGRect(x: offset.x, y: offset.y, width: inner.height * scale.x, height: inner.height * scale.y)
        let whole = CGRect(x: -padding, y: -padding, width: inner.width + 2 * padding, height: inner.height + 2 * padding)
        return !whole.insetBy(dx: -0.5, dy: -0.5).contains(drawn)
    }

    /// What has room at this size inside: the cover beside the texts while they keep 110 pt (on one
    /// row, from a widget 150 pt wide), the playback line from 84 pt tall (never on one row),
    /// previous and next from 170 pt wide. The rest always.
    static func hasRoom(for element: ElementID, inner: CGSize) -> Bool {
        let oneRow = inner.height < WidgetMetrics.singleRowHeight
        switch element {
        case .artwork: return oneRow ? inner.width >= 150 : inner.width - inner.height >= 110
        case .progress: return !oneRow && inner.height >= 84
        case .skipButtons, .previousButton, .nextButton: return inner.width >= 170
        default: return true
        }
    }

    /// How wide the texts' column is beside the cover (all of the inside where it has no room).
    static func textColumnWidth(_ widget: IslandWidget, inner: CGSize) -> CGFloat {
        guard widget.shows(.artwork), hasRoom(for: .artwork, inner: inner) else { return inner.width }
        let spacing = inner.height >= 90 ? Metrics.Spacing.large : Metrics.Spacing.medium
        return max(0, inner.width - inner.height - spacing)
    }

    /// The cover grown in its shape (`ImageLook.Fit`): to the widget's edges — as tall (or wide)
    /// as the widget, from its leading edge — or over all of it, centred; as its scale and offset.
    /// In both layouts the cover is laid out as tall as the widget's inside (`inner`), at its
    /// top-leading corner, `padding` in from the widget's edges.
    static func placingArtwork(_ widget: IslandWidget, inner: CGSize, padding: CGFloat) -> IslandWidget {
        let fit = widget.imageLook(of: .artwork).fit
        guard fit != .own, inner.height > 0 else { return widget }
        let whole = CGSize(width: inner.width + 2 * padding, height: inner.height + 2 * padding)
        let side = fit == .edges ? min(whole.width, whole.height) : max(whole.width, whole.height)
        // From the cover's own corner, in the widget's inner points.
        let x = fit == .edges ? -padding : -padding + (whole.width - side) / 2
        let y = -padding + (whole.height - side) / 2
        var placed = widget
        let scale = Double(side / inner.height)
        placed.scales[.artwork] = ElementScale(x: scale, y: scale)
        placed.offsets[.artwork] = ElementOffset(x: Double(x), y: Double(y))
        return placed
    }

    private func minimal(_ media: MediaController, _ item: NowPlayingItem?) -> some View {
        HStack(spacing: Metrics.Spacing.medium) {
            if widget.shows(.artwork), Self.hasRoom(for: .artwork, inner: size) {
                artwork
            }
            titles(item, room: size.height * 2.4, oneLine: size.height < 34)
                .frame(maxWidth: .infinity, alignment: .leading)
                .elementGroup(Self.titleParts, of: widget)
            controls(media, item)
                .elementGroup(Self.buttonParts, of: widget)
        }
    }

    /// Title over artist, sized from the room, one line each (shrinking a little before they are
    /// cut). On one line, the artist joins the title's line while both fit, and gives way first.
    /// Either may be restyled in Customize (`WidgetLabel`).
    @ViewBuilder private func titles(_ item: NowPlayingItem?, room: CGFloat, oneLine: Bool) -> some View {
        let showsTitle = widget.shows(.trackInfo), showsArtist = widget.shows(.artist)
        let titleSize = Self.titleSize(room: room), artistSize = Self.artistSize(room: room)
        let title = Text(Self.title(item)).font(.system(size: titleSize, weight: .semibold))
        let artist = Text(Self.subtitle(item)).font(.system(size: artistSize)).foregroundStyle(.secondary)
        if oneLine {
            ViewThatFits(in: .horizontal) {
                if showsTitle, showsArtist {
                    // Two texts on one baseline, a space apart, so each moves by itself.
                    HStack(alignment: .firstTextBaseline, spacing: Metrics.Spacing.small) {
                        titleLabel(item, titleSize, title.lineLimit(1).fixedSize())
                        artistLabel(item, artistSize, artist.lineLimit(1).fixedSize())
                    }
                }
                if showsTitle {
                    titleLabel(item, titleSize, title.lineLimit(1).minimumScaleFactor(0.75))
                } else if showsArtist {
                    artistLabel(item, artistSize, artist.lineLimit(1).minimumScaleFactor(0.75))
                }
            }
        } else {
            VStack(alignment: .leading, spacing: Metrics.Spacing.xxSmall) {
                if showsTitle { titleLabel(item, titleSize, title.lineLimit(1).minimumScaleFactor(0.75)) }
                if showsArtist {
                    // Nothing playing: the hint may take two lines rather than end in "…".
                    artistLabel(item, artistSize, artist
                        .lineLimit(item == nil ? 2 : 1)
                        .minimumScaleFactor(0.85)
                        .fixedSize(horizontal: false, vertical: item == nil))
                }
            }
        }
    }

    private func titleLabel(_ item: NowPlayingItem?, _ size: CGFloat, _ plain: some View) -> some View {
        WidgetLabel(id: .trackInfo, text: Self.title(item), widget: widget, size: size, weight: .semibold,
                    isSecondary: false) { plain }
            .movableElement(.trackInfo, of: widget)
    }

    private func artistLabel(_ item: NowPlayingItem?, _ size: CGFloat, _ plain: some View) -> some View {
        WidgetLabel(id: .artist, text: Self.subtitle(item), widget: widget, size: size, weight: .regular,
                    isSecondary: true) { plain }
            .movableElement(.artist, of: widget)
    }

    /// Back, previous, play or pause, next, forward — or, while nothing plays, a button that opens
    /// the player.
    @ViewBuilder private func controls(_ media: MediaController, _ item: NowPlayingItem?) -> some View {
        let row = Self.controlRow(widget, inner: size)
        let points = row.points
        let seconds = widget.effectiveSeekSeconds
        HStack(spacing: points) {
            if item != nil {
                if row.showsSeek {
                    NowPlayingButton(title: "Back \(seconds) Seconds", symbol: Self.seekSymbol(back: true, seconds: seconds),
                                     points: points, look: widget.buttonLook(of: .seekBackButton)) { media.skip(by: -Double(seconds)) }
                        .movableElement(.seekBackButton, of: widget)
                }
                // Previous and next from 170 pt.
                if widget.shows(.skipButtons), Self.hasRoom(for: .skipButtons, inner: size) {
                    NowPlayingButton(title: "Previous", symbol: "backward.fill", points: points,
                                     look: widget.buttonLook(of: .previousButton)) { media.send(.previous) }
                        .movableElement(.previousButton, of: widget)
                }
                if widget.shows(.playbackButtons) {
                    // As wide as the wider of play and pause, whichever it shows: the two differ by a
                    // point, and the buttons beside it moved with every toggle.
                    SteadyRoom(symbols: ["play.fill", "pause.fill"], points: points) {
                        NowPlayingButton(title: media.isPlaying ? "Pause" : "Play", symbol: media.isPlaying ? "pause.fill" : "play.fill",
                                         points: points, look: widget.buttonLook(of: .playbackButtons)) { media.send(.togglePlayPause) }
                    }
                    .movableElement(.playbackButtons, of: widget)
                }
                if widget.shows(.skipButtons), Self.hasRoom(for: .skipButtons, inner: size) {
                    NowPlayingButton(title: "Next", symbol: "forward.fill", points: points,
                                     look: widget.buttonLook(of: .nextButton)) { media.send(.next) }
                        .movableElement(.nextButton, of: widget)
                }
                if row.showsSeek {
                    NowPlayingButton(title: "Forward \(seconds) Seconds", symbol: Self.seekSymbol(back: false, seconds: seconds),
                                     points: points, look: widget.buttonLook(of: .seekForwardButton)) { media.skip(by: Double(seconds)) }
                        .movableElement(.seekForwardButton, of: widget)
                }
            } else if size.width >= 150 {
                // Where play and pause will be.
                NowPlayingButton(title: "Open Music", symbol: "arrow.up.forward.app", points: points,
                                 look: widget.buttonLook(of: .playbackButtons)) { media.openPlayerApp() }
                    .movableElement(.playbackButtons, of: widget)
            }
        }
        .fixedSize()
    }

    /// The parts in the column of titles, and in the row of buttons (each drawn over or under the
    /// rest as a group).
    static let titleParts: [ElementID] = [.trackInfo, .artist]
    static let buttonParts: [ElementID] = [.seekBackButton, .previousButton, .playbackButtons, .nextButton, .seekForwardButton]

    /// The system symbol of a jump back or forward by `seconds` (one of `IslandWidget.seekChoices`).
    static func seekSymbol(back: Bool, seconds: Int) -> String {
        (back ? "gobackward." : "goforward.") + String(seconds)
    }

    /// The row of buttons: its symbol size, and whether back and forward are in it. With them the
    /// buttons are made smaller until all fit their room (the column beside the cover, or on one
    /// row what the title leaves); where they do not fit even at 11 pt, back and forward give way.
    static func controlRow(_ widget: IslandWidget, inner: CGSize) -> (points: CGFloat, showsSeek: Bool) {
        let own = buttonPoints(height: inner.height)
        let oneRow = inner.height < WidgetMetrics.singleRowHeight
        let room: CGFloat
        if oneRow {
            let cover = widget.shows(.artwork) && hasRoom(for: .artwork, inner: inner) ? inner.height + Metrics.Spacing.medium : 0
            // At least this much of the row stays the title's.
            room = inner.width - cover - 90 - Metrics.Spacing.medium
        } else {
            room = textColumnWidth(widget, inner: inner)
        }
        let skips = widget.shows(.skipButtons) && hasRoom(for: .skipButtons, inner: inner) ? 2 : 0
        let shown = CGFloat(skips + (widget.shows(.playbackButtons) ? 1 : 0))
        // The size at which `count` buttons fill the room: a symbol about 1.4 times as wide as its
        // size, the gaps as wide as it.
        func fitting(_ count: CGFloat) -> CGFloat { count > 0 ? room / (count * 1.4 + count - 1) : own }
        if widget.shows(.seekButtons), fitting(shown + 2) >= 11 { return (min(own, fitting(shown + 2)), true) }
        // Under the titles the row never grows wider than the column: wider, it widened the column
        // past the widget's edge, and the line and the times with it.
        guard !oneRow else { return (own, false) }
        return (max(min(own, fitting(shown).rounded(.down)), 9), false)
    }

    /// The buttons' symbol size, sized with the widget (inside `height`): one row tall, smaller.
    static func buttonPoints(height: CGFloat) -> CGFloat { height < WidgetMetrics.singleRowHeight ? 15 : 20 }

    static func titleSize(room: CGFloat) -> CGFloat { WidgetMetrics.points(room, ratio: 0.12, min: 12, max: 20) }
    static func artistSize(room: CGFloat) -> CGFloat { WidgetMetrics.points(room, ratio: 0.1, min: 11, max: 16) }

    /// The size a text part is set at on its own in a widget whose inside is `inner`.
    static func textSize(of id: ElementID, inner: CGSize) -> CGFloat {
        // The times under the line: its callout size.
        if id == .elapsedTime || id == .remainingTime { return 12 }
        let room = inner.height < WidgetMetrics.singleRowHeight ? inner.height * 2.4 : inner.height
        return id == .trackInfo ? titleSize(room: room) : artistSize(room: room)
    }

    /// What the editor shows while nothing plays.
    static let sample = NowPlayingItem(title: String(localized: "Title"), artist: String(localized: "Artist"), album: "",
                                       duration: 210, artworkData: nil, bundleIdentifier: nil)

    static func title(_ item: NowPlayingItem?) -> String {
        guard let item else { return String(localized: "Nothing Playing") }
        return item.title.isEmpty ? String(localized: "Unknown Title") : item.title
    }

    static func subtitle(_ item: NowPlayingItem?) -> String {
        guard let item else { return String(localized: "Music you play appears here.") }
        return item.artist.isEmpty ? item.album : item.artist
    }
}

/// The cover (a click opens the player), or a note while nothing plays.
struct NowPlayingArtwork: View {
    let side: CGFloat
    /// Grown to the widget's edges or over it, and cut to its outline (`ArtworkView.drawsAsPicture`).
    var isGrown = false

    @Environment(AppModel.self) private var model

    var body: some View {
        let media = model.media
        Group {
            if let item = media.item {
                ArtworkView(image: media.artwork, bundleIdentifier: item.bundleIdentifier,
                            minimumRadius: side < 44 ? 6 : Metrics.Expanded.artworkMinimumRadius, drawsAsPicture: isGrown)
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
}

/// A button of Now Playing: its symbol, nothing more — or as Customize set it (`ButtonLook`).
/// Its content in the room the largest of `symbols` takes at `points`, whichever it shows: a button
/// that swaps its symbol (play and pause) keeps its size, and nothing beside it moves.
struct SteadyRoom<Content: View>: View {
    let symbols: [String]
    let points: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            ForEach(symbols, id: \.self) { symbol in
                Image(systemName: symbol).font(.system(size: points)).hidden()
            }
            content
        }
    }
}

struct NowPlayingButton: View {
    let title: String
    let symbol: String
    let points: CGFloat
    var look: ButtonLook = .plain
    let action: () -> Void

    var body: some View {
        if look == .plain {
            Button(title, systemImage: symbol, action: action)
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .font(.system(size: points))
                .help(title)
        } else {
            // The drawn button is the button (`WidgetButtonLabel.action`): its whole shape takes clicks.
            WidgetButtonLabel(look: look, symbol: symbol, points: points, action: action, title: title)
        }
    }
}
