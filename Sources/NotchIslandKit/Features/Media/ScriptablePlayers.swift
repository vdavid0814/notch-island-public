import Foundation

// Pure pieces of the Music + Spotify source: the players, how their broadcasts and seed results parse,
// and which player owns the island. No notifications or Apple Events here.

nonisolated struct ScriptablePlayer: Sendable, Hashable, Identifiable {
    nonisolated enum ArtworkSource: Sendable, Hashable {
        /// Music: `raw data of artwork 1` returns the image bytes.
        case rawData
        /// Spotify: `artwork url` returns an https URL to download.
        case url
    }

    let bundleID: String
    let displayName: String
    /// Posted on `DistributedNotificationCenter` at every playback change; needs no permission.
    let notificationName: String
    /// Multiplier from the scripting dictionary's `duration` to seconds: Music reports seconds (real),
    /// Spotify milliseconds (the legacy seed took Spotify's as seconds, 1000× too long).
    let scriptDurationScale: Double
    let artwork: ArtworkSource

    var id: String { bundleID }

    static let music = ScriptablePlayer(
        bundleID: "com.apple.Music", displayName: "Music",
        notificationName: "com.apple.Music.playerInfo", scriptDurationScale: 1, artwork: .rawData
    )
    static let spotify = ScriptablePlayer(
        bundleID: "com.spotify.client", displayName: "Spotify",
        notificationName: "com.spotify.client.PlaybackStateChanged", scriptDurationScale: 0.001, artwork: .url
    )
    static let all = [music, spotify]

    static func player(for bundleID: String?) -> ScriptablePlayer? {
        all.first { $0.bundleID == bundleID }
    }
}

/// One observation of one player, from a broadcast or a seed pull.
nonisolated struct PlayerReport: Sendable, Equatable {
    nonisolated enum State: Sendable, Equatable { case playing, paused, stopped }

    var state: State
    var title = ""
    var artist = ""
    var album = ""
    var duration: TimeInterval?
    /// Spotify broadcasts carry it; Music's never do.
    var position: TimeInterval?
    /// Music persistent ID (16 uppercase hex digits) or Spotify track URI.
    var trackID: String?

    /// Parses a playerInfo / PlaybackStateChanged userInfo dictionary.
    static func broadcast(_ info: [AnyHashable: Any]) -> PlayerReport {
        let state: State = switch info["Player State"] as? String {
        case "Playing": .playing
        case "Paused": .paused
        default: .stopped
        }
        var report = PlayerReport(state: state)
        report.title = info["Name"] as? String ?? ""
        report.artist = info["Artist"] as? String ?? ""
        report.album = info["Album"] as? String ?? ""
        // Both players send integer milliseconds: Music as "Total Time", Spotify as "Duration".
        if let milliseconds = number(info["Total Time"]) ?? number(info["Duration"]), milliseconds > 0 {
            report.duration = milliseconds / 1000
        }
        report.position = number(info["Playback Position"]).map { max(0, $0) }
        // Music's key is "PersistentID" (an integer); the spaced spelling is accepted too.
        report.trackID = persistentID(info["PersistentID"]) ?? persistentID(info["Persistent ID"])
            ?? (info["Track ID"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return report
    }

    /// Parses the `niseed` result: {state, position, name, artist, album, duration, identifier}.
    static func seed(_ value: ScriptValue, player: ScriptablePlayer) -> PlayerReport? {
        guard let items = value.items, items.count >= 6, let stateText = items[0].text else { return nil }
        let state: State = switch stateText.lowercased() {
        case "playing", "fast forwarding", "rewinding": .playing
        case "paused": .paused
        default: .stopped
        }
        var report = PlayerReport(state: state)
        report.position = items[1].number.map { max(0, $0) }
        report.title = items[2].text ?? ""
        report.artist = items[3].text ?? ""
        report.album = items[4].text ?? ""
        if let duration = items[5].number, duration > 0 {
            report.duration = duration * player.scriptDurationScale
        }
        if items.count > 6, let identifier = items[6].text, !identifier.isEmpty {
            report.trackID = player == .music ? identifier.uppercased() : identifier
        }
        return report
    }

    private static func number(_ raw: Any?) -> Double? {
        switch raw {
        case let number as NSNumber: number.doubleValue
        case let text as String: AppleScriptNumber.parse(text)
        default: nil
        }
    }

    /// Music broadcasts the persistent ID as a signed 64-bit integer; AppleScript returns the same
    /// value as 16 hex digits. Normalising both lets a seed and a later broadcast agree on identity.
    static func persistentID(_ raw: Any?) -> String? {
        switch raw {
        case let number as NSNumber:
            String(format: "%016llX", UInt64(bitPattern: number.int64Value))
        case let text as String where !text.isEmpty:
            text.uppercased()
        default:
            nil
        }
    }
}

/// What the source knows about one player's current track.
nonisolated struct PlayerTrack: Sendable, Equatable {
    var snapshot: NowPlayingSnapshot
    var trackID: String?
    /// Changes whenever the player moves to a different track. Async pulls capture it and are applied
    /// only if it is unchanged, so a slow reply can never paint the previous track's data on a new one.
    var generation: Int
}

/// Which player owns the island, and each player's last known track. Pure.
nonisolated struct ScriptableState: Sendable, Equatable {
    struct Outcome: Sendable, Equatable {
        /// The island's snapshot (the active player's) changed.
        var changed = false
        /// The reported player moved to a different track.
        var newTrack = false
        /// The report carried no usable position; pull it once.
        var needsPosition = false
        /// Players whose state is unknown or stale and should be asked (the active one just went away).
        var requery: [String] = []
    }

    private(set) var tracks: [String: PlayerTrack] = [:]
    private(set) var activeBundleID: String?
    private var lastGeneration = 0

    var activeSnapshot: NowPlayingSnapshot? {
        activeBundleID.flatMap { tracks[$0]?.snapshot }
    }

    func generation(of bundleID: String) -> Int? {
        tracks[bundleID]?.generation
    }

    /// Same track when the IDs agree, or — because a seed and a broadcast may not share an ID format —
    /// when title, artist and album all agree.
    static func isSameTrack(_ track: PlayerTrack, _ report: PlayerReport) -> Bool {
        if let lhs = track.trackID, let rhs = report.trackID, lhs == rhs { return true }
        let item = track.snapshot.item
        return item.title == report.title && item.artist == report.artist && item.album == report.album
    }

    mutating func ingest(_ report: PlayerReport, from player: ScriptablePlayer, at now: Date) -> Outcome {
        if report.state == .stopped { return remove(player.bundleID) }
        // An empty title (a Spotify ad, a transitional state) is ignored entirely — before arbitration,
        // so it cannot move the island to a player whose track we cannot show.
        guard !report.title.isEmpty else { return Outcome() }

        let before = activeSnapshot
        let bundleID = player.bundleID
        let existing = tracks[bundleID]
        let sameTrack = existing.map { Self.isSameTrack($0, report) } ?? false
        let playing = report.state == .playing
        var outcome = Outcome()

        let duration = report.duration ?? (sameTrack ? existing?.snapshot.item.duration : nil)
        let elapsed: TimeInterval
        if let position = report.position {
            elapsed = position
        } else if sameTrack, let clock = existing?.snapshot.clock {
            elapsed = clock.position(at: now, duration: duration)
        } else {
            // A new track normally starts at 0; pull once to be sure (Music never broadcasts position).
            elapsed = 0
            outcome.needsPosition = true
        }

        let generation: Int
        if sameTrack, let existing {
            generation = existing.generation
        } else {
            lastGeneration += 1
            generation = lastGeneration
            outcome.newTrack = true
        }

        let item = NowPlayingItem(
            title: report.title,
            artist: report.artist,
            album: report.album,
            duration: duration,
            // Keep artwork across updates of the same track instead of blanking it for a moment.
            artworkData: sameTrack ? existing?.snapshot.item.artworkData : nil,
            bundleIdentifier: bundleID
        )
        let clock = PlaybackClock(
            elapsed: min(max(0, elapsed), duration ?? .greatestFiniteMagnitude),
            at: now,
            // The scripting dictionaries expose no playback rate.
            rate: playing ? 1 : 0
        )
        tracks[bundleID] = PlayerTrack(
            snapshot: NowPlayingSnapshot(item: item, isPlaying: playing, clock: clock),
            trackID: report.trackID ?? (sameTrack ? existing?.trackID : nil),
            generation: generation
        )

        // A player that starts playing takes the island. A pause keeps it for its own player, and takes
        // it over from another player only if that one is not playing (the most recent pause wins).
        if playing || activeBundleID == nil || activeBundleID == bundleID
            || activeSnapshot?.isPlaying != true {
            activeBundleID = bundleID
        }
        outcome.changed = activeSnapshot != before
        return outcome
    }

    /// The player stopped or quit. If it owned the island, another known player takes over (a playing
    /// one first) and every other player is re-queried: its last report may be stale, and a player
    /// that is already playing sends nothing until its next change.
    mutating func remove(_ bundleID: String) -> Outcome {
        let before = activeSnapshot
        tracks[bundleID] = nil
        var outcome = Outcome()
        if activeBundleID == bundleID {
            let candidates = tracks.sorted { $0.key < $1.key }
            activeBundleID = (candidates.first { $0.value.snapshot.isPlaying } ?? candidates.first)?.key
            outcome.requery = ScriptablePlayer.all.map(\.bundleID).filter { $0 != bundleID }
        }
        outcome.changed = activeSnapshot != before
        return outcome
    }

    /// Returns whether the island's snapshot changed.
    mutating func updatePosition(_ position: TimeInterval, for bundleID: String, generation: Int, at now: Date) -> Bool {
        guard var track = tracks[bundleID], track.generation == generation else { return false }
        let duration = track.snapshot.item.duration
        track.snapshot.clock = PlaybackClock(
            elapsed: min(max(0, position), duration ?? .greatestFiniteMagnitude),
            at: now,
            rate: track.snapshot.isPlaying ? 1 : 0
        )
        tracks[bundleID] = track
        return bundleID == activeBundleID
    }

    /// Returns whether the island's snapshot changed.
    mutating func attachArtwork(_ data: Data, for bundleID: String, generation: Int) -> Bool {
        guard var track = tracks[bundleID], track.generation == generation,
              track.snapshot.item.artworkData != data else { return false }
        track.snapshot.item.artworkData = data
        tracks[bundleID] = track
        return bundleID == activeBundleID
    }

    /// Applies a command's expected result to the active player. Returns whether anything changed.
    mutating func applyOptimistic(_ command: MediaCommand, at now: Date) -> Bool {
        guard let bundleID = activeBundleID, var track = tracks[bundleID] else { return false }
        track.snapshot = track.snapshot.applying(command, at: now)
        tracks[bundleID] = track
        return true
    }

    /// Puts back a track saved before an optimistic update whose command failed, unless the player has
    /// reported something newer since.
    mutating func restore(_ saved: PlayerTrack, for bundleID: String, ifUnchangedSince optimistic: PlayerTrack) -> Bool {
        guard tracks[bundleID] == optimistic else { return false }
        tracks[bundleID] = saved
        return bundleID == activeBundleID
    }
}
