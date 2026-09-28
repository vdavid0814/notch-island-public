import SwiftUI

/// A transient notice that drops just below the notch.
struct BannerView: View {
    let kind: BannerKind

    var body: some View {
        switch kind {
        case .level(let level): LevelBanner(kind: level)
        // Over macOS's own card: its lines, where it draws them.
        case .levelCovering(.volume): SystemVolumeCovering()
        case .levelCovering(let level): LevelBanner(kind: level, banner: .levelCovering(level))
        case .levelPill(let level): LevelPill(kind: level)
        case .power(let event): PowerBanner(event: event)
        case .timerFinished: TimerDoneBanner()
        case .dropTarget: DropBanner()
        case .airPods(let info):
            if AirPodsSystemCard.current == .cover { SystemAirPodsCovering(info: info) } else { AirPodsBanner(info: info) }
        }
    }
}

/// Shared banner structure: a header band in the notch's height with the banner's identity in the
/// leading ear and a short value in the trailing ear, and one detail row below.
struct BannerLayout<HeaderLeading: View, HeaderTrailing: View, Row: View>: View {
    /// Over macOS's volume card: the slider's bottom lies exactly where the fade starts to clear, so
    /// the whole row stays on solid black (asked for, v0.4.7).
    static func coveringRowBottom(layout: IslandLayout, kind: BannerKind) -> CGFloat {
        let size = layout.size(for: .banner(kind))
        let (start, _) = IslandFade.span(solidDepth: IslandLayout.overdraw + layout.notch.height,
                                         height: size.height + IslandLayout.overdraw,
                                         stretch: IslandFade.coveringStretch)
        return max(size.height - (start - IslandLayout.overdraw), 0)
    }

    let kind: BannerKind
    @ViewBuilder var headerLeading: HeaderLeading
    @ViewBuilder var headerTrailing: HeaderTrailing
    @ViewBuilder var row: Row

    @Environment(AppModel.self) private var model

    var body: some View {
        let layout = model.layout
        let split = NotchSplit(
            layout: layout,
            presentation: .banner(kind),
            outerInset: Metrics.Banner.horizontalInset,
            clearance: Metrics.notchClearance
        )
        VStack(spacing: 0) {
            NotchSplitBand(split: split, height: layout.notch.height) {
                headerLeading
                    .font(.system(size: layout.notch.height * 0.5, weight: .semibold))
                    .imageScale(.medium)
            } trailing: {
                headerTrailing
                    .font(.subheadline.weight(.semibold).monospacedDigit())
            }
            HStack(spacing: Metrics.Banner.rowSpacing) {
                row
            }
            // Over macOS's volume card the island is taller: the slider sits low in it, near the
            // bottom edge, not in the middle of the space.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: kind.isCovering ? .bottom : .center)
            .padding(.horizontal, split.contentInset)
            .padding(.bottom, kind.isCovering ? Self.coveringRowBottom(layout: layout, kind: kind) : Metrics.Banner.rowBottomInset)
        }
    }
}
