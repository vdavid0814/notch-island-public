import SwiftUI

/// Charger connected / removed, fully charged, low battery. The event says why the banner is up;
/// the live `PowerState` supplies the numbers, so the copy stays true if the state moves on.
struct PowerBanner: View {
    let event: PowerEvent

    @Environment(AppModel.self) private var model

    var body: some View {
        let state = model.power.state
        let copy = PowerCopy(event: event, state: state)
        BannerLayout(kind: .power(event)) {
            Image(systemName: copy.systemImage)
                // Hierarchical keeps the outline quieter than the charge; an empty low battery has
                // no charge to show, so it is drawn solid to read as red.
                .symbolRenderingMode(copy.tint == .low ? .monochrome : .hierarchical)
                .foregroundStyle(copy.tint.style)
                .contentTransition(.symbolEffect(.replace))
                .accessibilityHidden(true)
        } headerTrailing: {
            if state.hasBattery {
                Text(IslandFormat.percent(Double(state.level) / 100))
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
                    .animation(Motion.content, value: state.level)
            }
        } row: {
            Text(copy.title)
                .font(.headline)
                .lineLimit(1)
            Spacer(minLength: Metrics.Spacing.medium)
            if !copy.detail.isEmpty {
                Text(copy.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
