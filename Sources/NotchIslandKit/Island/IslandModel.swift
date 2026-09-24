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

    /// Called synchronously before `presentation` changes (the window controller grows the stage here).
    @ObservationIgnored var willTransition: ((_ from: IslandPresentation, _ to: IslandPresentation) -> Void)?
    /// Called right after `presentation` changed (the window controller arms the settle here).
    @ObservationIgnored var didTransition: ((_ from: IslandPresentation, _ to: IslandPresentation) -> Void)?

    /// While true, a transition's hooks are running; see `apply`.
    @ObservationIgnored private var isApplying = false
    /// The latest request made from inside a transition's hooks.
    @ObservationIgnored private var deferred: (presentation: IslandPresentation, animation: Animation?)?

    /// No-op if equal. A request made from inside a transition (a hook that ends up here again) is
    /// not nested into it: it runs on the next main-actor turn, latest request winning, so every
    /// transition's hooks stay strictly bracketed and a window re-stage never happens in the middle
    /// of another one, or inside the display pass a hook may have triggered.
    func apply(_ next: IslandPresentation, animation: Animation?) {
        guard !isApplying else {
            let isFirst = deferred == nil
            deferred = (next, animation)
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
        withAnimation(animation) {
            presentation = next
        }
        didTransition?(from, next)
    }

    private func applyDeferred() {
        guard let deferred else { return }
        apply(deferred.presentation, animation: deferred.animation)
    }

    func setHovering(_ hovering: Bool) {
        guard hovering != isHovering else { return }
        isHovering = hovering
    }
}
