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
    /// Kept closed for the next open (`IslandContentStack.keptPage`): the other pages are let go.
    @Environment(\.isIslandPanelHidden) private var isPanelHidden
    /// The pages built so far, kept while the panel is open: a switch only shows one and hides the
    /// other. Built at the switch, the new page was one 45–60 ms turn of the main thread (every
    /// widget of it), the first 5–7 frames of its slide lost at 120 Hz (measured with `NI_TRACE`).
    @State private var built: [ExpandedPage] = []
    @State private var visibility = PageVisibility()
    /// Pages switched away from that fade out where they are; the others wait at their side.
    @State private var leaving: Set<ExpandedPage> = []
    /// The page last switched to (still the old one in the switch's first update).
    @State private var shownPage: ExpandedPage?

    var body: some View {
        let layout = model.layout
        let presentation = IslandPresentation.expanded(page)
        let split = NotchSplit(
            layout: layout,
            presentation: presentation,
            outerInset: Metrics.Expanded.horizontalInset,
            clearance: Metrics.notchClearance
        )
        let scale = layout.factor
        let pages = built.contains(page) ? built : built + [page]
        let order = model.pickerPages
        let left = shownPage.map { $0 == page ? leaving : leaving.union([$0]) } ?? leaving
        // Its own curve: the new page glides into place rather than blinking in (Reduce Motion: a
        // cross-fade).
        let animation = reduceMotion ? Animation.easeOut(duration: 0.18) : PageSlide.animation

        VStack(spacing: 0) {
            ExpandedHeader(split: split, height: layout.notch.height)
                .opacity(model.isPictureScene && !model.pictureShowsWidgets ? 0 : 1)
            ZStack(alignment: .top) {
                ForEach(pages, id: \.self) { kept in
                    let isShown = kept == page
                    // As the header's picker lists the pages, a hidden one waits on its side of the
                    // shown one and comes in from there. Only the page coming in moves: a moving
                    // page is drawn again in every frame, its glass too (moving both cost half
                    // again as much, measured), so the one left fades out where it is.
                    let offset = isShown || left.contains(kept) || reduceMotion ? 0
                        : Self.side(of: kept, from: page, in: order) * PageSlide.distance * scale
                    pageView(kept, scale: scale)
                        .environment(\.panelPageShown, visibility.object(for: kept, shown: isShown))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .offset(x: offset)
                        // A hidden page goes to its side at once.
                        .animation(isShown ? animation : nil, value: offset)
                        // Hidden, it is only transparent: views at opacity 0 take no clicks or hover.
                        .opacity(isShown ? 1 : 0)
                        .animation(animation, value: isShown)
                }
            }
            // Photographed for Settings' pictures: the island alone, nothing on it.
            .opacity(model.isPictureScene && !model.pictureShowsWidgets ? 0 : 1)
            .padding(.top, Metrics.Expanded.pageTopInset)
            .padding(.bottom, Metrics.Expanded.pageBottomInset)
            .padding(.horizontal, split.contentInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .controlSize(Metrics.controlSize(forScale: scale))
        .onChange(of: page, initial: true) { old, new in
            if old != new { leaving.insert(old) }
            leaving.remove(new)
            shownPage = new
            if !built.contains(new) { built.append(new) }
            visibility.show(new)
        }
        // Once the switch has settled, the pages left wait at their side again.
        .task(id: page) {
            try? await Task.sleep(for: .seconds(0.3))
            guard !Task.isCancelled, !leaving.isEmpty else { return }
            withoutAnimation { leaving.removeAll() }
        }
        .task(id: isPanelHidden) { await isPanelHidden ? letOthersGo() : buildOthers() }
    }

    /// The panel's other pages built, hidden, once it has opened and settled: one a turn, each in a
    /// turn of its own on the efficiency cores (`MainThrift.lowPowerTurn`), so that the first switch
    /// to any of them only shows it.
    private func buildOthers() async {
        try? await Task.sleep(for: .seconds(0.8))
        for other in model.pickerPages where !built.contains(other) {
            guard !Task.isCancelled, !isPanelHidden else { return }
            MainThrift.lowPowerTurn {
                guard !isPanelHidden, !built.contains(other) else { return }
                withoutAnimation { built.append(other) }
            }
            try? await Task.sleep(for: .seconds(0.15))
        }
    }

    /// Kept hidden for the next open, the panel keeps only its page: hidden, every page is part of
    /// every other update the island makes (`IslandContentStack.keepDuration`).
    private func letOthersGo() async {
        try? await Task.sleep(for: .seconds(1))
        guard !Task.isCancelled, built != [page] else { return }
        MainThrift.lowPowerTurn {
            guard isPanelHidden else { return }
            withoutAnimation {
                built = [page]
                leaving.removeAll()
            }
            visibility.keep(only: page)
        }
    }

    /// +1: `page` waits on the trailing side of `shown` (after it in the header's order), -1: the leading.
    private static func side(of page: ExpandedPage, from shown: ExpandedPage, in order: [ExpandedPage]) -> CGFloat {
        (order.firstIndex(of: page) ?? 0) >= (order.firstIndex(of: shown) ?? 0) ? 1 : -1
    }

    @ViewBuilder private func pageView(_ page: ExpandedPage, scale: CGFloat) -> some View {
        switch page {
        case .shelf: ShelfPage(scale: scale, thumbnails: thumbnails)
        case .whatsNew: WhatsNewPage(scale: scale)
        // Home, the timer's, the battery's and the user's: each a board of widgets.
        default: HomePage(page: page).environment(\.shelfThumbnails, thumbnails)
        }
    }
}

/// Each built page's `PanelPageShown`, made with the page and kept with it.
private final class PageVisibility {
    private var objects: [ExpandedPage: PanelPageShown] = [:]

    func object(for page: ExpandedPage, shown: Bool) -> PanelPageShown {
        if let object = objects[page] { return object }
        let object = PanelPageShown(shown)
        objects[page] = object
        return object
    }

    func show(_ page: ExpandedPage) {
        for (each, object) in objects where object.isShown != (each == page) { object.isShown = each == page }
    }

    func keep(only page: ExpandedPage) {
        objects = objects.filter { $0.key == page }
    }
}

/// How a page of the panel comes in: it slides a short way in from its side of the header's order
/// as it fades in, the one left fades out where it is. No blur of either page (the island's content
/// swap blurs both every frame).
enum PageSlide {
    /// How far the new page travels, at the island's scale 1.
    static let distance: CGFloat = 22
    /// Quick out of the start, long and soft into place, about as short as the cross-fade it
    /// replaces (SwiftUI draws each of its frames on the main thread).
    static let animation = Animation.timingCurve(0.25, 0.8, 0.25, 1, duration: 0.24)
}
