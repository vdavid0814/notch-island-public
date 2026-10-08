import AppKit
import SwiftUI

/// What Customize needs to know of each kind's text and button parts, so its panels work alike for
/// every widget: the text a text part shows now (or a sample) and its own size and weight, and a
/// button's title, symbol and symbol size. Each the widget itself draws them with — as Customize's
/// editor draws it, a picture (switches on, the battery's and the levels' samples), so the panels
/// measure what is seen there.
@MainActor enum WidgetParts {
    // MARK: Texts

    static func text(of id: ElementID, in widget: IslandWidget, model: AppModel) -> String {
        switch id {
        case .trackInfo: NowPlayingWidget.title(model.media.item ?? NowPlayingWidget.sample)
        case .artist: NowPlayingWidget.subtitle(model.media.item ?? NowPlayingWidget.sample)
        case .readout:
            switch widget.kind {
            case .stopwatch: IslandFormat.clock(model.timers.stopwatch.elapsed(at: .now))
            case .timer: TimerWidget.timeText(model.timers, units: TimerWidget.units(widget), picture: true, at: .now)
            default: DateTimeWidget.timeText(.now)
            }
        case .dateLine: DateTimeWidget.dateText(.now)
        case .controlName: widget.kind.control?.title ?? ""
        case .controlStatus:
            widget.kind.control.map { ControlWidget.status($0, on: ControlWidget.isOn($0, model: model, picture: true), picture: true) } ?? ""
        case .levelValue:
            widget.kind.level.map { LevelWidget.valueText(LevelWidget.reading($0, model: model, picture: true) ?? .unavailable) } ?? ""
        case .elapsedTime, .remainingTime: "0:00"
        case .value:
            switch widget.kind {
            case .batteryChart: BatteryWidget.percentText(BatteryWidget.sample)
            case .batteryUsage: IslandFormat.percent(0.7)
            default: Readouts.picture(widget).value
            }
        case .label:
            switch widget.kind {
            case .batteryChart: BatteryChartWidget.caption
            case .analogClock: ClockFaceWidget.caption(widget.config, here: .current)
            case .monthCalendar: MonthGrid(date: .now, calendar: .current, locale: .current).title
            case .batteryUsage: DailyUsageWidget.title
            default: Readouts.picture(widget).caption
            }
        case .usageDay: String(localized: "Today")
        case .rulerUnit: TimerWidget.unit(model.timers, units: TimerWidget.units(widget)).shortTitle
        case .monthDays: "24"
        case .shelfCount: ShelfWidget.countText(ShelfWidget.sampleCount)
        case .percentage: BatteryWidget.percentText(BatteryWidget.sample)
        case .timeRemaining: BatteryWidget.remaining(BatteryWidget.sample) ?? String(localized: "Charging")
        default: id.clipRow.map { ClipboardWidget.text(row: $0, items: []) } ?? ""
        }
    }

    /// Its own size in a widget whose inside is `inner`, before Customize sets one.
    static func textSize(of id: ElementID, in widget: IslandWidget, inner: CGSize) -> CGFloat {
        switch id {
        case .readout:
            switch widget.kind {
            case .stopwatch: StopwatchWidget.readoutPoints(inner: inner)
            case .timer: TimerWidget.readoutPoints(widget, inner: inner)
            default: DateTimeWidget.timePoints(inner: inner)
            }
        case .dateLine: DateTimeWidget.datePoints(inner: inner)
        case .controlName:
            widget.kind.control.map { ControlWidget.labelLayout($0, widget: widget, inner: inner, picture: true).name } ?? 13
        case .controlStatus:
            widget.kind.control.map { ControlWidget.labelLayout($0, widget: widget, inner: inner, picture: true).status } ?? 11
        case .levelValue: LevelWidget.valuePoints(inner: inner)
        case .value:
            switch widget.kind {
            case .batteryChart: BatteryChartWidget.valuePoints
            case .batteryUsage: DailyUsageWidget.valuePoints(inner: inner)
            default: ReadingWidget.valuePoints(widget, reading: Readouts.picture(widget), inner: inner)
            }
        case .label:
            switch widget.kind {
            case .batteryChart: BatteryChartWidget.captionPoints
            case .analogClock: ClockFaceWidget.captionPoints(inner: inner)
            case .monthCalendar: MonthCalendarWidget.titlePoints(inner: inner)
            case .batteryUsage: DailyUsageWidget.titlePoints(inner: inner)
            default: ReadingWidget.captionPoints(inner: inner)
            }
        case .usageDay: DailyUsageWidget.dayPoints(inner: inner)
        case .rulerUnit: RulerUnitName.points(markerSize: TimerWidget.rulerSpace(inner: inner) < 30 ? 6 : 9)
        case .monthDays: MonthCalendarWidget.dayPoints(widget, inner: inner)
        case .shelfCount: ShelfWidget.countPoints(inner: inner)
        case .percentage: BatteryWidget.percentPoints(inner: inner)
        case .timeRemaining:
            widget.shows(.batteryGlyph) || widget.shows(.percentage)
                ? BatteryWidget.timePoints(inner: inner) : BatteryWidget.timeAlonePoints(inner: inner)
        default:
            widget.kind == .clipboard ? ClipboardWidget.textPoints(widget, inner: inner) : NowPlayingWidget.textSize(of: id, inner: inner)
        }
    }

    static func weight(of id: ElementID, in widget: IslandWidget) -> NSFont.Weight {
        switch id {
        case .trackInfo, .controlName, .value, .percentage: .semibold
        case .label: widget.kind == .monthCalendar || widget.kind == .batteryUsage ? .semibold : .medium
        case .readout: widget.kind == .stopwatch || widget.kind == .timer ? .regular : .semibold
        case .usageDay, .shelfCount, .monthDays: .medium
        case .rulerUnit: RulerUnitName.weight
        case .dateLine: .medium
        default: id.clipRow != nil ? .medium : .regular
        }
    }

    // MARK: Buttons

    static func buttonTitle(of id: ElementID, in widget: IslandWidget) -> String {
        switch id {
        case .previousButton: String(localized: "Previous")
        case .nextButton: String(localized: "Next")
        case .playbackButtons: String(localized: "Play / Pause")
        case .seekBackButton: String(localized: "Back")
        case .seekForwardButton: String(localized: "Forward")
        case .resetButton: String(localized: "Reset")
        case .stopwatchButton: String(localized: "Start / Pause")
        case .controlButton: widget.kind.control?.title ?? String(localized: "Button")
        case .levelIcon, .symbol: String(localized: "Symbol")
        case .batteryRing: String(localized: "Battery")
        case .timerActions: String(localized: "Start / Pause")
        case .face: String(localized: "Clock Face")
        case .addMinute: String(localized: "+1 Minute")
        case .timerCancel: String(localized: "Cancel")
        case .shelfTray: String(localized: "Tray")
        case .shelfAirDrop: String(localized: "AirDrop")
        case .shelfClear: String(localized: "Clear")
        default: id.clipRow.map { String(localized: "Symbol \($0)") } ?? String(localized: "Button")
        }
    }

    /// The symbol it shows now.
    static func buttonSymbol(of id: ElementID, in widget: IslandWidget, model: AppModel) -> String {
        switch id {
        case .previousButton: "backward.fill"
        case .nextButton: "forward.fill"
        case .seekBackButton: NowPlayingWidget.seekSymbol(back: true, seconds: widget.effectiveSeekSeconds)
        case .seekForwardButton: NowPlayingWidget.seekSymbol(back: false, seconds: widget.effectiveSeekSeconds)
        case .resetButton: "arrow.counterclockwise"
        case .stopwatchButton: model.timers.stopwatch.isRunning ? "pause.fill" : "play.fill"
        case .timerActions: TimerWidget.action(model.timers.countdown).symbol
        case .face: "clock"
        case .addMinute: "plus"
        case .timerCancel: "xmark"
        case .shelfTray: "tray.full.fill"
        case .shelfAirDrop: "dot.radiowaves.up.forward"
        case .shelfClear: "xmark"
        case _ where id.clipRow != nil: ClipboardWidget.symbol
        case .controlButton:
            widget.kind.control.map { $0.symbol(on: ControlWidget.isOn($0, model: model, picture: true)) } ?? "circle"
        case .symbol: Readouts.picture(widget).symbol
        case .batteryRing: BatteryWidget.ringSymbol(BatteryWidget.sample)
        case .levelIcon:
            widget.kind.level.map { $0.symbol(LevelWidget.reading($0, model: model, picture: true) ?? .unavailable) } ?? "circle"
        default: model.media.isPlaying ? "pause.fill" : "play.fill"
        }
    }

    /// Its symbol's size in a widget whose inside is `inner`.
    static func buttonPoints(of id: ElementID, in widget: IslandWidget, inner: CGSize) -> CGFloat {
        if widget.kind.control != nil { return ControlWidget.buttonPoints(widget, inner: inner) }
        if widget.kind.level != nil { return LevelWidget.iconPoints(inner: inner) }
        if widget.kind.isReadout { return ReadingWidget.symbolPoints(inner: inner) }
        return switch widget.kind {
        case .nowPlaying: NowPlayingWidget.controlRow(widget, inner: inner).points
        case .stopwatch: StopwatchWidget.buttonPoints(inner: inner)
        case .timer: TimerWidget.buttonPoints(widget, inner: inner)
        case .analogClock:
            ClockFaceButton.points(diameter: ClockFaceWidget.diameter(widget, inner: inner), look: widget.buttonLook(of: id))
        case .shelf: ShelfWidget.symbolPoints(inner: inner)
        case .clipboard: ClipboardWidget.symbolPoints(widget, inner: inner)
        case .battery:
            // As the ring's inside takes it: a shape fills it, a symbol alone is the ring's own size.
            widget.buttonLook(of: id).material.hasShape
                ? (BatteryWidget.ringDiameter(widget, inner: inner, showsTime: false)
                   - 2 * max(3, BatteryWidget.ringDiameter(widget, inner: inner, showsTime: false) * 0.1)) / 1.35
                : BatteryWidget.ringSymbolPoints(diameter: BatteryWidget.ringDiameter(widget, inner: inner, showsTime: false),
                                                 showsPercentage: widget.shows(.percentage))
        default: 20
        }
    }
}
