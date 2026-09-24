import Foundation

// Pure pieces of the MediaRemote adapter integration: where it lives, how its stdout is framed and
// parsed, how diffs merge, and when a dead child is restarted. No process handling here.

/// A vendored copy of ungive/mediaremote-adapter (BSD-3-Clause).
nonisolated struct AdapterInstallation: Sendable, Equatable {
    static let directoryName = "MediaRemoteAdapter"
    static let scriptName = "mediaremote-adapter.pl"
    static let frameworkName = "MediaRemoteAdapter.framework"
    /// An Apple platform binary. Since macOS 15.4 MediaRemote refuses Now Playing data to unentitled
    /// processes but not to platform binaries, so the adapter's helper framework is loaded into perl.
    static let perlURL = URL(fileURLWithPath: "/usr/bin/perl")

    /// Absolute paths: the adapter rejects relative ones.
    let scriptURL: URL
    let frameworkURL: URL

    init(directory: URL) {
        scriptURL = directory.appendingPathComponent(Self.scriptName)
        frameworkURL = directory.appendingPathComponent(Self.frameworkName, isDirectory: true)
    }

    /// Where to look, in order: the app bundle's Resources (how it ships), then — only for an unbundled
    /// development build (`swift run`, tests) — `Vendor/MediaRemoteAdapter` in any ancestor of the
    /// executable, which finds `<project>/Vendor/…` from `<project>/.build/<triple>/debug/`.
    static func candidateDirectories(resourceURL: URL?, executableURL: URL?, isAppBundle: Bool) -> [URL] {
        var candidates: [URL] = []
        if let resourceURL {
            candidates.append(resourceURL.appendingPathComponent(directoryName, isDirectory: true))
        }
        if !isAppBundle, let executableURL {
            var directory = executableURL.deletingLastPathComponent()
            for _ in 0..<6 {
                candidates.append(directory.appendingPathComponent("Vendor", isDirectory: true)
                    .appendingPathComponent(directoryName, isDirectory: true))
                let parent = directory.deletingLastPathComponent()
                if parent.path == directory.path { break }
                directory = parent
            }
        }
        return candidates
    }

    /// Filesystem checks only; nothing is executed.
    static func locate(fileManager: FileManager = .default) -> AdapterInstallation? {
        guard fileManager.isExecutableFile(atPath: perlURL.path) else { return nil }
        let bundle = Bundle.main
        let candidates = candidateDirectories(
            resourceURL: bundle.resourceURL,
            executableURL: bundle.executableURL,
            isAppBundle: bundle.bundleURL.pathExtension == "app"
        )
        for directory in candidates {
            let installation = AdapterInstallation(directory: directory)
            var isDirectory: ObjCBool = false
            if fileManager.isReadableFile(atPath: installation.scriptURL.path),
               fileManager.fileExists(atPath: installation.frameworkURL.path, isDirectory: &isDirectory),
               isDirectory.boolValue {
                return installation
            }
        }
        return nil
    }
}

/// Splits a byte stream into newline-terminated lines.
///
/// A line longer than `maxLineLength` is skipped on its own — the bytes up to its newline are dropped
/// and the next line parses normally. (The legacy reader cleared its whole buffer at 1 MiB, which cut a
/// large artwork snapshot mid-line and silently lost the update, title included.) The limit only guards
/// against a wedged producer; real artwork lines are a few MiB at most.
nonisolated struct LineFramer: Sendable {
    static let defaultMaxLineLength = 32 << 20

    let maxLineLength: Int
    private var pending = Data()
    private var discarding = false
    private(set) var droppedLines = 0

    init(maxLineLength: Int = LineFramer.defaultMaxLineLength) {
        self.maxLineLength = maxLineLength
    }

    mutating func append(_ chunk: Data) -> [Data] {
        var lines: [Data] = []
        var start = chunk.startIndex
        while let newline = chunk[start...].firstIndex(of: 0x0A) {
            let piece = chunk[start..<newline]
            start = chunk.index(after: newline)
            if discarding {
                discarding = false
                continue
            }
            if pending.count + piece.count > maxLineLength {
                pending.removeAll()
                droppedLines += 1
                continue
            }
            if pending.isEmpty {
                if !piece.isEmpty { lines.append(Data(piece)) }
            } else {
                pending.append(piece)
                lines.append(pending)
                pending = Data()
            }
        }
        let tail = chunk[start...]
        if !discarding, !tail.isEmpty {
            if pending.count + tail.count > maxLineLength {
                pending.removeAll()
                discarding = true
                droppedLines += 1
            } else {
                pending.append(tail)
            }
        }
        return lines
    }
}

/// A JSON field in an adapter update. Diffs distinguish "not mentioned" (keep) from an explicit JSON
/// `null` (clear) — the legacy code stringified `NSNull` into the token `"<null>"`.
nonisolated enum AdapterField<Value: Sendable & Equatable>: Sendable, Equatable {
    case absent
    case cleared
    case value(Value)

    func merged(into current: Value?) -> Value? {
        switch self {
        case .absent: current
        case .cleared: nil
        case .value(let value): value
        }
    }
}

/// One stdout line of `mediaremote-adapter.pl … stream`, typed. Parsing (including the base64 artwork
/// decode) happens off the main actor.
nonisolated struct AdapterUpdate: Sendable, Equatable {
    /// true: merge into the accumulated state; false: replace it.
    var isDiff = false
    var title: AdapterField<String> = .absent
    var artist: AdapterField<String> = .absent
    var album: AdapterField<String> = .absent
    var duration: AdapterField<TimeInterval> = .absent
    var elapsed: AdapterField<TimeInterval> = .absent
    var timestamp: AdapterField<Date> = .absent
    var rate: AdapterField<Double> = .absent
    var playing: AdapterField<Bool> = .absent
    var artwork: AdapterField<Data> = .absent
    var bundleIdentifier: AdapterField<String> = .absent
    var parentBundleIdentifier: AdapterField<String> = .absent
    var uniqueIdentifier: AdapterField<String> = .absent

    /// nil for anything that is not a JSON object (a partial or foreign line is skipped, not fatal).
    static func parse(_ line: Data) -> AdapterUpdate? {
        guard let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { return nil }
        // Data lines are tagged `"type": "data"` (or untagged); any other message type must not be
        // mistaken for a full update with nothing playing.
        if let type = object["type"] as? String, type != "data" { return nil }
        var update = AdapterUpdate()
        update.isDiff = (object["diff"] as? NSNumber)?.boolValue ?? false
        let payload: [String: Any]
        if let nested = object["payload"] {
            // `"payload": null` is a full update with nothing playing.
            payload = nested as? [String: Any] ?? [:]
        } else {
            payload = object
        }
        update.title = string(payload["title"])
        update.artist = string(payload["artist"])
        update.album = string(payload["album"])
        update.duration = seconds(payload, key: "duration", microsKey: "durationMicros")
        update.elapsed = seconds(payload, key: "elapsedTime", microsKey: "elapsedTimeMicros")
        update.timestamp = date(payload)
        update.rate = number(payload["playbackRate"])
        update.playing = bool(payload["playing"])
        update.artwork = artworkData(payload["artworkData"])
        update.bundleIdentifier = string(payload["bundleIdentifier"])
        update.parentBundleIdentifier = string(payload["parentApplicationBundleIdentifier"])
        update.uniqueIdentifier = string(payload["uniqueIdentifier"])
        return update
    }

    private static func string(_ raw: Any?) -> AdapterField<String> {
        switch raw {
        case nil: .absent
        case is NSNull: .cleared
        case let text as String: .value(text)
        case let number as NSNumber: .value(number.stringValue)
        default: .cleared
        }
    }

    private static func number(_ raw: Any?) -> AdapterField<Double> {
        switch raw {
        case nil: .absent
        case let number as NSNumber: .value(number.doubleValue)
        case let text as String: Double(text).map(AdapterField.value) ?? .cleared
        default: .cleared
        }
    }

    private static func bool(_ raw: Any?) -> AdapterField<Bool> {
        switch raw {
        case nil: .absent
        case let number as NSNumber: .value(number.boolValue)
        default: .cleared
        }
    }

    private static func seconds(_ payload: [String: Any], key: String, microsKey: String) -> AdapterField<TimeInterval> {
        if case .value(let micros) = number(payload[microsKey]) { return .value(micros / 1_000_000) }
        return number(payload[key])
    }

    /// When `elapsedTime` was true. Seen as epoch milliseconds; also accepted as seconds, microseconds
    /// (`timestampEpochMicros`, the adapter's `--micros` mode) or an ISO-8601 string, so an upstream
    /// format change degrades to "anchored on arrival" instead of a wildly wrong position.
    private static func date(_ payload: [String: Any]) -> AdapterField<Date> {
        if case .value(let micros) = number(payload["timestampEpochMicros"]) {
            return .value(Date(timeIntervalSince1970: micros / 1_000_000))
        }
        switch payload["timestamp"] {
        case nil: return .absent
        case let number as NSNumber: return .value(epochDate(number.doubleValue))
        case let text as String:
            if let value = Double(text) { return .value(epochDate(value)) }
            if let date = try? Date(text, strategy: .iso8601) { return .value(date) }
            let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
            return (try? fractional.parse(text)).map(AdapterField.value) ?? .cleared
        default: return .cleared
        }
    }

    /// Unit by magnitude: today is ~1.8e9 s, ~1.8e12 ms, ~1.8e15 µs since 1970.
    static func epochDate(_ value: Double) -> Date {
        let seconds = value < 1e11 ? value : (value < 1e14 ? value / 1_000 : value / 1_000_000)
        return Date(timeIntervalSince1970: seconds)
    }

    private static func artworkData(_ raw: Any?) -> AdapterField<Data> {
        switch raw {
        case nil: .absent
        case let text as String:
            Data(base64Encoded: text, options: .ignoreUnknownCharacters).flatMap { $0.isEmpty ? nil : $0 }
                .map(AdapterField.value) ?? .cleared
        default: .cleared
        }
    }
}

/// The adapter's accumulated state (full updates replace it, diffs merge into it).
nonisolated struct AdapterTrackState: Sendable, Equatable {
    var title: String?
    var artist: String?
    var album: String?
    var duration: TimeInterval?
    var elapsed: TimeInterval?
    /// When `elapsed` was true: the adapter's timestamp, else the moment the value arrived.
    var anchor: Date?
    var rate: Double?
    var isPlaying: Bool?
    var artwork: Data?
    var bundleIdentifier: String?
    var parentBundleIdentifier: String?
    var uniqueIdentifier: String?

    mutating func apply(_ update: AdapterUpdate, receivedAt now: Date) {
        if !update.isDiff { self = AdapterTrackState() }
        title = update.title.merged(into: title)
        artist = update.artist.merged(into: artist)
        album = update.album.merged(into: album)
        duration = update.duration.merged(into: duration)
        elapsed = update.elapsed.merged(into: elapsed)
        rate = update.rate.merged(into: rate)
        isPlaying = update.playing.merged(into: isPlaying)
        artwork = update.artwork.merged(into: artwork)
        bundleIdentifier = update.bundleIdentifier.merged(into: bundleIdentifier)
        parentBundleIdentifier = update.parentBundleIdentifier.merged(into: parentBundleIdentifier)
        uniqueIdentifier = update.uniqueIdentifier.merged(into: uniqueIdentifier)
        switch (update.timestamp, update.elapsed) {
        case (.value(let date), _): anchor = date
        case (.cleared, _), (.absent, .value): anchor = now
        case (.absent, _): break
        }
        if elapsed == nil { anchor = nil }
    }

    /// nil when nothing is playing (no title).
    var snapshot: NowPlayingSnapshot? {
        guard let title, !title.isEmpty else { return nil }
        let playing = isPlaying ?? false
        // MediaRemote briefly reports rate 0 while starting to play; a playing clock must advance.
        let playingRate = rate.flatMap { $0 > 0 ? $0 : nil } ?? 1
        let clock = elapsed.map { PlaybackClock(elapsed: $0, at: anchor ?? .now, rate: playing ? playingRate : 0) }
        let item = NowPlayingItem(
            title: title,
            artist: artist ?? "",
            album: album ?? "",
            duration: duration.flatMap { $0 > 0 ? $0 : nil },
            artworkData: artwork,
            // Web players report a helper process; the parent is the browser the user knows.
            bundleIdentifier: parentBundleIdentifier ?? bundleIdentifier
        )
        return NowPlayingSnapshot(item: item, isPlaying: playing, clock: clock)
    }

    /// Writes an optimistic snapshot's playback state back, so a later unrelated diff (artwork, say)
    /// does not flip the controls back before the adapter confirms the command.
    mutating func adopt(_ optimistic: NowPlayingSnapshot) {
        isPlaying = optimistic.isPlaying
        if let clock = optimistic.clock {
            elapsed = clock.elapsed
            anchor = clock.at
            if clock.rate > 0 { rate = clock.rate }
        }
    }
}

nonisolated enum AdapterExit: Sendable, Equatable {
    case status(Int32)
    case signal(Int32)
    case launchFailed(String)
}

nonisolated enum AdapterRestartDecision: Sendable, Equatable {
    case restart(after: TimeInterval)
    case giveUp(String)
}

/// When a dead adapter child is restarted. Pure.
///
/// * A non-zero exit status is fatal by the adapter's contract (retrying fails the same way).
/// * A clean exit or a signal is transient: restart after 2, 4, 8, 16 s; give up at the fifth
///   consecutive failure. A run that lasted `healthyRunDuration` with output resets the count, so
///   crashes spread over a long session (sleep/wake cycles) never add up to a give-up.
/// * A child that dies without printing anything twice in a row is not going to work: give up early
///   so the fallback source takes over within seconds instead of after half a minute.
nonisolated struct AdapterRestartPolicy: Sendable, Equatable {
    static let maxConsecutiveFailures = 5
    static let maxSilentFailures = 2
    static let healthyRunDuration: TimeInterval = 60

    private(set) var consecutiveFailures = 0
    private(set) var silentFailures = 0
    private var launchedAt: Date?
    private var producedOutput = false

    static func backoff(afterFailures count: Int) -> TimeInterval {
        min(60, pow(2, Double(max(1, count))))
    }

    mutating func launched(at now: Date) {
        launchedAt = now
        producedOutput = false
    }

    mutating func receivedOutput() {
        producedOutput = true
        silentFailures = 0
    }

    mutating func exited(_ exit: AdapterExit, at now: Date) -> AdapterRestartDecision {
        defer { launchedAt = nil; producedOutput = false }
        switch exit {
        case .launchFailed(let reason):
            return .giveUp("could not start perl: \(reason)")
        case .status(let code) where code != 0:
            return .giveUp("adapter exited with status \(code)")
        case .status, .signal:
            break
        }
        if producedOutput, let launchedAt, now.timeIntervalSince(launchedAt) >= Self.healthyRunDuration {
            consecutiveFailures = 0
        }
        consecutiveFailures += 1
        if !producedOutput {
            silentFailures += 1
            if silentFailures >= Self.maxSilentFailures { return .giveUp("adapter produced no output") }
        }
        if consecutiveFailures >= Self.maxConsecutiveFailures { return .giveUp("adapter restarted too often") }
        return .restart(after: Self.backoff(afterFailures: consecutiveFailures))
    }
}

/// Adapters left behind by builds that ran them without the lifeline watchdog (or killed with it
/// before it could act): perl processes running our adapter script whose parent is gone (re-parented
/// to launchd). They keep a MediaRemote subscription and a process alive for nothing.
nonisolated enum AdapterOrphans {
    /// Parses `ps -axo pid=,ppid=,command=` output. Pure, for tests.
    static func orphans(in psOutput: String, runningScript script: String) -> [pid_t] {
        psOutput.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard fields.count == 3, let pid = pid_t(fields[0]), fields[1] == "1",
                  fields[2].contains(script) else { return nil }
            return pid
        }
    }

    /// Blocking (runs `ps`); call off the main actor.
    static func terminate(runningScript script: String) {
        let ps = Process()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-axo", "pid=,ppid=,command="]
        let pipe = Pipe()
        ps.standardOutput = pipe
        ps.standardError = FileHandle.nullDevice
        do { try ps.run() } catch { return }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        ps.waitUntilExit()
        let found = orphans(in: String(decoding: data, as: UTF8.self), runningScript: script)
        for pid in found { kill(pid, SIGTERM) }
        if !found.isEmpty {
            Log.media.notice("ended \(found.count, privacy: .public) orphaned adapter process(es)")
        }
    }
}
