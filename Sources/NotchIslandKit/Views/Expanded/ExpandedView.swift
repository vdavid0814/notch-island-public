import SwiftUI

/// The full panel: a header band in the notch's height, then the page.
///
/// The header is shared by every page and stays put; only the page area swaps when the page
/// changes, so switching pages never flickers the controls the pointer is on.
struct ExpandedView: View {
    let page: ExpandedPage
    let thumbnails: ThumbnailCache

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let layout = model.layout
        let presentation = IslandPresentation.expanded(page)
        let split = NotchSplit(
            layout: layout,
            presentation: presentation,
            outerInset: Metrics.Expanded.horizontalInset,
            clearance: Metrics.notchClearance
        )
        let scale = layout.scale.factor
        // As the island's own content swaps (`IslandRootView`): on battery, or when the system asks
        // for less work, a plain cross-fade — the blur-replace blurs both pages every frame.
        let lightSwap = model.activity.prefersReducedWork || model.power.isOnBattery

        VStack(spacing: 0) {
            ExpandedHeader(split: split, height: layout.notch.height)
            ZStack(alignment: .top) {
                pageView(scale: scale)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .id(page)
                    .transition(.islandContent(reduceMotion: reduceMotion || lightSwap))
            }
            .padding(.top, Metrics.Expanded.pageTopInset)
            .padding(.bottom, Metrics.Expanded.pageBottomInset)
            .padding(.horizontal, split.contentInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .controlSize(Metrics.controlSize(forScale: scale))
    }

    @ViewBuilder private func pageView(scale: CGFloat) -> some View {
        switch page {
        case .home: HomePage(thumbnails: thumbnails)
        case .shelf: ShelfPage(scale: scale, thumbnails: thumbnails)
        case .timer: TimerPage()
        case .battery: BatteryPage()
        }
    }
}
