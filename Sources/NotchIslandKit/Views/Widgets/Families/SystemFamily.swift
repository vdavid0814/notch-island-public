import SwiftUI

/// The Mac's readings (`SystemSpecs`): each kind to its view, a kind not built yet to its placeholder.
struct SystemFamily: View, WidgetFamilyElements {
    let widget: IslandWidget
    let size: CGSize

    var body: some View {
        switch widget.kind {
        case .systemStats: SystemStatsWidget(widget: widget, size: size)
        case .network, .diskSpace, .uptime:
            SystemReadingSource(kind: widget.kind) { ReadingWidget(widget: widget, size: size, reading: $0) }
        default: WidgetPlaceholder(kind: widget.kind, size: size)
        }
    }

    func demands(_ input: PlanInput) -> [ElementDemand] {
        widget.kind == .systemStats ? input.demands() : ReadingWidget.demands(input)
    }

    func element(_ id: ElementID) -> SystemElement { SystemElement(widget: widget, id: id, widgetSize: size) }
}

/// One element of a system widget on its own (a custom layout): a load as a ring where its
/// rectangle is about square, as a bar where it is wide.
struct SystemElement: View {
    let widget: IslandWidget
    let id: ElementID
    /// The room inside the widget: "Memory" or "RAM", as the stacks word it.
    let widgetSize: CGSize

    @Environment(\.widgetPlan) private var plan
    @Environment(\.widgetStyle) private var style
    @Environment(\.isWidgetPreview) private var isPreview
    @Environment(AppModel.self) private var model

    var body: some View {
        let stats = model.stats
        let room = plan?.elements[id]?.size ?? CGSize(width: 80, height: 20)
        Group {
            switch (widget.kind, id) {
            case (.systemStats, .cpuLoad), (.systemStats, .memoryLoad):
                let isCPU = id == .cpuLoad
                let value = isPreview ? (isCPU ? 0.23 : 0.61) : (isCPU ? stats.cpu : stats.memory)
                let tall = widgetSize.height >= 56
                let itemWidth = !tall && widgetSize.width >= 200 ? widgetSize.width / 2 : widgetSize.width
                let title = isCPU ? "CPU" : itemWidth < 170 ? "RAM" : "Memory"
                if room.width < room.height * 1.6 {
                    StatRing(id: id, title: title, value: value, diameter: min(room.width, room.height))
                } else {
                    // The size the stacks drew it at (kept when it was unlocked), else what its height takes.
                    StatBar(id: id, title: title, value: value,
                            textSize: style.element(id)?.text.points.map { CGFloat($0) }
                                ?? min(max(room.height * 0.42, 7), 13, WidgetType.size(fittingLines: 1, in: room.height)))
                }
            case (.network, _), (.diskSpace, _), (.uptime, _):
                SystemReadingSource(kind: widget.kind) { ReadingElement(id: id, reading: $0) }
            default:
                EmptyView()
            }
        }
        .whileShown { if !isPreview, widget.kind == .systemStats { withoutAnimation { stats.startObserving() } } }
            stop: { if !isPreview, widget.kind == .systemStats { stats.stopObserving() } }
    }
}

/// Processor and memory load, as two rings or two bars, sampled only while the widget is shown
/// (`SystemStatsMonitor`). A picture in Settings shows sample values and reads nothing.
struct SystemStatsWidget: View {
    let widget: IslandWidget
    let size: CGSize

    @Environment(\.widgetFrameProbe) private var probe
    @Environment(\.widgetStyle) private var style
    @Environment(AppModel.self) private var model
    @Environment(\.isWidgetPreview) private var isPreview

    var body: some View {
        let stats = model.stats
        // "RAM" where "Memory" would not fit beside its bar (each bar gets half a wide widget).
        let tall = size.height >= 56
        let itemWidth = !tall && size.width >= 200 ? size.width / 2 : size.width
        let narrow = itemWidth < 170
        let items: [(option: ElementID, title: String, value: Double)] = [
            (.cpuLoad, "CPU", isPreview ? 0.23 : stats.cpu),
            (.memoryLoad, narrow ? "RAM" : "Memory", isPreview ? 0.61 : stats.memory),
        ].filter { widget.shows($0.option) }
        Group {
            if tall {
                // Rings side by side.
                HStack(spacing: 10) {
                    ForEach(items, id: \.option) { item in
                        let room = min(size.height - 4, size.width / CGFloat(max(items.count, 1)) - 10)
                        StatRing(id: item.option, title: item.title, value: item.value,
                                 diameter: WidgetType.fitted(room, fit: room, widget.size(of: item.option), floor: 20))
                            .editorElement(item.option, in: probe)
                    }
                }
            } else {
                // Bars stacked (one row) or side by side (wide).
                let side = size.width >= 200
                let layout = side ? AnyLayout(HStackLayout(spacing: 12)) : AnyLayout(VStackLayout(spacing: 3))
                let rowHeight = side || items.count < 2 ? size.height : (size.height - 3) / 2
                let barWidth = (side ? itemWidth - 12 : size.width) - 8
                layout {
                    ForEach(items, id: \.option) { item in
                        // The name and the value beside a bar of at least 14 pt.
                        let fit = min(WidgetType.size(fittingLines: 1, in: rowHeight),
                                      WidgetType.size(fitting: item.title + "100%", in: barWidth - 12 - 14, weight: .semibold))
                        let textSize = style.textPoints(item.option, auto: WidgetType.fitted(WidgetType.points(rowHeight, ratio: 0.42, min: 8, max: 13),
                                                                                             fit: fit, widget.size(of: item.option), floor: 7),
                                                        fit: fit)
                        StatBar(id: item.option, title: item.title, value: item.value, textSize: textSize)
                            .editorElement(item.option, in: probe,
                                           drawn: .text(TypeSpec(points: textSize, weight: .medium), lines: 1, fit: fit))
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        // No animation on the readings: an ease to every two-second sample kept the open panel
        // redrawing ~50 frames out of every 100 (measured, ~5% CPU). A step is one frame.
        .frame(width: size.width, height: size.height)
        .whileShown { if !isPreview { withoutAnimation { stats.startObserving() } } } stop: { if !isPreview { stats.stopObserving() } }
    }
}

private struct StatRing: View {
    let id: ElementID
    let title: String
    let value: Double
    let diameter: CGFloat

    @Environment(\.widgetStyle) private var style
    @Environment(\.widgetArtworkColor) private var artwork

    var body: some View {
        let ring = ResolvedLine(style.element(id))
        let line = ring.thickness ?? max(3, diameter * 0.1)
        ZStack {
            Circle().stroke(ring.trackStyle(.white.opacity(0.14), artwork: artwork), lineWidth: line)
            Circle()
                .trim(from: 0, to: value)
                .stroke(ring.fillColor(value: value, artwork: artwork) ?? StatTint.color(value),
                        style: StrokeStyle(lineWidth: line, lineCap: ring.cap?.lineCap ?? .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(IslandFormat.percent(value))
                    .font(.system(size: diameter * 0.22, weight: .semibold, design: .rounded).monospacedDigit())
                    .transaction { $0.animation = nil }
                Text(title)
                    .font(.system(size: diameter * 0.14, weight: .medium))
                    .foregroundStyle(.secondary)
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

private struct StatBar: View {
    let id: ElementID
    let title: String
    let value: Double
    let textSize: CGFloat

    @Environment(\.widgetStyle) private var style
    @Environment(\.widgetArtworkColor) private var artwork

    var body: some View {
        let bar = ResolvedLine(style.element(id))
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: textSize, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize()
                .frame(minWidth: textSize * 2.2, alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    bar.barShape(height: proxy.size.height).fill(bar.trackStyle(.white.opacity(0.14), artwork: artwork))
                    bar.barShape(height: proxy.size.height).fill(bar.fillColor(value: value, artwork: artwork) ?? StatTint.color(value))
                        .frame(width: max(proxy.size.height, proxy.size.width * value))
                }
            }
            .frame(height: bar.thickness ?? max(4, textSize * 0.45))
            Text(IslandFormat.percent(value))
                .font(.system(size: textSize, weight: .semibold).monospacedDigit())
                .frame(minWidth: textSize * 2.6, alignment: .trailing)
                .transaction { $0.animation = nil }
        }
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(title) \(IslandFormat.percent(value))"))
    }
}

/// Green while there is headroom, yellow when busy, red when nearly full.
private enum StatTint {
    static func color(_ value: Double) -> Color {
        value < 0.6 ? .green : value < 0.85 ? .yellow : .red
    }
}
