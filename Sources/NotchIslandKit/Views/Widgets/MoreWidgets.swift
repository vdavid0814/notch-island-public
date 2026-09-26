import SwiftUI

/// The time, large, with today's date under it (or beside it when the widget is one row wide
/// enough). Re-rendered once a minute, on the minute.
struct DateTimeWidget: View {
    let widget: IslandWidget
    let size: CGSize

    var body: some View {
        PanelTimelineView(.everyMinute) { context in
            let showsTime = widget.shows(.readout), showsDate = widget.shows(.dateLine)
            let tall = size.height >= 56
            // Never wider than the widget, nor taller than its share of it; below that cap S, M
            // and L stay apart (`WidgetType.fitted`).
            let dateSize = WidgetType.fitted(WidgetType.points(size.height, ratio: tall ? 0.18 : 0.42, min: 9, max: 17),
                                             fit: WidgetType.size(fittingLines: 1, in: tall ? size.height * 0.34 : size.height),
                                             widget.size(of: .dateLine), floor: 8)
            let timeText = context.date.formatted(.dateTime.hour().minute())
            let timeSize = WidgetType.fitted(
                WidgetType.points(tall ? size.height * 0.62 : size.height, ratio: 0.8, min: 13, max: 48),
                fit: min(WidgetType.size(fitting: timeText, in: size.width - 8, weight: .semibold, rounded: true, monospacedDigits: true),
                         WidgetType.size(fittingLines: 1, in: tall && showsDate ? size.height - dateSize * WidgetType.lineHeight : size.height) * 1.08),
                widget.size(of: .readout), floor: 11)
            let time = Text(context.date, format: .dateTime.hour().minute())
                .font(.system(size: timeSize, weight: .semibold, design: .rounded).monospacedDigit())
            // The longest date that fits: "Thursday, 24 September", "Thu, 24 Sep", "24".
            let date = ViewThatFits(in: .horizontal) {
                Text(context.date, format: .dateTime.weekday(.wide).day().month(.wide)).fixedSize()
                Text(context.date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated)).fixedSize()
                Text(context.date, format: .dateTime.weekday(.abbreviated).day()).fixedSize()
                Text(context.date, format: .dateTime.day()).fixedSize()
            }
            .font(.system(size: dateSize, weight: .medium))
            .foregroundStyle(.secondary)
            Group {
                if tall {
                    VStack(alignment: .leading, spacing: 0) {
                        if showsDate { date }
                        if showsTime { time.lineLimit(1).minimumScaleFactor(0.6) }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            if showsTime { time.lineLimit(1).fixedSize() }
                            if showsDate { date }
                        }
                        if showsTime { time.lineLimit(1).minimumScaleFactor(0.6) } else { date }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(.horizontal, 4)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Processor and memory load, as two rings or two bars, sampled only while the widget is shown
/// (`SystemStatsMonitor`). A picture in Settings shows sample values and reads nothing.
struct SystemStatsWidget: View {
    let widget: IslandWidget
    let size: CGSize

    @Environment(AppModel.self) private var model
    @Environment(\.isWidgetPreview) private var isPreview

    var body: some View {
        let stats = model.stats
        // "RAM" where "Memory" would not fit beside its bar (each bar gets half a wide widget).
        let tall = size.height >= 56
        let itemWidth = !tall && size.width >= 200 ? size.width / 2 : size.width
        let narrow = itemWidth < 170
        let items: [(option: WidgetOption, title: String, value: Double)] = [
            (.cpuLoad, "CPU", isPreview ? 0.23 : stats.cpu),
            (.memoryLoad, narrow ? "RAM" : "Memory", isPreview ? 0.61 : stats.memory),
        ].filter { widget.shows($0.option) }
        Group {
            if tall {
                // Rings side by side.
                HStack(spacing: 10) {
                    ForEach(items, id: \.option) { item in
                        let room = min(size.height - 4, size.width / CGFloat(max(items.count, 1)) - 10)
                        StatRing(title: item.title, value: item.value,
                                 diameter: WidgetType.fitted(room, fit: room, widget.size(of: item.option), floor: 20))
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
                        StatBar(title: item.title, value: item.value,
                                textSize: WidgetType.fitted(WidgetType.points(rowHeight, ratio: 0.42, min: 8, max: 13),
                                                            fit: fit, widget.size(of: item.option), floor: 7))
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
    let title: String
    let value: Double
    let diameter: CGFloat

    var body: some View {
        let line = max(3, diameter * 0.1)
        ZStack {
            Circle().stroke(.white.opacity(0.14), lineWidth: line)
            Circle()
                .trim(from: 0, to: value)
                .stroke(StatTint.color(value), style: StrokeStyle(lineWidth: line, lineCap: .round))
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
    let title: String
    let value: Double
    let textSize: CGFloat

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: textSize, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize()
                .frame(minWidth: textSize * 2.2, alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.14))
                    Capsule().fill(StatTint.color(value))
                        .frame(width: max(proxy.size.height, proxy.size.width * value))
                }
            }
            .frame(height: max(4, textSize * 0.45))
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
