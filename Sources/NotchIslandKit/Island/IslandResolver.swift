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
    /// Settings is open in the island: below the assistant, above everything else.
    var wantsSettings: Bool = false
    /// How much of the assistant shows (see `AssistantRoom`).
    var assistantRoom: AssistantRoom = .field
    var wantsExpanded: Bool = false
    var page: ExpandedPage = .home
    var banner: BannerKind? = nil
    var isDragInProgress: Bool = false
    /// A window dragged under the notch can be let go there (Window Anchor).
    var isAnchorTargeted: Bool = false
    /// Running, paused, or finished-but-unacknowledged.
    var countdownActive: Bool = false
    /// Running, or paused with time on the clock.
    var stopwatchActive: Bool = false
    /// `MediaController.isActive`, already gated by the Now Playing preference.
    var nowPlayingActive: Bool = false
    /// The screen is being recorded (`ScreenRecorder`).
    var recordingActive: Bool = false
    /// While recording, the panel was asked for (a page by name, or from the recording card): it
    /// opens instead of the card.
    var wantsPanelWhileRecording: Bool = false
}

nonisolated enum IslandResolver {
    /// Highest priority wins. What the user asked for beats what the system
    /// wants to say; a drag in flight beats a notice, because the drop banner
    /// is only useful while the drag lasts; ongoing activities come last since
    /// they are always there to fall back to.
    static func resolve(_ i: IslandInputs) -> IslandPresentation {
        if i.wantsAssistant { return .assistant(i.assistantRoom) }
        if i.wantsSettings { return .settings }
        // While recording, the pointer opens the recording card; the panel only when asked for.
        if i.wantsExpanded { return .expanded(i.recordingActive && !i.wantsPanelWhileRecording ? .recording : i.page) }
        if i.isHidden {
            // Only the direct answer to something the user just did gets through.
            if let banner = i.banner, banner.showsWhileHidden { return .banner(banner) }
            return .idle
        }
        if i.isDragInProgress { return .banner(.dropTarget) }
        if i.isAnchorTargeted { return .banner(.anchorTarget) }
        if let banner = i.banner { return .banner(banner) }
        if i.recordingActive { return .compact(.recording) }
        if i.countdownActive { return .compact(.timer) }
        if i.stopwatchActive { return .compact(.stopwatch) }
        if i.nowPlayingActive { return .compact(.nowPlaying) }
        return .idle
    }
}
