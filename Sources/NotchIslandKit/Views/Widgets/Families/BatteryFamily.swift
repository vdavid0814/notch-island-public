import SwiftUI

/// The battery's widgets (`BatterySpecs`): each kind to its view, a kind not built yet to its placeholder.
struct BatteryFamily: View, WidgetFamilyElements {
    let widget: IslandWidget
    let size: CGSize

    var body: some View {
        switch widget.kind {
        case .battery: BatteryWidget(widget: widget, size: size)
        case .batteryChart: BatteryChartWidget(widget: widget, size: size)
        case .batteryTime, .batteryHealth, .batteryCycles, .batteryPower, .batteryTemperature, .charger:
            BatteryFigureWidget(widget: widget, size: size)
        default: WidgetPlaceholder(kind: widget.kind, size: size)
        }
    }

    func demands(_ input: PlanInput) -> [ElementDemand] {
        widget.kind == .battery
            ? input.demands(types: [.percentage: BatteryWidget.percentType.at(22), .timeRemaining: BatteryWidget.timeType.at(12)])
            : ReadingWidget.demands(input)
    }

    func element(_ id: ElementID) -> BatteryElement { BatteryElement(widget: widget, id: id) }
}

/// One element of a battery widget on its own (a custom layout), at the size the layout plans.
struct BatteryElement: View {
    let widget: IslandWidget
    let id: ElementID

    @Environment(\.widgetPlan) private var plan
    @Environment(\.widgetStyle) private var style
    @Environment(AppModel.self) private var model

    var body: some View {
        let state = model.power.state
        let planned = plan?.elements[id]
        let room = planned?.size ?? CGSize(width: 40, height: 20)
        let alignment = style.element(id)?.text.alignment?.frameAlignment ?? .leading
        switch (widget.kind, id) {
        case (.battery, .batteryGlyph):
            // The percentage inside it, as the stacks drew it, unless the layout places it apart.
            let inside = widget.shows(.percentage) && plan?.elements[.percentage] == nil
            if room.width < room.height * 1.4 {
                BatteryRing(level: state.level, isCharging: state.isCharging, tint: state.tint,
                            showsPercentage: inside && min(room.width, room.height) >= 40, diameter: min(room.width, room.height),
                            percentSize: widget.size(of: .percentage))
            } else {
                BatteryGlyph(level: state.level, isCharging: state.isCharging, tint: state.tint, showsPercentage: inside,
                             height: min(room.height, room.width / 2.2))
            }
        case (.battery, .percentage):
            Text(state.hasBattery ? IslandFormat.percent(Double(state.level) / 100) : "—")
                .widgetText(.percentage, BatteryWidget.percentType.at(planned?.points ?? 16), in: style)
                .foregroundStyle(state.tint.style)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, alignment: alignment)
        case (.battery, .timeRemaining):
            if let text = BatteryWidget.remaining(state) {
                Text(text)
                    .widgetText(.timeRemaining, BatteryWidget.timeType.at(planned?.points ?? 11), in: style)
                    .foregroundStyle(.secondary)
                    .lineLimit(style.element(.timeRemaining)?.text.lineLimit ?? 1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: alignment)
            }
        case (.batteryChart, .chart):
            BatteryChartElement(widget: widget, size: room)
        case (_, .value), (_, .label), (_, .symbol):
            BatteryFigureElement(widget: widget, id: id)
        default:
            EmptyView()
        }
    }
}

struct BatteryWidget: View {
    let widget: IslandWidget
    let size: CGSize

    @Environment(\.widgetFrameProbe) private var probe
    @Environment(\.widgetStyle) private var style
    @Environment(AppModel.self) private var model

    /// The percentage's type (rounded, digits of one width) and the time left's.
    static let percentType = TypeSpec(points: 16, design: .rounded, weight: .semibold, monospacedDigits: true)
    static let timeType = TypeSpec(points: 11)

    /// Automatic: a ring when the widget is about square, the battery when it is wide.
    private var layout: WidgetLayout {
        switch widget.layout {
        case .automatic: size.width < size.height * 1.4 ? .ring : .glyph
        default: widget.layout
        }
    }

    var body: some View {
        let state = model.power.state
        Group {
            if layout == .ring {
                ring(state)
            } else {
                glyph(state)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private func ring(_ state: PowerState) -> some View {
        let side = min(size.width, size.height)
        let diameter = WidgetType.fitted(side, fit: side, widget.size(of: .batteryGlyph), floor: 20)
        let timeFit = WidgetType.size(fittingLines: 1, in: size.height - diameter - Metrics.Spacing.xSmall)
        let timeSize = style.textPoints(.timeRemaining, auto: WidgetType.fitted(11, fit: timeFit, widget.size(of: .timeRemaining), floor: 8),
                                        fit: timeFit)
        return VStack(spacing: Metrics.Spacing.xSmall) {
            BatteryRing(level: state.level, isCharging: state.isCharging, tint: state.tint,
                        showsPercentage: widget.shows(.percentage) && diameter >= 40, diameter: diameter,
                        percentSize: widget.size(of: .percentage))
                .editorElement(.batteryGlyph, in: probe)
            if widget.shows(.timeRemaining), size.height - diameter >= 14, let text = Self.remaining(state) {
                Text(text).widgetTextElement(.timeRemaining, Self.timeType.at(timeSize), fit: timeFit, in: style, probe: probe)
                    .foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            }
        }
    }

    // The battery with its percentage inside; the time left beside it (or under it when the
    // widget is tall). Without the battery element, the percentage alone, large.
    private func glyph(_ state: PowerState) -> some View {
        let tall = size.height >= 70
        let time = widget.shows(.timeRemaining) && (size.width >= 110 || tall) ? Self.remaining(state) : nil
        // Beside the battery (or the percentage), the time left takes what the other leaves.
        let share: CGFloat = time == nil || tall ? 1 : 0.5
        let glyphHeight = WidgetType.fitted(
            WidgetType.points(size.height, ratio: tall ? 0.3 : 0.5, min: 11, max: 34),
            fit: min((size.width - 8) * share / 2.35, size.height * (tall ? 0.5 : 0.8)),
            widget.size(of: .batteryGlyph), floor: 9)
        let percentText = state.hasBattery ? IslandFormat.percent(Double(state.level) / 100) : "—"
        let percentFit = min(WidgetType.size(fitting: "100%", in: (size.width - 8) * share, weight: .semibold, rounded: true,
                                             monospacedDigits: true),
                             WidgetType.size(fittingLines: tall && time != nil ? 1.6 : 1, in: size.height))
        let percentSize = style.textPoints(.percentage, auto: WidgetType.fitted(
            WidgetType.points(size.height, ratio: 0.42, min: 13, max: 34), fit: percentFit, widget.size(of: .percentage), floor: 10),
            fit: percentFit)
        let besideWidth = widget.shows(.batteryGlyph) ? glyphHeight * 2.35 : WidgetType.textWidth(percentText, size: percentSize)
        let timeFit = min(WidgetType.size(fitting: time ?? "", in: tall ? size.width - 8 : size.width - besideWidth - Metrics.Spacing.medium - 8),
                          WidgetType.size(fittingLines: 1, in: tall ? size.height * 0.3 : size.height))
        let timeSize = style.textPoints(.timeRemaining, auto: WidgetType.fitted(
            WidgetType.points(size.height, ratio: 0.18, min: 10, max: 15), fit: timeFit, widget.size(of: .timeRemaining), floor: 8),
            fit: timeFit)
        let layout = tall ? AnyLayout(VStackLayout(spacing: Metrics.Spacing.small))
                          : AnyLayout(HStackLayout(spacing: Metrics.Spacing.medium))
        return layout {
            if widget.shows(.batteryGlyph) {
                BatteryGlyph(level: state.level, isCharging: state.isCharging, tint: state.tint,
                             showsPercentage: widget.shows(.percentage), height: glyphHeight)
                    .ownDirection()
                    .editorElement(.batteryGlyph, in: probe)
            } else if widget.shows(.percentage) {
                Text(percentText)
                    .widgetTextElement(.percentage, Self.percentType.at(percentSize), fit: percentFit, in: style, probe: probe)
                    .foregroundStyle(state.tint.style)
                    .contentTransition(.opacity)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            if let text = time {
                Text(text)
                    .widgetTextElement(.timeRemaining, Self.timeType.at(timeSize), fit: timeFit, in: style, probe: probe)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .ownDirection()
            }
        }
        .mirroredSides(widget.mirrored && !tall)
    }

    static func remaining(_ state: PowerState) -> String? {
        if state.isCharging { return String(localized: "Charging") }
        guard let minutes = state.minutesRemaining, minutes > 0 else { return nil }
        let text = Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .narrow))
        return String(localized: "\(text) left")
    }
}
