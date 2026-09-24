import SwiftUI

/// A transient notice that drops just below the notch.
struct BannerView: View {
    let kind: BannerKind

    var body: some View {
        switch kind {
        case .level(let level): LevelBanner(kind: level)
        case .levelPill(let level): LevelPill(kind: level)
        case .power(let event): PowerBanner(event: event)
        case .timerFinished: TimerDoneBanner()
        case .dropTarget: DropBanner()
        case .airPods(let info): AirPodsBanner(info: info)
        }
    }
}

/// Shared banner structure: a header band in the notch's height with the banner's identity in the
/// leading ear and a short value in the trailing ear, and one detail row below.
struct BannerLayout<HeaderLeading: View, HeaderTrailing: View, Row: View>: View {
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, split.contentInset)
            .padding(.bottom, Metrics.Banner.rowBottomInset)
        }
    }
}
