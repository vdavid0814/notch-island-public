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
///   `presentation` inside `withAnimation(Motion…)`; outline, radii and the content swap all ride
///   that one transaction. No second animation is attached to the size here.
/// * **Shapes move, frames do not.** The island is drawn on a canvas the size of its window, which
///   changes only when the window is re-staged (twice per transition). A morph animates the drawn
///   outline (`IslandSurface`), never a frame: a frame changing every frame re-laid the content out
///   and had the window server allocate new offscreen textures for the glass and the outline
///   mask at every size — ~100 MB per open, ~400 MB for Settings, freed a second later (measured).
struct IslandRootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Lives as long as the island, so shelf thumbnails survive page switches.
    @State private var thumbnails = ThumbnailCache()
    /// Fade style only: the glass is switched off while the island is a black pill at the notch's
    /// height (it would be sampling a backdrop nobody can see); see `glassRetirement`. nil for an
    /// island that has just emerged.
    @State private var isGlassRetired: Bool?

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
        // While the render server moves the outline, the surface is drawn still as the hold says,
        // and stays until the outline has landed, also in the notch (`IslandOutlineMotion`).
        let hold = model.island.surfaceHold
        let layout = model.layout
        if presentation.isIdle && hold == nil {
            // Alpha > 0 so the window server delivers hover to the notch; see `hitTargetOpacity`.
            IslandShape(
                bottomRadius: layout.bottomRadius(for: .idle),
                shoulderRadius: layout.shoulderRadius(for: .idle)
            )
            .fill(Color.primary.opacity(Metrics.hitTargetOpacity))
            .frame(width: layout.notch.width, height: layout.notch.height)
            .accessibilityHidden(true)
            .onAppear { isGlassRetired = nil }
        } else {
            let surfaceOf = hold?.presentation ?? presentation
            let outline = hold?.outline ?? layout.outline(for: presentation)
            // Settings is a large page: it grows in without the blur (an offscreen pass over the
            // whole page each frame) and on plain black. Live glass the size of the screen under it
            // cost ~40 MB while open and ~300 MB more at its peak (measured) for a surface its own
            // window colour hides; its faint see-through look comes from the system's window
            // vibrancy instead (`SettingsBackdrop`), which the window server draws.
            let isOpaquePage = surfaceOf.isSettings
            // The AirPods card lies over macOS's own card to hide it: glass would let it show through.
            let coversSystemCard: Bool = if case .banner(.airPods) = surfaceOf { AirPodsSystemCard.current == .cover } else { false }
            let glassStyle = isOpaquePage || coversSystemCard ? IslandGlassStyle.black : model.effectiveGlassStyle
            let wantsGlass = glassStyle != .fade || outline.size.height > layout.notch.height + 0.5
            let reducesWork = model.activity.prefersReducedWork
            // On battery the content swaps with a plain cross-fade: the blur-replace costs about a
            // seventh of an open's main-thread time (measured).
            let lightContentSwap = reducesWork || (model.power.state.hasBattery && !model.power.state.isPluggedIn)
            IslandContentStack(
                presentation: presentation,
                layout: layout,
                crossFades: reduceMotion || lightContentSwap || presentation.isSettings,
                thumbnails: thumbnails
            )
            .transition(IslandSurfaceTransition(surface: IslandSurface(
                size: outline.size,
                bottomRadius: outline.bottomRadius,
                shoulderRadius: outline.shoulderRadius,
                notch: IslandOutline(size: layout.notch, bottomRadius: layout.bottomRadius(for: .idle),
                                     shoulderRadius: layout.shoulderRadius(for: .idle)),
                glassStyle: glassStyle,
                showsGlass: wantsGlass || isGlassRetired == false,
                // Low Power Mode or thermal pressure: the growth is drawn without its animated blur,
                // the most expensive part of it (an offscreen pass over the whole island every frame).
                blursGrowth: !(reduceMotion || reducesWork || isOpaquePage),
                solidDepth: IslandLayout.overdraw + layout.notch.height,
                // Under Reduce Motion the island cross-fades as SwiftUI animates it; otherwise it
                // grows out of the notch on the render server. Between two open presentations the
                // surface follows its outline here (`Motion.surfaceFollowsOutline`).
                isStill: !reduceMotion
            )))
            .task(id: wantsGlass) { await glassRetirement(wantsGlass: wantsGlass) }
        }
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

/// What the island shows, at the presentation's own size, top-centred on the island's canvas (its
/// window). Nothing here changes while the island moves: the outline, glass and shade around it are
/// `IslandSurface`'s, so a morph never re-evaluates or re-lays out the content.
private struct IslandContentStack: View {
    let presentation: IslandPresentation
    let layout: IslandLayout
    /// Cross-fade the content instead of the blur-replace.
    let crossFades: Bool
    let thumbnails: ThumbnailCache

    /// The panel's last page, kept alive (hidden) while the island shows something else: opening
    /// the panel again only shows it, instead of building every view of the page (~25–40 ms in
    /// one burst, the largest part of an open's energy, measured).
    @State private var keptPage: ExpandedPage?
    /// How long a closed panel is kept for the next open.
    static let keepDuration: Duration = .seconds(10)

    var body: some View {
        let shownPage: ExpandedPage? = if case .expanded(let page) = presentation { page } else { nil }
        // On a canvas-sized base, as an overlay: the kept panel is larger than a small island's
        // window, and as the stack's own size it grew the root past the window, which then sat
        // the pill 67 pt above the screen for as long as the panel was kept (seen, measured).
        Color.clear.overlay(alignment: .top) { ZStack(alignment: .top) {
            if let page = shownPage ?? keptPage {
                let isShown = shownPage != nil
                // Hidden, it is only transparent: views at opacity 0 take no clicks or hover, and it
                // lies under whatever the island shows instead. (Moved out of the way, the timer's
                // lazy ruler was rebuilt at every open; switching hit testing or accessibility off
                // and on re-derived the whole page: ~15 ms per open each, measured.)
                content(for: .expanded(page))
                    // The panel's content leaves in a tenth of a second and the glass shrinks alone:
                    // riding the whole close spring, every frame re-rendered the content too.
                    .opacity(isShown ? 1 : 0)
                    .animation(isShown ? nil : .easeOut(duration: 0.1), value: isShown)
                    .environment(\.isIslandPanelHidden, !isShown)
            }
            if shownPage == nil {
                content(for: presentation)
                    .id(presentation.surfaceKey)
                    .transition(.islandContent(reduceMotion: crossFades))
            }
        } }
        .onChange(of: shownPage, initial: true) { _, page in if let page { keptPage = page } }
        // Kept only for a while: hidden, it is part of every other update the island makes (a
        // volume banner cost twice as much with it, measured). Quick re-opens are where it pays.
        .task(id: shownPage == nil ? keptPage : nil) {
            guard shownPage == nil, keptPage != nil else { return }
            try? await Task.sleep(for: Self.keepDuration, tolerance: .seconds(1))
            guard !Task.isCancelled else { return }
            withoutAnimation { keptPage = nil }
        }
        // The island's panel never becomes key (it must not steal focus), so by default every
        // control in it would draw in the inactive, desaturated style of a background window.
        // Like Control Center, it is a surface the user operates directly: draw controls active.
        .environment(\.appearsActive, true)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

extension IslandContentStack {
    /// One presentation's content at its own size, top-centred on the canvas.
    @ViewBuilder func content(for presentation: IslandPresentation) -> some View {
        let contentSize = layout.size(for: presentation)
        // Each content view is laid out at its own presentation's size, so while the outline
        // springs between two sizes neither the outgoing nor the incoming content reflows.
        IslandContent(presentation: presentation, thumbnails: thumbnails)
            .frame(width: contentSize.width, height: contentSize.height, alignment: .top)
            // Where the glass shows through, text and symbols keep a soft dark halo, so they
            // stay readable over a bright desktop without darkening the glass itself.
            .modifier(GlassLegibility())
            // Concentric corners inside (the artwork) follow the island they belong to.
            .containerShape(IslandShape(bottomRadius: layout.bottomRadius(for: presentation),
                                        shoulderRadius: layout.shoulderRadius(for: presentation)))
            // Every child fills the canvas, so the stack's size never changes: sized by its
            // children, it grew from the old content's size to the new one's with the spring,
            // and every frame re-laid out and re-placed the whole content inside it (measured:
            // most of an open's CPU) although nothing on screen moved.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            // The content takes its new size at once: grown or shrunk along the spring, it was
            // laid out again at every size (Siri's gallery reflowed its grid every frame). The
            // outline around it reveals or hides it; what swaps inside animates on its own.
            .transaction(value: contentSize) { $0.animation = nil }
    }
}

extension EnvironmentValues {
    /// The panel is kept alive but hidden (`IslandContentStack.keptPage`): whatever it would keep
    /// running on its own (clocks, monitors) waits until it is shown again.
    @Entry var isIslandPanelHidden = false
}

/// A faint dark halo around the island's content on see-through styles (none on solid black).
///
/// Just enough to lift white text off a bright spot behind the glass: at 0.55 / 2.5 pt it read as
/// a glow around every word and tile, so it is a whisper now — tight and light. The fade style's
/// black under the content does most of the work.
private struct GlassLegibility: ViewModifier {
    @Environment(\.islandGlassStyle) private var style

    static let opacity: Double = 0.18
    static let radius: CGFloat = 1.2

    func body(content: Content) -> some View {
        content.shadow(color: .black.opacity(style.hasGlassSurface ? Self.opacity : 0), radius: Self.radius)
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

/// The island's surface around its content: outline, shade, glass — and its motion.
///
/// Size and radii ride the transaction's spring (they are animatable data), and so does the
/// emergence: as a transition, the island is inserted at the notch (0) and grows to its
/// presentation (1), and shrinks back into the notch when it is removed. The spring may carry
/// either past its end, which is the open's overshoot. Everything that changes per frame is drawn
/// here, around the content, so the content itself never re-renders while the island moves.
///
/// One glass container holds the island and every glass control on it. The outline clip sits
/// outside it, and cuts the content with it: a container renders its glass past any clip inside
/// it (the rim would show), and a second clip on the content alone only cost per-frame work.
nonisolated private struct IslandSurfaceTransition: Transition {
    let surface: IslandSurface

    func body(content: Content, phase: TransitionPhase) -> some View {
        var surface = surface
        surface.emergence = phase.isIdentity || surface.isStill ? 1 : 0
        return content.modifier(surface)
    }
}

nonisolated private struct IslandSurface: ViewModifier, Animatable {
    var size: CGSize
    var bottomRadius: CGFloat
    var shoulderRadius: CGFloat
    /// The idle outline, where an emerging island starts.
    let notch: IslandOutline
    let glassStyle: IslandGlassStyle
    let showsGlass: Bool
    let blursGrowth: Bool
    /// The shade's solid black from the top (fade style).
    let solidDepth: CGFloat
    /// The island is inserted and removed at its presentation: the render server grows it out of the
    /// notch and back (`IslandOutlineMotion`).
    let isStill: Bool
    /// 0 in the notch, 1 at the presentation.
    var emergence: Double = 1

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<AnimatablePair<CGFloat, CGFloat>, Double>> {
        // Always the real values: a move on the render server changes them only in transactions
        // that animate nothing (`IslandModel.apply`), while one SwiftUI animates
        // (`Motion.surfaceFollowsOutline`) springs them frame by frame.
        get {
            AnimatablePair(AnimatablePair(size.width, size.height),
                           AnimatablePair(AnimatablePair(bottomRadius, shoulderRadius), emergence))
        }
        set {
            size = CGSize(width: newValue.first.first, height: newValue.first.second)
            bottomRadius = newValue.second.first.first
            shoulderRadius = newValue.second.first.second
            emergence = newValue.second.second
        }
    }

    func body(content: Content) -> some View {
        // The outline the presentations morph between, and the one drawn: pulled into the notch
        // while the island emerges.
        let frame = IslandOutline(size: size, bottomRadius: bottomRadius, shoulderRadius: shoulderRadius)
        let drawn = notch.mixed(with: frame, by: emergence)
        let reveal = min(max(emergence, 0), 1)
        // The glass's outline, `overdraw` taller at the top (above the screen edge), and the surface
        // it is drawn on: larger by the style's rim inset, so the rim light on its edge lies outside
        // the outline and is clipped (see `IslandGlassStyle.rimInset`).
        let surface = drawn.withTopInset(IslandLayout.overdraw).inset(by: -glassStyle.rimInset)
        // Fade: the glass is off whenever the outline, as drawn this frame, is no taller than the
        // notch band — the pill is all black there, and the glass would only add its edge light
        // around it. `showsGlass` alone held the glass for up to ~2.8 s after a shrink had landed
        // (`IslandRootView.glassRetirement` waits for the slowest spring), and the rim lit the
        // pill's edge all that time. Per frame, it goes the moment the outline reaches the band
        // on the way down and returns the moment it leaves it on the way up.
        let glassOn = showsGlass && (glassStyle != .fade || drawn.size.height > notch.size.height + 1)
        let parksGlass = isStill
        GlassEffectContainer {
            content
                .opacity(reveal)
                .blur(radius: blursGrowth ? 6 * (1 - reveal) : 0)
                // The glass extends `overdraw` above the window, where the window edge clips it, so
                // its top edge (and the rim light that comes with an edge) is never on screen.
                .padding(.top, IslandLayout.overdraw)
                .islandSurfaceShade(glassStyle, solidDepth: solidDepth,
                                    size: CGSize(width: size.width, height: size.height + IslandLayout.overdraw),
                                    in: surface.inset(by: -IslandGlassStyle.shadeBleed))
                // Off, the glass is parked out of sight rather than taken down (`IslandGlassBody`);
                // while SwiftUI animates the surface (Reduce Motion) it goes, as a parked glass
                // would slide along the transaction.
                .islandGlass(in: IslandGlassBody(outline: surface, isParked: !glassOn && parksGlass),
                             isEnabled: glassOn || parksGlass)
                .background {
                    // The shoulders beside the glass body, in the glass's smoke (`IslandGlassBody`).
                    IslandShoulders(outline: surface)
                        .fill(Color.black.opacity(glassOn && glassStyle.hasGlassSurface ? IslandGlassStyle.smokeOpacity : 0),
                              style: FillStyle(eoFill: true))
                }
                .environment(\.islandGlassStyle, glassStyle)
                .padding(.top, -IslandLayout.overdraw)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipShape(drawn)
    }
}


extension AnyTransition {
    /// Content swaps inside the island: a blur-replace, or a plain cross-fade under Reduce Motion (and
    /// on battery, see `IslandRootView`).
    static func islandContent(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : AnyTransition(.blurReplace)
    }
}
