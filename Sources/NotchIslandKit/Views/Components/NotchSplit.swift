import SwiftUI

/// Horizontal geometry of a band that straddles the physical notch: leading ear | notch gap |
/// trailing ear.
///
/// The camera housing has no pixels, so anything laid out across it is simply cut in half. Every
/// row in the notch's height (the compact pill, a banner's header, the expanded header) is built
/// from this split so that nothing can land in the gap. The island is always centred on the notch
/// (`IslandLayout.islandRect`), which is what makes a symmetric split correct.
nonisolated struct NotchSplit: Sendable, Equatable {
    /// Full island frame width, shoulders included.
    let islandWidth: CGFloat
    let notchWidth: CGFloat
    /// Width of each concave shoulder; the body starts this far in from the frame edge.
    let shoulder: CGFloat
    /// Inset of the ear content from the body edge (clears the round bottom corners).
    let outerInset: CGFloat
    /// Space kept free either side of the notch.
    let clearance: CGFloat

    /// Distance from the frame edge to the start of ear content — also the horizontal inset for any
    /// full-width row below the band, so rows and ears share one leading edge.
    var contentInset: CGFloat { max(shoulder, 0) + outerInset }

    /// Width available to each ear's content.
    var earWidth: CGFloat {
        max(0, Metrics.earWidth(islandWidth: islandWidth, notchWidth: notchWidth, shoulder: shoulder)
            - outerInset - clearance)
    }

    /// The reserved middle: the notch plus clearance on both sides.
    var gapWidth: CGFloat { notchWidth + 2 * clearance }

    /// Ear frames in island-local coordinates (origin top-leading), for tests and hit reasoning.
    var leadingEar: ClosedRange<CGFloat> { contentInset...(contentInset + earWidth) }
    var trailingEar: ClosedRange<CGFloat> { (islandWidth - contentInset - earWidth)...(islandWidth - contentInset) }
    var notchGap: ClosedRange<CGFloat> { ((islandWidth - notchWidth) / 2)...((islandWidth + notchWidth) / 2) }
}

extension NotchSplit {
    init(layout: IslandLayout, presentation: IslandPresentation, outerInset: CGFloat, clearance: CGFloat) {
        self.init(
            islandWidth: layout.size(for: presentation).width,
            notchWidth: layout.notch.width,
            shoulder: layout.shoulderRadius(for: presentation),
            outerInset: outerInset,
            clearance: clearance
        )
    }
}

/// Lays out two ears around the notch gap. The gap is empty space, never a view that draws.
///
/// Each ear is a fixed clear frame with its content overlaid, so an ear with nothing to show (a
/// banner without a trailing value) still holds its width. A bare frame around empty content
/// collapses, the band re-centres, and the other ear slides towards the notch.
struct NotchSplitBand<Leading: View, Trailing: View>: View {
    let split: NotchSplit
    let height: CGFloat
    var leadingAlignment: Alignment = .leading
    var trailingAlignment: Alignment = .trailing
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: split.earWidth, height: height)
                .overlay(alignment: leadingAlignment) { leading }
            Spacer(minLength: 0)
                .frame(width: split.gapWidth)
            Color.clear
                .frame(width: split.earWidth, height: height)
                .overlay(alignment: trailingAlignment) { trailing }
        }
        .padding(.horizontal, split.contentInset)
        .frame(width: split.islandWidth, height: height)
    }
}
