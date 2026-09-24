import SwiftUI

/// The countdown reached zero. Stays until acknowledged (BannerCenter gives up after 30 s).
struct TimerDoneBanner: View {
    @Environment(AppModel.self) private var model
    /// Flipped once on appear to ring the bell: a finite bounce, not an indefinite effect.
    @State private var ring = false

    var body: some View {
        BannerLayout(kind: .timerFinished) {
            Image(systemName: "bell.fill")
                .foregroundStyle(.tint)
                .symbolEffect(.bounce, options: .repeat(3), value: ring)
                .accessibilityHidden(true)
        } headerTrailing: {
            Text(IslandFormat.clock(0))
                .foregroundStyle(.secondary)
        } row: {
            Text("Timer Finished")
                .font(.headline)
                .lineLimit(1)
            Spacer(minLength: Metrics.Spacing.medium)
            Button("+1 min") {
                model.timers.add(seconds: 60)
                model.banners.dismiss(.timerFinished)
            }
            .islandButton()
            Button("Done") {
                model.timers.acknowledge()
                model.banners.dismiss(.timerFinished)
            }
            .islandButton(prominent: true)
        }
        .onAppear { ring.toggle() }
    }
}
