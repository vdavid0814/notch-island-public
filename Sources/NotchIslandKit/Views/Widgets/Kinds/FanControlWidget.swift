import SwiftUI

/// Fan Control: in a row, a dial of the fans' speed, a dial of the chip's temperature, and one graph
/// of both — the heat as a line, the fans under it as a row of strokes, far apart while they turn
/// slowly, packed together while they turn fast. The fan is the answer to the heat: the line
/// climbs, the strokes tighten a moment later. Everything is coloured by its reading, green where
/// it is low, yellow halfway, red at the top (`FanTint`).
///
/// The dials are plain arcs open at the bottom, filled as far as the fans turn between standing
/// still and their fastest (the chip between 25 and 100 °C), a bead at the fill's end; over the
/// value a word — the fans' (Auto, Manual, Resting, At max,
/// Off), the chip's (Cool, Warm, Hot) — and under it the dial's name. Turning the fan's dial —
/// dragging anywhere on it — holds the fans at that speed, down to none (a dot where they are
/// held), and they stay there; its word, Manual, is a button that gives them back to macOS.
///
/// The graph reaches back ten seconds to ten minutes: a click on its time under it unfolds the timer's
/// ruler in its place to set that (Done at its left), as Customize's Settings does. Every part is
/// moved and resized in Customize; a graph keeps its lines thin when made lower.
///
/// Read every second while shown (`FanCenter`, `ThermalMonitor`); a picture (the gallery,
/// Customize) shows samples. Offered only on a Mac with a fan (MacBook Pro).
///
/// Each part reads what it shows by itself (`FanDialPart`, `ChipDialPart`, `FanGraphPart`): a turn
/// of the dial redraws the dial alone, a reading the parts that show it.
struct FanControlWidget: View {
    let widget: IslandWidget
    let size: CGSize

    @Environment(AppModel.self) private var model
    @Environment(\.isWidgetPreview) private var isPreview
    @Environment(\.widgetRenderMode) private var renderMode

    /// A MacBook Pro's fan turning at a little over half of what it can, left to macOS.
    static let sample = [FanReading(index: 0, rpm: 3400, minimum: 1200, maximum: 5800, target: 0, isManual: false)]
    /// The chip warm after a load, for the pictures.
    static let sampleChip = ChipReading(average: 71, hottest: 78)

    /// Ten minutes of a chip given a load and the fans answering it, for the pictures: a reading
    /// every five seconds up to `now`, ending at `sample` and `sampleChip`.
    static func sampleHistory(now: Date) -> (temperatures: [SensorSample], speeds: [SensorSample]) {
        func ease(_ a: Double, _ b: Double, _ t: Double) -> Double {
            let x = min(max((t - a) / (b - a), 0), 1)
            return x * x * (3 - 2 * x)
        }
        let window = ThermalMonitor.window
        var temperatures: [SensorSample] = [], speeds: [SensorSample] = []
        for step in 0...120 {
            let t = Double(step) / 120
            let date = now.addingTimeInterval(-window * (1 - t))
            let celsius = 52 + 24 * ease(0.42, 0.55, t) - 5 * ease(0.7, 1, t) + 0.8 * sin(t * 40)
            let rpm = 2300 + 2200 * ease(0.48, 0.6, t) - 1100 * ease(0.72, 0.98, t)
            let phase = speeds.last.map { $0.phase + FanRhythm.advance(rpm: $0.value, maximum: 5800, seconds: date.timeIntervalSince($0.date)) } ?? 0
            temperatures.append(SensorSample(date: date, value: celsius))
            speeds.append(SensorSample(date: date, value: rpm, phase: phase))
        }
        return (temperatures, speeds)
    }

    /// How far back the graph reaches, in seconds: as set, or its longest.
    static func seconds(_ widget: IslandWidget) -> Int {
        clamped(widget.config.seconds ?? WidgetConfig.secondsRange.upperBound)
    }

    static func clamped(_ seconds: Int) -> Int {
        min(max(seconds, WidgetConfig.secondsRange.lowerBound), WidgetConfig.secondsRange.upperBound)
    }

    /// The seconds as stored: the longest is the graph's own (nil).
    static func stored(_ seconds: Int) -> Int? {
        let clamped = clamped(seconds)
        return clamped == WidgetConfig.secondsRange.upperBound ? nil : clamped
    }

    /// A reach in words: "10 min", "45 s", "2 min 30 s".
    static func span(_ seconds: Int) -> String {
        let minutes = seconds / 60, rest = seconds % 60
        if minutes == 0 { return String(localized: "\(rest) s") }
        return rest == 0 ? String(localized: "\(minutes) min") : String(localized: "\(minutes) min \(rest) s")
    }

    // MARK: Layout

    /// What the row holds at a size: the dials' diameter, whether the temperature's dial fits, and
    /// whether the graph does, with its width.
    struct Layout: Equatable {
        var dial: CGFloat
        var gap: CGFloat
        var showsTempDial: Bool
        var graphs: [ElementID]
        var graphWidth: CGFloat

        /// A graph narrower than this is not drawn.
        static let minimumGraph: CGFloat = 80
    }

    static func layout(_ widget: IslandWidget, inner: CGSize) -> Layout {
        // A little inside the widget's height: the arcs' round ends clear of its edges.
        let dial = max(min(inner.height * 0.94, inner.width), 16)
        let gap = min(max(inner.height * 0.12, 6), 14)
        var used = dial
        let tempDial = widget.shows(.tempDial) && inner.width - used >= gap + dial
        if tempDial { used += gap + dial }
        let room = inner.width - used - gap
        let graphs: [ElementID] = widget.shows(.tempGraph) && room >= Layout.minimumGraph ? [.tempGraph] : []
        return Layout(dial: dial, gap: gap, showsTempDial: tempDial, graphs: graphs, graphWidth: graphs.isEmpty ? 0 : room)
    }

    /// Whether `element` has room at this size (one switched on that has none is not drawn).
    static func hasRoom(for element: ElementID, in widget: IslandWidget, inner: CGSize) -> Bool {
        var shown = widget
        shown.options.insert(element)
        let layout = layout(shown, inner: inner)
        return switch element {
        case .tempDial: layout.showsTempDial
        case .tempGraph: layout.graphs.contains(element)
        case .value, .label: FanDial.showsTexts(diameter: layout.dial)
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
        return rpm(averageRPM(fans), locale: locale)
    }

    static func averageRPM(_ fans: [FanReading]) -> Double {
        fans.isEmpty ? 0 : fans.map(\.rpm).reduce(0, +) / Double(fans.count)
    }

    static func rpm(_ value: Double, locale: Locale) -> String {
        Int((value / 10).rounded() * 10).formatted(.number.locale(locale))
    }

    /// The fans' word over their speed: Auto — Resting while they stand still, At max at their
    /// fastest — or Manual (Off where held at none); what is missing when the fans cannot be set;
    /// for a few seconds, that the chip was too hot to keep them held.
    static func modeText(manual: Bool, access: FanCenter.Access, tooHot: Bool = false, rpm: Double? = nil,
                         maximum: Double? = nil) -> String {
        switch access {
        case .needsApproval: return String(localized: "Allow in Login Items")
        case .installing: return String(localized: "Password…")
        case .failed: return String(localized: "Unavailable")
        default: break
        }
        let stopped = rpm.map { $0 < 1 } ?? false
        if manual { return stopped ? String(localized: "Off") : String(localized: "Manual") }
        if tooHot { return String(localized: "Too hot") }
        if stopped { return String(localized: "Resting") }
        if let rpm, let maximum, maximum > 0, rpm >= maximum * 0.98 { return String(localized: "At max") }
        return String(localized: "Auto")
    }

    /// Something is missing to set the fans, or the chip was too hot to hold them: the word in
    /// orange. Held by hand is no warning: the graph shows what that does.
    static func isAlert(manual: Bool, access: FanCenter.Access, tooHot: Bool = false) -> Bool {
        switch access {
        case .needsApproval, .installing, .failed: true
        default: tooHot && !manual
        }
    }

    /// The chip's word over its degrees: cool under 55 °C, hot from 90 °C.
    static func warmth(_ celsius: Double) -> String {
        celsius < 55 ? String(localized: "Cool") : celsius < 90 ? String(localized: "Warm") : String(localized: "Hot")
    }

    /// The dial's tooltip: how to set the fans, or why they cannot be.
    static func accessHelp(_ access: FanCenter.Access) -> String {
        switch access {
        case .needsApproval: String(localized: "Switch NotchIsland on in System Settings ▸ General ▸ Login Items, then turn the dial again.")
        case .installing: String(localized: "macOS is asking for an administrator's password, once, to install the helper that sets the fans.")
        case .failed(let reason): String(localized: "The fans cannot be set: \(reason) Turn the dial to try again.")
        default: String(localized: "Turn the dial to set the fans' speed, down to none; it stays until you click Manual for automatic.")
        }
    }

    /// "52°", in the locale's unit.
    static func degrees(_ celsius: Double, locale: Locale) -> String {
        "\(degreeNumber(celsius, locale: locale))°"
    }

    /// "15°": a difference of degrees, in the locale's unit (no 32 added).
    static func degreeStep(_ celsius: Double, locale: Locale) -> String {
        "\(Int((locale.measurementSystem == .us ? celsius * 9 / 5 : celsius).rounded()))°"
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
        let layout = Self.layout(widget, inner: size)
        let lone = !layout.showsTempDial && layout.graphs.isEmpty
        HStack(spacing: layout.gap) {
            FanDialPart(widget: widget, diameter: layout.dial, picture: picture)
                .frame(width: layout.dial, height: layout.dial)
                .movableElement(.fanDial, of: widget)
            if layout.showsTempDial {
                ChipDialPart(widget: widget, diameter: layout.dial, picture: picture)
                    .frame(width: layout.dial, height: layout.dial)
                    .movableElement(.tempDial, of: widget)
            }
            if !layout.graphs.isEmpty {
                // The graph, as large as Customize resized it (from its top-leading corner), its lines as thin.
                let scale = widget.scale(of: .tempGraph)
                let drawn = CGSize(width: layout.graphWidth * scale.x, height: size.height * scale.y)
                FanGraphPart(widget: widget, picture: picture, size: drawn)
                    .frame(width: drawn.width, height: drawn.height)
                    .frame(width: layout.graphWidth, height: size.height, alignment: .topLeading)
                    .movableElement(.tempGraph, of: widget, drawsScale: false)
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
}

/// The fan's dial with the fans as they are: their speed, whether they are held and at what, and
/// what is missing to set them.
private struct FanDialPart: View {
    let widget: IslandWidget
    let diameter: CGFloat
    let picture: Bool

    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale
    @Environment(\.reportsProgressParts) private var reportsParts

    var body: some View {
        let center = model.fans
        let fans = picture || center.fans.isEmpty ? FanControlWidget.sample : center.fans
        let manual = !picture && center.isManual
        let access = picture ? FanCenter.Access.unknown : center.access
        let tooHot = !picture && center.isTooHot
        let rpm = FanControlWidget.averageRPM(fans)
        FanDial(fans: fans, held: picture ? nil : center.heldFraction, isManual: manual, diameter: diameter,
                number: widget.shows(.value) ? FanControlWidget.rpmText(fans, locale: locale) : nil,
                mode: widget.shows(.label) ? FanControlWidget.modeText(manual: manual, access: access, tooHot: tooHot, rpm: rpm,
                                                                        maximum: fans.map(\.maximum).max()) : nil,
                modeIsAlert: FanControlWidget.isAlert(manual: manual, access: access, tooHot: tooHot),
                look: widget.progressLook(of: .fanDial), nameStyle: widget.textStyles[.fanName],
                valueStyle: widget.textStyles[.value], reportsFrame: reportsParts, isLive: !picture,
                set: { center.setSpeed($0) }, automatic: { center.setAutomatic() },
                onInteraction: { model.island.isInteracting = $0 })
            .help(FanControlWidget.accessHelp(access))
    }
}

/// The chip's dial at the chip's temperature now.
private struct ChipDialPart: View {
    let widget: IslandWidget
    let diameter: CGFloat
    let picture: Bool

    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale
    @Environment(\.reportsProgressParts) private var reportsParts

    var body: some View {
        let chip = picture ? FanControlWidget.sampleChip : model.thermals.chip
        TemperatureDial(celsius: chip?.average, diameter: diameter,
                        number: chip.map { FanControlWidget.degreeNumber($0.average, locale: locale) },
                        unit: FanControlWidget.degreeUnit(locale: locale), look: widget.progressLook(of: .tempDial),
                        nameStyle: widget.textStyles[.tempName], valueStyle: widget.textStyles[.tempValue],
                        reportsFrame: reportsParts, isLive: !picture)
    }
}

/// The graph of the heat and the fans, as far back as the widget is set to — or, unfolded by a
/// click on its time, the timer's ruler setting that (`FanHistorySetter`).
private struct FanGraphPart: View {
    let widget: IslandWidget
    let picture: Bool
    let size: CGSize

    @Environment(AppModel.self) private var model
    @Environment(\.widgetDate) private var fixedDate
    @Environment(\.locale) private var locale

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
        let look = widget.chartLook(of: .tempGraph)
        let colors = FanHeatGraph.colors(look, model: model)
        let history: (temperatures: [SensorSample], speeds: [SensorSample]) =
            picture ? FanControlWidget.sampleHistory(now: now) : (model.thermals.temperatures, model.thermals.speeds)
        let stopped = !picture && model.fans.isManual ? String(localized: "Fan off") : String(localized: "Fan resting")
        let window = TimeInterval(FanControlWidget.seconds(widget))
        let range = look.range(own: FanHeatGraph.temperatureRange, gap: 5)
        let setHistory: (() -> Void)? = picture ? nil : { unfold() }
        let fans = picture || model.fans.fans.isEmpty ? FanControlWidget.sample : model.fans.fans
        return FanHeatGraph(temperatures: history.temperatures, speeds: history.speeds, now: now, window: window, range: range,
                            heat: colors.heat, fan: colors.fan, fanMaximum: fans.map(\.maximum).max() ?? 5800, corners: look.corners,
                            stopped: stopped, locale: locale, size: size, textStyle: widget.textStyles[.tempGraphText],
                            setHistory: setHistory)
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

/// How far back the graph reaches, set as the timer is: its ruler over a row of Done (at the left)
/// and the time (at the right), in the timer's orange. The ruler sets the minutes or the seconds —
/// a click on either in the time, or on the unit's name beside the marker, picks which — and each
/// step of it is felt.
struct FanHistorySetter: View {
    @Binding var seconds: Int
    let size: CGSize
    let done: () -> Void

    @Environment(AppModel.self) private var model
    @State private var unit = TimerUnit.minutes

    var body: some View {
        let space = TimerWidget.rulerSpace(inner: size)
        let spacing = TimerWidget.spacing(inner: size)
        let row = size.height - space - spacing
        let diameter = min(max(row * 0.82, 22), 40).rounded()
        let points = max(min(WidgetMetrics.points(row, ratio: 0.72, min: 12, max: 44), (size.width * 0.45 / 2.6).rounded(.down)), 10)
        let range = Self.range(of: unit, at: seconds)
        VStack(spacing: spacing) {
            TimerRuler(minutes: Binding(get: { unit == .minutes ? seconds / 60 : seconds % 60 }, set: set),
                       range: range, minimum: 0, unit: unit, nextUnit: nextUnit, unitName: RulerUnitName(),
                       showsLabels: size.height >= 100, tint: TimerWidget.tint,
                       onInteraction: { model.island.isInteracting = $0 }, markerSize: space < 30 ? 7 : 9, isAwake: true)
                .frame(height: space)
            HStack(alignment: .bottom) {
                Button(action: done) {
                    Label {
                        Text("Done")
                    } icon: {
                        Image(systemName: "checkmark")
                            .font(.system(size: diameter * 0.4, weight: .semibold))
                            .frame(width: diameter - 2 * TimerWidget.glassPadding, height: diameter - 2 * TimerWidget.glassPadding)
                    }
                }
                .islandButton(.circle, prominent: true)
                .controlSize(.large)
                .help("Done")
                Spacer(minLength: 4)
                // "2:30", as the timer writes it: the part the ruler sets bright, a click on the other picks it.
                HStack(spacing: 0) {
                    part(.minutes, "\(seconds / 60)")
                    Text(":").opacity(LabelSegment.fadedOpacity)
                    part(.seconds, String(format: "%02d", seconds % 60))
                }
                .font(.system(size: points, design: .rounded).monospacedDigit())
                .foregroundStyle(TimerWidget.tint)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .transaction { $0.animation = nil }
            }
            .frame(height: max(row, 0), alignment: .bottom)
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .tint(TimerWidget.tint)
    }

    /// What the ruler offers in `unit` at a reach of `seconds`: minutes 0 to 10; seconds from 10
    /// while the minutes are 0 (nothing it cannot be set to), from 0 once a minute is set.
    static func range(of unit: TimerUnit, at seconds: Int) -> ClosedRange<Int> {
        if unit == .minutes { return 0...(WidgetConfig.secondsRange.upperBound / 60) }
        return (seconds < 60 ? WidgetConfig.secondsRange.lowerBound : 0)...59
    }

    private func part(_ part: TimerUnit, _ text: String) -> some View {
        Text(text)
            .opacity(unit == part ? 1 : LabelSegment.fadedOpacity)
            .contentShape(.rect)
            .onTapGesture { unit = part }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(Text("\(part == .minutes ? seconds / 60 : seconds % 60) \(part.accessibilityTitle)"))
    }

    private func nextUnit() {
        unit = unit == .minutes ? .seconds : .minutes
    }

    /// The ruler moved: the unit it sets to `value`, the other kept, held between ten seconds and
    /// ten minutes; a tick felt for each change.
    private func set(_ value: Int) {
        let total = unit == .minutes ? value * 60 + seconds % 60 : seconds / 60 * 60 + value
        let held = FanControlWidget.clamped(total)
        guard held != seconds else { return }
        seconds = held
        model.haptics.play(.tick)
    }
}

// MARK: - The dials

/// The dials' arc: open at the bottom, from 135° (bottom left) round through the top to 405°.
nonisolated enum FanDialGeometry {
    static let start: Double = 135
    static let sweep: Double = 270

    /// The dials' and graphs' own texts and lines: white on the dark island, black where its content
    /// is drawn light (Light Mode on Liquid Glass, `IslandGlassStyle.appearsLight`).
    static func ink(_ scheme: ColorScheme) -> Color { scheme == .light ? .black : .white }

    /// The arc under the fill: faint, a little stronger on a light island.
    static func track(_ scheme: ColorScheme) -> Color { scheme == .light ? .black.opacity(0.12) : .white.opacity(0.08) }
}

/// The fan's dial, made as the chip's is: its arc, in the colour of the speed, with a bead at the fill's end, the fans' word
/// over their speed with "rpm", and its name in the arc's opening, always; a dot on the arc where
/// they are held. Standing still, the word alone in the middle. Held by hand, the word (Manual) is
/// a button that gives them back to macOS. Too small for texts (under 56 pt), the arc alone.
struct FanDial: View {
    let fans: [FanReading]
    /// Where the fans are held (0…1), while manual.
    let held: Double?
    let isManual: Bool
    let diameter: CGFloat
    var showsTexts = true
    /// "2,450"; nil: the speed is not shown.
    let number: String?
    var unit = "rpm"
    /// "Auto", "Manual"… (or what is missing to set the fans), over the speed; nil: not shown.
    var mode: String?
    /// The word in orange (something is missing).
    var modeIsAlert = false
    /// "Fan": in the arc's opening, whatever the mode.
    var name = String(localized: "Fan")
    /// How the arc is drawn and where its name and speed are (`ProgressLook`, as a line's).
    var look: ProgressLook = .plain
    var nameStyle: TextStyle?
    var valueStyle: TextStyle?
    var reportsFrame = false
    /// On the island (not a picture): the arc's glides on the render server.
    var isLive = false
    let set: (Double) -> Void
    let automatic: () -> Void
    var onInteraction: (Bool) -> Void = { _ in }

    @State private var dragged: Double?
    @Environment(\.colorScheme) private var scheme

    static var start: Double { FanDialGeometry.start }
    static var sweep: Double { FanDialGeometry.sweep }

    static func showsTexts(diameter: CGFloat) -> Bool { diameter >= 56 }

    static func line(diameter: CGFloat) -> CGFloat { max(diameter * 0.059, 2) }

    /// The word's middle, from the dial's (y down): over the speed.
    static func modeCenter(diameter: CGFloat) -> CGFloat { -diameter * 0.178 }

    static func modePoints(diameter: CGFloat) -> CGFloat { WidgetMetrics.points(diameter, ratio: 0.1, min: 7, max: 12) }

    /// The word alone in the middle, while the fans stand still.
    static func restingPoints(diameter: CGFloat) -> CGFloat { WidgetMetrics.points(diameter, ratio: 0.17, min: 8, max: 22) }

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
        let stopped = FanControlWidget.averageRPM(fans) < 1
        ZStack {
            // The arc, dragged anywhere on the dial.
            ZStack {
                Circle().fill(.white.opacity(0.001))
                // A dot where the fans are held; any other knob the look picks, where they turn too;
                // else a bead at the fill's end.
                if isLive, RingLayers.supports(look) {
                    // Live: the glides on the render server (`RingLayers`).
                    RingLayers(fraction: running, diameter: diameter, line: line, look: look, start: Self.start, sweep: Self.sweep,
                               automaticTrack: FanDialGeometry.track(scheme), minimumFill: stopped ? 0 : 0.004,
                               automaticFill: FanTint.at(running).color, knobAt: knob, forcesKnob: isManual || dragged != nil,
                               animatesKnob: dragged == nil, bead: FanTint.at(running).color)
                } else {
                    ProgressRing(fraction: running, diameter: diameter, line: line, look: look, start: Self.start, sweep: Self.sweep,
                                 // Standing still: no fill at all (a round end's dot read as turning).
                                 automaticTrack: FanDialGeometry.track(scheme), minimumFill: stopped ? 0 : 0.004,
                                 automaticFill: AnyShapeStyle(FanTint.at(running).color),
                                 knobAt: knob, forcesKnob: isManual || dragged != nil, animatesKnob: dragged == nil,
                                 bead: FanTint.at(running).color, animation: isLive ? .easeOut(duration: 0.6) : nil, reportsFrame: reportsFrame)
                }
            }
            .contentShape(Circle())
            .gesture(drag)

            if texts {
                if stopped, let mode {
                    // Standing still: the word alone, no bare zero.
                    word(mode, points: Self.restingPoints(diameter: diameter), opacity: 0.72)
                        .frame(maxWidth: diameter * 0.7)
                } else {
                    if let number {
                        let points = WidgetMetrics.points(diameter, ratio: 0.2, min: 8, max: 26)
                        RingText(text: speed(number, points: points), style: valueStyle, size: points, weight: .semibold, design: .rounded,
                                 automatic: AnyShapeStyle(.primary), part: .remaining, look: look, reportsFrame: reportsFrame,
                                 limit: RingText.valueLimit(diameter: diameter, line: line))
                            .offset(y: diameter * 0.02)
                            // A new reading each second: it just changes (a cross-fade a second smeared).
                            .transaction { $0.animation = nil }
                            .allowsHitTesting(false)
                    }
                    if let mode {
                        word(mode, points: Self.modePoints(diameter: diameter), opacity: 0.5)
                            .frame(maxWidth: diameter * 0.6)
                            .offset(y: Self.modeCenter(diameter: diameter))
                    }
                }
                RingText(text: Text(name), style: nameStyle, size: WidgetMetrics.points(diameter, ratio: 0.095, min: 7, max: 12),
                         weight: .semibold, part: .elapsed, look: look, reportsFrame: reportsFrame,
                         limit: RingText.nameLimit(diameter: diameter))
                    .offset(y: diameter * 0.39)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .contain)
        .accessibilityRepresentation {
            Slider(value: Binding(get: { knob }, set: set), in: 0...1) { Text("Fan speed") }
        }
    }

    /// The fans' word, in the name's type: held by hand, a button back to Automatic.
    @ViewBuilder private func word(_ text: String, points: CGFloat, opacity: Double) -> some View {
        let label = Text(text)
            .font(modeFont(points))
            .foregroundStyle(modeIsAlert ? AnyShapeStyle(Color.orange) : AnyShapeStyle(FanDialGeometry.ink(scheme).opacity(opacity)))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .transaction { $0.animation = nil }
        if isManual {
            Button(action: automatic) { label.contentShape(.rect) }
                .buttonStyle(.plain)
                .help("Back to Automatic")
                .accessibilityLabel(Text("Back to Automatic"))
                .besideProgressParts()
        } else {
            label
                .allowsHitTesting(false)
                .besideProgressParts()
        }
    }

    /// The word's type: the name's where Customize set one (at the word's own size), else the dial's.
    private func modeFont(_ points: CGFloat) -> Font {
        guard var style = nameStyle else { return .system(size: points, weight: .medium, design: .rounded) }
        style.size = Double(points)
        return Font(style.font(size: points, weight: .medium))
    }

    /// "2,450 rpm": the speed with its unit under half as large and dimmer — in the style's type
    /// where it has one (its colour then the unit's too).
    private func speed(_ number: String, points: CGFloat) -> Text {
        guard let valueStyle = RingText.capped(valueStyle) else {
            return Text(number)
                + Text(" " + unit).font(.system(size: points * 0.45, weight: .medium, design: .rounded)).foregroundStyle(FanDialGeometry.ink(scheme).opacity(0.5))
        }
        var small = valueStyle
        small.size = (valueStyle.size ?? Double(points)) * 0.45
        return Text(number) + Text(" " + unit).font(Font(small.font(size: points * 0.45, weight: .semibold)))
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

/// The chip's temperature as a dial like the fan's (`ReadingDial`): its arc, in the colour of the
/// warmth, filled from 25 to 100 °C with a bead at the end, its word (Cool, Warm, Hot) over the
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
    /// On the island (not a picture): the arc's glides on the render server.
    var isLive = false

    /// The dial's: fixed, so a reading is always as far along.
    static let range = 25.0...100.0

    static func fraction(_ celsius: Double) -> Double {
        min(max((celsius - range.lowerBound) / (range.upperBound - range.lowerBound), 0), 1)
    }

    var body: some View {
        ReadingDial(fraction: celsius.map(Self.fraction), diameter: diameter, number: number, unit: unit,
                    word: celsius.map(FanControlWidget.warmth), name: String(localized: "Chip"), look: look, nameStyle: nameStyle,
                    valueStyle: valueStyle, reportsFrame: reportsFrame, isLive: isLive,
                    accessibilityLabel: String(localized: "Chip temperature \(number ?? "—") \(unit)"))
    }
}

/// A reading as a dial, made as the fan's is — the chip's temperature, System's loads: its arc open
/// at the bottom, filled as far as the reading in its colour (`FanTint`: green, yellow, red) with a
/// bead at the fill's end, its word over the value, the value with its unit smaller and dimmer, and
/// its name in the arc's opening. Too small for texts (under 56 pt), the arc alone.
struct ReadingDial: View {
    /// 0…1 along the arc; nil before the first reading (nothing filled).
    let fraction: Double?
    let diameter: CGFloat
    /// "52"; nil before the first reading.
    let number: String?
    /// "°C", " GB": after the number, `unitScale` as large.
    let unit: String
    var unitScale: CGFloat = 0.5
    /// "Warm": over the value; nil: none.
    let word: String?
    /// "Chip": in the arc's opening.
    let name: String
    /// How the arc is drawn and where its name and value are (`ProgressLook`, as a line's).
    var look: ProgressLook = .plain
    var nameStyle: TextStyle?
    var valueStyle: TextStyle?
    var reportsFrame = false
    /// On the island (not a picture): the arc's glides on the render server.
    var isLive = false
    let accessibilityLabel: String

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let line = FanDial.line(diameter: diameter)
        let filled = fraction ?? 0
        let texts = FanDial.showsTexts(diameter: diameter)
        ZStack {
            if isLive, RingLayers.supports(look) {
                RingLayers(fraction: filled, diameter: diameter, line: line, look: look, start: FanDialGeometry.start,
                           sweep: FanDialGeometry.sweep, automaticTrack: FanDialGeometry.track(scheme), minimumFill: fraction == nil ? 0 : 0.004,
                           automaticFill: FanTint.at(filled).color, bead: FanTint.at(filled).color)
            } else {
                ProgressRing(fraction: filled, diameter: diameter, line: line, look: look, start: FanDialGeometry.start,
                             sweep: FanDialGeometry.sweep, automaticTrack: FanDialGeometry.track(scheme), minimumFill: fraction == nil ? 0 : 0.004,
                             automaticFill: AnyShapeStyle(FanTint.at(filled).color), bead: FanTint.at(filled).color,
                             animation: isLive ? .easeOut(duration: 0.6) : nil, reportsFrame: reportsFrame)
            }
            if texts {
                let points = WidgetMetrics.points(diameter, ratio: 0.2, min: 8, max: 26)
                if let word {
                    Text(word)
                        .font(wordFont(FanDial.modePoints(diameter: diameter)))
                        .foregroundStyle(FanDialGeometry.ink(scheme).opacity(0.5))
                        .frame(maxWidth: diameter * 0.6)
                        .minimumScaleFactor(0.5)
                        .offset(y: FanDial.modeCenter(diameter: diameter))
                        .transaction { $0.animation = nil }
                        .besideProgressParts()
                }
                RingText(text: value(points: points), style: valueStyle, size: points, weight: .semibold, design: .rounded,
                         automatic: AnyShapeStyle(.primary), part: .remaining, look: look, reportsFrame: reportsFrame,
                         limit: RingText.valueLimit(diameter: diameter, line: line))
                    .offset(y: diameter * 0.02)
                    .transaction { $0.animation = nil }
                RingText(text: Text(name), style: nameStyle, size: WidgetMetrics.points(diameter, ratio: 0.095, min: 7, max: 12),
                         weight: .semibold, part: .elapsed, look: look, reportsFrame: reportsFrame,
                         limit: RingText.nameLimit(diameter: diameter))
                    .offset(y: diameter * 0.39)
            }
        }
        .lineLimit(1)
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabel))
    }

    /// The word's type: the name's where Customize set one (at the word's own size), else the dial's.
    private func wordFont(_ points: CGFloat) -> Font {
        guard var style = nameStyle else { return .system(size: points, weight: .medium, design: .rounded) }
        style.size = Double(points)
        return Font(style.font(size: points, weight: .medium))
    }

    /// "52°C": the value with its unit smaller and dimmer — in the style's type where it has one
    /// (its colour then the unit's too).
    private func value(points: CGFloat) -> Text {
        guard let valueStyle = RingText.capped(valueStyle) else {
            return Text(number ?? "—")
                + Text(unit).font(.system(size: points * unitScale, weight: .medium, design: .rounded)).foregroundStyle(FanDialGeometry.ink(scheme).opacity(0.5))
        }
        var small = valueStyle
        small.size = (valueStyle.size ?? Double(points)) * Double(unitScale)
        return Text(number ?? "—") + Text(unit).font(Font(small.font(size: points * unitScale, weight: .semibold)))
    }
}

// MARK: - The graph

/// Green where a reading is low, yellow halfway, red at the top — smoothly between them: the fan's
/// dial by its speed, the chip's dial and the heat line by the temperature, each of the fans'
/// strokes by their speed at its moment.
nonisolated struct FanTint: Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double

    static let low = FanTint(red: 0.30, green: 0.85, blue: 0.45)
    static let middle = FanTint(red: 1.0, green: 0.82, blue: 0.25)
    static let high = FanTint(red: 1.0, green: 0.30, blue: 0.25)

    /// At `fraction` of the way from low (0) to high (1).
    static func at(_ fraction: Double) -> FanTint {
        let f = min(max(fraction.isFinite ? fraction : 0, 0), 1)
        let (from, to, t) = f < 0.5 ? (low, middle, f * 2) : (middle, high, (f - 0.5) * 2)
        // Weighted so that the ends come out exactly.
        return FanTint(red: from.red * (1 - t) + to.red * t, green: from.green * (1 - t) + to.green * t,
                       blue: from.blue * (1 - t) + to.blue * t)
    }

    /// A colour Customize picked, as a tint.
    init(_ color: Color) {
        let rgb = NSColor(color).usingColorSpace(.sRGB) ?? .white
        self.init(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent)
    }

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    var color: Color { Color(.sRGB, red: red, green: green, blue: blue) }

    func cgColor(_ alpha: Double = 1) -> CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}

/// The heat and the fans over the last minutes, in one graph: the chip's temperature as a line
/// over a soft fill, from 30° up to a dotted limit (100°, written over it), in the colour of its
/// warmth, its newest reading a dot at the right; a dotted line at the lowest temperature in view,
/// written at its left; under it the fans as a row of strokes, one stamped wherever their run
/// passes a step (`FanRhythm`) — the faster they turn, the closer and the redder. Under the row,
/// its key: how far back it reaches (a button: the ruler to set that), slow and fast, now.
///
/// Live, it slides: each new reading is drawn once, and Core Animation carries the drawing left in
/// a short soft glide on the render server (`FanGraphLayerView`) — one step a reading looked like a
/// jump on a short graph.
///
/// Where the fans stand still the row is empty and says so; a graph whose past is shorter than it
/// reaches says it fills in. Lower than 56 pt, the lines and the row alone; lower than 22, the line.
///
/// Set in Customize as a chart is (`ChartLook`): its corners are the line's joins and the dot at
/// the newest reading, its high colour the heat's, its low colour the fans' (each by its reading
/// while Automatic), its range the line's; its texts in one style.
struct FanHeatGraph: View {
    let temperatures: [SensorSample]
    let speeds: [SensorSample]
    let now: Date
    /// How far back it reaches, in seconds.
    let window: TimeInterval
    /// The temperatures from the bottom of the line's room to its dotted limit.
    let range: ClosedRange<Double>
    /// The line's colour and the strokes'; nil: by the reading (`FanTint`).
    var heat: Color?
    var fan: Color?
    /// The fans' fastest, for the strokes' colours.
    var fanMaximum: Double = 5800
    var corners: ChartLook.Corners = .rounded
    /// Where the fans stand still, in the row: "Fan resting" (or "Fan off", held there).
    let stopped: String
    let locale: Locale
    let size: CGSize
    /// The texts' type and colour; nil: the graph's own.
    var textStyle: TextStyle?
    /// A click on its time: the ruler setting how far back it reaches; nil: a picture (drawn still).
    var setHistory: (() -> Void)?

    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme

    /// The line's own range: a floor of 30° up to the 100° limit.
    static let temperatureRange = 30.0...100.0
    /// The texts' sizes Customize offers.
    static let textSizes = 6.0...15.0

    /// The texts' own size on a graph `height` tall.
    static func textPoints(height: CGFloat) -> CGFloat { WidgetMetrics.points(height, ratio: 0.075, min: 8, max: 11) }

    /// The line's colour and the strokes' where the look picks one; nil: by the reading.
    @MainActor static func colors(_ look: ChartLook, model: AppModel) -> (heat: Color?, fan: Color?) {
        func resolve(_ color: TextStyle.TextColor) -> Color? {
            switch color {
            case .automatic: nil
            case .custom(let rgb): rgb.color
            case .artwork: model.media.artworkColor.map { Color($0) } ?? .islandAccent
            }
        }
        return (resolve(look.highColor), resolve(look.lowColor))
    }

    /// Where its parts are, at a size: the dotted limit (the range's top) and the line's floor, the
    /// row of strokes under them, and the key under the row.
    nonisolated struct Layout: Equatable, Sendable {
        var showsTexts: Bool
        var limit: CGFloat
        var floor: CGFloat
        /// The row of strokes; empty where it has no room.
        var row: ClosedRange<CGFloat>?
        var key: CGFloat
        var line: CGFloat
        /// The newest reading's x: the dot clear of the right edge.
        var right: CGFloat
    }

    static func layout(_ size: CGSize, caption: CGFloat) -> Layout {
        let h = size.height
        let line = max(1.25, h * 0.0125)
        let right = max(size.width - line * 3 - 1, 1)
        if h >= 56 {
            // The proposal's proportions: the line's room 63 %, a gap, the strokes 20 %, a gap.
            let room = h - 2 * caption - 2
            let limit = caption + 2
            return Layout(showsTexts: true, limit: limit, floor: limit + room * 0.63,
                          row: (limit + room * 0.723)...(limit + room * 0.927), key: h - caption, line: line, right: right)
        }
        let limit = line * 3
        if h >= 22 {
            return Layout(showsTexts: false, limit: limit, floor: h * 0.62, row: (h * 0.72)...h, key: h, line: line, right: right)
        }
        return Layout(showsTexts: false, limit: limit, floor: h - 1, row: nil, key: h, line: line, right: right)
    }

    /// How far back it reaches, under its left end: "10 min ago", "2 min 30 s ago".
    static func reach(_ window: TimeInterval) -> String {
        String(localized: "\(FanControlWidget.span(Int(window.rounded()))) ago")
    }

    var body: some View {
        let points = CGFloat(min(textStyle?.size ?? Double(Self.textPoints(height: size.height)), Self.textSizes.upperBound))
        let caption = (points * 1.25).rounded(.up)
        let layout = Self.layout(size, caption: caption)
        // Drawn from the newest reading (at the right edge), not from the moment the body is made.
        let newest = temperatures.last?.date ?? now
        let start = newest.addingTimeInterval(-window)
        // Live, the drawing reaches a slide's length further left, under the edge: a slide starts
        // with the picture a step to the right, and without it that strip flashed empty.
        let lead = setHistory == nil ? 0 : min(Self.leadSeconds, window)
        let shown = Self.within(temperatures, from: start.addingTimeInterval(-lead))
        let drawing = drawing(layout: layout, newest: newest, shown: shown, lead: lead)
        let lowest = shown.filter { $0.date >= start }.map(\.value).min()
        let ink = inkColor
        ZStack(alignment: .topLeading) {
            limitLine(layout: layout, points: points, caption: caption, ink: ink)
            if setHistory == nil, let lowest {
                // A picture's; the live graph's is a layer of its own, gliding on the render server.
                lowestLine(lowest, layout: layout, points: points, caption: caption, ink: ink)
            }
            if setHistory == nil {
                // A picture: drawn still, its newest dot with it.
                Canvas { context, _ in
                    context.withCGContext { drawing.draw(in: $0, fade: fadesIn, dot: true) }
                }
                .frame(width: size.width, height: size.height)
                .allowsHitTesting(false)
            } else {
                FanGraphLayers(drawing: drawing, newest: newest, window: window, fadesIn: fadesIn,
                               dots: shown.last.map { [FanGraphLayers.Dot(y: y($0.value, layout: layout), tint: drawing.heatTint(at: y($0.value, layout: layout)))] } ?? [],
                               lowest: lowest.map { celsius in
                                   FanGraphLayers.Lowest(y: y(celsius, layout: layout),
                                                         text: layout.showsTexts ? FanControlWidget.degrees(celsius, locale: locale) : nil,
                                                         font: Self.nsFont(points, weight: .medium, style: textStyle, digits: true),
                                                         ink: FanTint(ink), line: FanTint(FanDialGeometry.ink(scheme)), width: size.width)
                               })
                    .frame(width: size.width, height: size.height)
            }
            if layout.showsTexts {
                texts(layout: layout, points: points, caption: caption, drawing: drawing, ink: ink)
                FanGraphKey(graph: self, points: points, ink: ink)
                    .frame(width: size.width, height: caption)
                    .offset(y: layout.key)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .underline(textStyle?.isUnderlined ?? false)
        .strikethrough(textStyle?.isStruckThrough ?? false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Chip \(temperatures.last.map { FanControlWidget.degrees($0.value, locale: locale) } ?? "—")"))
    }

    /// A full past fades in at the left: it goes on beyond the edge.
    private var fadesIn: Bool {
        guard let first = temperatures.first, let last = temperatures.last else { return false }
        return first.date <= last.date.addingTimeInterval(-window + 5)
    }

    /// How far left of the edge the live drawing reaches: the longest slide (`FanGraphLayerView`).
    static let leadSeconds: TimeInterval = 3

    /// What is drawn, from the newest reading: the line's points and colours, the strokes and theirs
    /// — `lead` seconds of them left of the graph's edge.
    private func drawing(layout: Layout, newest: Date, shown: [SensorSample], lead: TimeInterval) -> FanGraphDrawing {
        let room = layout.right * CGFloat(lead / window)
        func x(_ date: Date) -> CGFloat {
            room + layout.right * CGFloat(1 - min(max(newest.timeIntervalSince(date) / window, -1), 1 + lead / window))
        }
        let strokes = FanRhythm.strokes(speeds, window: window, after: newest.addingTimeInterval(-window - lead))
        let strokeTints: [FanTint] = strokes.map { date in
            if let fan { return FanTint(fan) }
            return FanTint.at((Self.value(speeds, at: date) ?? 0) / max(fanMaximum, 1))
        }
        // The line coloured by its height: nine stops from the floor to the limit, each the
        // warmth there (as the chip's dial), or the look's one colour.
        let heatStops: [FanGraphDrawing.Stop] = if let heat {
            [FanGraphDrawing.Stop(y: layout.floor, tint: FanTint(heat)), FanGraphDrawing.Stop(y: layout.limit, tint: FanTint(heat))]
        } else {
            (0...8).map { step in
                let celsius = range.lowerBound + (range.upperBound - range.lowerBound) * Double(step) / 8
                return FanGraphDrawing.Stop(y: y(celsius, layout: layout), tint: FanTint.at(TemperatureDial.fraction(celsius)))
            }
        }
        return FanGraphDrawing(size: CGSize(width: layout.right + room, height: size.height), lead: room, layout: layout,
                               points: shown.map { CGPoint(x: x($0.date), y: y($0.value, layout: layout)) },
                               breaks: Self.breaks(shown), strokes: strokes.map(x), strokeTints: strokeTints,
                               heatStops: heatStops, corners: corners)
    }

    /// The readings from `start` on, with the one before it (the line comes in from the left edge).
    static func within(_ samples: [SensorSample], from start: Date) -> [SensorSample] {
        guard let first = samples.firstIndex(where: { $0.date >= start }) else { return [] }
        return Array(samples[max(first - 1, 0)...])
    }

    /// Where the line breaks: the readings that come after a gap.
    static func breaks(_ samples: [SensorSample]) -> Set<Int> {
        Set(zip(samples, samples.dropFirst()).enumerated()
            .filter { $0.element.1.date.timeIntervalSince($0.element.0.date) > FanRhythm.gap }.map { $0.offset + 1 })
    }

    /// The value at `date` in readings oldest first, as the line draws it: between the two readings
    /// round it, in proportion; nil across a gap or beyond the ends.
    static func value(_ samples: [SensorSample], at date: Date) -> Double? {
        guard let first = samples.first, let last = samples.last else { return nil }
        var low = 0, high = samples.count
        while low < high {
            let middle = (low + high) / 2
            if samples[middle].date < date { low = middle + 1 } else { high = middle }
        }
        if low == 0 { return abs(first.date.timeIntervalSince(date)) < 2 ? first.value : nil }
        if low == samples.count { return date.timeIntervalSince(last.date) < FanRhythm.gap ? last.value : nil }
        let before = samples[low - 1], after = samples[low]
        let span = after.date.timeIntervalSince(before.date)
        guard span <= FanRhythm.gap else { return nil }
        guard span > 0 else { return after.value }
        return before.value + (after.value - before.value) * date.timeIntervalSince(before.date) / span
    }

    func y(_ value: Double, layout: Layout) -> CGFloat {
        let span = max(range.upperBound - range.lowerBound, 0.001)
        let share = min(max((value - range.lowerBound) / span, 0), 1)
        return layout.floor - (layout.floor - layout.limit) * CGFloat(share)
    }

    // MARK: Lines and texts

    /// The limit, dotted, at the top of the line's room, its value over its left end.
    @ViewBuilder private func limitLine(layout: Layout, points: CGFloat, caption: CGFloat, ink: Color) -> some View {
        FanDottedLine()
            .stroke(FanDialGeometry.ink(scheme).opacity(0.22), style: StrokeStyle(lineWidth: 0.75, dash: [1.5, 3.5]))
            .frame(width: size.width, height: 1)
            .offset(y: layout.limit - 0.5)
        if layout.showsTexts {
            Text(FanControlWidget.degrees(range.upperBound, locale: locale))
                .font(Self.font(points, weight: .medium, style: textStyle))
                .foregroundStyle(ink.opacity(0.45))
                .frame(height: caption)
                .offset(y: layout.limit - caption - 1)
        }
    }

    /// The lowest temperature in view: a dotted line at its height, its value at its left (a
    /// picture's: the live graph's glides to a new lowest as layers, `FanGraphLayerView`).
    @ViewBuilder private func lowestLine(_ celsius: Double, layout: Layout, points: CGFloat, caption: CGFloat, ink: Color) -> some View {
        let level = y(celsius, layout: layout)
        HStack(spacing: 4) {
            if layout.showsTexts {
                Text(FanControlWidget.degrees(celsius, locale: locale))
                    .font(Self.font(points, weight: .medium, style: textStyle).monospacedDigit())
                    .foregroundStyle(ink.opacity(0.45))
                    .fixedSize()
            }
            FanDottedLine()
                .stroke(FanDialGeometry.ink(scheme).opacity(0.22), style: StrokeStyle(lineWidth: 0.75, dash: [1.5, 3.5]))
                .frame(height: 1)
        }
        .frame(width: size.width, height: caption)
        .offset(y: level - caption / 2)
        .allowsHitTesting(false)
    }

    /// What a short past is missing, and where the fans stand still.
    @ViewBuilder private func texts(layout: Layout, points: CGFloat, caption: CGFloat, drawing: FanGraphDrawing, ink: Color) -> some View {
        // A past shorter than the graph: what is missing says it fills in.
        if let first = temperatures.first, let last = temperatures.last {
            let reach = last.date.timeIntervalSince(first.date)
            let left = drawing.points.first.map { $0.x - drawing.lead } ?? layout.right
            if reach < window * 0.6, left > size.width * 0.3 {
                Text("Fills in over \(FanControlWidget.span(Int(window.rounded())))")
                    .font(Self.font(points, weight: .medium, style: textStyle))
                    .foregroundStyle(ink.opacity(0.34))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: left - 8, height: caption)
                    .offset(y: (layout.limit + layout.floor - caption) / 2)
            }
        }
        // The fans standing still: the row says so after its last stroke.
        if let row = layout.row, let rpm = speeds.last?.value, rpm < 1 {
            let after = drawing.strokes.last.map { $0 - drawing.lead + 8 } ?? 0
            if after < size.width * 0.72 {
                Text(stopped)
                    .font(Self.font(points, weight: .medium, style: textStyle))
                    .foregroundStyle(ink.opacity(0.45))
                    .lineLimit(1)
                    .fixedSize()
                    .frame(height: caption)
                    .offset(x: max(after, 0), y: (row.lowerBound + row.upperBound - caption) / 2)
            }
        }
    }

    /// The texts' type: the style's (at `points`), or the graph's own.
    static func font(_ points: CGFloat, weight: NSFont.Weight, style: TextStyle?) -> Font {
        guard var style else {
            return .system(size: points, weight: weight == .semibold ? .semibold : .medium, design: .rounded)
        }
        style.size = Double(points)
        return Font(style.font(size: points, weight: weight))
    }

    /// The same type for the layers; its figures all as wide where `digits`.
    static func nsFont(_ points: CGFloat, weight: NSFont.Weight, style: TextStyle?, digits: Bool = false) -> NSFont {
        if var style {
            style.size = Double(points)
            return style.font(size: points, weight: weight)
        }
        let base = digits ? NSFont.monospacedDigitSystemFont(ofSize: points, weight: weight) : NSFont.systemFont(ofSize: points, weight: weight)
        return base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: points) } ?? base
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

/// A line across its rectangle's middle, to be dotted.
nonisolated struct FanDottedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

/// A graph's drawing in Core Graphics that the live graph slides (`FanGraphLayers`): Fan Control's
/// heat and fans, System's loads. `size` is the room up to the newest reading's x (`right`), `lead`
/// of it left of the graph's edge.
nonisolated protocol SlidingGraphDrawing: Equatable, Sendable {
    var size: CGSize { get }
    var lead: CGFloat { get }
    /// The newest reading's x: where the dots are.
    var right: CGFloat { get }
    /// The lines' width (the dots are sized by it).
    var line: CGFloat { get }
    var corners: ChartLook.Corners { get }
    func draw(in cg: CGContext, fade: Bool, dot: Bool)
}

extension SlidingGraphDrawing {
    func isSame(as other: (any SlidingGraphDrawing)?) -> Bool { (other as? Self) == self }
}

/// The graph's drawing in Core Graphics — the strokes, the line over its fill, the newest dot — so
/// that the live graph's layer and a picture's Canvas draw the same pixels. `size` is the room up to
/// the newest reading's x.
nonisolated struct FanGraphDrawing: SlidingGraphDrawing {
    struct Stop: Equatable, Sendable {
        var y: CGFloat
        var tint: FanTint
    }

    var size: CGSize
    /// The room left of the graph's edge the drawing reaches into (live: under the edge).
    var lead: CGFloat = 0
    var layout: FanHeatGraph.Layout
    var points: [CGPoint]
    var breaks: Set<Int>
    var strokes: [CGFloat]
    var strokeTints: [FanTint]
    /// The line's colour by its height, from the floor up.
    var heatStops: [Stop]
    var corners: ChartLook.Corners

    var right: CGFloat { layout.right }
    var line: CGFloat { layout.line }

    /// The line's colour at a height.
    func heatTint(at y: CGFloat) -> FanTint {
        guard let first = heatStops.first, let last = heatStops.last else { return .middle }
        if y >= first.y { return first.tint }
        if y <= last.y { return last.tint }
        for (below, above) in zip(heatStops, heatStops.dropFirst()) where y <= below.y && y >= above.y {
            let t = Double((below.y - y) / max(below.y - above.y, 0.001))
            return FanTint(red: below.tint.red + (above.tint.red - below.tint.red) * t,
                           green: below.tint.green + (above.tint.green - below.tint.green) * t,
                           blue: below.tint.blue + (above.tint.blue - below.tint.blue) * t)
        }
        return last.tint
    }

    /// The heat's gradient from the floor to the limit, each stop at `alpha(y)`.
    private func heatGradient(_ alpha: (CGFloat) -> Double) -> CGGradient? {
        let span = max(layout.floor - layout.limit, 0.001)
        let stops = heatStops.isEmpty ? [Stop(y: layout.floor, tint: .middle)] : heatStops
        return CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                          colors: stops.map { $0.tint.cgColor(alpha($0.y)) } as CFArray,
                          locations: stops.map { min(max((layout.floor - $0.y) / span, 0), 1) })
    }

    func draw(in cg: CGContext, fade: Bool, dot: Bool) {
        if fade { cg.beginTransparencyLayer(auxiliaryInfo: nil) }
        let floorPoint = CGPoint(x: 0, y: layout.floor), limitPoint = CGPoint(x: 0, y: layout.limit)

        // The fans: a stroke at each of their moments, in their colour then, fading downwards.
        if let row = layout.row {
            let width = max(1, (row.upperBound - row.lowerBound) * 0.08)
            for (x, tint) in zip(strokes, strokeTints) where x >= -width && x <= size.width + width {
                cg.saveGState()
                cg.addPath(CGPath(roundedRect: CGRect(x: x - width / 2, y: row.lowerBound, width: width, height: row.upperBound - row.lowerBound),
                                  cornerWidth: width / 2, cornerHeight: width / 2, transform: nil))
                cg.clip()
                if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                             colors: [tint.cgColor(0.95), tint.cgColor(0.35)] as CFArray, locations: [0, 1]) {
                    cg.drawLinearGradient(gradient, start: CGPoint(x: 0, y: row.lowerBound), end: CGPoint(x: 0, y: row.upperBound), options: [])
                }
                cg.restoreGState()
            }
        }

        // The heat: each run of readings a line over its fill (a gap breaks it).
        var runs: [[CGPoint]] = [[]]
        for (index, point) in points.enumerated() {
            if breaks.contains(index) { runs.append([]) }
            runs[runs.count - 1].append(point)
        }
        let span = max(layout.floor - layout.limit, 0.001)
        let fill = heatGradient { 0.15 * Double(min(max((layout.floor - $0) / span, 0), 1)) }
        let line = heatGradient { _ in 1 }
        for run in runs where run.count >= 2 {
            let path = CGMutablePath()
            path.addLines(between: run)
            let area = CGMutablePath()
            area.addPath(path)
            area.addLine(to: CGPoint(x: run[run.count - 1].x, y: layout.floor))
            area.addLine(to: CGPoint(x: run[0].x, y: layout.floor))
            area.closeSubpath()
            if let fill {
                cg.saveGState()
                cg.addPath(area)
                cg.clip()
                cg.drawLinearGradient(fill, start: floorPoint, end: limitPoint, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
                cg.restoreGState()
            }
            if let line {
                cg.saveGState()
                cg.addPath(path)
                cg.setLineWidth(layout.line)
                switch corners {
                case .rounded: cg.setLineCap(.round); cg.setLineJoin(.round)
                case .slight: cg.setLineCap(.butt); cg.setLineJoin(.bevel)
                case .square: cg.setLineCap(.square); cg.setLineJoin(.miter)
                }
                cg.replacePathWithStrokedPath()
                cg.clip()
                cg.drawLinearGradient(line, start: floorPoint, end: limitPoint, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
                cg.restoreGState()
            }
        }

        // The newest reading: a dot cut out of what is behind it.
        if dot, let last = points.last {
            Self.dot(in: cg, at: last, radius: layout.line * 2, ring: layout.line, tint: heatTint(at: last.y), corners: corners)
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

    static func dotPath(_ center: CGPoint, radius: CGFloat, corners: ChartLook.Corners) -> CGPath {
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        return switch corners {
        case .rounded: CGPath(ellipseIn: rect, transform: nil)
        case .slight: CGPath(roundedRect: rect, cornerWidth: radius / 2, cornerHeight: radius / 2, transform: nil)
        case .square: CGPath(rect: rect, transform: nil)
        }
    }

    static func dot(in cg: CGContext, at point: CGPoint, radius: CGFloat, ring: CGFloat, tint: FanTint, corners: ChartLook.Corners) {
        cg.addPath(dotPath(point, radius: radius + ring, corners: corners))
        cg.setFillColor(CGColor(gray: 0, alpha: 0.85))
        cg.fillPath()
        cg.addPath(dotPath(point, radius: radius, corners: corners))
        cg.setFillColor(tint.cgColor())
        cg.fillPath()
    }
}

/// Under the row of strokes: how far back the graph reaches (a glass button: the ruler), slow and
/// fast, now.
private struct FanGraphKey: View {
    let graph: FanHeatGraph
    let points: CGFloat
    let ink: Color

    var body: some View {
        HStack(spacing: 0) {
            // On Liquid Glass, so it reads as the button it is (a picture draws the glass still).
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
                rhythmKey
                Spacer(minLength: 4)
            }
            if graph.size.width >= 120 {
                Text("now").foregroundStyle(ink.opacity(0.45))
            }
        }
        .font(FanHeatGraph.font(points, weight: .medium, style: graph.textStyle))
        .lineLimit(1)
    }

    /// "slow ||| ||||fast": seven strokes closing up between the two words, green to red.
    private var rhythmKey: some View {
        let scale = points / 24
        let offsets: [CGFloat] = [0, 24, 44, 60, 72, 82, 90]
        let width = max(3.5 * scale, 1)
        return HStack(spacing: 16 * scale) {
            Text("slow").foregroundStyle(ink.opacity(0.6))
            ZStack(alignment: .leading) {
                ForEach(Array(offsets.enumerated()), id: \.offset) { index, offset in
                    RoundedRectangle(cornerRadius: width / 2)
                        .fill(graph.fan ?? FanTint.at(Double(index) / Double(offsets.count - 1)).color)
                        .frame(width: width, height: 20 * scale)
                        .offset(x: offset * scale)
                }
            }
            .frame(width: 90 * scale + width, alignment: .leading)
            Text("fast").foregroundStyle(ink.opacity(0.6))
        }
    }
}

/// The live graph's drawing as layers: drawn once a reading, then slid left by Core Animation in a
/// short soft glide to where it now stands, the newest dots (one a line) gliding up or down at the
/// right edge with it, the lowest's dotted line gliding to a new lowest — on the render server, nothing done
/// on the main thread between readings (the lowest's glide as SwiftUI animation was 300 ms of the
/// main thread in 0.8 s, measured). A step under two points (a long graph) is not slid: it is too
/// small to be seen as a jump.
struct FanGraphLayers: NSViewRepresentable {
    struct Dot: Equatable {
        var y: CGFloat
        var tint: FanTint
    }

    let drawing: any SlidingGraphDrawing
    let newest: Date
    let window: TimeInterval
    let fadesIn: Bool
    let dots: [Dot]
    var lowest: Lowest?

    /// The lowest temperature's dotted line: its height, its value (nil: none written) in the
    /// graph's type and colour, across `width`.
    struct Lowest {
        var y: CGFloat
        var text: String?
        var font: NSFont
        var ink: FanTint
        /// The dotted line's colour (at its own faintness).
        var line = FanTint(red: 1, green: 1, blue: 1)
        var width: CGFloat
    }

    func makeNSView(context: Context) -> FanGraphLayerView { FanGraphLayerView() }

    func updateNSView(_ view: FanGraphLayerView, context: Context) {
        view.show(drawing, newest: newest, window: window, fadesIn: fadesIn, dots: dots)
        view.showLowest(lowest)
    }
}

final class FanGraphLayerView: NSView {
    private let clip = CALayer()
    private let content = CALayer()
    private let fade = CAGradientLayer()
    /// Each newest dot's dark ring and its fill, made as the lines need them.
    private var rings: [CAShapeLayer] = []
    private var fills: [CAShapeLayer] = []

    /// A reading's glide: how long, and its curve (soft at both ends).
    static let glide: TimeInterval = 0.35
    static let easing = CAMediaTimingFunction(controlPoints: 0.45, 0, 0.25, 1)

    private let lowest = CALayer()
    private let lowestLine = CAShapeLayer()
    private let lowestText = CATextLayer()
    private var lowestShown: (text: String?, width: CGFloat, fontSize: CGFloat)?

    private var drawing: (any SlidingGraphDrawing)?
    private var drawnScale: CGFloat = 0
    private var newest: Date?
    private var dotYs: [CGFloat] = []

    private static let still: [String: any CAAction] = [
        "position": NSNull(), "bounds": NSNull(), "frame": NSNull(), "contents": NSNull(), "path": NSNull(), "fillColor": NSNull(),
        "transform": NSNull(), "hidden": NSNull(), "mask": NSNull(),
    ]

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        clip.masksToBounds = true
        clip.addSublayer(content)
        fade.colors = [CGColor(gray: 0, alpha: 0), CGColor(gray: 0, alpha: 1)]
        fade.startPoint = CGPoint(x: 0, y: 0.5)
        fade.endPoint = CGPoint(x: 0.12, y: 0.5)
        lowestLine.strokeColor = CGColor(gray: 1, alpha: 0.22)
        lowestLine.fillColor = nil
        lowestLine.lineWidth = 0.75
        lowestLine.lineDashPattern = [1.5, 3.5]
        lowest.addSublayer(lowestLine)
        lowest.addSublayer(lowestText)
        lowest.isHidden = true
        for sublayer in [clip, content, fade, lowest, lowestLine, lowestText] as [CALayer] {
            sublayer.actions = Self.still
        }
        layer?.addSublayer(lowest)
        layer?.addSublayer(clip)
    }

    /// At least `count` dots' layers, over the drawing, each line's over the one before.
    private func makeDots(_ count: Int) {
        while rings.count < count {
            let ring = CAShapeLayer(), fill = CAShapeLayer()
            ring.fillColor = CGColor(gray: 0, alpha: 0.85)
            for dot in [ring, fill] {
                dot.actions = Self.still
                dot.isHidden = true
                layer?.addSublayer(dot)
            }
            rings.append(ring)
            fills.append(fill)
        }
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    /// Clicks go to what is under it.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        // Drawn again at the new screen's pixels.
        drawnScale = 0
        lowestText.contentsScale = window?.backingScaleFactor ?? 2
        if let drawing { render(drawing) }
    }

    /// The lowest's dotted line, its value at its left: moved to a new lowest in a short glide on the
    /// render server (from wherever a glide under way has it).
    func showLowest(_ new: FanGraphLayers.Lowest?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard let new else {
            lowest.isHidden = true
            return
        }
        let height = ceil(new.font.ascender - new.font.descender + new.font.leading)
        lowestLine.strokeColor = new.line.cgColor(0.22)
        if lowestShown.map({ $0.text != new.text || $0.width != new.width || $0.fontSize != new.font.pointSize }) ?? true {
            lowestShown = (new.text, new.width, new.font.pointSize)
            var start: CGFloat = 0
            if let text = new.text {
                let string = NSAttributedString(string: text, attributes: [.font: new.font, .foregroundColor: NSColor(cgColor: new.ink.cgColor(0.45)) ?? .white])
                let width = ceil(string.size().width)
                lowestText.string = string
                lowestText.contentsScale = window?.backingScaleFactor ?? 2
                lowestText.frame = CGRect(x: 0, y: 0, width: width, height: height)
                lowestText.isHidden = false
                start = width + 4
            } else {
                lowestText.isHidden = true
            }
            let path = CGMutablePath()
            path.move(to: CGPoint(x: start, y: height / 2))
            path.addLine(to: CGPoint(x: new.width, y: height / 2))
            lowestLine.path = path
        }
        lowest.bounds = CGRect(x: 0, y: 0, width: new.width, height: height)
        lowest.anchorPoint = .zero
        let top = new.y - height / 2
        // The same lowest again: a glide under way goes on.
        guard lowest.isHidden || lowest.position.y != top else { return }
        let was = lowest.presentation()?.position.y ?? lowest.position.y
        let moved = !lowest.isHidden && abs(was - top) > 0.25
        lowest.isHidden = false
        lowest.position = CGPoint(x: 0, y: top)
        lowest.removeAnimation(forKey: "glide")
        if moved {
            let glide = CABasicAnimation(keyPath: "position.y")
            glide.fromValue = was
            glide.toValue = top
            glide.duration = 0.4
            glide.timingFunction = CAMediaTimingFunction(name: .easeOut)
            lowest.add(glide, forKey: "glide")
        }
    }

    func show(_ drawing: any SlidingGraphDrawing, newest: Date, window: TimeInterval, fadesIn: Bool, dots: [FanGraphLayers.Dot]) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let frame = CGRect(x: 0, y: 0, width: drawing.size.width - drawing.lead, height: drawing.size.height)
        let resized = clip.frame != frame
        clip.frame = frame
        // Its lead under the clip's left edge.
        content.frame = CGRect(x: -drawing.lead, y: 0, width: drawing.size.width, height: drawing.size.height)
        fade.frame = clip.bounds
        clip.mask = fadesIn ? fade : nil
        if !drawing.isSame(as: self.drawing) { render(drawing) }

        // Slid from where the last drawing stood (a slide under way, too) to rest, in a short glide
        // that starts and settles softly, then still until the next reading: the window server
        // draws a third of the time it did for a slide as long as the readings are apart (that one
        // was ~160 mW of it for a short graph, measured).
        let step = self.newest.map { newest.timeIntervalSince($0) } ?? 0
        let shift = drawing.right * CGFloat(step / max(window, 1))
        let slides = !resized && step > 0 && step <= 3 && shift >= 2
        let under = (content.presentation()?.value(forKeyPath: "transform.translation.x") as? CGFloat) ?? 0
        // The same reading again (another part of the widget changed): the slide under way goes on.
        let isNew = step > 0 || resized || self.newest == nil
        if isNew { content.removeAnimation(forKey: "slide") }
        if slides {
            let slide = CABasicAnimation(keyPath: "transform.translation.x")
            slide.fromValue = under + shift
            slide.toValue = 0
            slide.duration = min(Self.glide, step)
            slide.timingFunction = Self.easing
            content.add(slide, forKey: "slide")
        }
        if step > 0 || self.newest == nil { self.newest = newest }

        // The newest dots at the right edge, each on its line there.
        makeDots(dots.count)
        for (index, dot) in dots.enumerated() {
            let ring = rings[index], fill = fills[index]
            let center = CGPoint(x: drawing.right, y: dot.y)
            ring.path = FanGraphDrawing.dotPath(center, radius: drawing.line * 3, corners: drawing.corners)
            fill.path = FanGraphDrawing.dotPath(center, radius: drawing.line * 2, corners: drawing.corners)
            fill.fillColor = dot.tint.cgColor()
            ring.isHidden = false
            fill.isHidden = false
            let was = (fill.presentation()?.value(forKeyPath: "transform.translation.y") as? CGFloat) ?? 0
            if isNew { for layer in [ring, fill] { layer.removeAnimation(forKey: "glide") } }
            if slides, index < dotYs.count {
                let glide = CABasicAnimation(keyPath: "transform.translation.y")
                glide.fromValue = dotYs[index] + was - dot.y
                glide.toValue = 0
                glide.duration = min(Self.glide, step)
                glide.timingFunction = Self.easing
                for layer in [ring, fill] { layer.add(glide, forKey: "glide") }
            }
        }
        for index in dots.count..<rings.count {
            rings[index].isHidden = true
            fills[index].isHidden = true
        }
        dotYs = dots.map(\.y)
    }

    /// The drawing as the content layer's picture, at the screen's pixels.
    private func render(_ drawing: any SlidingGraphDrawing) {
        self.drawing = drawing
        let scale = window?.backingScaleFactor ?? 2
        let width = Int((drawing.size.width * scale).rounded(.up)), height = Int((drawing.size.height * scale).rounded(.up))
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            content.contents = nil
            return
        }
        // Top-left, in points, as SwiftUI draws.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        drawing.draw(in: context, fade: false, dot: false)
        drawnScale = scale
        content.contentsScale = scale
        content.contents = context.makeImage()
    }
}
