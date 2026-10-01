import SwiftUI

/// The battery the way the Mac's menu bar draws it with the percentage on: a white body filled to
/// the charge, the number cut out of it, and the terminal nub. No bolt: charging shows only as the
/// body staying white (it turns yellow in Low Power Mode and red when low) and in the
/// accessibility value.
///
/// Sized by `height` (the body's height); everything else follows from it, so the same glyph works
/// in the header band and large in a widget.
struct BatteryGlyph: View {
    let level: Int
    let isCharging: Bool
    let tint: StatusTint
    var showsPercentage = true
    var height: CGFloat = 13
    /// A widget's own colours for the charge and the empty body (its style's), and the type of the
    /// percentage cut out of it (the style's design, weight, italic).
    var fillColor: Color? = nil
    var bodyColor: Color? = nil
    var numberType: TypeSpec? = nil

    var body: some View {
        let level = min(max(level, 0), 100)
        let width = (height * 2.2).rounded()
        let radius = height * 0.3
        let fill: AnyShapeStyle = fillColor.map { AnyShapeStyle($0) } ?? (tint == .charging ? AnyShapeStyle(.white) : tint.style)
        let empty: AnyShapeStyle = bodyColor.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.white.opacity(0.35))
        HStack(spacing: height * 0.1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(empty)
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(fill)
                    .frame(width: max(level == 0 ? 0 : height * 0.35, width * CGFloat(level) / 100))
                // Cut out of the body, so it reads dark on the fill and on the empty part alike.
                // One type size at every level; "100" narrows its digits if it has to rather than
                // shrink or truncate.
                if showsPercentage {
                    ViewThatFits(in: .horizontal) {
                        number(level, width: .standard)
                        number(level, width: .condensed)
                        number(level, width: .compressed)
                        number(level, width: .compressed).minimumScaleFactor(0.5)
                    }
                    .frame(width: width - height * 0.24)
                    .frame(maxWidth: .infinity)
                    .blendMode(.destinationOut)
                }
            }
            .frame(width: width, height: height)
            .clipShape(.rect(cornerRadius: radius, style: .continuous))
            .compositingGroup()
            UnevenRoundedRectangle(bottomTrailingRadius: height * 0.14, topTrailingRadius: height * 0.14)
                .fill(level >= 99 ? fill : empty)
                .frame(width: max(1.5, height * 0.12), height: height * 0.36)
        }
        .animation(Motion.content, value: level)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Battery \(IslandFormat.percent(Double(level) / 100))"))
        .accessibilityValue(isCharging ? Text("Charging") : Text(""))
    }

    /// The percentage at its natural size (never truncated), in the menu bar's semibold.
    private func number(_ level: Int, width: Font.Width) -> some View {
        Text("\(level)")
            .font(numberType.map { WidgetTypography.font($0.at(height * 0.9)) } ?? .system(size: height * 0.9, weight: .semibold).monospacedDigit())
            .tracking(-height * 0.02)
            .fontWidth(width)
            .lineLimit(1)
            .contentTransition(.opacity)
    }
}

/// The battery as a ring filled to the charge, the percentage in the middle (the Batteries
/// widget's look).
struct BatteryRing: View {
    let level: Int
    let isCharging: Bool
    let tint: StatusTint
    var showsPercentage = true
    let diameter: CGFloat
    /// The percentage's own size (the widget's Percentage element).
    var percentSize: ElementSize = .medium

    var body: some View {
        let level = min(max(level, 0), 100)
        let line = max(3, diameter * 0.1)
        let points = WidgetType.ringText("100%", diameter: diameter, ratio: 0.22, percentSize)
        ZStack {
            Circle().stroke(.white.opacity(0.16), lineWidth: line)
            Circle()
                .trim(from: 0, to: CGFloat(level) / 100)
                .stroke(tint.style, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Image(systemName: isCharging ? "bolt.fill" : "laptopcomputer")
                    // Gives way to a large percentage: the two share the ring's inside.
                    .font(.system(size: showsPercentage ? min(diameter * 0.2, max(6, diameter * 0.46 - points)) : diameter * 0.34,
                                  weight: .semibold))
                    .foregroundStyle(isCharging ? tint.style : AnyShapeStyle(.secondary))
                if showsPercentage {
                    Text("\(level)%")
                        .font(.system(size: points, weight: .semibold, design: .rounded).monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .contentTransition(.opacity)
                }
            }
            .padding(line * 1.4)
        }
        .frame(width: diameter, height: diameter)
        .animation(Motion.content, value: level)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Battery \(IslandFormat.percent(Double(level) / 100))"))
    }
}
