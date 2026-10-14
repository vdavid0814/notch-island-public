import SwiftUI

/// Processor, graphics and memory load (the graphics switched on by hand), as lines (a row tall),
/// rings (two rows) or — two rows tall and wide enough, as large as the timer — a graph of them made
/// as Fan Control's (`LoadGraph`): as far back as its ruler (or Settings) sets it, the percentages
/// the look sets dotted across it. Switched on, Dials draws the loads as Fan Control's dials beside
/// it (`ReadingDial`): the processor's and the graphics processor's in percent, memory's in
/// gigabytes. Sampled only while the widget is shown (`SystemStatsMonitor`). A picture in Settings
/// shows sample values and reads nothing.
struct SystemStatsWidget: View {
    let widget: IslandWidget
    let size: CGSize

    @Environment(AppModel.self) private var model
    @Environment(\.isWidgetPreview) private var isPreview
    @Environment(\.widgetRenderMode) private var renderMode
    @Environment(\.reportsProgressParts) private var reportsParts

    /// What the monitor was asked for while shown: given back the same.
    @State private var observed: SystemStatsMonitor.Needs?

    /// The loads, in the order they are drawn.
    static let loads: [ElementID] = [.cpuLoad, .gpuLoad, .memoryLoad]

    /// The pictures' loads.
    static func sample(_ load: ElementID) -> Double {
        switch load {
        case .gpuLoad: 0.41
        case .memoryLoad: 0.61
        default: 0.23
        }
    }

    /// A load's name in a line, a ring, a dial and the graph's key.
    static func title(_ load: ElementID, narrow: Bool = true) -> String {
        switch load {
        case .gpuLoad: "GPU"
        case .memoryLoad: narrow ? "RAM" : "Memory"
        default: "CPU"
        }
    }

    /// A load's name and value as texts styled on their own (`ProgressLook.Part`).
    static func titleID(_ load: ElementID) -> ElementID {
        switch load {
        case .gpuLoad: .gpuTitle
        case .memoryLoad: .memoryTitle
        default: .cpuTitle
        }
    }

    static func valueID(_ load: ElementID) -> ElementID {
        switch load {
        case .gpuLoad: .gpuValue
        case .memoryLoad: .memoryValue
        default: .cpuValue
        }
    }

    // MARK: Layout

    /// What it draws at a size: lines, rings, or the large view — the dials' row (with their
    /// diameter) and the graph (with its width) after it.
    struct Layout: Equatable {
        enum Style: Equatable { case bars, rings, large }

        var style: Style
        var dial: CGFloat = 0
        var gap: CGFloat = 0
        var dials: [ElementID] = []
        var graphWidth: CGFloat = 0

        var showsGraph: Bool { graphWidth > 0 }

        /// From this tall, rings or the large view; lines under it.
        static let tallHeight: CGFloat = 56
        /// A graph narrower than this is not drawn (four columns have room for it, three not).
        static let minimumGraph: CGFloat = 150
    }

    static func layout(_ widget: IslandWidget, inner: CGSize) -> Layout {
        let loads = Self.loads.filter(widget.shows)
        guard inner.height >= Layout.tallHeight else { return Layout(style: .bars) }
        guard !loads.isEmpty else { return Layout(style: .rings) }
        // The dials as Fan Control's: a little inside the height, all of them in the width.
        let gap = min(max(inner.height * 0.12, 6), 14)
        var dial: CGFloat = 0, used: CGFloat = 0
        let dials = widget.shows(.statsDials) ? loads : []
        if !dials.isEmpty {
            let count = CGFloat(dials.count)
            dial = max(min(inner.height * 0.94, (inner.width - gap * (count - 1)) / count), 16)
            used = dial * count + gap * (count - 1) + gap
        }
        let room = inner.width - used
        let graph = widget.shows(.statsGraph) && room >= Layout.minimumGraph ? room : 0
        guard !dials.isEmpty || graph > 0 else { return Layout(style: .rings) }
        return Layout(style: .large, dial: dial, gap: gap, dials: dials, graphWidth: graph)
    }

    /// Which of its layouts it uses (`IslandWidgetView.layout(of:inner:)`): parts moved at one are
    /// not taken along to another.
    static func layoutIndex(_ widget: IslandWidget, inner: CGSize) -> Int {
        let layout = layout(widget, inner: inner)
        return switch layout.style {
        case .rings: 0
        case .bars: barsSide(widget, inner: inner) ? 1 : 2
        case .large: 3 + (layout.dials.isEmpty ? 0 : 1) + (layout.showsGraph ? 2 : 0)
        }
    }

    /// Whether `element` has room at this size (one switched on that has none is not drawn).
    static func hasRoom(for element: ElementID, in widget: IslandWidget, inner: CGSize) -> Bool {
        switch element {
        case .statsGraph:
            var shown = widget
            shown.options.insert(.statsGraph)
            return layout(shown, inner: inner).showsGraph
        case .statsDials: return inner.height >= Layout.tallHeight
        default: return true
        }
    }

    /// `load` is drawn as a dial where the widget is tall enough for rings (Dials switched on).
    static func drawsDials(_ load: ElementID, in widget: IslandWidget) -> Bool {
        loads.contains(load) && widget.kind == .systemStats && widget.shows(.statsDials)
    }

    /// The lines side by side (a row, wide enough for each) rather than one over another.
    static func barsSide(_ widget: IslandWidget, inner: CGSize) -> Bool {
        inner.width >= 100 * CGFloat(max(loads.filter(widget.shows).count, 2))
    }

    /// The rows' type size, as the widget sets it inside `inner`.
    static func barTextSize(_ widget: IslandWidget, inner: CGSize) -> CGFloat {
        let count = loads.filter { widget.shows($0) }.count
        let spacing = barSpacing(count: count)
        let rowHeight = barsSide(widget, inner: inner) || count < 2 ? inner.height : (inner.height - spacing * CGFloat(count - 1)) / CGFloat(count)
        // Three rows in one a row tall: smaller still, so they fit inside it.
        return WidgetMetrics.points(rowHeight, ratio: count > 2 ? 0.8 : 0.42, min: count > 2 ? 7 : 8, max: 13)
    }

    /// Between rows one over another: three closer together than two.
    static func barSpacing(count: Int) -> CGFloat { count > 2 ? 1 : 3 }

    // MARK: Body

    var body: some View {
        let picture = isPreview || renderMode == .canvas
        let layout = Self.layout(widget, inner: size)
        let needs: SystemStatsMonitor.Needs = [widget.shows(.gpuLoad) ? .gpu : [], layout.showsGraph ? .graph : []]
        Group {
            switch layout.style {
            case .large: large(layout, picture: picture)
            case .rings: rings
            case .bars: bars
            }
        }
        // No animation on the readings: an ease to every two-second sample kept the open panel
        // redrawing ~50 frames out of every 100 (measured, ~5% CPU). A step is one frame.
        .frame(width: size.width, height: size.height, alignment: layout.showsGraph ? .leading : .center)
        .whileShown { if !picture { withoutAnimation { observe(needs) } } } stop: { if !picture { unobserve() } }
        .onChange(of: needs) { _, needs in
            guard observed != nil else { return }
            unobserve()
            withoutAnimation { observe(needs) }
        }
    }

    private func observe(_ needs: SystemStatsMonitor.Needs) {
        observed = needs
        model.stats.startObserving(needs)
        if needs.contains(.graph) { model.stats.keepHistory(gpu: needs.contains(.gpu)) }
    }

    private func unobserve() {
        guard let observed else { return }
        model.stats.stopObserving(observed)
        self.observed = nil
    }

    private func value(_ load: ElementID) -> Double {
        if isPreview { return Self.sample(load) }
        return switch load {
        case .gpuLoad: model.stats.gpu ?? 0
        case .memoryLoad: model.stats.memory
        default: model.stats.cpu
        }
    }

    /// The dials' row and the graph after it.
    private func large(_ layout: Layout, picture: Bool) -> some View {
        HStack(spacing: layout.gap) {
            ForEach(layout.dials, id: \.self) { load in
                LoadDialPart(widget: widget, load: load, diameter: layout.dial, picture: picture)
                    .frame(width: layout.dial, height: layout.dial)
                    .movableElement(load, of: widget)
            }
            if layout.showsGraph {
                // The graph, as large as Customize resized it (from its top-leading corner), its lines as thin.
                let scale = widget.scale(of: .statsGraph)
                let drawn = CGSize(width: layout.graphWidth * scale.x, height: size.height * scale.y)
                LoadGraphPart(widget: widget, picture: picture, size: drawn)
                    .frame(width: drawn.width, height: drawn.height)
                    .frame(width: layout.graphWidth, height: size.height, alignment: .topLeading)
                    .movableElement(.statsGraph, of: widget, drawsScale: false)
            }
        }
    }

    private var rings: some View {
        let items = Self.loads.filter(widget.shows)
        return HStack(spacing: 10) {
            ForEach(items, id: \.self) { load in
                StatRing(title: Self.title(load), value: value(load),
                         diameter: min(size.height - 4, size.width / CGFloat(max(items.count, 1)) - 10) * 0.86,
                         look: widget.progressLook(of: load), reportsFrame: reportsParts,
                         titleStyle: widget.textStyles[Self.titleID(load)], valueStyle: widget.textStyles[Self.valueID(load)])
                    .movableElement(load, of: widget)
            }
        }
    }

    private var bars: some View {
        let items = Self.loads.filter(widget.shows)
        // Side by side when wide: each bar gets its share.
        let side = Self.barsSide(widget, inner: size)
        // "RAM" where "Memory" would not fit beside its bar.
        let narrow = (side ? size.width / CGFloat(max(items.count, 1)) : size.width) < 170
        let textSize = Self.barTextSize(widget, inner: size)
        // As wide as the widest title, so the lines start under one another.
        let titleWidth = items.map { ((Self.title($0, narrow: narrow) as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: textSize, weight: .medium)])).width.rounded(.up) }
            .max() ?? 0
        let layout = side ? AnyLayout(HStackLayout(spacing: 12)) : AnyLayout(VStackLayout(spacing: Self.barSpacing(count: items.count)))
        return layout {
            ForEach(items, id: \.self) { load in
                StatBar(line: load, title: Self.title(load, narrow: narrow), value: value(load), textSize: textSize, titleWidth: titleWidth,
                        look: widget.progressLook(of: load), reportsFrame: reportsParts,
                        titleStyle: widget.textStyles[Self.titleID(load)], valueStyle: widget.textStyles[Self.valueID(load)])
                    .movableElement(load, of: widget)
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: Pictures

    /// Ten minutes of a Mac given some work, for the pictures: a reading every five seconds up to
    /// `now`, ending at the sample loads.
    static func sampleHistory(now: Date) -> [ElementID: [SensorSample]] {
        func ease(_ a: Double, _ b: Double, _ t: Double) -> Double {
            let x = min(max((t - a) / (b - a), 0), 1)
            return x * x * (3 - 2 * x)
        }
        var history: [ElementID: [SensorSample]] = [:]
        for step in 0...120 {
            let t = Double(step) / 120
            let date = now.addingTimeInterval(-SystemStatsMonitor.window * (1 - t))
            let cpu = 0.12 + 0.5 * ease(0.38, 0.46, t) - 0.39 * ease(0.62, 0.9, t) + 0.04 * sin(t * 47)
            let gpu = 0.08 + 0.55 * ease(0.4, 0.5, t) - 0.22 * ease(0.66, 0.95, t) + 0.03 * sin(t * 31 + 1)
            let memory = 0.52 + 0.12 * ease(0.38, 0.55, t) - 0.03 * ease(0.8, 1, t)
            history[.cpuLoad, default: []].append(SensorSample(date: date, value: cpu))
            history[.gpuLoad, default: []].append(SensorSample(date: date, value: gpu))
            history[.memoryLoad, default: []].append(SensorSample(date: date, value: memory))
        }
        return history
    }

    // MARK: Texts

    /// "23": a load in whole percent.
    static func percentNumber(_ fraction: Double) -> String { "\(Int((min(max(fraction, 0), 1) * 100).rounded()))" }

    /// "16.12": gigabytes (as Activity Monitor counts them) to two decimals, in the locale's way.
    static func gigabytes(_ bytes: UInt64, locale: Locale = .current) -> String {
        (Double(bytes) / 1_073_741_824).formatted(.number.precision(.fractionLength(2)).locale(locale))
    }

    /// A load's word over its dial: idle, light, busy, heavy.
    static func word(_ fraction: Double) -> String {
        fraction < 0.1 ? String(localized: "Idle") : fraction < 0.6 ? String(localized: "Light")
            : fraction < 0.85 ? String(localized: "Busy") : String(localized: "Heavy")
    }

    /// Memory's word: of how much there is ("of 16 GB").
    static func memoryWord(physical: UInt64) -> String {
        String(localized: "of \(Int((Double(physical) / 1_073_741_824).rounded())) GB")
    }
}

/// One load as a dial, made as Fan Control's chip dial is (`ReadingDial`): the processor's and the
/// graphics processor's in percent under their word, memory's in gigabytes under how much there
/// is; each tinted by its load (green, yellow, red).
struct LoadDial: View {
    let load: ElementID
    /// 0…1; nil before the first reading.
    let fraction: Double?
    /// Memory's in bytes (nil: not read yet).
    var bytes: UInt64?
    var physical: UInt64 = ProcessInfo.processInfo.physicalMemory
    let diameter: CGFloat
    var look: ProgressLook = .plain
    var nameStyle: TextStyle?
    var valueStyle: TextStyle?
    var reportsFrame = false
    var isLive = false

    @Environment(\.locale) private var locale

    var body: some View {
        let memory = load == .memoryLoad
        let number = memory ? bytes.map { SystemStatsWidget.gigabytes($0, locale: locale) } : fraction.map(SystemStatsWidget.percentNumber)
        let unit = memory ? " GB" : "%"
        let name = SystemStatsWidget.title(load)
        ReadingDial(fraction: fraction, diameter: diameter, number: number, unit: unit, unitScale: memory ? 0.45 : 0.5,
                    word: memory ? SystemStatsWidget.memoryWord(physical: physical) : fraction.map(SystemStatsWidget.word),
                    name: name, look: look, nameStyle: nameStyle, valueStyle: valueStyle, reportsFrame: reportsFrame, isLive: isLive,
                    accessibilityLabel: "\(name) \(number ?? "—")\(unit)")
    }
}

/// A load's dial with the load as it is now (or a picture's).
private struct LoadDialPart: View {
    let widget: IslandWidget
    let load: ElementID
    let diameter: CGFloat
    let picture: Bool

    @Environment(AppModel.self) private var model
    @Environment(\.reportsProgressParts) private var reportsParts

    var body: some View {
        let stats = model.stats
        let live: Double? = switch load {
        case .gpuLoad: stats.gpu
        case .memoryLoad: stats.memoryBytes == nil ? nil : stats.memory
        default: stats.cpu
        }
        let fraction = picture ? SystemStatsWidget.sample(load) : live
        let bytes = picture ? UInt64(Double(stats.physicalMemory) * SystemStatsWidget.sample(.memoryLoad)) : stats.memoryBytes
        LoadDial(load: load, fraction: fraction, bytes: bytes, physical: stats.physicalMemory, diameter: diameter,
                 look: widget.progressLook(of: load), nameStyle: widget.textStyles[SystemStatsWidget.titleID(load)],
                 valueStyle: widget.textStyles[SystemStatsWidget.valueID(load)], reportsFrame: reportsParts, isLive: !picture)
    }
}

/// The loads' graph, as far back as the widget is set to — or, unfolded by a click on its time, the
/// timer's ruler setting that (`FanHistorySetter`, as Fan Control's graph).
private struct LoadGraphPart: View {
    let widget: IslandWidget
    let picture: Bool
    let size: CGSize

    @Environment(AppModel.self) private var model
    @Environment(\.widgetDate) private var fixedDate

    @State private var isSetting = false
    @State private var draft = WidgetConfig.secondsRange.upperBound

    var body: some View {
        ZStack(alignment: .top) {
            if isSetting {
                FanHistorySetter(seconds: $draft, size: size, done: fold)
                    .transition(.move(edge: .top).combined(with: .opacity))
            } else {
                graph
                    .transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .clipped()
        // Away before Done (the island closed): what was set stays.
        .onDisappear { if isSetting { commit() } }
    }

    private var graph: some View {
        let now = fixedDate ?? .now
        let look = widget.chartLook(of: .statsGraph)
        let stats = model.stats
        let history = picture ? SystemStatsWidget.sampleHistory(now: now)
            : [.cpuLoad: stats.cpuHistory, .gpuLoad: stats.gpuHistory, .memoryLoad: stats.memoryHistory]
        let series = SystemStatsWidget.loads.filter(widget.shows).map { load in
            LoadGraph.Series(id: load, name: SystemStatsWidget.title(load), samples: history[load] ?? [],
                             tint: LoadGraph.tint(of: load, look: look, model: model))
        }
        return LoadGraph(series: series, now: now, window: TimeInterval(FanControlWidget.seconds(widget)), percentages: look.percentages,
                         corners: look.corners, size: size, textStyle: widget.textStyles[.statsGraphText],
                         setHistory: picture ? nil : { unfold() })
    }

    private func unfold() {
        draft = FanControlWidget.seconds(widget)
        withAnimation(Motion.content) { isSetting = true }
    }

    private func fold() {
        commit()
        withAnimation(Motion.content) { isSetting = false }
    }

    private func commit() {
        let seconds = FanControlWidget.stored(draft)
        guard widget.config.seconds != seconds else { return }
        model.boards.store(containing: widget.id)?.update(widget.id) { $0.config.seconds = seconds }
    }
}

/// One load as a ring with its value and name inside: the ring drawn as the load's line is
/// (`ProgressLook`, in the load's colour unless set), the two texts moved and set as its look and
/// their styles say — the same as beside the line (`StatBar`).
struct StatRing: View {
    let title: String
    let value: Double
    let diameter: CGFloat
    var look: ProgressLook = .plain
    var reportsFrame = false
    var titleStyle: TextStyle?
    var valueStyle: TextStyle?

    @Environment(\.colorScheme) private var scheme

    /// The value's and the name's own sizes in a ring `diameter` wide.
    static func valuePoints(diameter: CGFloat) -> CGFloat { diameter * 0.22 }
    static func titlePoints(diameter: CGFloat) -> CGFloat { diameter * 0.14 }

    var body: some View {
        let line = max(3, diameter * 0.1)
        ZStack {
            // Its line's middle on the ring's edge, as these rings have always been drawn.
            ProgressRing(fraction: value, diameter: max(diameter, 10) + line, line: line, look: look,
                         automaticTrack: scheme == .light ? .black.opacity(0.14) : .white.opacity(0.14),
                         automaticFill: AnyShapeStyle(StatTint.color(value)),
                         reportsFrame: reportsFrame)
                .frame(width: max(diameter, 10), height: max(diameter, 10))
            VStack(spacing: 0) {
                RingText(text: Text(IslandFormat.percent(value)), style: valueStyle, size: Self.valuePoints(diameter: diameter),
                         weight: .semibold, design: .rounded, automatic: AnyShapeStyle(.primary), part: .remaining, look: look,
                         reportsFrame: reportsFrame, limit: RingText.valueLimit(diameter: diameter, line: line))
                    .transaction { $0.animation = nil }
                RingText(text: Text(title), style: titleStyle, size: Self.titlePoints(diameter: diameter), part: .elapsed, look: look,
                         reportsFrame: reportsFrame, limit: RingText.valueLimit(diameter: diameter, line: line))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(line * 1.5)
        }
        .frame(width: max(diameter, 10), height: max(diameter, 10))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(title) \(IslandFormat.percent(value))"))
    }
}

/// One load as a line between its name and its value; the line drawn as Now Playing's is
/// (`ProgressLook`, in the load's colour unless set), the name and value moved and set as its look
/// and their text styles say.
struct StatBar: View {
    let line: ElementID
    let title: String
    let value: Double
    let textSize: CGFloat
    let titleWidth: CGFloat
    let look: ProgressLook
    let reportsFrame: Bool
    var titleStyle: TextStyle?
    var valueStyle: TextStyle?

    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 6) {
            styled(Text(title), titleStyle, weight: .medium, part: .elapsed)
                .frame(width: max(titleWidth, textSize * 2.2), alignment: .leading)
            ScrubTrack(position: value, duration: 1, look: look, reportsFrame: reportsFrame, drawsOnLayer: false,
                       automaticFill: StatTint.color(value), isAdjustable: false) { _ in } commit: {}
            styled(Text(IslandFormat.percent(value)).monospacedDigit(), valueStyle, weight: .semibold, part: .remaining)
                .frame(minWidth: textSize * 2.6, alignment: .trailing)
                .transaction { $0.animation = nil }
        }
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(title) \(IslandFormat.percent(value))"))
    }

    /// A text in its style (or as the row sets it), moved as the look says.
    @ViewBuilder private func styled(_ text: some View, _ style: TextStyle?, weight: NSFont.Weight,
                                     part: ProgressLook.Part) -> some View {
        let offset = look.offset(of: part)
        Group {
            if let style {
                text
                    .font(Font(style.font(size: textSize, weight: weight)))
                    .underline(style.isUnderlined)
                    .strikethrough(style.isStruckThrough)
                    .foregroundStyle(color(style.color, part: part))
            } else {
                text
                    .font(.system(size: textSize, weight: weight == .medium ? .medium : .semibold))
                    .foregroundStyle(color(.automatic, part: part))
            }
        }
        .fixedSize()
        .reportsProgressPart(part, if: reportsFrame)
        .offset(x: offset.x, y: offset.y)
    }

    /// Automatic: the name dimmer, the value bright. Artwork: the cover's, as on every other text.
    private func color(_ color: TextStyle.TextColor, part: ProgressLook.Part) -> AnyShapeStyle {
        switch color {
        case .automatic: part == .elapsed ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary)
        case .custom(let rgb): AnyShapeStyle(rgb.color)
        case .artwork: AnyShapeStyle(model.media.artworkColor.map { Color($0) } ?? .islandAccent)
        }
    }
}

/// Green while there is headroom, yellow when busy, red when nearly full.
private enum StatTint {
    static func color(_ value: Double) -> Color {
        value < 0.6 ? .green : value < 0.85 ? .yellow : .red
    }
}
