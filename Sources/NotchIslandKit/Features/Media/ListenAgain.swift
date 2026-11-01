import AppKit

/// The song last played in Music, kept on disk so Now Playing can offer it again while nothing
/// plays (General ▸ Listen Again): its title, artist and album beside the cover's bytes.
nonisolated struct LastPlayedTrack: Sendable, Equatable, Codable {
    var title: String
    var artist: String
    var album: String
    var playedAt: Date

    init(title: String, artist: String, album: String, playedAt: Date = .now) {
        self.title = title
        self.artist = artist
        self.album = album
        self.playedAt = playedAt
    }

    /// A track Music reported, worth keeping: Music's, with a title.
    init?(_ item: NowPlayingItem, at date: Date = .now) {
        guard item.bundleIdentifier == ScriptablePlayer.music.bundleID else { return nil }
        let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        self.init(title: title, artist: item.artist, album: item.album, playedAt: date)
    }

    /// The same song (the date aside).
    func isSameSong(as other: LastPlayedTrack) -> Bool {
        title == other.title && artist == other.artist && album == other.album
    }
}

/// Where the last Music track is kept: `Application Support/NotchIsland/LastPlayed.json`, its cover
/// beside it. Read once at launch, written only when Music moves to another song (or its cover
/// comes in), off the main thread.
nonisolated enum LastPlayedStore {
    static var directory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("NotchIsland", isDirectory: true)
    }

    private static var trackURL: URL? { directory?.appendingPathComponent("LastPlayed.json") }
    private static var artworkURL: URL? { directory?.appendingPathComponent("LastPlayed.artwork") }

    static func load() -> (track: LastPlayedTrack, artwork: Data?)? {
        guard let trackURL, let data = try? Data(contentsOf: trackURL),
              let track = try? JSONDecoder().decode(LastPlayedTrack.self, from: data) else { return nil }
        return (track, artworkURL.flatMap { try? Data(contentsOf: $0) })
    }

    static func save(_ track: LastPlayedTrack, artwork: Data?) {
        guard let directory, let trackURL, let artworkURL else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(track).write(to: trackURL, options: .atomic)
            if let artwork {
                try artwork.write(to: artworkURL, options: .atomic)
            } else {
                try? FileManager.default.removeItem(at: artworkURL)
            }
        } catch {
            Log.media.error("could not keep the last played track: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// Listen Again: Music comes to the front at the song, without playing it (asked for) — at Music's
/// current track where that is it, else at the library's match by title and artist; a song not in
/// the library is searched for in Music (`searchURL`).
nonisolated enum ListenAgain {
    enum Outcome: String, Sendable {
        case shown, missing, failed
    }

    /// Runs the script on a thread of its own (an Apple Event waits for Music, which may launch).
    static func show(_ track: LastPlayedTrack) async -> Outcome {
        let source = script(for: track)
        return await Task.detached(priority: .userInitiated) {
            guard let script = NSAppleScript(source: source) else { return Outcome.failed }
            var error: NSDictionary?
            let result = script.executeAndReturnError(&error)
            if let error {
                Log.media.error("listen again failed: \(String(describing: error), privacy: .public)")
                return .failed
            }
            return Outcome(rawValue: result.stringValue ?? "") ?? .failed
        }.value
    }

    /// The script: Music in front, revealing its current track when it is this one, else the
    /// library's first match. Nothing is played.
    static func script(for track: LastPlayedTrack) -> String {
        let title = quoted(track.title), artist = quoted(track.artist)
        let match = track.artist.isEmpty ? "name is \(title)" : "name is \(title) and artist is \(artist)"
        return """
        with timeout of 10 seconds
        \ttell application id "\(ScriptablePlayer.music.bundleID)"
        \t\tactivate
        \t\ttry
        \t\t\tset theTrack to current track
        \t\t\tif (name of theTrack) is \(title) and (artist of theTrack) is \(artist) then
        \t\t\t\treveal theTrack
        \t\t\t\treturn "shown"
        \t\t\tend if
        \t\tend try
        \t\tset theHits to (every track of library playlist 1 whose \(match))
        \t\tif theHits is {} then return "missing"
        \t\treveal item 1 of theHits
        \t\treturn "shown"
        \tend tell
        end timeout
        """
    }

    /// Apple Music's search for the song (its title and artist), which Music opens.
    static func searchURL(for track: LastPlayedTrack) -> URL? {
        var components = URLComponents(string: "music://music.apple.com/search")
        components?.queryItems = [URLQueryItem(name: "term", value: [track.title, track.artist].filter { !$0.isEmpty }.joined(separator: " "))]
        return components?.url
    }

    /// An AppleScript string literal of `text`.
    static func quoted(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}

/// When a new track's title deserves the notch (Live Activities ▸ Now Playing ▸ New Track): a
/// track playing whose title differs from the last one played. A pause and a resume, the same
/// track reported again or by another source, and the gap between two tracks are none.
nonisolated struct TrackAnnouncer: Sendable, Equatable {
    private(set) var lastTitle: String?

    /// Whether `snapshot` starts another track. `quiet`: noted, not announced (what already plays
    /// when the app starts).
    mutating func isNewTrack(_ snapshot: NowPlayingSnapshot?, quiet: Bool = false) -> Bool {
        guard let snapshot, snapshot.isPlaying else { return false }
        let title = snapshot.item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title != lastTitle else { return false }
        lastTitle = title
        return !quiet
    }
}
