import SwiftUI

/// The island: one Liquid Glass silhouette hanging from the top edge of the screen.
///
/// Rules this view exists to keep:
/// * **One glass shape.** Every state is the same `IslandShape` in one `GlassEffectContainer`, so a
///   change of state is a single morph of one surface, never a cross-fade between two.
/// * **Nothing outside the shape.** The window server routes clicks by pixel alpha, so any stray
///   pixel around the island would swallow menu-bar clicks. Content is clipped to the silhouette,
///   including content that is mid-transition.
/// * **No glass at idle.** Glass samples its backdrop continuously; at idle the notch only needs an
///   invisible hover target.
/// * **Everything grows out of the notch.** The glass is inserted at the notch's own size and
///   springs out to its presentation's size; on the way back to idle it shrinks into the notch the
///   same way before it is removed (`NotchEmergence`).
/// * **Sizes come from `IslandLayout`, animation from the transaction.** `IslandModel.apply` sets
///   `presentation` inside `withAnimation(Motion…)`; frame, radii and the content swap all ride that
///   one transaction. No second animation is attached to the size here.
struct IslandRootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Lives as long as the island, so shelf thumbnails survive page switches.
    @State private var thumbnails = ThumbnailCache()

    init() {}

    var body: some View {
        ZStack(alignment: .top) {
            island
        }
        .environment(\.islandGlassStyle, model.effectiveGlassStyle)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
    }

    @ViewBuilder private var island: some View {
        let presentation = model.island.presentation
        let layout = model.layout
        if presentation.isIdle {
            // Alpha > 0 so the window server delivers hover to the notch; see `hitTargetOpacity`.
            IslandShape(
                bottomRadius: layout.bottomRadius(for: .idle),
                shoulderRadius: layout.shoulderRadius(for: .idle)
            )
            .fill(Color.primary.opacity(Metrics.hitTargetOpacity))
            .frame(width: layout.notch.width, height: layout.notch.height)
            .accessibilityHidden(true)
        } else {
            // One glass container for the island and every glass control on it. Both the emergence
            // and the outline clip sit outside it: a container animates the insertion of its own
            // shapes itself (it would swallow the emergence), and renders its glass past any clip
            // inside it (the rim would show).
            GlassEffectContainer {
                GlassIsland(
                    presentation: presentation,
                    layout: layout,
                    reduceMotion: reduceMotion,
                    // On battery the content swaps with a plain cross-fade: the blur-replace costs
                    // about a seventh of an open's main-thread time (measured).
                    lightContentSwap: model.activity.prefersReducedWork
                        || (model.power.state.hasBattery && !model.power.state.isPluggedIn),
                    reducesWork: model.activity.prefersReducedWork,
                    thumbnails: thumbnails
                )
            }
            .transition(NotchEmergence(layout: layout, presentation: presentation))
        }
    }
}

/// The visible island: content clipped to the silhouette, on one glass surface.
private struct GlassIsland: View {
    let presentation: IslandPresentation
    let layout: IslandLayout
    let reduceMotion: Bool
    /// Cross-fade the content instead of the blur-replace.
    let lightContentSwap: Bool
    /// Low Power Mode or thermal pressure: the growth is drawn without its animated blur, which is
    /// the most expensive part of it (an offscreen pass over the whole island every frame).
    let reducesWork: Bool
    let thumbnails: ThumbnailCache
    @Environment(\.islandEmergence) private var emergence
    @Environment(\.islandGlassStyle) private var chosenStyle
    /// Fade style only: the glass is switched off while the island is a black pill at the notch's
    /// height (it would be sampling a backdrop nobody can see); see `glassRetirement`.
    @State private var isGlassRetired: Bool?

    var body: some View {
        // Between the notch (0) and the presentation (1). The spring may carry it past 1, which is
        // the open's overshoot. The content keeps its own size and is revealed by the silhouette as
        // the glass grows, so it never reflows.
        let contentSize = layout.size(for: presentation)
        let notch = layout.size(for: .idle)
        let geometry = EmergingSilhouette(layout: layout, presentation: presentation, emergence: emergence)
        let retraction = geometry.retraction
        let bottomRadius = geometry.bottomRadius
        let shoulderRadius = geometry.shoulderRadius
        let reveal = min(max(emergence, 0), 1)
        // Settings is a large page: it grows in without the blur (an offscreen pass over the whole
        // page each frame) and on plain black. Live glass the size of the screen under it cost
        // ~40 MB while open and ~300 MB more at its peak (measured) for a surface its own window
        // colour hides; its faint see-through look comes from the system's window vibrancy
        // instead (`SettingsBackdrop`), which the window server draws.
        let isOpaquePage = presentation.isSettings
        // The AirPods card lies over macOS's own card to hide it: glass would let it show through.
        let coversSystemCard: Bool = if case .banner(.airPods) = presentation { AirPodsSystemCard.current == .cover } else { false }
        let glassStyle = isOpaquePage || coversSystemCard ? IslandGlassStyle.black : chosenStyle
        let blursGrowth = !(reduceMotion || reducesWork || isOpaquePage)
        let wantsGlass = glassStyle != .fade || contentSize.height > notch.height + 0.5
        let showsGlass = wantsGlass || isGlassRetired == false
        let silhouette = IslandShape(bottomRadius: bottomRadius, shoulderRadius: shoulderRadius, retraction: retraction)
        // The glass's outline, `overdraw` taller at the top (above the screen edge), and the surface
        // it is drawn on: larger by the style's rim inset, so the rim light on its edge lies outside
        // the outline and is clipped (see `IslandGlassStyle.rimInset`).
        let outline = IslandShape(bottomRadius: bottomRadius, shoulderRadius: shoulderRadius,
                                  topInset: IslandLayout.overdraw, retraction: retraction)
        let surface = outline.inset(by: -glassStyle.rimInset)

        ZStack(alignment: .top) {
            // Each content view is laid out at its own presentation's size, so while the frame
            // springs between two sizes neither the outgoing nor the incoming content reflows.
            IslandContent(presentation: presentation, thumbnails: thumbnails)
                .frame(width: contentSize.width, height: contentSize.height, alignment: .top)
                .id(presentation.surfaceKey)
                .transition(.islandContent(reduceMotion: reduceMotion || lightContentSwap || isOpaquePage))
        }
        .opacity(reveal)
        .blur(radius: blursGrowth ? 6 * (1 - reveal) : 0)
        // The island's panel never becomes key (it must not steal focus), so by default every
        // control in it would draw in the inactive, desaturated style of a background window.
        // Like Control Center, it is a surface the user operates directly: draw controls active.
        .environment(\.appearsActive, true)
        .frame(width: contentSize.width, height: contentSize.height, alignment: .top)
        .clipShape(silhouette)
        .containerShape(silhouette)
        // The glass extends `overdraw` above the window, where the window edge clips it, so its top
        // edge (and the rim light that comes with an edge) is never on screen.
        .padding(.top, IslandLayout.overdraw)
        .islandSurfaceShade(
            glassStyle,
            solidDepth: IslandLayout.overdraw + layout.notch.height,
            in: surface
        )
        // `rimInset` larger than the outline, so its rim falls outside the outline clip that
        // `EmergenceProgress` applies around the container.
        .islandGlass(in: surface, isEnabled: showsGlass)
        .environment(\.islandGlassStyle, glassStyle)
        .padding(.top, -IslandLayout.overdraw)
        .task(id: wantsGlass) { await glassRetirement(wantsGlass: wantsGlass) }

    }

    /// Glass comes back at once when the island grows past the notch (under the black band, so the
    /// switch is invisible). It goes only once a shrink into the pill has settled, never while a
    /// larger island is still animating down over it.
    private func glassRetirement(wantsGlass: Bool) async {
        if wantsGlass {
            isGlassRetired = false
            return
        }
        if isGlassRetired != nil {
            try? await Task.sleep(for: .seconds(Motion.settleDuration(for: Motion.durationRange.upperBound)))
            guard !Task.isCancelled else { return }
        }
        isGlassRetired = true
    }
}

/// The island's outline part-way out of the notch: `emergence` 0 is the notch, 1 the presentation
/// (past 1 during the open's overshoot). The frame keeps the content's size throughout; the
/// outline is drawn pulled in from it, top-centred on the notch (see `IslandShape.retraction`).
nonisolated struct EmergingSilhouette {
    let retraction: CGSize
    let bottomRadius: CGFloat
    let shoulderRadius: CGFloat

    init(layout: IslandLayout, presentation: IslandPresentation, emergence: Double) {
        let t = CGFloat(emergence)
        let content = layout.size(for: presentation)
        let notch = layout.size(for: .idle)
        retraction = CGSize(
            width: (content.width - notch.width) * (1 - t) / 2,
            height: (content.height - notch.height) * (1 - t)
        )
        bottomRadius = max(0, Self.mix(layout.bottomRadius(for: .idle), layout.bottomRadius(for: presentation), t))
        shoulderRadius = max(0, Self.mix(layout.shoulderRadius(for: .idle), layout.shoulderRadius(for: presentation), t))
    }

    /// The visible outline, in the island's frame.
    var shape: IslandShape {
        IslandShape(bottomRadius: bottomRadius, shoulderRadius: shoulderRadius, retraction: retraction)
    }

    static func mix(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
        a + (b - a) * t
    }
}

private struct IslandContent: View {
    let presentation: IslandPresentation
    let thumbnails: ThumbnailCache

    var body: some View {
        switch presentation {
        case .idle:
            Color.clear
        case .compact(let activity):
            CompactView(activity: activity)
        case .banner(let kind):
            BannerView(kind: kind)
        case .expanded(let page):
            ExpandedView(page: page, thumbnails: thumbnails)
        case .assistant:
            AssistantView()
        case .settings:
            IslandSettingsView()
        }
    }
}

extension IslandPresentation {
    /// Identity of the island's content for the swap transition. All expanded pages share one
    /// surface (the header stays put) and swap only their page area; everything else follows
    /// `contentKey`.
    nonisolated var surfaceKey: String {
        isExpanded ? "expanded" : contentKey
    }
}

/// Insertion and removal of the glass island: it starts as the notch and grows to its size, and
/// shrinks back into the notch when it goes.
///
/// A plain `.frame` change cannot do this: an inserted view has no previous layout to animate
/// from, so it would simply appear at full size. Instead the transition animates a progress value
/// (`islandEmergence`) with the transaction's spring, and `GlassIsland` sizes its glass from it.
nonisolated private struct NotchEmergence: Transition {
    let layout: IslandLayout
    let presentation: IslandPresentation

    func body(content: Content, phase: TransitionPhase) -> some View {
        content.modifier(EmergenceProgress(progress: phase.isIdentity ? 1 : 0, layout: layout, presentation: presentation))
    }
}

/// Animates the emergence, and clips the island (glass container included) to its outline at that
/// progress — outside the container, where a clip reaches the glass and cuts its rim.
nonisolated private struct EmergenceProgress: ViewModifier, Animatable {
    var progress: Double
    let layout: IslandLayout
    let presentation: IslandPresentation

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content
            .environment(\.islandEmergence, progress)
            .clipShape(EmergingSilhouette(layout: layout, presentation: presentation, emergence: progress).shape)
    }
}

extension EnvironmentValues {
    /// 0 while the glass island sits in the notch, 1 once it has grown to its presentation.
    @Entry var islandEmergence: Double = 1
}

extension AnyTransition {
    /// Content swaps inside the island: a blur-replace, or a plain cross-fade under Reduce Motion (and
    /// on battery, see `GlassIsland.lightContentSwap`).
    static func islandContent(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : AnyTransition(.blurReplace)
    }
}
