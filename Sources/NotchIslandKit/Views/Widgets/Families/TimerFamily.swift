import SwiftUI

/// The timer and the stopwatch (`TimerSpecs`): each kind to its view, a kind not built yet to its placeholder.
struct TimerFamily: View, WidgetFamilyElements {
    let widget: IslandWidget
    let size: CGSize

    var body: some View {
        switch widget.kind {
        case .timer: TimerWidget(widget: widget, size: size)
        case .stopwatch: StopwatchWidget(widget: widget, size: size)
        default: WidgetPlaceholder(kind: widget.kind, size: size)
        }
    }

    func demands(_ input: PlanInput) -> [ElementDemand] {
        input.demands(types: [.readout: TimerWidget.readoutType.at(28)])
    }

    func element(_ id: ElementID) -> TimerElement { TimerElement(widget: widget, id: id) }
}

/// One element of the timer or the stopwatch on its own (a custom layout): the very pieces their
/// stacks are built from, at the sizes the layout plans (`\.widgetPlan`).
struct TimerElement: View {
    let widget: IslandWidget
    let id: ElementID

    @Environment(\.widgetPlan) private var plan
    @Environment(\.widgetStyle) private var style
    @Environment(AppModel.self) private var model

    var body: some View {
        let timers = model.timers
        let planned = plan?.elements[id]
        let accent = widget.tint.color ?? TimerRuler.tint
        let units = TimerDraftUnits(hours: widget.shows(.timerHours), seconds: widget.shows(.timerSeconds))
        let controlSize = style.controlSize(id, height: planned?.size.height ?? 28)
        Group {
            switch (widget.kind, id) {
            case (.timer, .ruler):
                let height = planned?.size.height ?? 44
                TimerRulerElement(widget: widget, units: units, accent: accent, compact: height < 30, showsLabels: height >= 58)
            case (.timer, .readout):
                TimerTime(units: units, accent: accent, points: planned?.points ?? 28)
                    .widgetText(.readout, TimerWidget.readoutType.at(planned?.points ?? 28), in: style)
                    .foregroundStyle(accent.opacity(timers.countdown.isPaused ? 0.55 : 1))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: style.element(.readout)?.text.alignment?.frameAlignment ?? .center)
            case (.timer, .timerActions):
                HStack(spacing: Metrics.Spacing.medium) {
                    TimerActions(widget: widget, units: units, accent: accent,
                                 wide: (planned?.size.width ?? 0) >= (planned?.size.height ?? 0) * 2.5, showsAddMinute: false)
                }
                .controlSize(controlSize)
            case (.timer, .addMinute):
                if timers.countdown.isRunning || timers.countdown.isPaused || timers.countdown.isFinished {
                    TimerAddMinute(widget: widget).controlSize(controlSize)
                }
            case (.stopwatch, .readout):
                StopwatchTime(style: style, points: planned?.points ?? 24)
                    .frame(maxWidth: .infinity, alignment: style.element(.readout)?.text.alignment?.frameAlignment ?? .leading)
            case (.stopwatch, .resetButton):
                if timers.isStopwatchActive { StopwatchReset(style: style).controlSize(controlSize) }
            case (.stopwatch, .stopwatchButton):
                StopwatchStartPause(style: style).controlSize(controlSize)
            default:
                EmptyView()
            }
        }
        .animation(Motion.content, value: timers.countdown)
    }
}

/// The iPhone-style timer: a ruler to set the length, one action, and the time in large orange digits.
struct TimerWidget: View {
    let widget: IslandWidget
    let size: CGSize

    @Environment(\.widgetFrameProbe) private var probe
    @Environment(\.widgetStyle) private var style
    @Environment(AppModel.self) private var model
    /// The button row's actions (Start; Pause, +1 and Cancel): the time gets the rest of the row.
    @State private var actionsWidth: CGFloat = 0

    /// The time's type: rounded digits of one width, at the size the row gives it.
    static let readoutType = TypeSpec(points: 28, design: .rounded, weight: .regular, monospacedDigits: true)

    /// Orange, like the iPhone's timer, unless the widget has its own tint.
    private var accent: Color { widget.tint.color ?? TimerRuler.tint }

    private var draftUnits: TimerDraftUnits {
        TimerDraftUnits(hours: widget.shows(.timerHours), seconds: widget.shows(.timerSeconds))
    }

    var body: some View {
        let timers = model.timers
        // The ruler stays at every island size: a short widget gets a shorter ruler and smaller
        // digits rather than losing it (it was dropped below 62 pt, i.e. at Extra Small).
        let isShort = size.height < 66
        let spacing = isShort ? 3 : Metrics.Spacing.small
        let rulerHeight: CGFloat = ((size.height >= 100 ? 44 : 22) * widget.size(of: .ruler).factor).rounded()
        // Ticks plus the marker under them, cut down to what is left above the button row.
        let rulerSpace = min(rulerHeight + 14, size.height - Self.minimumRowHeight - spacing)
        let isCompactRuler = rulerSpace < 30
        let showsRuler = widget.shows(.ruler) && rulerSpace >= Self.minimumRulerSpace
        let rowHeight = showsRuler ? size.height - rulerSpace - spacing : size.height
        VStack(spacing: spacing) {
            if showsRuler {
                TimerRulerElement(widget: widget, units: draftUnits, accent: accent, compact: isCompactRuler,
                                  showsLabels: size.height >= 100)
                    .frame(height: rulerSpace)
                    .editorElement(.ruler, in: probe)
            }
            HStack(spacing: Metrics.Spacing.medium) {
                // One group, as wide as its buttons: the time gets the rest of the row.
                HStack(spacing: Metrics.Spacing.medium) {
                    TimerActions(widget: widget, units: draftUnits, accent: accent, wide: size.width >= 190, showsAddMinute: true)
                }
                .ownDirection()
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { actionsWidth = $0 }
                .buttonElement(.timerActions, in: probe)
                Spacer(minLength: 0)
                if widget.shows(.readout) {
                    let (points, fit) = readoutPoints(timers, rowHeight: rowHeight)
                    // One size for every part of the time. (A shrink-to-fit on the row shrank each
                    // part on its own — a big "0" beside a small ":05:00".) The size is measured to
                    // fit; the smaller ones only catch a measurement that came out short.
                    // The style's size is drawn as set where it fits; wide type (Expanded, wide
                    // letter spacing) the fit does not measure steps down rather than spill.
                    ViewThatFits(in: .horizontal) {
                        readout(points: points, fit: fit)
                        readout(points: points * 0.85, fit: fit)
                        readout(points: points * 0.7, fit: fit)
                        readout(points: points * 0.55, fit: fit)
                        readout(points: points * 0.4, fit: fit)
                    }
                    .foregroundStyle(accent.opacity(timers.countdown.isPaused ? 0.55 : 1))
                    .ownDirection()
                }
            }
            .frame(height: rowHeight)
            .mirroredSides(widget.mirrored)
        }
        .frame(width: size.width, height: size.height)
        .animation(Motion.content, value: timers.countdown)
        .animation(Motion.content, value: timers.draftUnit)
        .onReceive(NotificationCenter.default.publisher(for: .demoNextTimerUnit)) { _ in
            let units = draftUnits
            guard !units.isMinutesOnly else { return }
            timers.draftUnit = units.next(after: timers.draftUnit)
        }
        // Switching Hours or Seconds off drops what they can no longer show.
        .onChange(of: draftUnits, initial: true) { _, units in
            units.normalize(timers)
        }
    }

    /// The time's type size, and the most the row takes: the row's height sets its design size,
    /// and the room beside the buttons caps it — below that cap, so S, M and L stay apart
    /// (`WidgetType.fitted`). A fixed size (the style's) is drawn as set, up to that cap.
    private func readoutPoints(_ timers: TimerStore, rowHeight: CGFloat) -> (CGFloat, CGFloat) {
        let design = WidgetType.points(rowHeight, ratio: 0.72, min: 12, max: 44)
        let room = size.width - actionsWidth - Metrics.Spacing.medium
        let fit = min(WidgetType.size(fitting: TimerTime.text(timers, units: draftUnits), in: room, rounded: true, monospacedDigits: true),
                      WidgetType.size(fittingLines: 1, in: rowHeight))
        let auto = WidgetType.fitted(design, fit: fit, widget.size(of: .readout), floor: 10)
        return (style.textPoints(.readout, auto: auto, fit: fit), fit)
    }

    /// The start button and the time need this much height beside a ruler.
    static let minimumRowHeight: CGFloat = 18
    /// Below this the ruler's ticks would be too short to read or grab.
    static let minimumRulerSpace: CGFloat = 18

    private func readout(points: CGFloat, fit: CGFloat) -> some View {
        TimerTime(units: draftUnits, accent: accent, points: points)
            .widgetTextElement(.readout, Self.readoutType.at(points), fit: fit, in: style, probe: probe)
            .lineLimit(1)
            .fixedSize()
    }

    static func minutesLeft(_ state: CountdownState, at date: Date) -> Int {
        Int(((state.remaining(at: date) ?? 0) / 60).rounded(.up))
    }
}

/// The ruler: set the length while idle, the minutes left while it runs.
struct TimerRulerElement: View {
    let widget: IslandWidget
    let units: TimerDraftUnits
    let accent: Color
    let compact: Bool
    let showsLabels: Bool

    @Environment(AppModel.self) private var model

    var body: some View {
        let timers = model.timers
        let markerSize: CGFloat = compact ? 6 : 9
        switch timers.countdown {
        case .idle:
            let unit = units.units.contains(timers.draftUnit) ? timers.draftUnit : .minutes
            let range = units.range(of: unit)
            TimerRuler(
                minutes: Binding(
                    get: { units.value(of: unit, in: timers.draftDuration) },
                    set: { timers.draftDuration = units.duration(setting: unit, to: $0, in: timers.draftDuration) }
                ),
                // Minutes only: 0 stays on the ruler as a landmark, the ruler settles on 1.
                range: units.isMinutesOnly ? 0...range.upperBound : range,
                minimum: range.lowerBound,
                unit: unit,
                // Too short for the unit's name under the marker: tap a part of the time instead.
                nextUnit: units.isMinutesOnly || compact ? nil : { timers.draftUnit = units.next(after: unit) },
                showsLabels: showsLabels,
                tint: accent,
                onInteraction: { model.island.isInteracting = $0 },
                markerSize: markerSize
            )
            // The ruler swaps only its scale per unit (see `TimerRuler`); the marker stays.
            .onChange(of: timers.draftDuration) { model.haptics.play(.tick) }
        case .running(let endDate, _):
            // Re-read once per remaining minute, on the countdown's own minute boundaries.
            let remaining = max(0, endDate.timeIntervalSinceNow)
            let boundary = endDate.addingTimeInterval(-60 * (remaining / 60).rounded(.up))
            PanelTimelineView(.periodic(from: boundary, by: 60)) { context in
                TimerRuler(
                    minutes: .constant(TimerWidget.minutesLeft(timers.countdown, at: context.date)),
                    isEditable: false,
                    showsLabels: showsLabels,
                    tint: accent,
                    markerSize: markerSize
                )
            }
        case .paused, .finished:
            TimerRuler(minutes: .constant(TimerWidget.minutesLeft(timers.countdown, at: .now)), isEditable: false,
                       showsLabels: showsLabels, tint: accent, markerSize: markerSize)
        }
    }
}

/// The time: the length being set (each unit's part tappable when there are several), or the
/// countdown. Its type is set by whoever draws it (`widgetText`).
struct TimerTime: View {
    let units: TimerDraftUnits
    let accent: Color
    let points: CGFloat

    @Environment(AppModel.self) private var model

    var body: some View {
        let timers = model.timers
        Group {
            switch timers.countdown {
            case .idle:
                if units.isMinutesOnly {
                    // Follows the ruler exactly, unanimated: a cross-fade per tick smeared the digits.
                    Text(IslandFormat.clock(timers.draftDuration))
                        .transaction { $0.animation = nil }
                } else {
                    // Each part is tappable: the ruler then sets that unit. The one being set is bright.
                    HStack(spacing: 0) {
                        ForEach(Array(units.units.enumerated()), id: \.element) { index, unit in
                            if index > 0 { Text(":").opacity(0.45) }
                            let value = units.value(of: unit, in: timers.draftDuration)
                            Text(index == 0 ? "\(value)" : String(format: "%02d", value))
                                .opacity(unit == timers.draftUnit ? 1 : 0.45)
                                .contentShape(.rect)
                                .onTapGesture { timers.draftUnit = unit }
                                .accessibilityAddTraits(.isButton)
                                .accessibilityLabel(Text("\(value) \(unit.accessibilityTitle)"))
                        }
                    }
                }
            default:
                CountdownReadout(state: timers.countdown)
            }
        }
    }

    /// The time as it reads now (a running countdown only gets shorter).
    static func text(_ timers: TimerStore, units: TimerDraftUnits) -> String {
        switch timers.countdown {
        case .idle:
            if units.isMinutesOnly { return IslandFormat.clock(timers.draftDuration) }
            return units.units.enumerated().map { index, unit in
                let value = units.value(of: unit, in: timers.draftDuration)
                return index == 0 ? "\(value)" : String(format: "%02d", value)
            }.joined(separator: ":")
        default:
            return IslandFormat.clock((timers.countdown.remaining(at: .now) ?? 0).rounded(.up))
        }
    }
}

/// The timer's one action (Start, Pause or Resume, Done) and, with it, +1 and Cancel.
struct TimerActions: View {
    let widget: IslandWidget
    let units: TimerDraftUnits
    let accent: Color
    /// Room for the action's title ("Start Timer"); otherwise its symbol in a circle.
    let wide: Bool
    /// +1 drawn here (the stacks); a custom layout places it on its own.
    let showsAddMinute: Bool

    @Environment(\.widgetFrameProbe) private var probe
    @Environment(\.widgetStyle) private var style
    @Environment(AppModel.self) private var model
    /// In a custom layout, the group's rectangle: its buttons share it.
    @Environment(\.elementFill) private var fill

    var body: some View {
        let timers = model.timers
        // The action alone, or with Cancel (and +1 where drawn here): each an equal share of the width.
        let count = timers.countdown.isRunning || timers.countdown.isPaused ? 2 + (showsAddMinute && widget.shows(.addMinute) ? 1 : 0)
                  : timers.countdown.isFinished && showsAddMinute && widget.shows(.addMinute) ? 2 : 1
        buttons(timers)
            .environment(\.elementFill, fill.map { fill in
                CGSize(width: max((fill.width - Metrics.Spacing.medium * CGFloat(count - 1)) / CGFloat(count), 1), height: fill.height)
            })
    }

    @ViewBuilder private func buttons(_ timers: TimerStore) -> some View {
        switch timers.countdown {
        case .idle:
            Button {
                timers.start(duration: units.normalized(timers.draftDuration))
            } label: {
                if wide { Text("Start Timer") } else { Label("Start", systemImage: "play.fill") }
            }
            .widgetButton(.timerActions, in: style)
            .timerAction(iconOnly: !wide, tint: accent)
            // 0:00, on the way to another time: nothing to count down.
            .disabled(!units.canStart(timers.draftDuration))
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
            .widgetButton(.timerActions, in: style)
            .timerAction(iconOnly: !wide, tint: accent)
            if showsAddMinute, widget.shows(.addMinute) {
                TimerAddMinute(widget: widget)
            }
            Button {
                timers.cancel()
            } label: {
                Label("Cancel", systemImage: "xmark")
            }
            .widgetButton(.timerActions.part("cancel"), in: style)
            .islandButton(.circle)
            .help("Cancel the timer")
        case .finished:
            Button {
                timers.acknowledge()
                model.banners.dismiss(.timerFinished)
            } label: {
                if wide { Text("Done") } else { Label("Done", systemImage: "checkmark") }
            }
            .widgetButton(.timerActions, in: style)
            .timerAction(iconOnly: !wide, tint: accent)
            if showsAddMinute, widget.shows(.addMinute) {
                TimerAddMinute(widget: widget)
            }
        }
    }
}

/// +1: a minute more, running or finished.
struct TimerAddMinute: View {
    let widget: IslandWidget

    @Environment(\.widgetFrameProbe) private var probe
    @Environment(\.widgetStyle) private var style
    @Environment(AppModel.self) private var model

    var body: some View {
        let timers = model.timers
        Button("+1") {
            let wasFinished = timers.countdown.isFinished
            timers.add(seconds: 60)
            if wasFinished { model.banners.dismiss(.timerFinished) }
        }
        .widgetButton(.addMinute, in: style)
        .islandButton(.circle)
        .help("Add a minute")
        .buttonElement(.addMinute, in: probe)
    }
}

struct StopwatchWidget: View {
    let widget: IslandWidget
    let size: CGSize

    @Environment(\.widgetFrameProbe) private var probe
    @Environment(\.widgetStyle) private var style
    @Environment(AppModel.self) private var model
    /// The buttons beside the time: it gets the rest of the row.
    @State private var buttonsWidth: CGFloat = 0

    var body: some View {
        let timers = model.timers
        HStack(spacing: Metrics.Spacing.medium) {
            if widget.shows(.readout) {
                let (points, fit) = readoutPoints(timers)
                StopwatchTime(style: style, points: points, fit: fit, probe: probe)
                    .frame(maxWidth: .infinity, alignment: widget.mirrored ? .trailing : .leading)
                    .ownDirection()
            } else {
                Spacer(minLength: 0)
            }
            HStack(spacing: Metrics.Spacing.medium) {
                if widget.shows(.resetButton), timers.isStopwatchActive {
                    StopwatchReset(style: style)
                        .buttonElement(.resetButton, in: probe)
                }
                StopwatchStartPause(style: style)
                    .buttonElement(.stopwatchButton, in: probe)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { buttonsWidth = $0 }
            if !widget.shows(.readout) { Spacer(minLength: 0) }
        }
        .mirroredSides(widget.mirrored)
        .frame(width: size.width, height: size.height)
        .animation(Motion.content, value: timers.stopwatch)
    }

    /// Sized for the widest time it will show before the next redraw of the widget (the digits
    /// tick on their own): "00:00" under an hour, "0:00:00" from the fifty-ninth minute.
    private func readoutPoints(_ timers: TimerStore) -> (CGFloat, CGFloat) {
        let elapsed = timers.stopwatch.elapsed(at: .now)
        let template = elapsed >= 59 * 60 ? "0:00:00" : "00:00"
        let room = size.width - buttonsWidth - Metrics.Spacing.medium
        let fit = min(WidgetType.size(fitting: template, in: room, rounded: true, monospacedDigits: true),
                      WidgetType.size(fittingLines: 1, in: size.height))
        let auto = WidgetType.fitted(WidgetType.points(size.height, ratio: 0.55, min: 15, max: 40), fit: fit,
                                     widget.size(of: .readout), floor: 11)
        return (style.textPoints(.readout, auto: auto, fit: fit), fit)
    }
}

/// The stopwatch's time, bright while it runs.
struct StopwatchTime: View {
    let style: ResolvedWidgetStyle
    let points: CGFloat
    var fit: CGFloat?
    var probe: WidgetFrameProbe?

    @Environment(AppModel.self) private var model

    var body: some View {
        let timers = model.timers
        StopwatchReadout(state: timers.stopwatch)
            .widgetTextElement(.readout, TimerWidget.readoutType.at(points), fit: fit, in: style, probe: probe)
            .foregroundStyle(timers.stopwatch.isRunning ? .primary : .secondary)
            .lineLimit(1)
            // Only for a measurement that came out short: the size is fitted already.
            .minimumScaleFactor(0.7)
    }
}

struct StopwatchReset: View {
    let style: ResolvedWidgetStyle

    @Environment(AppModel.self) private var model

    var body: some View {
        Button {
            model.timers.resetStopwatch()
        } label: {
            Label("Reset", systemImage: "arrow.counterclockwise")
        }
        .widgetButton(.resetButton, in: style)
        .islandButton(.circle)
        .help("Reset")
    }
}

struct StopwatchStartPause: View {
    let style: ResolvedWidgetStyle

    @Environment(AppModel.self) private var model

    var body: some View {
        let timers = model.timers
        let running = timers.stopwatch.isRunning
        Button {
            running ? timers.pauseStopwatch() : timers.startStopwatch()
        } label: {
            Label(running ? "Pause" : "Start", systemImage: running ? "pause.fill" : "play.fill")
                .contentTransition(.symbolEffect(.replace))
        }
        .widgetButton(.stopwatchButton, in: style)
        .islandButton(.circle, prominent: true)
        .help(running ? "Pause" : "Start")
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
