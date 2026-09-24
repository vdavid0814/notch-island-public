import SwiftUI

/// An empty state sized for the island: symbol, title, one line of help.
///
/// `ContentUnavailableView` is built for window-sized areas; in the island's ~130-pt page it drops
/// its symbol and pins the title to the top. This is the same composition — hierarchical symbol,
/// headline, secondary message — at a scale that fits.
struct IslandEmptyState: View {
    let title: LocalizedStringKey
    let systemImage: String
    let message: LocalizedStringKey

    var body: some View {
        VStack(spacing: Metrics.Spacing.xSmall) {
            Image(systemName: systemImage)
                .font(.title)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .padding(.bottom, Metrics.Spacing.xSmall)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
