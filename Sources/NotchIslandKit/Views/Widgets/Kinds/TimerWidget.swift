import SwiftUI

/// The timer, the base of a ruler: a scale scrolled (or dragged) to the length, like the iPhone's
/// Dynamic Island timer, over a row of its buttons and the time in large orange digits. While it
/// counts, the ruler shows the minutes left and cannot be moved.
///
/// With Set hours or Set seconds on, the time reads in those units too: a click on a part of it
/// (or on the unit's name beside the ruler's marker) and the ruler sets that unit.
///
/// Each part is moved in Customize: the ruler with its colour, its ticks' ends and what is behind
/// it (`RulerLook`), the time as a text (`WidgetLabel`), the buttons as Now Playing's are
/// (`ButtonLook`). Its action (Start, Pause or Resume, Done) is always there; Cancel while it
/// counts; +1 where switched on — and in Customize's editor all of them, to be styled.
struct TimerWidget: View {
    let widget: IslandWidget
    let size: CGSize

    @Environment(AppModel.self) private var model
    @Environment(\.isElementEditing) private var isEditing
    @Environment(\.isWidgetPreview) private var isPreview
    @Environment(\.widgetShape) private var widgetShape
    /// The pointer is over the widget: the ruler's scroll view is made ready (`TimerRuler.isAwake`).
    @State private var isPointerOver = false

    /// Orange, like the iPhone's timer.
    static let tint = Color.orange
    /// The buttons and the time need this much height under a ruler.
    static let minimumRowHeight: CGFloat = 18
    /// Below this the ruler's ticks would be too short to read or grab.
    static let minimumRulerSpace: CGFloat = 18

    static func spacing(inner: CGSize) -> CGFloat { inner.height < 66 ? 3 : Metrics.Spacing.small }

    /// The ruler's room over the row (its ticks and the marker under them); 0 where it has none
    /// (a widget one row tall).
    static func rulerSpace(inner: CGSize) -> CGFloat {
        let ruler: CGFloat = inner.height >= 100 ? 44 : 22
        let space = min(ruler + 14, inner.height - minimumRowHeight - spacing(inner: inner))
        return space >= minimumRulerSpace ? space.rounded(.down) : 0
    }

    static func showsRuler(_ widget: IslandWidget, inner: CGSize) -> Bool {
        widget.shows(.ruler) && rulerSpace(inner: inner) > 0
    }

    /// The row of the buttons and the time.
    static func rowHeight(_ widget: IslandWidget, inner: CGSize) -> CGFloat {
        showsRuler(widget, inner: inner) ? inner.height - rulerSpace(inner: inner) - spacing(inner: inner) : inner.height
    }

    /// The time's size: as the row is tall, its widest time (`widest`) no wider than about three
    /// fifths of the row.
    static func readoutPoints(_ widget: IslandWidget, inner: CGSize) -> CGFloat {
        let row = rowHeight(widget, inner: inner)
        let em = textWidth(widest(units(widget)), points: 100) / 100
        return max(min(WidgetMetrics.points(row, ratio: 0.72, min: 12, max: 44), (inner.width * 0.62 / em).rounded(.down)), 10)
    }

    /// The widest the time can read in these units, set or counting: three digits of minutes
    /// ("120:59") without hours, "23:59:59" with them. Its size is chosen so this fits the row.
    static func widest(_ units: TimerDraftUnits) -> String {
        units.hours ? "00:00:00" : "000:00"
    }

    /// `text` in the time's own type (rounded figures, all as wide), `points` large.
    static func textWidth(_ text: String, points: CGFloat) -> CGFloat {
        let base = NSFont.monospacedDigitSystemFont(ofSize: points, weight: .regular)
        let font = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: points) } ?? base
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    /// The room its widest time takes, with a hair to spare.
    static func readoutWidth(_ widget: IslandWidget, inner: CGSize) -> CGFloat {
        textWidth(widest(units(widget)), points: readoutPoints(widget, inner: inner)) + 2
    }

    /// Every button's size, whatever its look: as the widget draws it (on glass) and as Customize
    /// restyles it (a shape as large) — so restyling one moves nothing.
    static func buttonDiameter(_ widget: IslandWidget, inner: CGSize) -> CGFloat {
        min(max(rowHeight(widget, inner: inner) * 0.82, 22), 40).rounded()
    }

    /// A restyled button's symbol size: its shape as large as the plain button
    /// (`WidgetButtonLabel.size`: 1.35 times its symbol).
    static func buttonPoints(_ widget: IslandWidget, inner: CGSize) -> CGFloat {
        (buttonDiameter(widget, inner: inner) / 1.35).rounded()
    }

    /// The glass button's own room round its symbol, at the size the timer draws it (`.large`).
    static let glassPadding = GlassButtonPicture.padding(.large).2

    /// The units the time is set in: minutes, and hours and seconds where switched on.
    static func units(_ widget: IslandWidget) -> TimerDraftUnits {
        TimerDraftUnits(hours: widget.shows(.timerHours), seconds: widget.shows(.timerSeconds))
    }

    /// The unit the ruler sets: the one picked, where the widget has it.
    static func unit(_ timers: TimerStore, units: TimerDraftUnits) -> TimerUnit {
        units.units.contains(timers.draftUnit) ? timers.draftUnit : .minutes
    }

    /// The length set, as the time shows it: "5:00", or in its units ("1:05", "0:05:30").
    static func draftText(_ duration: TimeInterval, units: TimerDraftUnits) -> String {
        if units.isMinutesOnly { return IslandFormat.minutesClock(duration) }
        return draftSegments(duration, units: units, current: nil).map(\.text).joined()
    }

    /// The length set in its units, the parts but `current` (and the colons) faded; `current` nil,
    /// none faded.
    static func draftSegments(_ duration: TimeInterval, units: TimerDraftUnits, current: TimerUnit?) -> [LabelSegment] {
        units.units.enumerated().flatMap { index, unit in
            let value = units.value(of: unit, in: duration)
            let part = LabelSegment(text: index == 0 ? "\(value)" : String(format: "%02d", value),
                                    isFaded: current.map { $0 != unit } ?? false)
            return index == 0 ? [part] : [LabelSegment(text: ":", isFaded: current != nil), part]
        }
    }

    /// A restyled time's parts: while the length is set in more units than minutes, the ones not
    /// being set faded, as the widget draws them; nil otherwise (one text).
    static func timeSegments(_ timers: TimerStore, units: TimerDraftUnits, picture: Bool) -> [LabelSegment]? {
        guard timers.countdown == .idle, !units.isMinutesOnly else { return nil }
        let unit = unit(timers, units: units)
        return draftSegments(timers.draftDuration, units: units, current: unit)
    }

    /// The time as it reads at `date`: the length being set, or what is left (in a picture too:
    /// Customize's editor shows the timer as it is).
    static func timeText(_ timers: TimerStore, units: TimerDraftUnits, picture: Bool, at date: Date) -> String {
        switch timers.countdown {
        case .idle:
            draftText(timers.draftDuration, units: units)
        default:
            countdownText((timers.countdown.remaining(at: date) ?? 0).rounded(.up), units: units)
        }
    }

    /// What is left, in the units the timer is set in: hours where it has them, minutes however
    /// many otherwise ("119:59").
    static func countdownText(_ seconds: TimeInterval, units: TimerDraftUnits) -> String {
        units.hours ? IslandFormat.clock(seconds) : IslandFormat.minutesClock(seconds)
    }

    /// Its action's name and symbol as it stands.
    static func action(_ countdown: CountdownState) -> (title: String, symbol: String) {
        switch countdown {
        case .idle: (String(localized: "Start"), "play.fill")
        case .running: (String(localized: "Pause"), "pause.fill")
        case .paused: (String(localized: "Resume"), "play.fill")
        case .finished: (String(localized: "Done"), "checkmark")
        }
    }

    /// The minutes left, rounded up (the ruler while it counts).
    static func minutesLeft(_ state: CountdownState, at date: Date) -> Int {
        Int(((state.remaining(at: date) ?? 0) / 60).rounded(.up))
    }

    private var isPicture: Bool { isPreview || isEditing }

    /// The time's box of its own hangs from the row's end (`WidgetKindSpec.trailingTexts`).
    static var hangsFromTrailing: Bool { IslandWidgetKind.timer.spec.trailingTexts.contains(.readout) }

    /// The unit's name beside the ruler's marker, as Customize set it; nil where it is switched off.
    static func unitName(_ widget: IslandWidget, reportsFrame: Bool = false) -> RulerUnitName? {
        guard widget.shows(.rulerUnit) else { return nil }
        return RulerUnitName(style: widget.textStyle(of: .rulerUnit), offset: widget.rulerLook(of: .ruler).unitOffset,
                             reportsFrame: reportsFrame)
    }

    var body: some View {
        let timers = model.timers
        let units = Self.units(widget)
        let showsRuler = Self.showsRuler(widget, inner: size)
        let rulerSpace = Self.rulerSpace(inner: size)
        VStack(spacing: showsRuler ? Self.spacing(inner: size) : 0) {
            if showsRuler {
                TimerRulerPart(look: widget.rulerLook(of: .ruler), units: units, compact: rulerSpace < 30,
                               showsLabels: size.height >= 100, isPicture: isPicture, unitName: Self.unitName(widget),
                               isAwake: isPointerOver)
                    .frame(height: rulerSpace)
                    .movableElement(.ruler, of: widget)
            }
            // In the widget's bottom corners: the buttons down to its bottom-left, the time's
            // digits (its baseline) down to its bottom-right — each as far in from the side as from
            // the bottom (concentric with a rounder corner).
            CornerRow(leadingRadius: widgetShape?.corners.bottomLeading ?? 0, trailingRadius: widgetShape?.corners.bottomTrailing ?? 0,
                      padding: WidgetMetrics.padding(for: widget)) {
                HStack(alignment: .bottom, spacing: Metrics.Spacing.medium) {
                    buttons(timers, units: units)
                }
                .controlSize(.large)
                if widget.shows(.readout) {
                    BaselineBottom { readout(timers, units: units) }
                }
            }
            .frame(height: Self.rowHeight(widget, inner: size))
        }
        .frame(width: size.width, height: size.height)
        .onHover { over in if !isPicture, over != isPointerOver { isPointerOver = over } }
        .tint(Self.tint)
        // Another unit picked: at once (the time's parts faded late, out of step with the ruler).
        .animation(Motion.content, value: timers.countdown)
        // Hours or Seconds switched off: what they can no longer show goes (live only: a picture
        // changes nothing).
        .onChange(of: units, initial: true) { _, units in
            if !isPicture { units.normalize(timers) }
        }
    }

    @ViewBuilder private func buttons(_ timers: TimerStore, units: TimerDraftUnits) -> some View {
        let countdown = timers.countdown
        let action = Self.action(countdown)
        button(.timerActions, title: action.title, symbol: action.symbol, prominent: true) {
            switch countdown {
            case .idle: timers.start(duration: units.normalized(timers.draftDuration))
            case .running: timers.pause()
            case .paused: timers.resume()
            case .finished:
                timers.acknowledge()
                model.banners.dismiss(.timerFinished)
            }
        }
        // 0:00, on the way to another time: nothing to count down.
        .disabled(countdown == .idle && !units.canStart(timers.draftDuration))
        if widget.shows(.addMinute) {
            button(.addMinute, title: String(localized: "+1 Minute"), symbol: "plus", prominent: false) {
                switch countdown {
                case .idle:
                    // A minute more on the length set: the ruler moves with it.
                    timers.draftDuration = units.normalized(timers.draftDuration + 60)
                    model.haptics.play(.tick)
                case .finished:
                    timers.add(seconds: 60)
                    model.banners.dismiss(.timerFinished)
                default:
                    timers.add(seconds: 60)
                }
            }
        }
        if countdown.isRunning || countdown.isPaused || isEditing {
            button(.timerCancel, title: String(localized: "Cancel"), symbol: "xmark", prominent: false) { timers.cancel() }
        }
    }

    /// The time: the length being set (following the ruler exactly, unanimated: a cross-fade per
    /// tick smeared the digits) or what is left; as the widget sets it, or restyled.
    @ViewBuilder private func readout(_ timers: TimerStore, units: TimerDraftUnits) -> some View {
        let points = Self.readoutPoints(widget, inner: size)
        let countdown = timers.countdown
        // From the row's end (the widget's corner): as its digits grow it grows to the left, and a
        // box of its own hangs from there too (`hangsFromTrailing`) — it never moves.
        // Orange, dimmed while paused — restyled with its colour left at Automatic too.
        let tint = Self.tint.opacity(countdown.isPaused ? 0.55 : 1)
        let plain = TimerTime(units: units, picture: isPicture)
            .font(.system(size: points, design: .rounded).monospacedDigit())
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
        let segments = Self.timeSegments(timers, units: units, picture: isPicture)
        let shown = widget.withOwnDesign(.rounded, for: .readout)
        Group {
            if widget.textStyle(of: .readout) == .plain, !isEditing {
                plain
            } else if countdown.isRunning {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    WidgetLabel(id: .readout, text: Self.timeText(timers, units: units, picture: isPicture, at: context.date),
                                widget: shown, size: points, weight: .regular, isSecondary: false, segments: segments,
                                hangsFromTrailing: Self.hangsFromTrailing, automaticColor: tint) { plain }
                }
            } else {
                WidgetLabel(id: .readout, text: Self.timeText(timers, units: units, picture: isPicture, at: .now), widget: shown,
                            size: points, weight: .regular, isSecondary: false, segments: segments,
                            hangsFromTrailing: Self.hangsFromTrailing, automaticColor: tint) { plain }
                    // Restyled, the time is one text: a click moves on to the next unit.
                    .contentShape(.rect)
                    .onTapGesture {
                        guard !isPicture, countdown == .idle, !units.isMinutesOnly else { return }
                        timers.draftUnit = units.next(after: Self.unit(timers, units: units))
                    }
            }
        }
        .movableElement(.readout, of: widget)
    }

    /// A button as the widget draws it (on glass), or as Customize styled it — either way
    /// `buttonDiameter` large.
    @ViewBuilder private func button(_ id: ElementID, title: String, symbol: String, prominent: Bool,
                                     action: @escaping () -> Void) -> some View {
        let look = widget.buttonLook(of: id)
        let diameter = Self.buttonDiameter(widget, inner: size)
        Group {
            if look == .plain {
                Button(action: action) {
                    Label {
                        Text(title)
                    } icon: {
                        // The circle is the glass's own padding round this: `diameter` across.
                        Image(systemName: symbol)
                            .font(.system(size: diameter * 0.4, weight: .semibold))
                            .contentTransition(.symbolEffect(.replace))
                            .frame(width: diameter - 2 * Self.glassPadding, height: diameter - 2 * Self.glassPadding)
                    }
                }
                .islandButton(.circle, prominent: prominent)
                .help(title)
            } else {
                NowPlayingButton(title: title, symbol: symbol, points: Self.buttonPoints(widget, inner: size), look: look, action: action)
                    .frame(width: diameter, height: diameter)
            }
        }
        .movableElement(id, of: widget)
    }
}

/// The time as the widget sets it: the length being set — in its units, each part a click away
/// from the ruler setting it, the one it sets bright — or the countdown.
private struct TimerTime: View {
    let units: TimerDraftUnits
    let picture: Bool

    @Environment(AppModel.self) private var model

    var body: some View {
        let timers = model.timers
        switch timers.countdown {
        case .idle:
            let duration = timers.draftDuration
            if units.isMinutesOnly {
                Text(IslandFormat.minutesClock(duration)).transaction { $0.animation = nil }
            } else {
                let current = TimerWidget.unit(timers, units: units)
                HStack(spacing: 0) {
                    ForEach(Array(units.units.enumerated()), id: \.element) { index, unit in
                        if index > 0 { Text(":").opacity(LabelSegment.fadedOpacity) }
                        let value = units.value(of: unit, in: duration)
                        Text(index == 0 ? "\(value)" : String(format: "%02d", value))
                            .opacity(unit == current ? 1 : LabelSegment.fadedOpacity)
                            .contentShape(.rect)
                            .onTapGesture { if !picture { timers.draftUnit = unit } }
                            .accessibilityAddTraits(.isButton)
                            .accessibilityLabel(Text("\(value) \(unit.accessibilityTitle)"))
                    }
                }
                .transaction { $0.animation = nil }
            }
        default:
            CountdownReadout(state: timers.countdown, minutesOnly: !units.hours)
        }
    }
}

/// The ruler, as its look sets it (`RulerLook`): set the length while idle (in the unit picked:
/// minutes 1 to 120, or hours, or seconds), the minutes left while it counts; the unit's name beside
/// its marker. A picture (the gallery, Customize's editor and its panel) draws it at rest, on the
/// length set, and takes no pointer; its part is its whole box whatever it reads.
struct TimerRulerPart: View {
    let look: RulerLook
    let units: TimerDraftUnits
    let compact: Bool
    let showsLabels: Bool
    let isPicture: Bool
    let unitName: RulerUnitName?
    var isAwake = false

    @Environment(AppModel.self) private var model
    @Environment(\.widgetLayerPass) private var layerPass

    var body: some View {
        GeometryReader { proxy in
            let shape = RoundedRectangle(cornerRadius: look.corners.radius(height: proxy.size.height), style: .continuous)
            let isGlass = RulerLook.isGlass(look)
            // On a background, kept off its edges (round ends: as far in as they are round).
            let inset: CGFloat = look.material.hasShape ? (look.corners == .round ? proxy.size.height * 0.35 : 5) : 0
            ruler
                .padding(.horizontal, inset)
                .padding(.vertical, look.material.hasShape ? 3 : 0)
                .opacity(layerPass == .underlay ? 0 : 1)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .background {
                    // Zoomed in Customize: the glass under the picture, the ticks in it (`SharpZoom`).
                    if look.material.hasShape, layerPass == .all || (layerPass == .underlay) == isGlass {
                        LookSurface(material: look.material, fill: look.fill, fillColor: look.fillColor, shape: shape)
                    }
                }
        }
    }

    private var tint: Color {
        switch look.color {
        case .automatic: TimerWidget.tint
        case .custom(let rgb): rgb.color
        case .artwork: model.media.artworkColor.map { Color($0) } ?? .islandAccent
        }
    }

    @ViewBuilder private var ruler: some View {
        let timers = model.timers
        let marker: CGFloat = compact ? 6 : 9
        let unit = TimerWidget.unit(timers, units: units)
        let range = units.range(of: unit)
        // Minutes only: 0 stays on the ruler as a landmark, it settles on 1.
        let shown = units.isMinutesOnly ? 0...range.upperBound : range
        // A click on the marker or the unit's name moves on to the next unit (and on a part of the time).
        let nextUnit: (() -> Void)? = units.isMinutesOnly ? nil : { timers.draftUnit = units.next(after: unit) }
        // Its colour the ruler's where Automatic, the cover's where Artwork.
        let artwork = model.media.artworkColor.map { Color($0) } ?? .islandAccent
        let unitName = unitName.map { name in
            var name = name
            name.color = name.style.color == .artwork ? artwork : tint
            return name
        }
        switch timers.countdown {
        case .idle where isPicture:
            TimerRuler(minutes: .constant(units.value(of: unit, in: timers.draftDuration)), range: shown,
                       minimum: range.lowerBound, unit: unit, nextUnit: nextUnit, unitName: unitName, showsLabels: showsLabels,
                       tint: tint, ends: look.ends, markerSize: marker)
                .allowsHitTesting(false)
        case .idle:
            TimerRuler(
                minutes: Binding(get: { units.value(of: unit, in: timers.draftDuration) },
                                 set: { timers.draftDuration = units.duration(setting: unit, to: $0, in: timers.draftDuration) }),
                range: shown,
                minimum: range.lowerBound,
                unit: unit,
                nextUnit: nextUnit,
                unitName: unitName,
                showsLabels: showsLabels,
                tint: tint,
                ends: look.ends,
                onInteraction: { model.island.isInteracting = $0 },
                markerSize: marker,
                isAwake: isAwake
            )
            .onChange(of: timers.draftDuration) { model.haptics.play(.tick) }
        case .running(let endDate, _) where !isPicture:
            // Read again once a minute, on the countdown's own minute boundaries.
            let remaining = max(0, endDate.timeIntervalSinceNow)
            let boundary = endDate.addingTimeInterval(-60 * (remaining / 60).rounded(.up))
            PanelTimelineView(.periodic(from: boundary, by: 60)) { context in
                TimerRuler(minutes: .constant(TimerWidget.minutesLeft(timers.countdown, at: context.date)), unitName: unitName,
                           isEditable: false, showsLabels: showsLabels, tint: tint, ends: look.ends, markerSize: marker)
            }
        default:
            TimerRuler(minutes: .constant(TimerWidget.minutesLeft(timers.countdown, at: .now)), unitName: unitName,
                       isEditable: false, showsLabels: showsLabels, tint: tint, ends: look.ends, markerSize: marker)
                .allowsHitTesting(!isPicture)
        }
    }
}

/// A row in the widget's bottom corners: its first subview (the buttons) in the bottom-leading one,
/// its second (the time, down to its baseline) in the bottom-trailing one — each as far in from
/// the side as from the bottom: no further in than the widget's padding, or concentric with a
/// corner rounder than the buttons (`ConcentricGeometry.cornerInset`). Measured and placed in one
/// pass: nothing moves once drawn.
struct CornerRow: Layout {
    let leadingRadius: CGFloat
    let trailingRadius: CGFloat
    let padding: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        return CGSize(width: proposal.width ?? sizes.reduce(0) { $0 + $1.width + Metrics.Spacing.medium },
                      height: proposal.height ?? sizes.map(\.height).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let first = subviews.first else { return }
        let size = first.sizeThatFits(.unspecified)
        let leading = ConcentricGeometry.cornerInset(radius: leadingRadius, part: size.height, padding: padding)
        first.place(at: CGPoint(x: bounds.minX + leading, y: bounds.maxY - leading), anchor: .bottomLeading,
                    proposal: ProposedViewSize(size))
        guard subviews.count > 1 else { return }
        let trailing = ConcentricGeometry.cornerInset(radius: trailingRadius, part: size.height, padding: padding)
        let room = max(0, bounds.width - leading - size.width - Metrics.Spacing.medium - trailing)
        let second = subviews[1]
        let other = second.sizeThatFits(ProposedViewSize(width: room, height: nil))
        second.place(at: CGPoint(x: bounds.maxX - trailing, y: bounds.maxY - trailing), anchor: .bottomTrailing,
                     proposal: ProposedViewSize(other))
    }
}

/// Its one subview as tall as down to its last baseline: the room under it (for descenders, which
/// digits never use) hangs below, so the digits stand on the row's bottom as the buttons do.
struct BaselineBottom<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        BaselineBottomLayout { content }
    }
}

private struct BaselineBottomLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let subview = subviews.first else { return .zero }
        let dimensions = subview.dimensions(in: Self.own(proposal))
        return CGSize(width: dimensions.width, height: min(dimensions[VerticalAlignment.lastTextBaseline], dimensions.height))
    }

    /// At its own height (offered only down to its baseline, a text shrank to fit).
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let subview = subviews.first else { return }
        let dimensions = subview.dimensions(in: Self.own(ProposedViewSize(width: bounds.width, height: nil)))
        subview.place(at: bounds.origin, proposal: ProposedViewSize(width: dimensions.width, height: dimensions.height))
    }

    private static func own(_ proposal: ProposedViewSize) -> ProposedViewSize {
        ProposedViewSize(width: proposal.width, height: nil)
    }
}

extension TimerDraftUnits {
    /// Switching Hours or Seconds off drops what they can no longer show.
    @MainActor func normalize(_ timers: TimerStore) {
        let normalized = draft(timers.draftDuration)
        if normalized != timers.draftDuration { timers.draftDuration = normalized }
        if !units.contains(timers.draftUnit) { timers.draftUnit = .minutes }
    }
}
