import SwiftUI

/// Fan Control: a dial round the fan. Its arc runs from the fans' slowest speed (bottom left) round
/// to their fastest (bottom right), filled as far as they run now, cool blue to hot red; ticks mark
/// each tenth. Turning it — dragging anywhere on it — holds the fans at that speed (Manual), the
/// knob where they are held; the fan in the middle is a button that gives them back to macOS (Auto,
/// its own curve, as from the factory). The speed and the mode sit inside the dial when it is about
/// square, beside it with the chip's temperature when it is wide.
///
/// Read every second while shown (`FanCenter`); a picture (the gallery, Customize) shows a sample.
/// Offered only on a Mac with a fan (MacBook Pro).
struct FanControlWidget: View {
    let widget: IslandWidget
    let size: CGSize

    @Environment(AppModel.self) private var model
    @Environment(\.isWidgetPreview) private var isPreview
    @Environment(\.widgetRenderMode) private var renderMode
    @Environment(\.locale) private var locale

    /// A MacBook Pro's fan turning at a quarter of its range, left to macOS, the chip at 46 °C.
    static let sample = [FanReading(index: 0, rpm: 2450, minimum: 1200, maximum: 5800, target: 0, isManual: false)]

    /// Wide: the speed and the mode beside the dial.
    static func isWide(_ inner: CGSize) -> Bool { inner.width >= inner.height * 1.7 }

    static func diameter(inner: CGSize) -> CGFloat { max(min(inner.width, inner.height), 24) }

    /// The speed's size: inside the dial, a share of it; beside it, of the widget's height.
    static func valuePoints(inner: CGSize) -> CGFloat {
        isWide(inner) ? WidgetMetrics.points(inner.height, ratio: 0.22, min: 12, max: 24)
            : WidgetMetrics.points(diameter(inner: inner), ratio: 0.13, min: 9, max: 20)
    }

    static func labelPoints(inner: CGSize) -> CGFloat {
        isWide(inner) ? WidgetMetrics.points(inner.height, ratio: 0.12, min: 9, max: 13)
            : WidgetMetrics.points(diameter(inner: inner), ratio: 0.075, min: 7, max: 12)
    }

    /// "2,450": the fans' average, to ten rpm.
    static func rpmText(_ fans: [FanReading], locale: Locale = .current) -> String {
        guard !fans.isEmpty else { return "—" }
        let rpm = fans.map(\.rpm).reduce(0, +) / Double(fans.count)
        return Int((rpm / 10).rounded() * 10).formatted(.number.locale(locale))
    }

    /// "2,450 rpm".
    static func valueText(_ fans: [FanReading], locale: Locale = .current) -> String {
        String(localized: "\(rpmText(fans, locale: locale)) rpm")
    }

    /// Auto or Manual; what is missing when the fans cannot be set.
    static func modeText(manual: Bool, access: FanCenter.Access) -> String {
        switch access {
        case .needsApproval: String(localized: "Allow in Login Items")
        case .failed: String(localized: "Unavailable")
        default: manual ? String(localized: "Manual") : String(localized: "Auto")
        }
    }

    var body: some View {
        let picture = isPreview || renderMode == .canvas
        let center = model.fans
        let fans = picture || center.fans.isEmpty ? Self.sample : center.fans
        let manual = !picture && center.isManual
        let held = picture ? nil : center.heldFraction
        let access = picture ? FanCenter.Access.unknown : center.access
        let chip = picture ? SystemReadings.sampleChip : model.thermals.chip
        let wide = Self.isWide(size)
        let diameter = Self.diameter(inner: size)
        let dial = FanDial(fans: fans, held: held, isManual: manual, diameter: diameter, showsTexts: !wide,
                           value: wide ? nil : valueLabel(fans), label: wide ? nil : modeLabel(manual: manual, access: access, chip: nil),
                           set: { center.setSpeed($0) }, automatic: { center.setAutomatic() },
                           onInteraction: { model.island.isInteracting = $0 })
            .frame(width: diameter, height: diameter)
            .movableElement(.fanDial, of: widget)
        Group {
            if wide {
                HStack(spacing: max(diameter * 0.12, 8)) {
                    dial
                    VStack(alignment: .leading, spacing: 2) {
                        valueLabel(fans)
                        modeLabel(manual: manual, access: access, chip: chip)
                    }
                    Spacer(minLength: 0)
                }
            } else {
                dial
            }
        }
        .frame(width: size.width, height: size.height)
        .whileShown {
            guard !picture else { return }
            withoutAnimation {
                center.startObserving()
                model.thermals.startObserving()
            }
        } stop: {
            guard !picture else { return }
            center.stopObserving()
            model.thermals.stopObserving()
        }
    }

    @ViewBuilder private func valueLabel(_ fans: [FanReading]) -> some View {
        if widget.shows(.value) {
            let points = Self.valuePoints(inner: size)
            let text = Self.valueText(fans, locale: locale)
            WidgetLabel(id: .value, text: text, widget: widget, size: points, weight: .semibold, isSecondary: false) {
                (Text(Self.rpmText(fans, locale: locale)).font(.system(size: points, weight: .semibold, design: .rounded).monospacedDigit())
                    + Text(" rpm").font(.system(size: points * 0.55, weight: .semibold)).foregroundStyle(.secondary))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    // A new reading each second: it just changes (a cross-fade a second smeared).
                    .transaction { $0.animation = nil }
            }
            .movableElement(.value, of: widget)
        }
    }

    @ViewBuilder private func modeLabel(manual: Bool, access: FanCenter.Access, chip: ChipReading?) -> some View {
        if widget.shows(.label) {
            let points = Self.labelPoints(inner: size)
            let mode = Self.modeText(manual: manual, access: access)
            let text = chip.map { "\(mode) · \(BatteryReadings.temperature($0.average, locale: locale))" } ?? mode
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

/// The dial: the track, its ticks, the arc of the speed, the knob where the fans are held, the fan
/// button in the middle and, when asked, the speed under it and the mode in the arc's opening.
struct FanDial<Value: View, Label: View>: View {
    let fans: [FanReading]
    /// Where the fans are held (0…1), while manual.
    let held: Double?
    let isManual: Bool
    let diameter: CGFloat
    let showsTexts: Bool
    let value: Value?
    let label: Label?
    let set: (Double) -> Void
    let automatic: () -> Void
    var onInteraction: (Bool) -> Void = { _ in }

    @State private var dragged: Double?
    @State private var taps = 0

    /// The arc opens at the bottom: from 135° (bottom left) round through the top to 405°.
    static var start: Double { 135 }
    static var sweep: Double { 270 }

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

    var body: some View {
        let line = max(diameter * 0.075, 3)
        let fan = fans.first
        let running = fan.map { $0.fraction(of: $0.rpm) } ?? 0
        let knob = dragged ?? held ?? running
        let button = diameter * (showsTexts ? 0.34 : 0.44)
        // The fan sits a little high when the speed goes under it.
        let lift = showsTexts && value != nil ? -diameter * 0.07 : 0
        ZStack {
            // The track, its ticks and the arc: dragged anywhere on the dial.
            ZStack {
                Circle().fill(.white.opacity(0.04))
                Circle()
                    .trim(from: 0, to: Self.sweep / 360)
                    .stroke(.white.opacity(0.12), style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .rotationEffect(.degrees(Self.start))
                FanTicks(start: Self.start, sweep: Self.sweep, count: 20)
                    .stroke(.white.opacity(0.28), style: StrokeStyle(lineWidth: max(line * 0.18, 0.75), lineCap: .round))
                    .padding(line * 1.15)
                Circle()
                    .trim(from: 0, to: Self.sweep / 360 * max(running, 0.004))
                    .stroke(FanTint.gradient, style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .rotationEffect(.degrees(Self.start))
                    .animation(.easeOut(duration: 0.6), value: running)
                // The knob: where the fans are held (filled), or where they run now (an outline to grab).
                FanKnob(isHeld: isManual || dragged != nil, color: FanTint.color(knob), size: line * 1.55)
                    .offset(Self.offset(of: knob, radius: (diameter - line) / 2))
                    .animation(dragged == nil ? .easeOut(duration: 0.3) : nil, value: knob)
            }
            .padding(line / 2)
            .contentShape(Circle())
            .gesture(drag)

            VStack(spacing: diameter * 0.015) {
                FanButton(isManual: isManual, color: FanTint.color(knob), diameter: button, taps: taps) {
                    taps += 1
                    if isManual { automatic() }
                }
                if showsTexts, let value { value.allowsHitTesting(false) }
            }
            .offset(y: showsTexts && value != nil ? diameter * 0.04 + lift : 0)

            if showsTexts, let label {
                label
                    .frame(maxWidth: diameter * 0.56)
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

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { drag in
                if dragged == nil { onInteraction(true) }
                let center = CGPoint(x: diameter / 2, y: diameter / 2)
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

    /// From the dial's middle to `fraction` along the arc.
    static func offset(of fraction: Double, radius: CGFloat) -> CGSize {
        let angle = (start + sweep * fraction) * .pi / 180
        return CGSize(width: cos(angle) * radius, height: sin(angle) * radius)
    }
}

/// The fan in the dial's middle: a button that gives the fans back to macOS. Lit in the speed's
/// colour while they are held, grey while macOS runs them.
private struct FanButton: View {
    let isManual: Bool
    let color: Color
    let diameter: CGFloat
    let taps: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(isManual ? AnyShapeStyle(color.opacity(0.22)) : AnyShapeStyle(.white.opacity(0.08)))
                Circle().strokeBorder(isManual ? AnyShapeStyle(color.opacity(0.7)) : AnyShapeStyle(.white.opacity(0.14)),
                                      lineWidth: max(diameter * 0.03, 1))
                Image(systemName: "fan.fill")
                    .font(.system(size: diameter * 0.52, weight: .semibold))
                    .foregroundStyle(isManual ? AnyShapeStyle(color) : AnyShapeStyle(.primary))
                    .symbolEffect(.bounce, value: taps)
                // "A": macOS's own curve.
                if !isManual {
                    Text("A")
                        .font(.system(size: diameter * 0.2, weight: .heavy, design: .rounded))
                        .foregroundStyle(.black)
                        .frame(width: diameter * 0.3, height: diameter * 0.3)
                        .background(Circle().fill(.green))
                        .offset(x: diameter * 0.34, y: diameter * 0.34)
                }
            }
            .frame(width: diameter, height: diameter)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(isManual ? "Back to Automatic" : "Automatic")
        .accessibilityLabel(Text(isManual ? "Back to Automatic" : "Automatic"))
    }
}

/// Where the fans are held: a dot in the speed's colour with a white rim; while macOS runs them, a
/// white outline where they are.
private struct FanKnob: View {
    let isHeld: Bool
    let color: Color
    let size: CGFloat

    var body: some View {
        ZStack {
            if isHeld {
                Circle().fill(color)
                Circle().strokeBorder(.white, lineWidth: max(size * 0.16, 1))
            } else {
                Circle().strokeBorder(.white.opacity(0.85), lineWidth: max(size * 0.14, 1))
            }
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.35), radius: size * 0.15)
    }
}

/// `count` ticks along the arc, every fifth longer.
private nonisolated struct FanTicks: Shape {
    let start: Double
    let sweep: Double
    let count: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = min(rect.width, rect.height) / 2
        for tick in 0...count {
            let angle = (start + sweep * Double(tick) / Double(count)) * .pi / 180
            let inner = radius * (tick % 5 == 0 ? 0.86 : 0.92)
            path.move(to: CGPoint(x: rect.midX + cos(angle) * inner, y: rect.midY + sin(angle) * inner))
            path.addLine(to: CGPoint(x: rect.midX + cos(angle) * radius, y: rect.midY + sin(angle) * radius))
        }
        return path
    }
}

/// The speed's colours, slowest to fastest: blue, cyan, green, yellow, orange, red.
private enum FanTint {
    static let stops: [(Double, Color)] = [
        (0, Color(red: 0.25, green: 0.55, blue: 1.0)), (0.25, Color(red: 0.2, green: 0.82, blue: 0.95)),
        (0.5, Color(red: 0.35, green: 0.9, blue: 0.45)), (0.7, Color(red: 1.0, green: 0.82, blue: 0.25)),
        (0.85, Color(red: 1.0, green: 0.55, blue: 0.15)), (1, Color(red: 1.0, green: 0.27, blue: 0.25)),
    ]

    /// Round the unrotated circle's first 270° (the arc is turned into place after).
    /// The round caps reach past both ends: red stays red after it, blue is blue before it.
    static let gradient = AngularGradient(stops: stops.map { Gradient.Stop(color: $0.1, location: $0.0 * 0.75) }
                                              + [.init(color: stops[stops.count - 1].1, location: 0.875),
                                                 .init(color: stops[0].1, location: 0.876), .init(color: stops[0].1, location: 1)],
                                          center: .center, startAngle: .zero, endAngle: .degrees(360))

    static func color(_ fraction: Double) -> Color {
        stops.last { $0.0 <= fraction }?.1 ?? stops[0].1
    }
}
