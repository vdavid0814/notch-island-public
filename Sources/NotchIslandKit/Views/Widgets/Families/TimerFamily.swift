import SwiftUI

/// The timer and the stopwatch (`TimerSpecs`): each kind to its view, a kind not built yet to its placeholder.
struct TimerFamily: View {
    let widget: IslandWidget
    let size: CGSize

    var body: some View {
        switch widget.kind {
        case .timer: TimerWidget(widget: widget, size: size)
        case .stopwatch: StopwatchWidget(widget: widget, size: size)
        default: WidgetPlaceholder(kind: widget.kind, size: size)
        }
    }
}

/// The iPhone-style timer: a ruler to set the length, one action, and the time in large orange digits.
struct TimerWidget: View {
    let widget: IslandWidget
    let size: CGSize

    @Environment(\.widgetFrameProbe) private var probe
    @Environment(AppModel.self) private var model
    /// The unit the ruler sets (with Hours or Seconds on): tap a part of the time, or the unit under
    /// the marker, to move on.
    @State private var editing: TimerUnit = .minutes
    /// The button row's actions (Start; Pause, +1 and Cancel): the time gets the rest of the row.
    @State private var actionsWidth: CGFloat = 0

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
                ruler(timers, compact: isCompactRuler)
                    .frame(height: rulerSpace)
                    .editorElement(.ruler, in: probe)
            }
            HStack(spacing: Metrics.Spacing.medium) {
                actions(timers)
                    .ownDirection()
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { actionsWidth = $0 }
                Spacer(minLength: 0)
                if widget.shows(.readout) {
                    let points = readoutPoints(timers, rowHeight: rowHeight)
                    // One size for every part of the time. (A shrink-to-fit on the row shrank each
                    // part on its own — a big "0" beside a small ":05:00".) The size is measured to
                    // fit; the smaller ones only catch a measurement that came out short.
                    ViewThatFits(in: .horizontal) {
                        readout(timers, points: points)
                        readout(timers, points: points * 0.85)
                        readout(timers, points: points * 0.7)
                    }
                    .foregroundStyle(accent.opacity(timers.countdown.isPaused ? 0.55 : 1))
                    .ownDirection()
                    .editorElement(.readout, in: probe)
                }
            }
            .frame(height: rowHeight)
            .mirroredSides(widget.mirrored)
        }
        .frame(width: size.width, height: size.height)
        .animation(Motion.content, value: timers.countdown)
        .animation(Motion.content, value: editing)
        .onReceive(NotificationCenter.default.publisher(for: .demoNextTimerUnit)) { _ in
            let units = draftUnits
            guard !units.isMinutesOnly else { return }
            editing = units.next(after: editing)
        }
        // Switching Hours or Seconds off drops what they can no longer show.
        .onChange(of: draftUnits, initial: true) { _, units in
            let normalized = units.draft(timers.draftDuration)
            if normalized != timers.draftDuration { timers.draftDuration = normalized }
            if !units.units.contains(editing) { editing = .minutes }
        }
    }

    @ViewBuilder private func ruler(_ timers: TimerStore, compact: Bool) -> some View {
        let showsLabels = size.height >= 100
        let markerSize: CGFloat = compact ? 6 : 9
        switch timers.countdown {
        case .idle:
            let units = draftUnits
            let unit = units.units.contains(editing) ? editing : .minutes
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
                nextUnit: units.isMinutesOnly || compact ? nil : { editing = units.next(after: unit) },
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
                    minutes: .constant(Self.minutesLeft(timers.countdown, at: context.date)),
                    isEditable: false,
                    showsLabels: showsLabels,
                    tint: accent,
                    markerSize: markerSize
                )
            }
        case .paused, .finished:
            TimerRuler(minutes: .constant(Self.minutesLeft(timers.countdown, at: .now)), isEditable: false,
                       showsLabels: showsLabels, tint: accent, markerSize: markerSize)
        }
    }

    /// The time's type size: the row's height sets its design size, and the room beside the
    /// buttons caps it — below that cap, so S, M and L stay apart (`WidgetType.fitted`).
    private func readoutPoints(_ timers: TimerStore, rowHeight: CGFloat) -> CGFloat {
        let design = WidgetType.points(rowHeight, ratio: 0.72, min: 12, max: 44)
        let room = size.width - actionsWidth - Metrics.Spacing.medium
        let fit = min(WidgetType.size(fitting: readoutText(timers), in: room, rounded: true, monospacedDigits: true),
                      WidgetType.size(fittingLines: 1, in: rowHeight))
        return WidgetType.fitted(design, fit: fit, widget.size(of: .readout), floor: 10)
    }

    /// The time as it reads now (a running countdown only gets shorter).
    private func readoutText(_ timers: TimerStore) -> String {
        switch timers.countdown {
        case .idle:
            let units = draftUnits
            if units.isMinutesOnly { return IslandFormat.clock(timers.draftDuration) }
            return units.units.enumerated().map { index, unit in
                let value = units.value(of: unit, in: timers.draftDuration)
                return index == 0 ? "\(value)" : String(format: "%02d", value)
            }.joined(separator: ":")
        default:
            return IslandFormat.clock((timers.countdown.remaining(at: .now) ?? 0).rounded(.up))
        }
    }

    /// The start button and the time need this much height beside a ruler.
    static let minimumRowHeight: CGFloat = 18
    /// Below this the ruler's ticks would be too short to read or grab.
    static let minimumRulerSpace: CGFloat = 18

    private func readout(_ timers: TimerStore, points: CGFloat) -> some View {
        time(timers)
            .font(.system(size: points, weight: .regular, design: .rounded).monospacedDigit())
            .lineLimit(1)
            .fixedSize()
    }

    static func minutesLeft(_ state: CountdownState, at date: Date) -> Int {
        Int(((state.remaining(at: date) ?? 0) / 60).rounded(.up))
    }

    @ViewBuilder private func time(_ timers: TimerStore) -> some View {
        switch timers.countdown {
        case .idle:
            let units = draftUnits
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
                            .opacity(unit == editing ? 1 : 0.45)
                            .contentShape(.rect)
                            .onTapGesture { editing = unit }
                            .accessibilityAddTraits(.isButton)
                            .accessibilityLabel(Text("\(value) \(unit.accessibilityTitle)"))
                    }
                }
            }
        default:
            CountdownReadout(state: timers.countdown)
        }
    }

    @ViewBuilder private func actions(_ timers: TimerStore) -> some View {
        let wide = size.width >= 190
        switch timers.countdown {
        case .idle:
            Button {
                timers.start(duration: draftUnits.normalized(timers.draftDuration))
            } label: {
                if wide { Text("Start Timer") } else { Label("Start", systemImage: "play.fill") }
            }
            .timerAction(iconOnly: !wide, tint: accent)
            // 0:00, on the way to another time: nothing to count down.
            .disabled(!draftUnits.canStart(timers.draftDuration))
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
            .timerAction(iconOnly: !wide, tint: accent)
            if widget.shows(.addMinute) {
                Button("+1") { timers.add(seconds: 60) }
                    .islandButton(.circle)
                    .help("Add a minute")
                    .editorElement(.addMinute, in: probe)
            }
            Button {
                timers.cancel()
            } label: {
                Label("Cancel", systemImage: "xmark")
            }
            .islandButton(.circle)
            .help("Cancel the timer")
        case .finished:
            Button {
                timers.acknowledge()
                model.banners.dismiss(.timerFinished)
            } label: {
                if wide { Text("Done") } else { Label("Done", systemImage: "checkmark") }
            }
            .timerAction(iconOnly: !wide, tint: accent)
            if widget.shows(.addMinute) {
                Button("+1") {
                    timers.add(seconds: 60)
                    model.banners.dismiss(.timerFinished)
                }
                .islandButton(.circle)
                .help("Add a minute")
                .editorElement(.addMinute, in: probe)
            }
        }
    }
}

struct StopwatchWidget: View {
    let widget: IslandWidget
    let size: CGSize

    @Environment(\.widgetFrameProbe) private var probe
    @Environment(AppModel.self) private var model
    /// The buttons beside the time: it gets the rest of the row.
    @State private var buttonsWidth: CGFloat = 0

    var body: some View {
        let timers = model.timers
        let running = timers.stopwatch.isRunning
        HStack(spacing: Metrics.Spacing.medium) {
            if widget.shows(.readout) {
                StopwatchReadout(state: timers.stopwatch)
                    .font(.system(size: readoutPoints(timers), weight: .regular, design: .rounded).monospacedDigit())
                    .foregroundStyle(running ? .primary : .secondary)
                    .lineLimit(1)
                    // Only for a measurement that came out short: the size is fitted already.
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: widget.mirrored ? .trailing : .leading)
                    .ownDirection()
                    .editorElement(.readout, in: probe)
            } else {
                Spacer(minLength: 0)
            }
            HStack(spacing: Metrics.Spacing.medium) {
                if widget.shows(.resetButton), timers.isStopwatchActive {
                    Button {
                        timers.resetStopwatch()
                    } label: {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                    }
                    .islandButton(.circle)
                    .help("Reset")
                    .editorElement(.resetButton, in: probe)
                }
                Button {
                    running ? timers.pauseStopwatch() : timers.startStopwatch()
                } label: {
                    Label(running ? "Pause" : "Start", systemImage: running ? "pause.fill" : "play.fill")
                        .contentTransition(.symbolEffect(.replace))
                }
                .islandButton(.circle, prominent: true)
                .help(running ? "Pause" : "Start")
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
    private func readoutPoints(_ timers: TimerStore) -> CGFloat {
        let elapsed = timers.stopwatch.elapsed(at: .now)
        let template = elapsed >= 59 * 60 ? "0:00:00" : "00:00"
        let room = size.width - buttonsWidth - Metrics.Spacing.medium
        let fit = min(WidgetType.size(fitting: template, in: room, rounded: true, monospacedDigits: true),
                      WidgetType.size(fittingLines: 1, in: size.height))
        return WidgetType.fitted(WidgetType.points(size.height, ratio: 0.55, min: 15, max: 40), fit: fit,
                                 widget.size(of: .readout), floor: 11)
    }
}
