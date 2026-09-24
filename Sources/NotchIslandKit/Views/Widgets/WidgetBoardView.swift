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
}

/// One widget on its plate, laid out for exactly `size`.
struct IslandWidgetView: View {
    let widget: IslandWidget
    let size: CGSize
    let thumbnails: ThumbnailCache

    @Environment(\.controlSize) private var controlSize

    var body: some View {
        let inner = CGSize(
            width: max(0, size.width - 2 * WidgetMetrics.padding),
            height: max(0, size.height - 2 * WidgetMetrics.padding)
        )
        let isSingleRow = inner.height < WidgetMetrics.singleRowHeight
        content(inner)
            .frame(width: inner.width, height: inner.height)
            .controlSize(isSingleRow ? .small : Metrics.Control.smaller(controlSize))
            .padding(WidgetMetrics.padding)
            .frame(width: size.width, height: size.height)
            .background(
                .white.opacity(0.06),
                in: RoundedRectangle(cornerRadius: min(WidgetMetrics.cornerRadius, size.height / 2), style: .continuous)
            )
    }

    @ViewBuilder private func content(_ inner: CGSize) -> some View {
        switch widget.kind {
        case .nowPlaying: NowPlayingWidget(widget: widget, size: inner)
        case .timer: TimerWidget(widget: widget, size: inner)
        case .stopwatch: StopwatchWidget(widget: widget, size: inner)
        case .shelf: ShelfWidget(widget: widget, size: inner, thumbnails: thumbnails)
        case .battery: BatteryWidget(widget: widget, size: inner)
        case .volume: LevelWidget(kind: .volume, widget: widget, size: inner)
        case .brightness: LevelWidget(kind: .brightness, widget: widget, size: inner)
        case .assistant: AssistantWidget(size: inner)
        }
    }
}

// MARK: - Now Playing

struct NowPlayingWidget: View {
    let widget: IslandWidget
    let size: CGSize

    @Environment(AppModel.self) private var model

    var body: some View {
        let media = model.media
        let isSingleRow = size.height < WidgetMetrics.singleRowHeight
        let showsArtwork = widget.shows(.artwork) && size.width >= size.height * 1.8
        HStack(spacing: isSingleRow ? Metrics.Spacing.medium : Metrics.Spacing.large) {
            if showsArtwork {
                Group {
                    if let item = media.item {
                        ArtworkView(
                            image: media.artwork,
                            bundleIdentifier: item.bundleIdentifier,
                            minimumRadius: isSingleRow ? 6 : Metrics.Expanded.artworkMinimumRadius
                        )
                        .onTapGesture { media.openPlayerApp() }
                        .help("Open the player")
                    } else {
                        Image(systemName: "music.note")
                            .font(isSingleRow ? .body : .title)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(.white.opacity(0.06), in: .rect(cornerRadius: isSingleRow ? 6 : 12))
                    }
                }
                .frame(width: size.height, height: size.height)
            }
            if isSingleRow {
                if widget.shows(.trackInfo) {
                    Text(title(media.item))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Spacer(minLength: 0)
                }
                controls(media, compact: true)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    if widget.shows(.trackInfo) {
                        CardTitle(title: title(media.item), subtitle: subtitle(media.item), isLarge: size.height >= 120)
                    }
                    Spacer(minLength: Metrics.Spacing.xSmall)
                    if widget.shows(.progress), size.height >= 80, let item = media.item {
                        PlaybackScrubber(clock: media.clock, duration: item.duration, isPlaying: media.isPlaying)
                    }
                    controls(media, compact: false)
                        .frame(maxWidth: .infinity)
                        .padding(.top, Metrics.Spacing.xSmall)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .onAppear { media.refreshPosition() }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .leading)
    }

    @ViewBuilder private func controls(_ media: MediaController, compact: Bool) -> some View {
        if media.item != nil {
            TransportControls(isPlaying: media.isPlaying, showsSkip: widget.shows(.skipButtons) && size.width >= 150)
        } else {
            Button("Open Music", systemImage: "arrow.up.forward.app") { media.openPlayerApp() }
                .buttonStyle(.islandGlass)
                .labelStyle(.titleAndIcon)
                .frame(maxWidth: compact ? nil : .infinity, alignment: .leading)
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

// MARK: - Timer

/// The iPhone-style timer: a ruler to set the length, one action, and the time in large orange digits.
struct TimerWidget: View {
    let widget: IslandWidget
    let size: CGSize

    @Environment(AppModel.self) private var model

    var body: some View {
        let timers = model.timers
        let rulerHeight: CGFloat = size.height >= 100 ? 44 : 22
        let showsRuler = widget.shows(.ruler) && size.height >= 62
        let rowHeight = showsRuler ? size.height - rulerHeight - 14 - Metrics.Spacing.small : size.height
        VStack(spacing: Metrics.Spacing.small) {
            if showsRuler {
                ruler(timers)
                    .frame(height: rulerHeight + 14)
            }
            HStack(spacing: Metrics.Spacing.medium) {
                actions(timers)
                Spacer(minLength: 0)
                if widget.shows(.readout) {
                    time(timers)
                        .font(.system(size: min(max(rowHeight * 0.8, 15), 44), weight: .regular, design: .rounded)
                            .monospacedDigit())
                        .foregroundStyle(TimerRuler.tint.opacity(timers.countdown.isPaused ? 0.55 : 1))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
            }
            .frame(height: rowHeight)
        }
        .frame(width: size.width, height: size.height)
        .animation(Motion.content, value: timers.countdown)
    }

    @ViewBuilder private func ruler(_ timers: TimerStore) -> some View {
        let showsLabels = size.height >= 100
        switch timers.countdown {
        case .idle:
            TimerRuler(
                minutes: Binding(
                    get: { Int(timers.draftMinutes.rounded()) },
                    set: { timers.draftMinutes = Double($0) }
                ),
                range: 0...Int(TimerStore.draftRange.upperBound),
                showsLabels: showsLabels,
                onInteraction: { model.island.isInteracting = $0 }
            )
            .onChange(of: timers.draftMinutes) { model.haptics.play(.tick) }
        case .running(let endDate, _):
            // Re-read once per remaining minute, on the countdown's own minute boundaries.
            let remaining = max(0, endDate.timeIntervalSinceNow)
            let boundary = endDate.addingTimeInterval(-60 * (remaining / 60).rounded(.up))
            TimelineView(.periodic(from: boundary, by: 60)) { context in
                TimerRuler(
                    minutes: .constant(Self.minutesLeft(timers.countdown, at: context.date)),
                    isEditable: false,
                    showsLabels: showsLabels
                )
            }
        case .paused, .finished:
            TimerRuler(minutes: .constant(Self.minutesLeft(timers.countdown, at: .now)), isEditable: false,
                       showsLabels: showsLabels)
        }
    }

    static func minutesLeft(_ state: CountdownState, at date: Date) -> Int {
        Int(((state.remaining(at: date) ?? 0) / 60).rounded(.up))
    }

    @ViewBuilder private func time(_ timers: TimerStore) -> some View {
        switch timers.countdown {
        case .idle:
            Text(IslandFormat.clock(timers.draftMinutes * 60))
                .contentTransition(.opacity)
                .animation(Motion.content, value: timers.draftMinutes)
        default:
            CountdownReadout(state: timers.countdown)
        }
    }

    @ViewBuilder private func actions(_ timers: TimerStore) -> some View {
        let wide = size.width >= 190
        switch timers.countdown {
        case .idle:
            Button {
                timers.start(minutes: timers.draftMinutes)
            } label: {
                if wide { Text("Start Timer") } else { Label("Start", systemImage: "play.fill") }
            }
            .buttonStyle(TimerActionStyle(iconOnly: !wide))
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
            .buttonStyle(TimerActionStyle(iconOnly: !wide))
            if widget.shows(.addMinute) {
                Button("+1") { timers.add(seconds: 60) }
                    .buttonStyle(.islandGlass(.circle))
                    .help("Add a minute")
            }
            Button {
                timers.cancel()
            } label: {
                Label("Cancel", systemImage: "xmark")
            }
            .buttonStyle(.islandGlass(.circle))
            .help("Cancel the timer")
        case .finished:
            Button {
                timers.acknowledge()
                model.banners.dismiss(.timerFinished)
            } label: {
                if wide { Text("Done") } else { Label("Done", systemImage: "checkmark") }
            }
            .buttonStyle(TimerActionStyle(iconOnly: !wide))
            if widget.shows(.addMinute) {
                Button("+1") {
                    timers.add(seconds: 60)
                    model.banners.dismiss(.timerFinished)
                }
                .buttonStyle(.islandGlass(.circle))
                .help("Add a minute")
            }
        }
    }
}

/// The timer's one action: orange text on orange-tinted glass, like the iPhone's "Start Timer".
struct TimerActionStyle: ButtonStyle {
    var iconOnly = false

    @Environment(\.controlSize) private var controlSize

    func makeBody(configuration: Configuration) -> some View {
        let height = Metrics.Control.height(controlSize)
        configuration.label
            .labelStyle(.iconOnly)
            .font(Metrics.Control.font(controlSize))
            .foregroundStyle(TimerRuler.tint)
            .padding(.horizontal, iconOnly ? 0 : Metrics.Control.horizontalPadding(controlSize) + 2)
            .frame(width: iconOnly ? height : nil, height: height)
            .contentShape(Capsule())
            .glassEffect(.clear.tint(TimerRuler.tint.opacity(configuration.isPressed ? 0.42 : 0.28)).interactive(),
                         in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(IslandGlass.press, value: configuration.isPressed)
    }
}

// MARK: - Stopwatch

struct StopwatchWidget: View {
    let widget: IslandWidget
    let size: CGSize

    @Environment(AppModel.self) private var model

    var body: some View {
        let timers = model.timers
        let running = timers.stopwatch.isRunning
        HStack(spacing: Metrics.Spacing.medium) {
            StopwatchReadout(state: timers.stopwatch)
                .font(.system(size: min(max(size.height * 0.55, 15), 40), weight: .regular, design: .rounded)
                    .monospacedDigit())
                .foregroundStyle(running ? .primary : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, alignment: .leading)
            if widget.shows(.resetButton), timers.isStopwatchActive {
                Button {
                    timers.resetStopwatch()
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.islandGlass(.circle))
                .help("Reset")
            }
            Button {
                running ? timers.pauseStopwatch() : timers.startStopwatch()
            } label: {
                Label(running ? "Pause" : "Start", systemImage: running ? "pause.fill" : "play.fill")
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.islandGlass(.circle, prominent: true))
            .help(running ? "Pause" : "Start")
        }
        .frame(width: size.width, height: size.height)
        .animation(Motion.content, value: timers.stopwatch)
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
        let showsPreviews = widget.shows(.previews) && size.height >= 56 && !items.isEmpty
        VStack(spacing: Metrics.Spacing.small) {
            if showsPreviews {
                let side = min(size.height - 34, 64)
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
                        Text(items.isEmpty ? "Drop files here" : "^[\(items.count) item](inflect: true)")
                            .foregroundStyle(items.isEmpty ? .secondary : .primary)
                            .contentTransition(.opacity)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                            .imageScale(.small)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .font(.subheadline.weight(.medium))
                .help("Open Shelf")
                if widget.shows(.shelfActions), !items.isEmpty, size.width >= 200 {
                    Button {
                        model.shelf.airDrop()
                    } label: {
                        Label("AirDrop", systemImage: "dot.radiowaves.up.forward")
                    }
                    .buttonStyle(.islandGlass(.circle))
                    .help("Send with AirDrop")
                    Button(role: .destructive) {
                        model.shelf.clear()
                    } label: {
                        Label("Clear", systemImage: "xmark")
                    }
                    .buttonStyle(.islandGlass(.circle))
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

    var body: some View {
        let state = model.power.state
        let tall = size.height >= 70
        let layout = tall ? AnyLayout(VStackLayout(spacing: Metrics.Spacing.xSmall)) : AnyLayout(HStackLayout(spacing: Metrics.Spacing.small))
        layout {
            Image(systemName: IslandFormat.batterySymbol(level: state.level, charging: state.isCharging))
                .symbolRenderingMode(state.tint == .low ? .monochrome : .hierarchical)
                .foregroundStyle(state.tint.style)
                .font(tall ? .largeTitle : .title3)
            if widget.shows(.percentage) || widget.shows(.timeRemaining) {
                VStack(alignment: tall ? .center : .leading, spacing: 0) {
                    if widget.shows(.percentage) {
                        Text(state.hasBattery ? IslandFormat.percent(Double(state.level) / 100) : "—")
                            .font((tall ? Font.title3 : .subheadline).weight(.semibold).monospacedDigit())
                            .contentTransition(.opacity)
                    }
                    if widget.shows(.timeRemaining), let text = remaining(state), size.width >= 110 || tall {
                        Text(text)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .animation(Motion.content, value: state.level)
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
        HStack(spacing: Metrics.Spacing.medium) {
            if widget.shows(.levelIcon) {
                LevelSymbol(kind: kind, reading: reading)
                    .frame(width: 20)
            }
            LevelSlider(kind: kind)
            if widget.shows(.levelValue), size.width >= 150 {
                LevelValue(reading: reading)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 34, alignment: .trailing)
            }
        }
        .padding(.horizontal, Metrics.Spacing.xSmall)
        .frame(width: size.width, height: size.height)
    }
}

// MARK: - Siri

/// One button: Siri in the notch (the assistant).
struct AssistantWidget: View {
    let size: CGSize

    @Environment(AppModel.self) private var model

    var body: some View {
        let tall = size.height >= 70
        Button {
            model.perform(.assistant)
        } label: {
            Group {
                if tall {
                    VStack(spacing: Metrics.Spacing.small) {
                        Image(systemName: "siri").font(.system(size: min(size.height * 0.4, 40)))
                        Text("Siri").font(.subheadline.weight(.semibold))
                    }
                } else {
                    Label("Siri", systemImage: "siri")
                        .labelStyle(size.width >= 90 ? AnyLabelStyle(.titleAndIcon) : AnyLabelStyle(.iconOnly))
                        .font(.subheadline.weight(.semibold))
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
