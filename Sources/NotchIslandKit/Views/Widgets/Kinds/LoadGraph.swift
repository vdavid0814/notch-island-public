import SwiftUI

/// System's graph, made as Fan Control's is (`FanHeatGraph`): each load the widget shows — the
/// processor, the graphics processor, memory — a line of its own colour over a soft fill, from 0 to
/// 100 %, its newest reading a dot at the right edge; the percentages the look sets (as the battery
/// chart's: 0, 50 and 100 % unless set) dotted across it and written at its left. Under it, its key:
/// how far back it reaches (a button: the timer's ruler to set that), the lines' names in their
/// colours, now.
///
/// Live, it slides as Fan Control's does: each new reading is drawn once and Core Animation carries
/// the drawing left in a short soft glide on the render server (`FanGraphLayers`).
///
/// Lower than 56 pt, the lines and the dotted percentages alone.
///
/// Set in Customize as a chart is (`ChartLook`): its corners are the lines' joins and the dots, its
/// low, middle and high colours the processor's, the graphics processor's and memory's, its
/// percentages its dotted lines; its texts in one style.
struct LoadGraph: View {
    /// One load's line: its readings (0…1, oldest first), its name in the key, its colour.
    struct Series: Equatable {
        var id: ElementID
        var name: String
        var samples: [SensorSample]
        var tint: FanTint
    }

    /// In the key's order (the processor first); drawn the other way round, the processor on top.
    let series: [Series]
    let now: Date
    /// How far back it reaches, in seconds.
    let window: TimeInterval
    /// The dotted lines, in percent (`ChartLook.percentages`); empty: none, nothing written.
    let percentages: [Int]
    var corners: ChartLook.Corners = .rounded
    let size: CGSize
    /// The texts' type and colour; nil: the graph's own.
    var textStyle: TextStyle?
    /// A click on its time: the ruler setting how far back it reaches; nil: a picture (drawn still).
    var setHistory: (() -> Void)?

    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme

    /// The lines' own colours: the processor blue, the graphics processor violet, memory orange.
    static let cpuTint = FanTint(red: 0.35, green: 0.72, blue: 1.0)
    static let gpuTint = FanTint(red: 0.76, green: 0.52, blue: 1.0)
    static let memoryTint = FanTint(red: 1.0, green: 0.62, blue: 0.28)

    /// A load's line colour: the look's where it picked one, else its own.
    @MainActor static func tint(of load: ElementID, look: ChartLook, model: AppModel) -> FanTint {
        let (color, own) = switch load {
        case .gpuLoad: (look.mediumColor, gpuTint)
        case .memoryLoad: (look.highColor, memoryTint)
        default: (look.lowColor, cpuTint)
        }
        return switch color {
        case .automatic: own
        case .custom(let rgb): FanTint(rgb.color)
        case .artwork: FanTint(model.media.artworkColor.map { Color($0) } ?? .islandAccent)
        }
    }

    /// Where its parts are, at a size: the percentages' column at the left, 100 % and 0 % (the
    /// plot's top and floor), the key under it.
    nonisolated struct Layout: Equatable, Sendable {
        var showsTexts: Bool
        /// The percentages' column, left of the plot (0 where none are written).
        var column: CGFloat
        var top: CGFloat
        var floor: CGFloat
        var key: CGFloat
        var line: CGFloat
        /// The plot's width, right of the column.
        var plot: CGFloat
        /// The newest reading's x in the plot: its dots clear of the right edge.
        var right: CGFloat
    }

    static func layout(_ size: CGSize, caption: CGFloat, column: CGFloat) -> Layout {
        let h = size.height
        let line = max(1.25, h * 0.0125)
        if h >= 56 {
            // 100 % and 0 % centred on their lines, the key under the 0 %.
            let plot = max(size.width - column, 1)
            return Layout(showsTexts: true, column: column, top: caption / 2, floor: h - caption - 3 - caption / 2, key: h - caption,
                          line: line, plot: plot, right: max(plot - line * 3 - 1, 1))
        }
        return Layout(showsTexts: false, column: 0, top: line * 3, floor: h - line * 3, key: h, line: line, plot: size.width,
                      right: max(size.width - line * 3 - 1, 1))
    }

    /// The percentages' column: "100 %" in the texts' type, and a gap.
    static func column(points: CGFloat, style: TextStyle?) -> CGFloat {
        let font = FanHeatGraph.nsFont(points, weight: .medium, style: style, digits: true)
        return (IslandFormat.percent(1) as NSString).size(withAttributes: [.font: font]).width.rounded(.up) + 5
    }

    var body: some View {
        let points = CGFloat(min(textStyle?.size ?? Double(FanHeatGraph.textPoints(height: size.height)), FanHeatGraph.textSizes.upperBound))
        let caption = (points * 1.25).rounded(.up)
        let column = size.height >= 56 && !percentages.isEmpty ? Self.column(points: points, style: textStyle) : 0
        let layout = Self.layout(size, caption: caption, column: column)
        // Drawn from the newest reading (at the right edge), not from the moment the body is made.
        let newest = series.compactMap { $0.samples.last?.date }.max() ?? now
        // Live, a slide's length further left, under the edge (as Fan Control's).
        let lead = setHistory == nil ? 0 : min(FanHeatGraph.leadSeconds, window)
        let drawing = drawing(layout: layout, newest: newest, lead: lead)
        let ink = inkColor
        ZStack(alignment: .topLeading) {
            percentLines(layout: layout, points: points, caption: caption, ink: ink)
            Group {
                if setHistory == nil {
                    // A picture: drawn still, its newest dots with it.
                    Canvas { context, _ in
                        context.withCGContext { drawing.draw(in: $0, fade: fadesIn, dot: true) }
                    }
                    .allowsHitTesting(false)
                } else {
                    FanGraphLayers(drawing: drawing, newest: newest, window: window, fadesIn: fadesIn,
                                   dots: drawing.lines.compactMap { line in line.points.last.map { FanGraphLayers.Dot(y: $0.y, tint: line.tint) } })
                }
            }
            .frame(width: layout.plot, height: size.height)
            .offset(x: layout.column)
            if layout.showsTexts {
                fillsIn(layout: layout, points: points, caption: caption, drawing: drawing, ink: ink)
                LoadGraphKey(graph: self, points: points, ink: ink)
                    .frame(width: size.width, height: caption)
                    .offset(y: layout.key)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .underline(textStyle?.isUnderlined ?? false)
        .strikethrough(textStyle?.isStruckThrough ?? false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(series.map { "\($0.name) \($0.samples.last.map { IslandFormat.percent($0.value) } ?? "—")" }
            .joined(separator: ", ")))
    }

    /// The longest past fills the graph: it fades in at the left, going on beyond the edge.
    private var fadesIn: Bool {
        series.contains { line in
            guard let first = line.samples.first, let last = line.samples.last else { return false }
            return first.date <= last.date.addingTimeInterval(-window + 5)
        }
    }

    /// What is drawn, from the newest reading: each line's points — `lead` seconds of them left of
    /// the graph's edge — the memory's first, the processor's last (on top).
    private func drawing(layout: Layout, newest: Date, lead: TimeInterval) -> LoadGraphDrawing {
        let room = layout.right * CGFloat(lead / window)
        func x(_ date: Date) -> CGFloat {
            room + layout.right * CGFloat(1 - min(max(newest.timeIntervalSince(date) / window, -1), 1 + lead / window))
        }
        let start = newest.addingTimeInterval(-window - lead)
        let lines = series.reversed().map { line in
            let shown = FanHeatGraph.within(line.samples, from: start)
            return LoadGraphDrawing.Line(points: shown.map { CGPoint(x: x($0.date), y: y($0.value, layout: layout)) },
                                         breaks: FanHeatGraph.breaks(shown), tint: line.tint)
        }
        return LoadGraphDrawing(size: CGSize(width: layout.right + room, height: size.height), lead: room, right: layout.right,
                                line: layout.line, top: layout.top, floor: layout.floor, lines: lines, corners: corners)
    }

    func y(_ value: Double, layout: Layout) -> CGFloat {
        layout.floor - (layout.floor - layout.top) * CGFloat(min(max(value, 0), 1))
    }

    // MARK: Lines and texts

    /// Each percentage dotted across the plot; those that fit written at its left (as the battery
    /// chart leaves out ones too close to the next).
    @ViewBuilder private func percentLines(layout: Layout, points: CGFloat, caption: CGFloat, ink: Color) -> some View {
        ForEach(percentages, id: \.self) { percent in
            FanDottedLine()
                .stroke(FanDialGeometry.ink(scheme).opacity(0.22), style: StrokeStyle(lineWidth: 0.75, dash: [1.5, 3.5]))
                .frame(width: layout.plot, height: 1)
                .offset(x: layout.column, y: y(Double(percent) / 100, layout: layout) - 0.5)
        }
        if layout.showsTexts, layout.column > 0 {
            ForEach(BatteryChartPlot.written(percentages, height: layout.floor - layout.top, line: caption), id: \.self) { percent in
                Text(verbatim: IslandFormat.percent(Double(percent) / 100))
                    .font(FanHeatGraph.font(points, weight: .medium, style: textStyle).monospacedDigit())
                    .foregroundStyle(ink.opacity(0.45))
                    .lineLimit(1)
                    .frame(width: layout.column - 5, height: caption, alignment: .trailing)
                    .offset(y: y(Double(percent) / 100, layout: layout) - caption / 2)
            }
        }
    }

    /// A past shorter than the graph: what is missing says it fills in.
    @ViewBuilder private func fillsIn(layout: Layout, points: CGFloat, caption: CGFloat, drawing: LoadGraphDrawing, ink: Color) -> some View {
        let samples = series.max { $0.samples.count < $1.samples.count }?.samples ?? []
        if let first = samples.first, let last = samples.last {
            let reach = last.date.timeIntervalSince(first.date)
            let left = drawing.lines.compactMap { $0.points.first.map { $0.x - drawing.lead } }.min() ?? layout.right
            if reach < window * 0.6, left > layout.plot * 0.3 {
                Text("Fills in over \(FanControlWidget.span(Int(window.rounded())))")
                    .font(FanHeatGraph.font(points, weight: .medium, style: textStyle))
                    .foregroundStyle(ink.opacity(0.34))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: max(left - 8, 0), height: caption)
                    .offset(x: layout.column, y: (layout.top + layout.floor - caption) / 2)
            }
        }
    }

    /// The texts' colour at full strength: the style's, else white.
    private var inkColor: Color {
        switch textStyle?.color ?? .automatic {
        case .automatic: FanDialGeometry.ink(scheme)
        case .custom(let rgb): rgb.color
        case .artwork: model.media.artworkColor.map { Color($0) } ?? .islandAccent
        }
    }
}

/// Under the graph: how far back it reaches (a glass button: the ruler), the lines' names in their
/// colours, now — as Fan Control's key.
private struct LoadGraphKey: View {
    let graph: LoadGraph
    let points: CGFloat
    let ink: Color

    var body: some View {
        HStack(spacing: 0) {
            Button(action: graph.setHistory ?? {}) {
                Text(FanHeatGraph.reach(graph.window))
                    .font(FanHeatGraph.font(points, weight: .semibold, style: graph.textStyle))
                    .foregroundStyle(ink.opacity(0.85))
            }
            .islandButton(.capsule)
            .controlSize(.mini)
            .help("How far back the graph reaches: click to set it")
            Spacer(minLength: 4)
            if graph.size.width >= 190 {
                HStack(spacing: points * 0.8) {
                    ForEach(graph.series, id: \.id) { line in
                        HStack(spacing: points * 0.3) {
                            Capsule()
                                .fill(line.tint.color)
                                .frame(width: points * 0.9, height: max(points * 0.22, 1.5))
                            Text(line.name).foregroundStyle(ink.opacity(0.6))
                        }
                    }
                }
                Spacer(minLength: 4)
            }
            if graph.size.width >= 120 {
                Text("now").foregroundStyle(ink.opacity(0.45))
            }
        }
        .font(FanHeatGraph.font(points, weight: .medium, style: graph.textStyle))
        .lineLimit(1)
    }
}

/// The loads' drawing in Core Graphics — each line over its fill, the newest dots — so that the live
/// graph's layer and a picture's Canvas draw the same pixels.
nonisolated struct LoadGraphDrawing: SlidingGraphDrawing {
    struct Line: Equatable, Sendable {
        var points: [CGPoint]
        /// The readings that come after a gap: the line breaks there.
        var breaks: Set<Int>
        var tint: FanTint
    }

    var size: CGSize
    var lead: CGFloat = 0
    var right: CGFloat
    var line: CGFloat
    /// 100 % and 0 %.
    var top: CGFloat
    var floor: CGFloat
    /// Bottom to top: the last drawn over the others.
    var lines: [Line]
    var corners: ChartLook.Corners

    func draw(in cg: CGContext, fade: Bool, dot: Bool) {
        if fade { cg.beginTransparencyLayer(auxiliaryInfo: nil) }
        let floorPoint = CGPoint(x: 0, y: floor), topPoint = CGPoint(x: 0, y: top)
        for series in lines {
            var runs: [[CGPoint]] = [[]]
            for (index, point) in series.points.enumerated() {
                if series.breaks.contains(index) { runs.append([]) }
                runs[runs.count - 1].append(point)
            }
            // A soft fill under each line, faint enough that three of them still read.
            let fill = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                  colors: [series.tint.cgColor(0), series.tint.cgColor(0.12)] as CFArray, locations: [0, 1])
            for run in runs where run.count >= 2 {
                let path = CGMutablePath()
                path.addLines(between: run)
                let area = CGMutablePath()
                area.addPath(path)
                area.addLine(to: CGPoint(x: run[run.count - 1].x, y: floor))
                area.addLine(to: CGPoint(x: run[0].x, y: floor))
                area.closeSubpath()
                if let fill {
                    cg.saveGState()
                    cg.addPath(area)
                    cg.clip()
                    cg.drawLinearGradient(fill, start: floorPoint, end: topPoint, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
                    cg.restoreGState()
                }
                cg.saveGState()
                cg.addPath(path)
                cg.setLineWidth(line)
                switch corners {
                case .rounded: cg.setLineCap(.round); cg.setLineJoin(.round)
                case .slight: cg.setLineCap(.butt); cg.setLineJoin(.bevel)
                case .square: cg.setLineCap(.square); cg.setLineJoin(.miter)
                }
                cg.setStrokeColor(series.tint.cgColor())
                cg.strokePath()
                cg.restoreGState()
            }
        }

        // The newest readings: a dot each, cut out of what is behind it.
        if dot {
            for series in lines {
                if let last = series.points.last {
                    FanGraphDrawing.dot(in: cg, at: last, radius: line * 2, ring: line, tint: series.tint, corners: corners)
                }
            }
        }

        if fade {
            cg.setBlendMode(.destinationOut)
            if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                         colors: [CGColor(gray: 0, alpha: 1), CGColor(gray: 0, alpha: 0)] as CFArray, locations: [0, 1]) {
                cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width * 0.12, y: 0), options: [])
            }
            cg.endTransparencyLayer()
        }
    }
}
