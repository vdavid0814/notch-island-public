import Foundation

/// Everything that decides what the island shows, as plain values.
///
/// The controller fills this from the stores; the resolver turns it into a
/// presentation. Keeping the decision a pure function of one value means the
/// priority order is readable in one place and testable without AppKit.
nonisolated struct IslandInputs: Sendable, Equatable {
    /// The playing video is in full screen: nothing shows by itself (no pill, no notice). What the
    /// user opens — pointer, click, file drag onto the notch — still opens.
    var isHidden: Bool = false
    /// The assistant (Siri in the notch) is open: it outranks everything, including hiding.
    var wantsAssistant: Bool = false
    /// How much of the assistant shows (see `AssistantRoom`).
    var assistantRoom: AssistantRoom = .field
    var wantsExpanded: Bool = false
    var page: ExpandedPage = .home
    var banner: BannerKind? = nil
    var isDragInProgress: Bool = false
    /// Running, paused, or finished-but-unacknowledged.
    var countdownActive: Bool = false
    /// Running, or paused with time on the clock.
    var stopwatchActive: Bool = false
    /// `MediaController.isActive`, already gated by the Now Playing preference.
    var nowPlayingActive: Bool = false
}

nonisolated enum IslandResolver {
    /// Highest priority wins. What the user asked for beats what the system
    /// wants to say; a drag in flight beats a notice, because the drop banner
    /// is only useful while the drag lasts; ongoing activities come last since
    /// they are always there to fall back to.
    static func resolve(_ i: IslandInputs) -> IslandPresentation {
        if i.wantsAssistant { return .assistant(i.assistantRoom) }
        if i.wantsExpanded { return .expanded(i.page) }
        if i.isHidden {
            // Only the direct answer to something the user just did gets through.
            if let banner = i.banner, banner.showsWhileHidden { return .banner(banner) }
            return .idle
        }
        if i.isDragInProgress { return .banner(.dropTarget) }
        if let banner = i.banner { return .banner(banner) }
        if i.countdownActive { return .compact(.timer) }
        if i.stopwatchActive { return .compact(.stopwatch) }
        if i.nowPlayingActive { return .compact(.nowPlaying) }
        return .idle
    }
}
