import Foundation

/// What preferences, permissions and system state currently ask of the long-running features.
///
/// `AppModel` snapshots this whenever one of its inputs changes and applies only the difference
/// (`actions(from:to:)`), so a preference write that does not affect a feature never restarts it —
/// the legacy app re-applied every module on every slider tick.
nonisolated struct FeatureState: Sendable, Equatable {
    var nowPlaying = false
    /// Browser and video-app playback on top of Music and Spotify.
    var webMedia = false
    var levels = false
    /// Swallow the volume/brightness keys (replace the system HUD).
    var interception = false
    /// The user wants interception but Accessibility is not granted yet.
    var needsAccessibility = false
    var dragMonitor = false
    var suspended = false
    /// Watch for full-screen windows: for hiding during full-screen video, and for keeping the
    /// menu bar from sliding down at the notch in any full-screen app.
    var fullscreenMonitor = false
    /// Some full-screen window is on the notch screen.
    var fullscreenPresent = false
    /// ⌘Space is taken over to open Siri in the notch.
    var commandSpace = false
    /// The playing video is in full screen on the notch screen and the island steps aside.
    var hidden = false
    /// The liquid runs out to macOS's volume card, to its AirPods card.
    var liquidVolume = false
    var liquidAirPods = false

    /// Everything stopped: the state before `start()` and after `stop()`.
    static let off = FeatureState()

    init() {}

    init(
        showNowPlaying: Bool,
        showWebMedia: Bool = true,
        showLevelHUD: Bool,
        levelWidgets: Bool = false,
        replaceSystemHUD: Bool,
        accessibilityTrusted: Bool,
        shelfEnabled: Bool,
        suspended: Bool,
        hideInFullscreen: Bool = false,
        fullscreenActive: Bool = false,
        fullscreenPresent: Bool = false,
        commandSpaceOpensSiri: Bool = false,
        liquidVolume: Bool = false,
        liquidAirPods: Bool = false
    ) {
        nowPlaying = showNowPlaying
        webMedia = showNowPlaying && showWebMedia
        // Levels are only read to drive the HUD or a volume/brightness widget; with neither, nothing
        // consumes them.
        levels = showLevelHUD || levelWidgets
        // Swallowing keys while the level HUD is hidden would leave the user with no HUD at all,
        // and while suspended (locked, asleep) the island is ordered out, so the system HUD has to
        // stay in charge there too.
        fullscreenMonitor = true
        self.fullscreenPresent = fullscreenPresent && !suspended
        commandSpace = commandSpaceOpensSiri && accessibilityTrusted && !suspended
        hidden = hideInFullscreen && fullscreenActive && !suspended
        // Hidden for a full-screen video is not such a case: the island still answers the keys there
        // (the level banner is the direct answer to a key press, and shows while hidden).
        interception = showLevelHUD && replaceSystemHUD && accessibilityTrusted && !suspended
        needsAccessibility = showLevelHUD && replaceSystemHUD && !accessibilityTrusted
        dragMonitor = shelfEnabled
        self.suspended = suspended
        self.liquidVolume = liquidVolume
        self.liquidAirPods = liquidAirPods
    }

    /// The side effects that move the features from `applied` (nil = never) to `new`, in the
    /// order they must run: the level reader starts before the interceptor is armed and the
    /// interceptor is disarmed before the reader stops.
    static func actions(from applied: FeatureState?, to new: FeatureState) -> [FeatureAction] {
        let old = applied ?? .off
        var actions: [FeatureAction] = []

        if new.nowPlaying != old.nowPlaying {
            actions.append(new.nowPlaying ? .startMedia : .stopMedia)
        }
        if new.webMedia != old.webMedia {
            actions.append(.setWebMedia(new.webMedia))
        }

        if new.levels != old.levels {
            if new.levels {
                actions.append(.startLevels)
                if new.interception { actions.append(.setInterception(true)) }
            } else {
                if old.interception { actions.append(.setInterception(false)) }
                actions.append(.stopLevels)
            }
        } else if new.interception != old.interception {
            actions.append(.setInterception(new.interception))
        }

        // Rising edge only; PermissionCenter additionally limits the prompt to once per launch.
        if new.needsAccessibility && !old.needsAccessibility {
            actions.append(.requestAccessibility)
        }

        if new.dragMonitor != old.dragMonitor {
            actions.append(new.dragMonitor ? .startDragMonitor : .stopDragMonitor)
        }

        if new.suspended != old.suspended {
            actions.append(.setSuspended(new.suspended))
        }

        if new.fullscreenMonitor != old.fullscreenMonitor {
            actions.append(.setFullscreenMonitor(new.fullscreenMonitor))
        }
        if new.hidden != old.hidden {
            actions.append(.setHidden(new.hidden))
        }
        if new.fullscreenPresent != old.fullscreenPresent {
            actions.append(.setFullscreenPresent(new.fullscreenPresent))
        }
        if new.commandSpace != old.commandSpace {
            actions.append(.setCommandSpace(new.commandSpace))
        }
        // A card's liquid turned on: its frames ahead of the first flow (at launch `AppModel.start`
        // works them out once the launch has settled).
        if applied != nil, (new.liquidVolume && !old.liquidVolume) || (new.liquidAirPods && !old.liquidAirPods) {
            actions.append(.prewarmLiquid)
        }
        return actions
    }
}

nonisolated enum FeatureAction: Sendable, Equatable {
    case startMedia, stopMedia
    case setWebMedia(Bool)
    case startLevels, stopLevels
    case setInterception(Bool)
    case requestAccessibility
    case startDragMonitor, stopDragMonitor
    case setSuspended(Bool)
    case setFullscreenMonitor(Bool)
    case setHidden(Bool)
    case setFullscreenPresent(Bool)
    case setCommandSpace(Bool)
    case prewarmLiquid
}
