import SwiftUI

/// Processor and memory load, as two rings (two rows tall) or two bars, sampled only while the
/// widget is shown (`SystemStatsMonitor`). A picture in Settings shows sample values and reads
/// nothing.
struct SystemStatsWidget: View {
    let widget: IslandWidget
    let size: CGSize

    @Environment(AppModel.self) private var model
    @Environment(\.isWidgetPreview) private var isPreview
    @Environment(\.reportsProgressParts) private var reportsParts

    /// The rows' type size, as the widget sets it inside `inner`.
    static func barTextSize(_ widget: IslandWidget, inner: CGSize) -> CGFloat {
        let count = [ElementID.cpuLoad, .memoryLoad].filter { widget.shows($0) }.count
        let side = inner.height < 56 && inner.width >= 200
        let rowHeight = side || count < 2 ? inner.height : (inner.height - 3) / 2
        return WidgetMetrics.points(rowHeight, ratio: 0.42, min: 8, max: 13)
    }

    var body: some View {
        let stats = model.stats
        let tall = size.height >= 56
        // Side by side when wide: each bar gets half.
        let side = !tall && size.width >= 200
        // "RAM" where "Memory" would not fit beside its bar.
        let narrow = (side ? size.width / 2 : size.width) < 170
        let items: [(id: ElementID, title: String, value: Double)] = [
            (.cpuLoad, "CPU", isPreview ? 0.23 : stats.cpu),
            (.memoryLoad, narrow ? "RAM" : "Memory", isPreview ? 0.61 : stats.memory),
        ].filter { widget.shows($0.id) }
        Group {
            if tall {
                HStack(spacing: 10) {
                    ForEach(items, id: \.id) { item in
                        StatRing(title: item.title, value: item.value,
                                 diameter: min(size.height - 4, size.width / CGFloat(max(items.count, 1)) - 10) * 0.86,
                                 look: widget.progressLook(of: item.id), reportsFrame: reportsParts,
                                 titleStyle: widget.textStyles[item.id == .cpuLoad ? .cpuTitle : .memoryTitle],
                                 valueStyle: widget.textStyles[item.id == .cpuLoad ? .cpuValue : .memoryValue])
                            .movableElement(item.id, of: widget)
                    }
                }
            } else {
                let rowHeight = side || items.count < 2 ? size.height : (size.height - 3) / 2
                let textSize = WidgetMetrics.points(rowHeight, ratio: 0.42, min: 8, max: 13)
                // As wide as the widest title, so the lines start under one another.
                let titleWidth = items.map { (($0.title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: textSize, weight: .medium)])).width.rounded(.up) }
                    .max() ?? 0
                let layout = side ? AnyLayout(HStackLayout(spacing: 12)) : AnyLayout(VStackLayout(spacing: 3))
                layout {
                    ForEach(items, id: \.id) { item in
                        StatBar(line: item.id, title: item.title, value: item.value, textSize: textSize, titleWidth: titleWidth,
                                look: widget.progressLook(of: item.id), reportsFrame: reportsParts,
                                titleStyle: widget.textStyles[item.id == .cpuLoad ? .cpuTitle : .memoryTitle],
                                valueStyle: widget.textStyles[item.id == .cpuLoad ? .cpuValue : .memoryValue])
                            .movableElement(item.id, of: widget)
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

    /// The value's and the name's own sizes in a ring `diameter` wide.
    static func valuePoints(diameter: CGFloat) -> CGFloat { diameter * 0.22 }
    static func titlePoints(diameter: CGFloat) -> CGFloat { diameter * 0.14 }

    var body: some View {
        let line = max(3, diameter * 0.1)
        ZStack {
            // Its line's middle on the ring's edge, as these rings have always been drawn.
            ProgressRing(fraction: value, diameter: max(diameter, 10) + line, line: line, look: look,
                         automaticTrack: .white.opacity(0.14), automaticFill: AnyShapeStyle(StatTint.color(value)),
                         reportsFrame: reportsFrame)
                .frame(width: max(diameter, 10), height: max(diameter, 10))
            VStack(spacing: 0) {
                RingText(text: Text(IslandFormat.percent(value)), style: valueStyle, size: Self.valuePoints(diameter: diameter),
                         weight: .semibold, design: .rounded, automatic: AnyShapeStyle(.primary), part: .remaining, look: look,
                         reportsFrame: reportsFrame)
                    .transaction { $0.animation = nil }
                RingText(text: Text(title), style: titleStyle, size: Self.titlePoints(diameter: diameter), part: .elapsed, look: look,
                         reportsFrame: reportsFrame)
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
