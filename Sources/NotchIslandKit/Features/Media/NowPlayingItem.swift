import Foundation

/// What is playing. Pure data: views derive everything else (artwork image, progress) from it.
nonisolated struct NowPlayingItem: Sendable, Equatable {
    var title: String
    var artist: String
    var album: String
    /// nil when unknown or live (a stream has no end).
    var duration: TimeInterval?
    /// Raw encoded image bytes. Kept as `Data` so the item stays `Sendable`; `MediaController` decodes
    /// it off the main thread once per distinct image.
    var artworkData: Data?
    /// The player app, for "open app" and its icon.
    var bundleIdentifier: String?
}

/// Playback position without a ticker: an anchor (`elapsed` was true at `at`) that advances at `rate`.
/// Views ask for `position(at:)` from inside a `TimelineView` that exists only while it is on screen,
/// so nothing wakes up just to count seconds.
nonisolated struct PlaybackClock: Sendable, Equatable {
    var elapsed: TimeInterval
    var at: Date
    /// 0 while paused, so a paused clock is constant.
    var rate: Double

    func position(at date: Date) -> TimeInterval {
        max(0, elapsed + date.timeIntervalSince(at) * rate)
    }

    /// `position(at:)` clamped to the track length (players report the anchor a little late, and a
    /// clock left running past the end must not show 4:05 of 4:03).
    func position(at date: Date, duration: TimeInterval?) -> TimeInterval {
        let raw = position(at: date)
        guard let duration, duration > 0 else { return raw }
        return min(raw, duration)
    }

    /// A clock that shows the same position from `date` on, advancing at `rate`.
    func reanchored(at date: Date, rate: Double) -> PlaybackClock {
        PlaybackClock(elapsed: position(at: date), at: date, rate: rate)
    }

    /// True when both clocks project the same timeline. Re-anchoring an unchanged timeline (a player
    /// re-sending its state) must not count as a change: publishing it would restart the scrubber.
    func isEquivalent(to other: PlaybackClock, tolerance: TimeInterval = 0.25) -> Bool {
        abs(rate - other.rate) < 0.001 && abs(position(at: other.at) - other.elapsed) < tolerance
    }
}

nonisolated enum MediaCommand: Sendable, Equatable {
    case play, pause, togglePlayPause, next, previous, seek(TimeInterval)
}

nonisolated enum MediaSourceStatus: Sendable, Equatable {
    /// Now Playing is turned off.
    case off
    /// Music and Spotify are read; `web` says how browsers and video apps are.
    case on(web: WebMediaStatus, automationIssue: String?)
}

/// How browser and video-app playback is being read (see `MediaSourcePolicy`).
nonisolated enum WebMediaStatus: Sendable, Equatable {
    /// Turned off by the user.
    case off
    /// This build has no MediaRemote adapter.
    case notInstalled
    /// No browser or video app is open: nothing runs until one opens.
    case standby
    /// A browser or video app is open and the system's Now Playing is being read.
    case listening
    /// The adapter failed and is cooling down before the next try.
    case retrying
}

/// One complete observation from a source. Sources emit these; `MediaController` dedupes and publishes.
nonisolated struct NowPlayingSnapshot: Sendable, Equatable {
    var item: NowPlayingItem
    var isPlaying: Bool
    /// nil when the position is unknown (the scrubber then hides its times).
    var clock: PlaybackClock?

    /// Dedupe rule: the full item must match (title, artist, album, duration, artwork bytes, player) —
    /// comparing a token instead lost metadata that arrived in a later update — and the clocks must
    /// project the same timeline.
    func isEquivalent(to other: NowPlayingSnapshot) -> Bool {
        guard item == other.item, isPlaying == other.isPlaying else { return false }
        switch (clock, other.clock) {
        case (nil, nil): return true
        case let (lhs?, rhs?): return lhs.isEquivalent(to: rhs)
        default: return false
        }
    }

    /// The state a command is expected to produce, shown immediately so the controls feel instant.
    /// The player's own report replaces it moments later (or, for a seek on Music, which does not
    /// broadcast seeks, it simply stays true).
    func applying(_ command: MediaCommand, at now: Date) -> NowPlayingSnapshot {
        var next = self
        switch command {
        case .play: next.setPlaying(true, at: now)
        case .pause: next.setPlaying(false, at: now)
        case .togglePlayPause: next.setPlaying(!isPlaying, at: now)
        case .next, .previous:
            // Both land at the start of a track (previous restarts the current one past a few seconds).
            // The new metadata follows from the player.
            next.clock = PlaybackClock(elapsed: 0, at: now, rate: isPlaying ? 1 : 0)
        case .seek(let target):
            let upper = item.duration.flatMap { $0 > 0 ? $0 : nil } ?? .greatestFiniteMagnitude
            let playingRate = clock.flatMap { $0.rate > 0 ? $0.rate : nil } ?? 1
            next.clock = PlaybackClock(elapsed: min(max(0, target), upper), at: now, rate: isPlaying ? playingRate : 0)
        }
        return next
    }

    private mutating func setPlaying(_ playing: Bool, at now: Date) {
        isPlaying = playing
        clock = clock?.reanchored(at: now, rate: playing ? 1 : 0)
    }
}
