import SwiftUI

/// The battery the way the Mac's menu bar draws it with the percentage on: a white body filled to
/// the charge, the number cut out of it, and the terminal nub. No bolt: charging shows only as the
/// body staying white (it turns yellow in Low Power Mode and red when low) and in the
/// accessibility value.
///
/// Sized by `height` (the body's height); everything else follows from it.
struct BatteryGlyph: View {
    let level: Int
    let isCharging: Bool
    let tint: StatusTint
    var showsPercentage = true
    var height: CGFloat = 13

    var body: some View {
        let level = min(max(level, 0), 100)
        let width = (height * 2.2).rounded()
        let radius = height * 0.3
        let fill: AnyShapeStyle = tint == .charging ? AnyShapeStyle(.white) : tint.style
        let empty = AnyShapeStyle(.white.opacity(0.35))
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
            .font(.system(size: height * 0.9, weight: .semibold).monospacedDigit())
            .tracking(-height * 0.02)
            .fontWidth(width)
            .lineLimit(1)
            .contentTransition(.opacity)
    }
}
