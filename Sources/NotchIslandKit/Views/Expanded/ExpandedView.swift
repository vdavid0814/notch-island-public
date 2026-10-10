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
    /// The page last switched to, and which way that switch went.
    @State private var shownPage: ExpandedPage?
    @State private var slidForward = true

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
        // As the header's picker lists the pages, the next one comes in from its side (Reduce
        // Motion: a cross-fade).
        let forward = page == shownPage ? slidForward : Self.isForward(from: shownPage ?? page, to: page, in: model.pickerPages)

        VStack(spacing: 0) {
            ExpandedHeader(split: split, height: layout.notch.height)
            ZStack(alignment: .top) {
                pageView(scale: scale)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .id(page)
                    .transition(reduceMotion ? .opacity : AnyTransition(PageSlide(distance: PageSlide.distance * scale)))
            }
            .environment(\.pageSlidesForward, forward)
            // Its own curve: the new page glides into place rather than blinking in.
            .animation(reduceMotion ? .easeOut(duration: 0.18) : PageSlide.animation, value: page)
            .padding(.top, Metrics.Expanded.pageTopInset)
            .padding(.bottom, Metrics.Expanded.pageBottomInset)
            .padding(.horizontal, split.contentInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .controlSize(Metrics.controlSize(forScale: scale))
        // Kept once the switch has happened, so the page coming in keeps its way.
        .onChange(of: page, initial: true) { old, new in
            slidForward = Self.isForward(from: old, to: new, in: model.pickerPages)
            shownPage = new
        }
    }

    private static func isForward(from old: ExpandedPage, to new: ExpandedPage, in order: [ExpandedPage]) -> Bool {
        (order.firstIndex(of: new) ?? 0) >= (order.firstIndex(of: old) ?? 0)
    }

    @ViewBuilder private func pageView(scale: CGFloat) -> some View {
        switch page {
        case .shelf: ShelfPage(scale: scale, thumbnails: thumbnails)
        case .whatsNew: WhatsNewPage(scale: scale)
        // Home, the timer's, the battery's and the user's: each a board of widgets.
        default: HomePage(page: page).environment(\.shelfThumbnails, thumbnails)
        }
    }
}

extension EnvironmentValues {
    /// The page switch goes forward in the header's order (the new page from the trailing side).
    @Entry var pageSlidesForward = true
}

/// A page of the panel coming in or going out: the new one slides a short way in from its side of
/// the header's order as it fades in, the one left fades out where it is. No blur of either page
/// (the island's content swap blurs both every frame), and only one page moves: a moving page is
/// drawn again in every frame, its glass too (moving both cost half again as much, measured).
struct PageSlide: Transition {
    /// How far the new page travels, at the island's scale 1.
    static let distance: CGFloat = 22
    /// Quick out of the start, long and soft into place, about as short as the cross-fade it
    /// replaces (SwiftUI draws each of its frames on the main thread).
    static let animation = Animation.timingCurve(0.25, 0.8, 0.25, 1, duration: 0.24)
    let distance: CGFloat

    func body(content: Content, phase: TransitionPhase) -> some View {
        content.modifier(PageSlideEffect(distance: distance, phase: phase))
    }
}

private struct PageSlideEffect: ViewModifier {
    let distance: CGFloat
    let phase: TransitionPhase
    @Environment(\.pageSlidesForward) private var forward

    func body(content: Content) -> some View {
        content
            .opacity(phase.isIdentity ? 1 : 0)
            .offset(x: phase == .willAppear ? (forward ? distance : -distance) : 0)
    }
}
