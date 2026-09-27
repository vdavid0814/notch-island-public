import SwiftUI

/// The island's observable UI state.
///
/// `presentation` changes only through `apply`, which brackets the change with
/// the window hooks: the stage must be grown *before* SwiftUI starts animating
/// towards a bigger island, or the first frames would be clipped.
@Observable final class IslandModel {
    private(set) var presentation: IslandPresentation = .idle
    var page: ExpandedPage = .home
    var isPinned: Bool = false
    private(set) var isHovering: Bool = false
    /// A slider drag or menu inside the island is in progress: never auto-close.
    var isInteracting: Bool = false
    /// A file drag is currently over the island.
    var isDropTargeted: Bool = false
    /// While the render server moves the island's outline (`IslandOutlineMotion`), the surface is
    /// drawn still, as this hold says; nil when the surface simply is `presentation`'s.
    private(set) var surfaceHold: SurfaceHold?

    /// Moves the outline on the render server; nil leaves every move to SwiftUI's transaction.
    @ObservationIgnored weak var outlineMover: (any IslandOutlineMover)?

    /// Called synchronously before `presentation` changes (the window controller grows the stage here).
    @ObservationIgnored var willTransition: ((_ from: IslandPresentation, _ to: IslandPresentation) -> Void)?
    /// Called right after `presentation` changed (the window controller arms the settle here).
    @ObservationIgnored var didTransition: ((_ from: IslandPresentation, _ to: IslandPresentation) -> Void)?

    /// Bumped a turn after each move on the render server; the island's root reads it, so a missed
    /// update of `presentation` is caught up then (see `apply`).
    private(set) var revision = 0
    /// While true, a transition's hooks are running; see `apply`.
    @ObservationIgnored private var isApplying = false
    /// The latest request made from inside a transition's hooks.
    @ObservationIgnored private var deferred: (presentation: IslandPresentation, animation: Animation?, spring: Spring?,
                                               surfaceFollows: Bool)?

    /// No-op if equal. A request made from inside a transition (a hook that ends up here again) is
    /// not nested into it: it runs on the next main-actor turn, latest request winning, so every
    /// transition's hooks stay strictly bracketed and a window re-stage never happens in the middle
    /// of another one, or inside the display pass a hook may have triggered.
    ///
    /// With a `spring` and an outline mover, the outline follows the spring on the render server and
    /// SwiftUI draws the surface once, still (`surfaceHold`), instead of every frame: the per-frame
    /// SwiftUI work was about half of an open's CPU (measured). Only the content's own short swap
    /// is animated here then (`Motion.contentSwap`).
    ///
    /// `surfaceFollows` (`Motion.surfaceFollowsOutline`): the surface rides `animation` instead,
    /// starting where a move on the render server has got to.
    func apply(_ next: IslandPresentation, animation: Animation?, spring: Spring? = nil, surfaceFollows: Bool = false) {
        guard !isApplying else {
            let isFirst = deferred == nil
            deferred = (next, animation, spring, surfaceFollows)
            Log.island.notice("deferred re-entrant transition to \(String(describing: next), privacy: .public)")
            if isFirst { Task { [weak self] in self?.applyDeferred() } }
            return
        }
        // A direct request is newer than anything deferred.
        deferred = nil
        guard next != presentation else { return }
        let from = presentation
        Log.island.info("transition \(String(describing: from), privacy: .public) → \(String(describing: next), privacy: .public)")
        isApplying = true
        defer { isApplying = false }
        willTransition?(from, next)
        if let spring, surfaceFollows {
            // A move on the render server stops where it is; the surface is drawn there, then
            // springs on from it with SwiftUI.
            if let live = outlineMover?.handOff(from: from, to: next, spring: spring) {
                withoutAnimation { surfaceHold = live }
            }
            withAnimation(animation) {
                surfaceHold = nil
                presentation = next
            }
        } else if let spring, let hold = outlineMover?.move(from: from, to: next, spring: spring) {
                withoutAnimation { surfaceHold = hold }
            withAnimation(Motion.contentSwap(from: from, to: next)) {
                presentation = next
            }
            // The new presentation once more, a turn later: SwiftUI now and then drew the island
            // between the hold and the presentation above (with the old content) and then missed
            // the presentation's change, and the old content stayed until the outline landed half a
            // second later (the panel's widgets on Settings' growing island; traced, v0.4.2 too).
            Task { @MainActor [weak self] in
                withAnimation(Motion.contentSwap(from: from, to: next)) { self?.revision &+= 1 }
            }
        } else {
            withAnimation(animation) {
                presentation = next
            }
        }
        didTransition?(from, next)
    }

    private func applyDeferred() {
        guard let deferred else { return }
        apply(deferred.presentation, animation: deferred.animation, spring: deferred.spring,
              surfaceFollows: deferred.surfaceFollows)
    }

    /// The outline has landed: the surface is drawn as `presentation`'s again.
    func releaseSurface(_ hold: SurfaceHold) {
        guard surfaceHold == hold else { return }
        withoutAnimation { surfaceHold = nil }
    }

    func setHovering(_ hovering: Bool) {
        guard hovering != isHovering else { return }
        isHovering = hovering
    }
}

/// How the island's surface is drawn while its outline moves on the render server: still, at an
/// outline that covers the whole move (the larger end, with the open's overshoot), in the style of
/// the presentation it belongs to.
nonisolated struct SurfaceHold: Equatable, Sendable {
    let id: Int
    let outline: IslandOutline
    /// Whose surface this is (its glass style): the one arriving, or the one leaving on a close.
    let presentation: IslandPresentation
}

/// Moves the island's drawn outline from one presentation to another along a spring, off the main
/// thread's frames (`IslandOutlineMotion`).
@MainActor protocol IslandOutlineMover: AnyObject {
    /// Starts the move and says how to draw the surface meanwhile; nil when the move is left to
    /// SwiftUI. Releases the hold (`IslandModel.releaseSurface`) once the outline has landed.
    func move(from: IslandPresentation, to: IslandPresentation, spring: Spring) -> SurfaceHold?

    /// The outline moves with SwiftUI this time (`Motion.surfaceFollowsOutline`): a move under way
    /// on the render server stops, and the hold returned is its outline at this moment, for SwiftUI
    /// to start from (nil when none was under way). The move is remembered, so one that follows it
    /// on the render server starts where it is.
    func handOff(from: IslandPresentation, to: IslandPresentation, spring: Spring) -> SurfaceHold?
}
