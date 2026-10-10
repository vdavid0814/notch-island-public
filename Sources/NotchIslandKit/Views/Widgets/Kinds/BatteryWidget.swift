import SwiftUI

/// The battery, the base of a ring: about square, a ring filled to the charge with the percentage
/// inside; wide, the battery with its percentage cut out of it and the time left beside it (under
/// it when tall). Without the battery, the percentage alone, large. Each of the three is moved in
/// Customize; the percentage and the time left are texts there.
struct BatteryWidget: View {
    let widget: IslandWidget
    let size: CGSize

    @Environment(AppModel.self) private var model
    @Environment(\.isWidgetPreview) private var isPreview

    /// A picture's battery: three quarters, on battery, a few hours left.
    static let sample = PowerState(hasBattery: true, level: 76, isCharging: false, isPluggedIn: false, isCharged: false,
                                   minutesRemaining: 192, isLowPowerMode: false)

    /// A ring where the widget is about square.
    static func isRing(_ inner: CGSize) -> Bool { inner.width < inner.height * 1.4 }

    static func isTall(_ inner: CGSize) -> Bool { inner.height >= 70 }

    /// The percentage's size, alone (no battery to cut it out of).
    static func percentPoints(inner: CGSize) -> CGFloat {
        let fit = (inner.width - 8) / 2.6
        return max(min(WidgetMetrics.points(inner.height, ratio: 0.42, min: 13, max: 34), fit.rounded(.down)), 10)
    }

    static func timePoints(inner: CGSize) -> CGFloat {
        isRing(inner) ? 11 : WidgetMetrics.points(inner.height, ratio: 0.18, min: 10, max: 15)
    }

    /// The time left alone (no battery, no percentage): larger, as the widget's one line, still
    /// fitting its width ("3h 12m left").
    static func timeAlonePoints(inner: CGSize) -> CGFloat {
        max(min(WidgetMetrics.points(inner.height, ratio: 0.32, min: 11, max: 18), (inner.width / 5.6).rounded(.down)), 9)
    }

    /// Only the time left switched on.
    private var timeIsAlone: Bool { !widget.shows(.batteryGlyph) && !widget.shows(.percentage) }

    /// "Charging"; on power, "Charged" (or "On Hold" while charging waits, as Battery Time says);
    /// "3h 12m left", or "Calculating…" while the system estimates (the first minutes off the
    /// charger), as macOS says it. Nil only without a battery.
    /// `short`: without "left" ("3h 12m", "—"), where the whole does not fit.
    static func remaining(_ state: PowerState, short: Bool = false) -> String? {
        if state.isCharging { return String(localized: "Charging") }
        if state.isPluggedIn { return state.isCharged ? String(localized: "Charged") : String(localized: "On Hold") }
        guard state.hasBattery else { return nil }
        guard let minutes = state.minutesRemaining, minutes > 0 else {
            return short ? "—" : String(localized: "Calculating…")
        }
        let text = Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .narrow))
        return short ? text : String(localized: "\(text) left")
    }

    static func percentText(_ state: PowerState) -> String {
        state.hasBattery ? IslandFormat.percent(Double(state.level) / 100) : "—"
    }

    var body: some View {
        let state = isPreview ? Self.sample : model.power.state
        Group {
            if Self.isRing(size) {
                ring(state)
            } else {
                glyph(state)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    /// The ring's diameter: the widget's height, less the time left's line under it.
    static func ringDiameter(_ widget: IslandWidget, inner: CGSize, showsTime: Bool) -> CGFloat {
        max(min(inner.width, inner.height - (showsTime ? 16 : 0)), 20)
    }

    /// The ring's symbol (the Mac, or the bolt while charging), as the ring sets it: smaller to
    /// make room for the percentage under it.
    static func ringSymbolPoints(diameter: CGFloat, showsPercentage: Bool) -> CGFloat {
        showsPercentage ? min(diameter * 0.2, max(6, diameter * 0.46 - ringPercentPoints(diameter: diameter))) : diameter * 0.34
    }

    static func ringPercentPoints(diameter: CGFloat) -> CGFloat { max(diameter * 0.22, 8) }

    static func ringSymbol(_ state: PowerState) -> String { state.isCharging ? "bolt.fill" : "laptopcomputer" }

    private func ring(_ state: PowerState) -> some View {
        let diameter = Self.ringDiameter(widget, inner: size, showsTime: showsTime(state))
        let showsPercent = widget.shows(.percentage) && diameter >= 40
        return VStack(spacing: Metrics.Spacing.xSmall) {
            if widget.shows(.batteryGlyph) {
                BatteryRing(level: state.level, isCharging: state.isCharging, tint: state.tint, diameter: diameter,
                            look: widget.buttonLook(of: .batteryRing), ring: widget.progressLook(of: .batteryRing),
                            showsPercentage: showsPercent) {
                    percentage(state, points: Self.ringPercentPoints(diameter: diameter), inRing: true)
                }
                .movableElement(.batteryRing, of: widget)
            } else if widget.shows(.percentage) {
                percentage(state, points: Self.percentPoints(inner: size))
            }
            if showsTime(state), let text = Self.remaining(state) {
                time(text, short: Self.remaining(state, short: true), points: timeIsAlone ? Self.timeAlonePoints(inner: size) : Self.timePoints(inner: size))
            }
        }
    }

    private func showsTime(_ state: PowerState) -> Bool {
        widget.shows(.timeRemaining) && Self.remaining(state) != nil
            && (Self.isRing(size) ? size.height - min(size.width, size.height) >= 14 || !widget.shows(.batteryGlyph) : true)
    }

    // The battery with its percentage inside; the time left beside it (or under it when the widget
    // is tall). Without the battery, the percentage alone, large.
    private func glyph(_ state: PowerState) -> some View {
        let tall = Self.isTall(size)
        // Beside the battery from a width that leaves it room; alone, at any width.
        let text = widget.shows(.timeRemaining) && (size.width >= 110 || tall || timeIsAlone) ? Self.remaining(state) : nil
        // Beside the battery, the time left takes what the battery leaves.
        let share: CGFloat = text == nil || tall ? 1 : 0.5
        let glyphHeight = max(min(WidgetMetrics.points(size.height, ratio: tall ? 0.3 : 0.5, min: 11, max: 34),
                                  (size.width - 8) * share / 2.35, size.height * (tall ? 0.5 : 0.8)), 9)
        let layout = tall ? AnyLayout(VStackLayout(alignment: .leading, spacing: Metrics.Spacing.small))
                          : AnyLayout(HStackLayout(spacing: Metrics.Spacing.medium))
        return layout {
            if widget.shows(.batteryGlyph) {
                BatteryGlyph(level: state.level, isCharging: state.isCharging, tint: state.tint,
                             showsPercentage: widget.shows(.percentage), height: glyphHeight)
                    .movableElement(.batteryGlyph, of: widget)
            } else if widget.shows(.percentage) {
                percentage(state, points: Self.percentPoints(inner: size))
            }
            if let text {
                time(text, short: Self.remaining(state, short: true), points: timeIsAlone ? Self.timeAlonePoints(inner: size) : Self.timePoints(inner: size))
            }
        }
        .frame(maxWidth: .infinity, alignment: tall ? .leading : .center)
    }

    /// The percentage; in the ring, the level alone ("76%") in the text's own colour.
    private func percentage(_ state: PowerState, points: CGFloat, inRing: Bool = false) -> some View {
        let text = inRing ? "\(min(max(state.level, 0), 100))%" : Self.percentText(state)
        let shown = widget.withOwnDesign(.rounded, for: .percentage)
        return WidgetLabel(id: .percentage, text: text, widget: shown, size: points, weight: .semibold, isSecondary: false) {
            Text(text)
                .font(.system(size: points, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(inRing ? AnyShapeStyle(.primary) : state.tint.style)
                .contentTransition(.opacity)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .movableElement(.percentage, of: widget)
    }

    /// The time left; `short` where it does not fit whole.
    private func time(_ text: String, short: String?, points: CGFloat) -> some View {
        WidgetLabel(id: .timeRemaining, text: text, widget: widget, size: points, weight: .regular, isSecondary: true) {
            ViewThatFits(in: .horizontal) {
                Text(text).fixedSize()
                Text(short ?? text).lineLimit(1).minimumScaleFactor(0.8)
            }
            .font(.system(size: points))
            .foregroundStyle(.secondary)
        }
        .movableElement(.timeRemaining, of: widget)
    }
}

/// The battery as a ring filled to the charge, its symbol (the Mac, or the bolt while charging)
/// and the percentage inside (the Batteries widget's look). Restyled in Customize, the inside is
/// the button its look makes — glass, a colour, a shape, its symbol as large and as far from the
/// middle as set — and the charge goes round its edge.
struct BatteryRing<Percentage: View>: View {
    let level: Int
    let isCharging: Bool
    let tint: StatusTint
    let diameter: CGFloat
    var look: ButtonLook = .plain
    /// The ring itself, drawn as a line is (`WidgetKindSpec.rings`).
    var ring: ProgressLook = .plain
    var showsPercentage = true
    @ViewBuilder let percentage: () -> Percentage

    var body: some View {
        let level = min(max(level, 0), 100)
        let line = max(3, diameter * 0.1)
        let symbol = isCharging ? "bolt.fill" : "laptopcomputer"
        let symbolPoints = BatteryWidget.ringSymbolPoints(diameter: diameter, showsPercentage: showsPercentage)
        ZStack {
            // Its line's middle on the ring's edge, as these rings have always been drawn.
            ProgressRing(fraction: Double(level) / 100, diameter: diameter + line, line: line, look: ring, automaticFill: tint.style)
                .frame(width: diameter, height: diameter)
            if look == .plain {
                VStack(spacing: 0) {
                    // Gives way to the percentage: the two share the ring's inside.
                    Image(systemName: symbol)
                        .font(.system(size: symbolPoints, weight: .semibold))
                        .foregroundStyle(isCharging ? tint.style : AnyShapeStyle(.secondary))
                    if showsPercentage { percentage() }
                }
                .padding(line * 1.4)
            } else {
                // The button inside the ring, as large as its inside at the look's own size.
                WidgetButtonLabel(look: look, symbol: symbol, points: look.material.hasShape
                                    ? (diameter - 2 * line) / 1.35 : symbolPoints)
                if showsPercentage {
                    percentage().offset(y: diameter * 0.2)
                }
            }
        }
        .frame(width: diameter, height: diameter)
        .animation(Motion.content, value: level)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Battery \(IslandFormat.percent(Double(level) / 100))"))
    }
}
