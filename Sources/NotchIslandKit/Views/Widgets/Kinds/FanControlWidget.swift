import SwiftUI

/// Fan Control: in a row, a dial round the fan, a dial of the chip's temperature, and a graph of
/// the temperature over the last ten minutes — with the fans' speed graphed beside it where the
/// widget is wide enough (about as wide as the panel).
///
/// The dials are plain arcs open at the bottom, filled as far as the fans turn between their slowest
/// and fastest (the chip between 30 and 100 °C), the value in the middle. Turning the fan's dial —
/// dragging anywhere on it — holds the fans at that speed (Manual, a dot where they are held); the
/// fan in it is a button that gives them back to macOS (Auto, its own curve, as from the factory).
/// Every part is moved and resized in Customize; a graph keeps its lines thin when made lower.
///
/// Read every second while shown (`FanCenter`, `ThermalMonitor`); a picture (the gallery,
/// Customize) shows samples. Offered only on a Mac with a fan (MacBook Pro).
struct FanControlWidget: View {
    let widget: IslandWidget
    let size: CGSize

    @Environment(AppModel.self) private var model
    @Environment(\.isWidgetPreview) private var isPreview
    @Environment(\.widgetRenderMode) private var renderMode
    @Environment(\.widgetDate) private var fixedDate
    @Environment(\.locale) private var locale
    @Environment(\.reportsProgressParts) private var reportsParts

    /// A MacBook Pro's fan turning at a quarter of its range, left to macOS, the chip at 46 °C.
    static let sample = [FanReading(index: 0, rpm: 2450, minimum: 1200, maximum: 5800, target: 0, isManual: false)]

    /// Ten minutes of a chip working now and then, for the pictures: a reading every fifteen seconds
    /// up to `now`.
    static func sampleTemperatures(now: Date) -> [SensorSample] {
        (0...40).map { step in
            let t = Double(step)
            return SensorSample(date: now.addingTimeInterval(-ThermalMonitor.window + t * 15),
                                value: 46 + 7 * sin(t / 4.2) + 4 * sin(t / 1.7) + (step > 30 ? Double(step - 30) * 0.9 : 0))
        }
    }

    static func sampleSpeeds(now: Date) -> [SensorSample] {
        sampleTemperatures(now: now).map { SensorSample(date: $0.date, value: 1200 + ($0.value - 34) * 75) }
    }

    // MARK: Layout

    /// What the row holds at a size: the dials' diameter, whether the temperature's dial fits, and
    /// the graphs that fit with their width.
    struct Layout: Equatable {
        var dial: CGFloat
        var gap: CGFloat
        var showsTempDial: Bool
        var graphs: [ElementID]
        var graphWidth: CGFloat

        /// A graph narrower than this is not drawn.
        static let minimumGraph: CGFloat = 80
        /// Two graphs side by side need this room: the widget about as wide as the panel.
        static let twoGraphs: CGFloat = 250
    }

    static func layout(_ widget: IslandWidget, inner: CGSize) -> Layout {
        // A little inside the widget's height: the arcs' round ends clear of its edges.
        let dial = max(min(inner.height * 0.94, inner.width), 16)
        let gap = min(max(inner.height * 0.12, 6), 14)
        var used = dial
        let tempDial = widget.shows(.tempDial) && inner.width - used >= gap + dial
        if tempDial { used += gap + dial }
        let room = inner.width - used - gap
        var graphs = [ElementID.tempGraph, .rpmGraph].filter { widget.shows($0) }
        if graphs.count == 2, room < Layout.twoGraphs { graphs = [graphs[0]] }
        if room < Layout.minimumGraph { graphs = [] }
        let width = graphs.isEmpty ? 0 : (room - gap * CGFloat(graphs.count - 1)) / CGFloat(graphs.count)
        return Layout(dial: dial, gap: gap, showsTempDial: tempDial, graphs: graphs, graphWidth: width)
    }

    /// Whether `element` has room at this size (one switched on that has none is not drawn).
    static func hasRoom(for element: ElementID, in widget: IslandWidget, inner: CGSize) -> Bool {
        var shown = widget
        shown.options.insert(element)
        let layout = layout(shown, inner: inner)
        return switch element {
        case .tempDial: layout.showsTempDial
        case .tempGraph, .rpmGraph: layout.graphs.contains(element)
        case .value, .label: FanDial<EmptyView, EmptyView>.showsTexts(diameter: layout.dial)
        default: true
        }
    }

    static func valuePoints(inner: CGSize) -> CGFloat {
        WidgetMetrics.points(max(min(inner.height, inner.width), 16), ratio: 0.2, min: 8, max: 26)
    }

    static func labelPoints(inner: CGSize) -> CGFloat {
        WidgetMetrics.points(max(min(inner.height, inner.width), 16), ratio: 0.095, min: 7, max: 12)
    }

    // MARK: Texts

    /// "2,450": the fans' average, to ten rpm.
    static func rpmText(_ fans: [FanReading], locale: Locale = .current) -> String {
        guard !fans.isEmpty else { return "—" }
        return rpm(fans.map(\.rpm).reduce(0, +) / Double(fans.count), locale: locale)
    }

    static func rpm(_ value: Double, locale: Locale) -> String {
        Int((value / 10).rounded() * 10).formatted(.number.locale(locale))
    }

    /// Auto or Manual; what is missing when the fans cannot be set.
    static func modeText(manual: Bool, access: FanCenter.Access) -> String {
        switch access {
        case .needsApproval: String(localized: "Allow in Login Items")
        case .installing: String(localized: "Password…")
        case .failed: String(localized: "Unavailable")
        default: manual ? String(localized: "Manual") : String(localized: "Auto")
        }
    }

    /// The dial's tooltip: how to set the fans, or why they cannot be.
    static func accessHelp(_ access: FanCenter.Access) -> String {
        switch access {
        case .needsApproval: String(localized: "Switch NotchIsland on in System Settings ▸ General ▸ Login Items, then turn the dial again.")
        case .installing: String(localized: "macOS is asking for an administrator's password, once, to install the helper that sets the fans.")
        case .failed(let reason): String(localized: "The fans cannot be set: \(reason) Turn the dial to try again.")
        default: String(localized: "Turn the dial to set the fans' speed; click the fan for automatic.")
        }
    }

    /// "52°", in the locale's unit.
    static func degrees(_ celsius: Double, locale: Locale) -> String {
        "\(degreeNumber(celsius, locale: locale))°"
    }

    /// "52": the degrees alone, in the locale's unit.
    static func degreeNumber(_ celsius: Double, locale: Locale) -> String {
        let value = locale.measurementSystem == .us ? celsius * 9 / 5 + 32 : celsius
        return "\(Int(value.rounded()))"
    }

    /// "°C", or "°F" in the US.
    static func degreeUnit(locale: Locale) -> String { locale.measurementSystem == .us ? "°F" : "°C" }

    // MARK: Body

    var body: some View {
        let picture = isPreview || renderMode == .canvas
        let center = model.fans
        let thermals = model.thermals
        let now = fixedDate ?? .now
        let fans = picture || center.fans.isEmpty ? Self.sample : center.fans
        let manual = !picture && center.isManual
        let access = picture ? FanCenter.Access.unknown : center.access
        let chip = picture ? SystemReadings.sampleChip : thermals.chip
        let layout = Self.layout(widget, inner: size)
        let lone = !layout.showsTempDial && layout.graphs.isEmpty
        HStack(spacing: layout.gap) {
            FanDial(fans: fans, held: picture ? nil : center.heldFraction, isManual: manual, diameter: layout.dial,
                    showsTexts: true, value: valueLabel(fans, dial: layout.dial),
                    label: modeLabel(manual: manual, access: access, dial: layout.dial),
                    look: widget.progressLook(of: .fanDial), nameStyle: widget.textStyles[.fanName],
                    unitStyle: widget.textStyles[.fanUnit], reportsFrame: reportsParts,
                    set: { center.setSpeed($0) }, automatic: { center.setAutomatic() },
                    onInteraction: { model.island.isInteracting = $0 })
                .frame(width: layout.dial, height: layout.dial)
                .help(Self.accessHelp(access))
                .movableElement(.fanDial, of: widget)
            if layout.showsTempDial {
                TemperatureDial(celsius: chip?.average, diameter: layout.dial, number: chip.map { Self.degreeNumber($0.average, locale: locale) },
                                unit: Self.degreeUnit(locale: locale), look: widget.progressLook(of: .tempDial),
                                nameStyle: widget.textStyles[.tempName], valueStyle: widget.textStyles[.tempValue],
                                reportsFrame: reportsParts)
                    .frame(width: layout.dial, height: layout.dial)
                    .movableElement(.tempDial, of: widget)
            }
            ForEach(layout.graphs, id: \.self) { id in
                graph(id, picture: picture, now: now, fans: fans, width: layout.graphWidth)
            }
        }
        .frame(width: size.width, height: size.height, alignment: lone ? .center : .leading)
        .whileShown {
            guard !picture else { return }
            withoutAnimation {
                center.startObserving()
                thermals.startObserving()
                thermals.keepHistory()
            }
        } stop: {
            guard !picture else { return }
            center.stopObserving()
            thermals.stopObserving()
        }
    }

    /// A graph, as large as Customize resized it (from its top-leading corner), its lines as thin.
    @ViewBuilder private func graph(_ id: ElementID, picture: Bool, now: Date, fans: [FanReading], width: CGFloat) -> some View {
        let scale = widget.scale(of: id)
        let drawn = CGSize(width: width * scale.x, height: size.height * scale.y)
        Group {
            if id == .tempGraph {
                SensorGraph(title: String(localized: "Chip"),
                            samples: picture ? Self.sampleTemperatures(now: now) : model.thermals.temperatures, now: now,
                            minimumSpan: 8, fixedRange: TemperatureDial.range,
                            colors: SensorGraph.colors(widget.chartLook(of: id), automatic: TemperatureDial.colors, model: model),
                            showsAverage: true, format: { Self.degrees($0, locale: locale) }, size: drawn,
                            look: widget.chartLook(of: id), textStyle: widget.textStyles[.tempGraphText])
            } else {
                let lowest = fans.map(\.minimum).min() ?? 0, highest = fans.map(\.maximum).max() ?? 1
                SensorGraph(title: String(localized: "Fan"),
                            samples: picture ? Self.sampleSpeeds(now: now) : model.thermals.speeds, now: now,
                            minimumSpan: 1, fixedRange: lowest...max(highest, lowest + 1),
                            colors: SensorGraph.colors(widget.chartLook(of: id), automatic: FanTint.colors, model: model),
                            showsAverage: false, format: { Self.rpm($0, locale: locale) }, size: drawn,
                            look: widget.chartLook(of: id), textStyle: widget.textStyles[.rpmGraphText])
            }
        }
        .frame(width: drawn.width, height: drawn.height)
        .frame(width: width, height: size.height, alignment: .topLeading)
        .movableElement(id, of: widget, drawsScale: false)
    }

    @ViewBuilder private func valueLabel(_ fans: [FanReading], dial: CGFloat) -> some View {
        if widget.shows(.value), FanDial<EmptyView, EmptyView>.showsTexts(diameter: dial) {
            let points = Self.valuePoints(inner: size)
            let text = Self.rpmText(fans, locale: locale)
            WidgetLabel(id: .value, text: text, widget: widget, size: points, weight: .semibold, isSecondary: false) {
                Text(text)
                    .font(.system(size: points, weight: .semibold, design: .rounded).monospacedDigit())
                    .lineLimit(1)
                .minimumScaleFactor(0.6)
                // A new reading each second: it just changes (a cross-fade a second smeared).
                .transaction { $0.animation = nil }
            }
            .movableElement(.value, of: widget)
        }
    }

    @ViewBuilder private func modeLabel(manual: Bool, access: FanCenter.Access, dial: CGFloat) -> some View {
        if widget.shows(.label), FanDial<EmptyView, EmptyView>.showsTexts(diameter: dial) {
            let points = Self.labelPoints(inner: size)
            let text = Self.modeText(manual: manual, access: access)
            WidgetLabel(id: .label, text: text, widget: widget, size: points, weight: .semibold, isSecondary: true,
                        automaticColor: manual ? .orange : nil) {
                Text(text)
                    .font(.system(size: points, weight: .semibold))
                    .foregroundStyle(manual ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .movableElement(.label, of: widget)
        }
    }
}

// MARK: - The dials

/// The dials' arc: open at the bottom, from 135° (bottom left) round through the top to 405°.
nonisolated enum FanDialGeometry {
    static let start: Double = 135
    static let sweep: Double = 270
}

/// The fan's dial: its arc, the fan (a button: back to Auto), the speed under it and the mode in the
/// arc's opening; a dot on the arc where the fans are held. Too small for texts (under 56 pt), the fan
/// alone.
struct FanDial<Value: View, Label: View>: View {
    let fans: [FanReading]
    /// Where the fans are held (0…1), while manual.
    let held: Double?
    let isManual: Bool
    let diameter: CGFloat
    let showsTexts: Bool
    let value: Value?
    let label: Label?
    /// How the arc is drawn and where its name and unit are (`ProgressLook`, as a line's).
    var look: ProgressLook = .plain
    var nameStyle: TextStyle?
    var unitStyle: TextStyle?
    var reportsFrame = false
    let set: (Double) -> Void
    let automatic: () -> Void
    var onInteraction: (Bool) -> Void = { _ in }

    @State private var dragged: Double?
    @State private var taps = 0

    static var start: Double { FanDialGeometry.start }
    static var sweep: Double { FanDialGeometry.sweep }

    static func showsTexts(diameter: CGFloat) -> Bool { diameter >= 56 }

    static func line(diameter: CGFloat) -> CGFloat { max(diameter * 0.055, 2) }

    /// The fan's middle, from the dial's (y down): over the speed when the texts are drawn.
    static func iconCenter(diameter: CGFloat, showsTexts: Bool) -> CGPoint {
        CGPoint(x: 0, y: showsTexts && self.showsTexts(diameter: diameter) ? -diameter * 0.235 : 0)
    }

    static func iconPoints(diameter: CGFloat, showsTexts: Bool) -> CGFloat {
        showsTexts && self.showsTexts(diameter: diameter) ? diameter * 0.19 : diameter * 0.36
    }

    /// 0…1 at a point of the dial (its middle `center`): along the arc; in its opening, the nearer
    /// end — the one the drag came from (`previous`), so it never jumps across.
    static func fraction(at point: CGPoint, center: CGPoint, previous: Double?) -> Double {
        let degrees = atan2(point.y - center.y, point.x - center.x) * 180 / .pi
        var along = (degrees - start).truncatingRemainder(dividingBy: 360)
        if along < 0 { along += 360 }
        if along <= sweep { return along / sweep }
        if let previous { return previous >= 0.5 ? 1 : 0 }
        return along < (sweep + 360) / 2 ? 1 : 0
    }

    /// From the dial's middle to `fraction` along the arc.
    static func offset(of fraction: Double, radius: CGFloat) -> CGSize {
        let angle = (start + sweep * fraction) * .pi / 180
        return CGSize(width: cos(angle) * radius, height: sin(angle) * radius)
    }

    var body: some View {
        let line = Self.line(diameter: diameter)
        let fan = fans.first
        let running = fan.map { $0.fraction(of: $0.rpm) } ?? 0
        let knob = dragged ?? held ?? running
        let texts = showsTexts && Self.showsTexts(diameter: diameter)
        let icon = Self.iconCenter(diameter: diameter, showsTexts: showsTexts)
        let points = Self.iconPoints(diameter: diameter, showsTexts: showsTexts)
        ZStack {
            // The arc, dragged anywhere on the dial.
            ZStack {
                Circle().fill(.white.opacity(0.001))
                // A dot where the fans are held; any other knob the look picks, where they turn too.
                ProgressRing(fraction: running, diameter: diameter, line: line, look: look, start: Self.start, sweep: Self.sweep,
                             automaticTrack: .white.opacity(0.1), minimumFill: 0.004, automaticFill: AnyShapeStyle(FanTint.color(running)),
                             knobAt: knob, forcesKnob: isManual || dragged != nil, animatesKnob: dragged == nil,
                             animation: .easeOut(duration: 0.6), reportsFrame: reportsFrame)
            }
            .contentShape(Circle())
            .gesture(drag)

            if texts {
                // The speed, under it the mode beside "rpm", and the dial's name in its opening.
                let small = WidgetMetrics.points(diameter, ratio: 0.095, min: 7, max: 12)
                VStack(spacing: 0) {
                    if let value { value }
                    HStack(spacing: small * 0.4) {
                        if let label { label }
                        RingText(text: Text("rpm"), style: unitStyle, size: small, part: .remaining, look: look,
                                 reportsFrame: reportsFrame)
                    }
                    .lineLimit(1)
                    .frame(maxWidth: diameter * 0.7)
                }
                .offset(y: diameter * 0.05)
                .allowsHitTesting(false)
                RingText(text: Text("Fan"), style: nameStyle, size: small, weight: .semibold, part: .elapsed, look: look,
                         reportsFrame: reportsFrame)
                    .offset(y: diameter * 0.39)
                    .allowsHitTesting(false)
            }
            FanButton(isManual: isManual, color: FanTint.color(knob), points: points, taps: taps) {
                taps += 1
                if isManual { automatic() }
            }
            .offset(x: icon.x, y: icon.y)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .contain)
        .accessibilityRepresentation {
            Slider(value: Binding(get: { knob }, set: set), in: 0...1) { Text("Fan speed") }
        }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { drag in
                if dragged == nil { onInteraction(true) }
                // The arc's own middle, where its look moved it.
                let center = CGPoint(x: diameter / 2 + look.barOffset.x, y: diameter / 2 + look.barOffset.y)
                let fraction = Self.fraction(at: drag.location, center: center, previous: dragged)
                guard fraction != dragged else { return }
                dragged = fraction
                set(fraction)
            }
            .onEnded { _ in
                dragged = nil
                onInteraction(false)
            }
    }
}

/// The fan: a button that gives the fans back to macOS. In the speed's colour while they are held,
/// white while macOS runs them.
private struct FanButton: View {
    let isManual: Bool
    let color: Color
    let points: CGFloat
    let taps: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "fan.fill")
                .font(.system(size: points, weight: .medium))
                .foregroundStyle(isManual ? AnyShapeStyle(color) : AnyShapeStyle(.primary.opacity(0.85)))
                .symbolEffect(.bounce, value: taps)
                .frame(width: points * 1.6, height: points * 1.6)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(isManual ? "Back to Automatic" : "Automatic")
        .accessibilityLabel(Text(isManual ? "Back to Automatic" : "Automatic"))
    }
}

/// The chip's temperature as a dial like the fan's: filled from 30 to 110 °C, the thermometer, the
/// degrees with their unit, and "Chip" in its opening.
struct TemperatureDial: View {
    let celsius: Double?
    let diameter: CGFloat
    /// "52"; nil before the first reading.
    let number: String?
    /// "°C".
    let unit: String
    /// How the arc is drawn and where its name and degrees are (`ProgressLook`, as a line's).
    var look: ProgressLook = .plain
    var nameStyle: TextStyle?
    var valueStyle: TextStyle?
    var reportsFrame = false

    /// The dial's and the graph's: fixed, so a reading is always as far along.
    static let range = 30.0...110.0
    static let colors: [Color] = [Color(red: 0.25, green: 0.7, blue: 1.0), Color(red: 0.35, green: 0.9, blue: 0.55),
                                  Color(red: 1.0, green: 0.8, blue: 0.25), Color(red: 1.0, green: 0.4, blue: 0.25)]

    static func fraction(_ celsius: Double) -> Double {
        min(max((celsius - range.lowerBound) / (range.upperBound - range.lowerBound), 0), 1)
    }

    static func color(_ fraction: Double) -> Color {
        colors[min(Int(fraction * Double(colors.count)), colors.count - 1)]
    }

    var body: some View {
        let line = FanDial<EmptyView, EmptyView>.line(diameter: diameter)
        let fraction = celsius.map(Self.fraction) ?? 0
        let texts = FanDial<EmptyView, EmptyView>.showsTexts(diameter: diameter)
        let points = FanDial<EmptyView, EmptyView>.iconPoints(diameter: diameter, showsTexts: true)
        ZStack {
            ProgressRing(fraction: fraction, diameter: diameter, line: line, look: look, start: FanDialGeometry.start,
                         sweep: FanDialGeometry.sweep, automaticTrack: .white.opacity(0.1), minimumFill: 0.004,
                         automaticFill: AnyShapeStyle(Self.color(fraction)), animation: .easeOut(duration: 0.6),
                         reportsFrame: reportsFrame)
            Image(systemName: fraction < 0.25 ? "thermometer.low" : fraction < 0.65 ? "thermometer.medium" : "thermometer.high")
                .font(.system(size: points, weight: .medium))
                .foregroundStyle(.primary.opacity(0.85))
                .offset(y: FanDial<EmptyView, EmptyView>.iconCenter(diameter: diameter, showsTexts: true).y)
            if texts {
                let points = WidgetMetrics.points(diameter, ratio: 0.2, min: 8, max: 26)
                RingText(text: degrees(points: points), style: valueStyle, size: points, weight: .semibold, design: .rounded,
                         automatic: AnyShapeStyle(.primary), part: .remaining, look: look, reportsFrame: reportsFrame)
                    .offset(y: diameter * 0.02)
                    .transaction { $0.animation = nil }
                RingText(text: Text("Chip"), style: nameStyle, size: WidgetMetrics.points(diameter, ratio: 0.095, min: 7, max: 12),
                         weight: .semibold, part: .elapsed, look: look, reportsFrame: reportsFrame)
                    .offset(y: diameter * 0.39)
            }
        }
        .lineLimit(1)
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Chip temperature \(number ?? "—") \(unit)"))
    }

    /// "52°C": the degrees with their unit half as large and dimmer — in the style's type where it
    /// has one (its colour then the unit's too).
    private func degrees(points: CGFloat) -> Text {
        guard let valueStyle else {
            return Text(number ?? "—")
                + Text(unit).font(.system(size: points * 0.5, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
        }
        var half = valueStyle
        half.size = (valueStyle.size ?? Double(points)) * 0.5
        return Text(number ?? "—") + Text(unit).font(Font(half.font(size: points * 0.5, weight: .semibold)))
    }
}

// MARK: - The graphs

/// A series over the last ten minutes: its line over a soft fill, in the colours of its values (cool
/// at the bottom, hot at the top), faint guides with their values beside them, and over it its name,
/// the average (dashed, where asked) and the value now. Lower than 40 pt, the line alone.
///
/// Set in Customize as a chart is (`ChartLook`): its corners are the line's joins and the mark at
/// the newest reading, its colours the low, the middle and the high readings', and its step how
/// often a value is written beside it (each with its guide); its texts in one style.
struct SensorGraph: View {
    let title: String
    let samples: [SensorSample]
    let now: Date
    /// The values' span at least (degrees, rpm), so a steady reading is not drawn as a storm.
    let minimumSpan: Double
    /// The range drawn; nil: the values' own, padded.
    let fixedRange: ClosedRange<Double>?
    let colors: [Color]
    let showsAverage: Bool
    let format: (Double) -> String
    let size: CGSize
    var look: ChartLook = .plain
    /// The texts' type and colour; nil: the graph's own.
    var textStyle: TextStyle?

    @Environment(AppModel.self) private var model

    static func range(of values: [Double], minimumSpan: Double) -> ClosedRange<Double> {
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        let middle = (low + high) / 2, span = max(high - low, minimumSpan) * 1.2
        return (middle - span / 2)...(middle + span / 2)
    }

    /// How far back the graph reaches: as far as it has readings, from a minute up to ten — so a
    /// graph just started fills its width and spreads out as its past grows.
    static func span(of samples: [SensorSample], now: Date) -> TimeInterval {
        let reach = samples.first.map { now.timeIntervalSince($0.date) } ?? 0
        return min(max(reach, 60), ThermalMonitor.window)
    }

    /// The line's colours, bottom to top: the graph's own, or — once the look picks any — the
    /// look's low, middle and high (one left automatic keeps the graph's there).
    @MainActor static func colors(_ look: ChartLook, automatic: [Color], model: AppModel) -> [Color] {
        guard look.lowColor != .automatic || look.mediumColor != .automatic || look.highColor != .automatic,
              let first = automatic.first, let last = automatic.last else { return automatic }
        func resolve(_ color: TextStyle.TextColor, _ own: Color) -> Color {
            switch color {
            case .automatic: own
            case .custom(let rgb): rgb.color
            case .artwork: model.media.artworkColor.map { Color($0) } ?? .islandAccent
            }
        }
        return [resolve(look.lowColor, first), resolve(look.mediumColor, automatic[automatic.count / 2]), resolve(look.highColor, last)]
    }

    /// The shares of the range with a guide, top and bottom always.
    static func guides(_ look: ChartLook) -> [Int] { look.percentages.isEmpty ? [0, 100] : look.percentages }

    /// A value's line height beside the plot, at its type's size.
    static func captionHeight(points: CGFloat) -> CGFloat { (points * 1.25).rounded(.up) }

    /// A value's top beside a plot `height` tall: centred on its guide, kept inside at the ends.
    static func captionTop(_ share: Int, height: CGFloat, caption: CGFloat) -> CGFloat {
        min(max(height * (1 - CGFloat(share) / 100) - caption / 2, 0), max(height - caption, 0))
    }

    /// The shares written: the ends always, those between where they are clear of the last one
    /// written and of the top (as the battery chart's percentages are).
    static func written(_ shares: [Int], height: CGFloat, caption: CGFloat) -> [Int] {
        guard let first = shares.first, let last = shares.last else { return [] }
        var kept = [first]
        for share in shares.dropFirst() where share != last {
            let top = captionTop(share, height: height, caption: caption)
            if abs(top - captionTop(kept[kept.count - 1], height: height, caption: caption)) >= caption,
               abs(top - captionTop(last, height: height, caption: caption)) >= caption {
                kept.append(share)
            }
        }
        if last != first { kept.append(last) }
        return kept
    }

    var body: some View {
        let window = ThermalMonitor.window
        let shown = samples.filter { now.timeIntervalSince($0.date) <= window }
        let values = shown.map(\.value)
        let range = fixedRange ?? Self.range(of: values, minimumSpan: minimumSpan)
        let average = values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        let header = size.height >= 40
        let axis = size.height >= 54 && size.width >= 110 && !look.percentages.isEmpty
        let titlePoints = CGFloat(textStyle?.size ?? Double(WidgetMetrics.points(size.height, ratio: 0.11, min: 8, max: 11)))
        let headerHeight = header ? (titlePoints * 1.15 * 1.25).rounded(.up) : 0
        let plotHeight = max(size.height - headerHeight - (header ? 3 : 0), 0)
        let axisPoints = max(titlePoints * 0.82, 7)
        let caption = Self.captionHeight(points: axisPoints)
        VStack(alignment: .leading, spacing: 3) {
            if header {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(title)
                        .foregroundStyle(ink(0.6, automatic: .secondary))
                    if showsAverage, let average {
                        Text("avg \(format(average))")
                            .foregroundStyle(ink(0.4, automatic: .tertiary))
                    }
                    Spacer(minLength: 2)
                    Text(values.last.map(format) ?? "—")
                        .font(font(titlePoints * 1.15, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(ink(1, automatic: .primary))
                }
                .font(font(titlePoints, weight: .medium))
                .lineLimit(1)
                .frame(height: headerHeight)
                .transaction { $0.animation = nil }
            }
            HStack(spacing: 4) {
                if axis {
                    let span = range.upperBound - range.lowerBound
                    ZStack(alignment: .topTrailing) {
                        ForEach(Self.written(look.percentages, height: plotHeight, caption: caption), id: \.self) { share in
                            Text(format(range.lowerBound + span * Double(share) / 100))
                                .frame(height: caption)
                                .offset(y: Self.captionTop(share, height: plotHeight, caption: caption))
                        }
                    }
                    .frame(height: plotHeight, alignment: .topTrailing)
                    .font(font(axisPoints, weight: .medium).monospacedDigit())
                    .foregroundStyle(ink(0.4, automatic: .tertiary))
                    .fixedSize(horizontal: true, vertical: false)
                }
                plot(shown, range: range, average: showsAverage ? average : nil)
                    .frame(height: plotHeight)
            }
        }
        .underline(textStyle?.isUnderlined ?? false)
        .strikethrough(textStyle?.isStruckThrough ?? false)
        .frame(width: size.width, height: size.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(title) \(values.last.map(format) ?? "—")"))
    }

    /// The texts' type: the style's (at `points`), or the graph's own.
    private func font(_ points: CGFloat, weight: NSFont.Weight, design: Font.Design = .default) -> Font {
        guard var style = textStyle else {
            return .system(size: points, weight: weight == .semibold ? .semibold : .medium, design: design)
        }
        style.size = Double(points)
        return Font(style.font(size: points, weight: weight))
    }

    /// The texts' colour: the style's, as strong as the text is in the graph's own.
    private func ink(_ strength: Double, automatic: some ShapeStyle) -> AnyShapeStyle {
        switch textStyle?.color ?? .automatic {
        case .automatic: AnyShapeStyle(automatic)
        case .custom(let rgb): AnyShapeStyle(rgb.color.opacity(strength))
        case .artwork: AnyShapeStyle((model.media.artworkColor.map { Color($0) } ?? .islandAccent).opacity(strength))
        }
    }

    private func plot(_ shown: [SensorSample], range: ClosedRange<Double>, average: Double?) -> some View {
        let window = Self.span(of: shown, now: now)
        let corners = look.corners
        let guides = Self.guides(look)
        return Canvas { context, size in
            let span = max(range.upperBound - range.lowerBound, 0.001)
            func y(_ value: Double) -> CGFloat { size.height * (1 - CGFloat((value - range.lowerBound) / span)) }
            func x(_ date: Date) -> CGFloat {
                // The newest reading's mark clear of the right edge.
                (size.width - 3) * CGFloat(1 - min(max(now.timeIntervalSince(date) / window, 0), 1))
            }
            // The guides: the top and the bottom, and those between fainter.
            for share in guides {
                var guide = Path()
                let level = size.height * (1 - CGFloat(share) / 100)
                guide.move(to: CGPoint(x: 0, y: level))
                guide.addLine(to: CGPoint(x: size.width, y: level))
                context.stroke(guide, with: .color(.white.opacity(share == 0 || share == 100 ? 0.1 : 0.06)), lineWidth: 0.5)
            }
            guard shown.count >= 2 else { return }
            var line = Path()
            for (index, sample) in shown.enumerated() {
                let point = CGPoint(x: x(sample.date), y: min(max(y(sample.value), 0), size.height))
                if index == 0 { line.move(to: point) } else { line.addLine(to: point) }
            }
            var area = line
            area.addLine(to: CGPoint(x: x(shown[shown.count - 1].date), y: size.height))
            area.addLine(to: CGPoint(x: x(shown[0].date), y: size.height))
            area.closeSubpath()
            let shading = GraphicsContext.Shading.linearGradient(Gradient(colors: colors), startPoint: CGPoint(x: 0, y: size.height),
                                                                 endPoint: .zero)
            context.drawLayer { layer in
                layer.opacity = 0.16
                layer.fill(area, with: shading)
            }
            let stroke: StrokeStyle = switch corners {
            case .rounded: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
            case .slight: StrokeStyle(lineWidth: 1.5, lineCap: .butt, lineJoin: .bevel)
            case .square: StrokeStyle(lineWidth: 1.5, lineCap: .square, lineJoin: .miter)
            }
            context.stroke(line, with: shading, style: stroke)
            if let average {
                var dash = Path()
                dash.move(to: CGPoint(x: 0, y: y(average)))
                dash.addLine(to: CGPoint(x: size.width, y: y(average)))
                context.stroke(dash, with: .color(.white.opacity(0.45)), style: StrokeStyle(lineWidth: 0.75, dash: [3, 3]))
            }
            let last = shown[shown.count - 1]
            let mark = CGRect(x: x(last.date) - 2.5, y: min(max(y(last.value), 0), size.height) - 2.5, width: 5, height: 5)
            let shape: Path = switch corners {
            case .rounded: Path(ellipseIn: mark)
            case .slight: Path(roundedRect: mark, cornerRadius: 1.25)
            case .square: Path(mark)
            }
            context.fill(shape, with: .color(.white))
        }
    }
}

/// The fans' colours, slowest to fastest: blue, cyan, green, yellow, orange, red.
enum FanTint {
    static let stops: [(Double, Color)] = [
        (0, Color(red: 0.25, green: 0.55, blue: 1.0)), (0.25, Color(red: 0.2, green: 0.82, blue: 0.95)),
        (0.5, Color(red: 0.35, green: 0.9, blue: 0.45)), (0.7, Color(red: 1.0, green: 0.82, blue: 0.25)),
        (0.85, Color(red: 1.0, green: 0.55, blue: 0.15)), (1, Color(red: 1.0, green: 0.27, blue: 0.25)),
    ]

    static var colors: [Color] { stops.map(\.1) }

    static func color(_ fraction: Double) -> Color {
        stops.last { $0.0 <= fraction }?.1 ?? stops[0].1
    }
}
