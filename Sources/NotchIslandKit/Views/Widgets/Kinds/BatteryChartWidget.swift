import SwiftUI

/// A chart, the base of every widget that draws a series (Battery Chart first): today's charge in
/// bars an hour wide, as the iPhone draws it — grey on battery, green while charging, red when low,
/// hatched where nothing is known, faintly shaded where the displays were off — with the level and
/// the day over it where there is room. The chart, the level and the caption are each moved in
/// Customize; the two texts are styled there.
struct BatteryChartWidget: View {
    let widget: IslandWidget
    let size: CGSize

    @Environment(AppModel.self) private var model
    @Environment(\.isWidgetPreview) private var isPreview
    @Environment(\.widgetDate) private var fixedDate
    @Environment(\.timeZone) private var timeZone

    static let valuePoints: CGFloat = 12
    static let captionPoints: CGFloat = 11

    /// The level and the day over the chart, from a widget this tall.
    static func showsHeader(_ widget: IslandWidget, inner: CGSize) -> Bool {
        inner.height >= 70 && (widget.shows(.value) || widget.shows(.label))
    }

    var body: some View {
        let header = Self.showsHeader(widget, inner: size)
        let headerHeight: CGFloat = header ? (max(Self.valuePoints, Self.captionPoints) * 1.2).rounded(.up) + 3 : 0
        let state = isPreview ? BatteryWidget.sample : model.power.state
        VStack(alignment: .leading, spacing: 3) {
            if header {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if widget.shows(.value) {
                        let text = BatteryWidget.percentText(state)
                        WidgetLabel(id: .value, text: text, widget: widget.withOwnDesign(.rounded, for: .value), size: Self.valuePoints,
                                    weight: .semibold, isSecondary: false) {
                            Text(text).font(.system(size: Self.valuePoints, weight: .semibold, design: .rounded).monospacedDigit())
                        }
                        .movableElement(.value, of: widget)
                    }
                    if widget.shows(.label) {
                        WidgetLabel(id: .label, text: Self.caption, widget: widget, size: Self.captionPoints, weight: .medium,
                                    isSecondary: true) {
                            Text(Self.caption).font(.system(size: Self.captionPoints, weight: .medium)).foregroundStyle(.secondary)
                        }
                        .movableElement(.label, of: widget)
                    }
                    Spacer(minLength: 0)
                }
                .lineLimit(1)
                .frame(height: headerHeight - 3)
            }
            BatteryChartElement(size: CGSize(width: size.width - 4, height: max(size.height - headerHeight, 0)),
                                look: widget.chartLook(of: .chart), picture: isPreview, date: fixedDate, timeZone: timeZone)
                .movableElement(.chart, of: widget)
        }
        .padding(.horizontal, 2)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    static var caption: String { String(localized: "Today") }
}

/// The day's charge, as the history has it (the shapes built off the main thread and kept by
/// `BatteryCenter`): redrawn for a new reading and at an hour's end, never between. A picture
/// draws the sample day the demo draws, built here (it reads nothing).
private struct BatteryChartElement: View {
    let size: CGSize
    let look: ChartLook
    let picture: Bool
    let date: Date?
    let timeZone: TimeZone

    @Environment(AppModel.self) private var model

    var body: some View {
        let battery = model.battery
        // The percentages beside it and the hours under it at every size (the percentages where set
        // to show any; the plot gives them room, and only 0 and 100 % are written where it is low).
        // A chart a row tall writes them smaller, so the hours fit under it too.
        let compact = size.height < BatteryChartPlot.compactBelow
        let hoursHeight = BatteryChartPlot.hoursHeight(compact: compact)
        let showsCaptions = !look.percentages.isEmpty && size.width >= BatteryChartPlot.percentWidth * 2
        let colors = BatteryChartColors(look, model: model)
        let cut = BatteryChartCut(corners: look.corners, mediumLevel: Double(ChartLook.mediumLevel),
                                  lines: look.percentages.isEmpty ? [0, 100] : look.percentages)
        let showsHours = size.height >= hoursHeight + BatteryChartPlot.captionHeight(compact: compact) * 2
        // Each hour is centred on its line, 00 and 24 on the plot's ends: half an hour's text of room
        // beside them (on the trailing side the percentages' column is room enough).
        let half = showsHours ? BatteryChartPlot.hourWidth(compact: compact) / 2 : 0
        // 0 and 100 % centred on their lines too: half a percentage's line of room over the plot, and
        // under it where no hours are (beside the hours, the 0 % is clear of the 24).
        let top = showsCaptions ? BatteryChartPlot.captionHeight(compact: compact) / 2 : 0
        let bottom = showsCaptions && !showsHours ? top : 0
        let plot = CGSize(width: max(size.width - half - (showsCaptions ? BatteryChartPlot.percentWidth : half), 0),
                          height: max(size.height - (showsHours ? hoursHeight : 0) - top - bottom, 0))
        Group {
            if picture {
                BatteryChartPlot(geometry: sample(plot, cut: cut), colors: colors, percentages: look.percentages,
                                 showsCaptions: showsCaptions, size: plot, showsHours: showsHours, compact: compact,
                                     lead: half, top: top)
            } else {
                let bucket = BatteryChartRange.today.bucketSeconds
                let start = Date(timeIntervalSinceReferenceDate: (Date().timeIntervalSinceReferenceDate / bucket).rounded(.down) * bucket)
                PanelTimelineView(.periodic(from: start, by: bucket)) { _ in
                    BatteryChartPlot(geometry: battery.chartGeometry(range: .today, style: .bars, size: plot, cut: cut),
                                     colors: colors, percentages: look.percentages,
                                     showsCaptions: showsCaptions, size: plot, showsHours: showsHours, compact: compact,
                                     lead: half, top: top)
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .whileShown { if !picture { battery.acquire(.history) } } stop: { if !picture { battery.release(.history) } }
        .accessibilityLabel("Battery chart")
    }

    /// The demo's day, up to the picture's moment (in its time zone, so a picture is the same on
    /// every Mac).
    private func sample(_ plot: CGSize, cut: BatteryChartCut) -> BatteryChartGeometry? {
        guard plot.width > 0, plot.height > 0 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let now = date ?? Date()
        let model = BatteryChartModel(records: BatteryHistory.demoRecords(now: now, calendar: calendar), range: .today, now: now,
                                      calendar: calendar)
        return BatteryChartGeometry(model: model, style: .bars, size: plot, cut: cut)
    }
}

/// A chart's colours: a bar's by how far the battery has run down (the look's, else the iPhone's
/// grey, and red when low), and green while charging.
struct BatteryChartColors {
    var high: AnyShapeStyle
    var medium: AnyShapeStyle
    var low: AnyShapeStyle
    var charging = AnyShapeStyle(Color.green)

    @MainActor init(_ look: ChartLook, model: AppModel) {
        func resolve(_ color: TextStyle.TextColor, _ automatic: Color) -> AnyShapeStyle {
            switch color {
            case .automatic: AnyShapeStyle(automatic)
            case .custom(let rgb): AnyShapeStyle(rgb.color)
            case .artwork: AnyShapeStyle(model.media.artworkColor.map { Color($0) } ?? .islandAccent)
            }
        }
        high = resolve(look.highColor, Color(white: 0.62))
        medium = resolve(look.mediumColor, Color(white: 0.62))
        low = resolve(look.lowColor, .red)
    }
}

/// The shapes, the percentages and the hours, at `size` (the plot's own).
struct BatteryChartPlot: View {
    @Environment(\.outlinesIslandText) private var edgesGrays
    let geometry: BatteryChartGeometry?
    let colors: BatteryChartColors
    /// Written beside the plot, low to high.
    let percentages: [Int]
    var showsCaptions: Bool
    let size: CGSize
    /// The hours under the plot (a short widget leaves them out).
    var showsHours = true
    /// A chart a row tall: its percentages and hours smaller (`compactBelow`).
    var compact = false
    /// Room before the plot, for the first hour centred on its start.
    var lead: CGFloat = 0
    /// Room over the plot, for the 100 % centred on its line.
    var top: CGFloat = 0

    /// A chart lower than this (a widget a row tall) writes its percentages and hours smaller.
    static let compactBelow: CGFloat = 44
    static func hoursHeight(compact: Bool) -> CGFloat { compact ? 10 : 14 }
    /// A percentage's line height.
    static func captionHeight(compact: Bool) -> CGFloat { compact ? 9 : 12 }
    /// Two digits' room in the hours' font.
    static func hourWidth(compact: Bool) -> CGFloat { compact ? 10 : 13 }
    /// The percentages beside the plot, where the captions are shown.
    static let percentWidth: CGFloat = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                Color.clear.frame(width: lead, height: 1)
                ZStack(alignment: .topLeading) {
                    if let geometry { shapes(geometry) }
                }
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                if showsCaptions {
                    ZStack(alignment: .topTrailing) {
                        let line = Self.captionHeight(compact: compact)
                        ForEach(Self.written(percentages, height: size.height, line: line), id: \.self) { value in
                            Text(verbatim: IslandFormat.percent(Double(value) / 100))
                                .frame(width: Self.percentWidth, height: line, alignment: .trailing)
                                .offset(y: Self.captionTop(value, height: size.height, line: line))
                        }
                    }
                    .frame(width: Self.percentWidth, height: size.height, alignment: .topTrailing)
                }
            }
            if showsHours {
                let height = Self.hoursHeight(compact: compact)
                // Every six hours, 00 to 24, each centred on its line (the hour its bar starts);
                // every other one, or the ends alone, where they would run into each other.
                ZStack(alignment: .topLeading) {
                    ForEach(Self.labelled(geometry?.ticks ?? [], width: size.width, digits: Self.hourWidth(compact: compact)),
                            id: \.x) { tick in
                        Text(tick.x >= size.width - 0.5 ? "24" : Self.hour(tick.date))
                            .fixedSize()
                            .position(x: lead + tick.x, y: height / 2 + 1)
                    }
                }
                .frame(width: lead + size.width, height: height, alignment: .topLeading)
            }
        }
        .padding(.top, top)
        .font(compact ? .system(size: 8).monospacedDigit() : .caption2.monospacedDigit())
        .foregroundStyle(.tertiary)
    }

    static func hour(_ date: Date) -> String { date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted))) }

    /// The ticks written: all of them, every other one, or the first and the last, the most that
    /// stay `digits` and a gap apart.
    static func labelled(_ ticks: [BatteryChartGeometry.Tick], width: CGFloat, digits: CGFloat) -> [BatteryChartGeometry.Tick] {
        guard ticks.count > 2 else { return ticks }
        let spacing = width / CGFloat(ticks.count - 1)
        let stride = [1, 2, 4].first { spacing * CGFloat($0) >= digits + 4 } ?? ticks.count - 1
        return ticks.enumerated().filter { $0.offset % stride == 0 || $0.offset == ticks.count - 1 }.map(\.element)
    }

    /// A percentage's top: centred on its line, 0 and 100 % too (half of them over and under the
    /// plot, in the room the chart leaves there).
    static func captionTop(_ value: Int, height: CGFloat, line captionHeight: CGFloat = captionHeight(compact: false)) -> CGFloat {
        height * (1 - CGFloat(value) / 100) - captionHeight / 2
    }

    /// The percentages that fit, each clear of the last one written: 0 and 100 % always, those
    /// between where there is room (every 10 % on a low chart writes every other one, or fewer).
    static func written(_ percentages: [Int], height: CGFloat, line: CGFloat = captionHeight(compact: false)) -> [Int] {
        guard let first = percentages.first, let last = percentages.last else { return [] }
        func top(_ value: Int) -> CGFloat { captionTop(value, height: height, line: line) }
        var kept: [Int] = [first]
        for value in percentages.dropFirst() where value != last {
            if abs(top(value) - top(kept.last!)) >= line, abs(top(value) - top(last)) >= line {
                kept.append(value)
            }
        }
        if last != first { kept.append(last) }
        return kept
    }

    @ViewBuilder private func shapes(_ geometry: BatteryChartGeometry) -> some View {
        ChartShape(path: geometry.displayOff).fill(.white.opacity(0.06))
        ChartShape(path: geometry.axis).stroke(.white.opacity(0.16), style: StrokeStyle(lineWidth: 0.5, dash: [1.5, 2.5]))
        ChartShape(path: geometry.gaps).stroke(.white.opacity(0.2), lineWidth: 1)
        // Charging: a faint column up to full behind the bar, a cap along the top of the run.
        ChartShape(path: geometry.chargingBand).fill(colors.charging).opacity(0.18)
        ChartShape(path: geometry.chargingCap).fill(colors.charging)
        ChartShape(path: geometry.level).fill(colors.high)
        ChartShape(path: geometry.medium).fill(colors.medium)
        ChartShape(path: geometry.charging).fill(colors.charging)
        ChartShape(path: geometry.low).fill(colors.low)
        // Light Mode on Liquid Glass: a faint edge round the grey bars (`IslandGlassStyle.grayEdge`).
        ChartShape(path: geometry.level).stroke(IslandGlassStyle.grayEdge(edgesGrays), lineWidth: IslandGlassStyle.grayEdgeWidth)
        ChartShape(path: geometry.medium).stroke(IslandGlassStyle.grayEdge(edgesGrays), lineWidth: IslandGlassStyle.grayEdgeWidth)
    }
}

/// A prebuilt path as a shape: equal paths are not drawn again.
nonisolated private struct ChartShape: Shape, Equatable {
    let path: Path

    func path(in rect: CGRect) -> Path { path }
}
