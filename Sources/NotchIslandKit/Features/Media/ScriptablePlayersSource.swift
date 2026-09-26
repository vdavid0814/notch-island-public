import AppKit

/// Music and Spotify without third-party code.
///
/// Push first: both players broadcast title, artist, album, state and duration on
/// `DistributedNotificationCenter` at every change, with no permission needed. Apple Events (through
/// `AppleScriptBridge`) fill what broadcasts lack, a handful per song and never on a schedule:
/// * a seed when the source starts, on wake, when a player launches, and when the island's player goes
///   away (a player that is already playing sends nothing until its next change);
/// * the position once per new track (Music broadcasts none) and when the island expands;
/// * the artwork once per track, with one delayed retry;
/// * transport commands, applied optimistically.
/// Every async reply is checked against the track generation (or, for seeds, the broadcast revision)
/// it was requested for before it is applied.
final class ScriptablePlayersSource: MediaSource {
    var onEvent: ((MediaSourceEvent) -> Void)?

    /// A launching player gets a moment to finish opening before it is asked anything.
    static let launchGrace: Duration = .milliseconds(1500)
    /// Music often has no artwork at the instant a track starts, and a streamed track's cover can
    /// take several seconds to arrive: retries after 2, 4 and 8 s (a handful of Apple Events per
    /// coverless track, none once it has one).
    static let artworkRetryDelay: Duration = .seconds(2)
    static let maxArtworkAttempts = 4

    private enum Job: Hashable {
        case seed(String), position(String), artwork(String), launch(String)

        var bundleID: String {
            switch self {
            case .seed(let id), .position(let id), .artwork(let id), .launch(let id): id
            }
        }
    }

    private let bridge = AppleScriptBridge()
    private let relay = NotificationRelay()
    private lazy var downloads = URLSession(configuration: .ephemeral)
    private var state = ScriptableState()
    private var isStarted = false
    private var isSuspended = false
    /// Bumped on every ingest per player: a seed reply is dropped if a broadcast arrived meanwhile.
    private var revisions: [String: Int] = [:]
    private var artworkAttempts: [String: (generation: Int, count: Int)] = [:]
    /// Players that refused Apple Events, in the order they did.
    private var deniedPlayers: [String] = []
    private var jobs: [Job: Task<Void, Never>] = [:]
    /// Off while the system's Now Playing (the adapter) covers Music and Spotify too, with artwork
    /// and position pushed: the broadcasts are still ingested (free, and they keep a fallback ready),
    /// but no Apple Event, artwork pull or Spotify download runs for a snapshot nobody shows.
    private var pullsEnabled = true

    // MARK: Lifecycle

    func start() {
        guard !isStarted else { return }
        isStarted = true
        for player in ScriptablePlayer.all {
            relay.observeDistributed(Notification.Name(player.notificationName)) { [weak self] notification in
                self?.ingest(PlayerReport.broadcast(notification.userInfo ?? [:]), from: player, pullsPosition: true)
            }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        relay.observe(NSWorkspace.didLaunchApplicationNotification, in: workspace) { [weak self] notification in
            self?.playerLaunched(notification)
        }
        relay.observe(NSWorkspace.didTerminateApplicationNotification, in: workspace) { [weak self] notification in
            self?.playerTerminated(notification)
        }
        Log.media.notice("scriptable source armed (Music + Spotify)")
        seedRunningPlayers()
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        relay.removeAll()
        cancelJobs { _ in true }
        state = ScriptableState()
        revisions.removeAll()
        artworkAttempts.removeAll()
        deniedPlayers.removeAll()
    }

    /// Broadcasts keep being ingested while suspended (free, and keeps the state right); pulls stop and
    /// in-flight ones are cancelled. Waking re-seeds, which re-anchors positions and fetches any artwork
    /// that was skipped.
    func setSuspended(_ suspended: Bool) {
        guard suspended != isSuspended else { return }
        isSuspended = suspended
        if suspended {
            cancelJobs { _ in true }
            // A cancelled fetch must not count as an attempt.
            artworkAttempts.removeAll()
        } else {
            seedRunningPlayers()
        }
    }

    func setPullsEnabled(_ enabled: Bool) {
        guard enabled != pullsEnabled else { return }
        pullsEnabled = enabled
        Log.media.info("Music/Spotify pulls \(enabled ? "resumed" : "paused: the system reports them", privacy: .public)")
        if enabled {
            guard isStarted, !isSuspended else { return }
            seedRunningPlayers()
        } else {
            cancelJobs { _ in true }
            artworkAttempts.removeAll()
            let bridge = bridge
            Task { await bridge.purge() }
        }
    }

    func refreshPosition() {
        guard pullsEnabled else { return }
        guard let player = ScriptablePlayer.player(for: state.activeBundleID) else { return }
        pullPosition(player)
    }

    // MARK: Commands

    func send(_ command: MediaCommand) {
        guard isStarted, let bundleID = state.activeBundleID, let player = ScriptablePlayer.player(for: bundleID),
              isRunning(bundleID), let saved = state.tracks[bundleID] else { return }
        let handler: ScriptHandler
        var argument: Double?
        switch command {
        case .play: handler = .play
        case .pause: handler = .pause
        case .togglePlayPause: handler = .toggle
        case .next: handler = .next
        case .previous: handler = .previous
        case .seek(let seconds):
            handler = .seek
            argument = max(0, seconds)
        }
        if state.applyOptimistic(command, at: .now) { emit() }
        let optimistic = state.tracks[bundleID]
        Task { [weak self, bridge] in
            let result = await bridge.run(handler, for: player, argument: argument)
            guard let self, self.isStarted else { return }
            switch result {
            case .success:
                self.automationWorked(for: player)
            case .failure(let failure):
                self.handle(failure, from: player, during: "command")
                // The command did not happen: take the optimistic state back unless the player has
                // reported something newer meanwhile.
                if let optimistic, self.state.restore(saved, for: bundleID, ifUnchangedSince: optimistic) {
                    self.emit()
                }
            }
        }
    }

    // MARK: Ingest

    private func ingest(_ report: PlayerReport, from player: ScriptablePlayer, pullsPosition: Bool) {
        guard isStarted else { return }
        let bundleID = player.bundleID
        revisions[bundleID, default: 0] += 1
        let outcome = state.ingest(report, from: player, at: .now)
        if outcome.newTrack {
            // Replies for the previous track would be dropped anyway; do not wait for them.
            cancelJobs { $0 == .artwork(bundleID) || $0 == .position(bundleID) }
        }
        if outcome.changed { emit() }
        guard !isSuspended, pullsEnabled else { return }
        if outcome.needsPosition, pullsPosition { pullPosition(player) }
        fetchArtworkIfNeeded(player)
        for bundleID in outcome.requery {
            if let other = ScriptablePlayer.player(for: bundleID) { seed(other) }
        }
    }

    private func emit() {
        onEvent?(.nowPlaying(state.activeSnapshot))
    }

    private func playerLaunched(_ notification: Notification) {
        guard let player = Self.player(in: notification) else { return }
        let job = Job.launch(player.bundleID)
        jobs[job]?.cancel()
        jobs[job] = Task { [weak self] in
            try? await Task.sleep(for: Self.launchGrace)
            guard !Task.isCancelled, let self else { return }
            self.jobs[job] = nil
            self.seed(player)
        }
    }

    private func playerTerminated(_ notification: Notification) {
        guard let player = Self.player(in: notification) else { return }
        let bundleID = player.bundleID
        cancelJobs { $0.bundleID == bundleID }
        artworkAttempts[bundleID] = nil
        let outcome = state.remove(bundleID)
        if outcome.changed { emit() }
        for other in outcome.requery {
            if let player = ScriptablePlayer.player(for: other) { seed(player) }
        }
    }

    private static func player(in notification: Notification) -> ScriptablePlayer? {
        let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        return ScriptablePlayer.player(for: app?.bundleIdentifier)
    }

    // MARK: Pulls

    private func seedRunningPlayers() {
        for player in ScriptablePlayer.all { seed(player) }
    }

    private func seed(_ player: ScriptablePlayer) {
        let bundleID = player.bundleID
        let job = Job.seed(bundleID)
        guard isStarted, !isSuspended, pullsEnabled, jobs[job] == nil, isRunning(bundleID) else { return }
        let revision = revisions[bundleID, default: 0]
        jobs[job] = Task { [weak self, bridge] in
            let result = await bridge.run(.seed, for: player)
            guard !Task.isCancelled, let self else { return }
            self.jobs[job] = nil
            switch result {
            case .success(let value):
                self.automationWorked(for: player)
                // A broadcast that arrived while the event was in flight is newer than this reply.
                guard self.revisions[bundleID, default: 0] == revision,
                      let report = PlayerReport.seed(value, player: player) else { return }
                self.ingest(report, from: player, pullsPosition: false)
            case .failure(let failure):
                self.handle(failure, from: player, during: "seed")
            }
        }
    }

    private func pullPosition(_ player: ScriptablePlayer) {
        let bundleID = player.bundleID
        let job = Job.position(bundleID)
        guard isStarted, !isSuspended, pullsEnabled, let generation = state.generation(of: bundleID), isRunning(bundleID) else { return }
        jobs[job]?.cancel()
        jobs[job] = Task { [weak self, bridge] in
            let result = await bridge.run(.position, for: player)
            guard !Task.isCancelled, let self else { return }
            self.jobs[job] = nil
            switch result {
            case .success(let value):
                self.automationWorked(for: player)
                if let position = value.number,
                   self.state.updatePosition(position, for: bundleID, generation: generation, at: .now) {
                    self.emit()
                }
            case .failure(let failure):
                self.handle(failure, from: player, during: "position")
            }
        }
    }

    private func fetchArtworkIfNeeded(_ player: ScriptablePlayer) {
        let bundleID = player.bundleID
        let job = Job.artwork(bundleID)
        guard isStarted, !isSuspended, pullsEnabled, jobs[job] == nil, let track = state.tracks[bundleID],
              track.snapshot.item.artworkData == nil, isRunning(bundleID) else { return }
        let generation = track.generation
        let previous = artworkAttempts[bundleID].flatMap { $0.generation == generation ? $0.count : nil } ?? 0
        guard previous < Self.maxArtworkAttempts else { return }
        let attempt = previous + 1
        artworkAttempts[bundleID] = (generation, attempt)
        jobs[job] = Task { [weak self] in
            let data = await self?.loadArtwork(for: player)
            guard !Task.isCancelled, let self else { return }
            self.jobs[job] = nil
            if let data, self.state.attachArtwork(data, for: bundleID, generation: generation) {
                self.emit()
            } else if self.state.generation(of: bundleID) != generation {
                self.fetchArtworkIfNeeded(player)
            } else if data == nil, attempt < Self.maxArtworkAttempts {
                self.jobs[job] = Task { [weak self] in
                    try? await Task.sleep(for: Self.artworkRetryDelay * (1 << (attempt - 1)), tolerance: .milliseconds(500))
                    guard !Task.isCancelled, let self else { return }
                    self.jobs[job] = nil
                    self.fetchArtworkIfNeeded(player)
                }
            }
        }
    }

    private func loadArtwork(for player: ScriptablePlayer) async -> Data? {
        switch await bridge.run(.artwork, for: player) {
        case .failure(let failure):
            handle(failure, from: player, during: "artwork")
            return nil
        case .success(let value):
            automationWorked(for: player)
            switch (player.artwork, value) {
            case (.rawData, .data(let data)):
                return data
            case (.url, .text(let text)):
                return await download(text)
            default:
                return nil
            }
        }
    }

    /// Spotify's artwork is a CDN URL. Plain http is upgraded (ATS would refuse it, and the CDN
    /// serves https); anything else is ignored.
    private func download(_ text: String) async -> Data? {
        guard var components = URLComponents(string: text), let scheme = components.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else { return nil }
        components.scheme = "https"
        guard let url = components.url else { return nil }
        do {
            let (data, response) = try await downloads.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty else { return nil }
            return data
        } catch {
            return nil
        }
    }

    // MARK: Failures & permission

    private func handle(_ failure: AppleScriptFailure, from player: ScriptablePlayer, during context: String) {
        switch failure {
        case .notPermitted:
            guard !deniedPlayers.contains(player.bundleID) else { return }
            deniedPlayers.append(player.bundleID)
            Log.media.error("Automation permission denied for \(player.displayName, privacy: .public)")
            onEvent?(.health(.automationDenied(player.displayName)))
        case .noSuchObject, .notRunning:
            break
        case .timedOut:
            Log.media.notice("\(player.displayName, privacy: .public) did not answer within 3 s (\(context, privacy: .public))")
        case .failed(let code, let message):
            Log.media.error("AppleScript error \(code, privacy: .public) (\(context, privacy: .public)): \(message, privacy: .public)")
        }
    }

    /// A successful event proves the permission exists now (granted later in System Settings).
    private func automationWorked(for player: ScriptablePlayer) {
        guard let index = deniedPlayers.firstIndex(of: player.bundleID) else { return }
        deniedPlayers.remove(at: index)
        if let still = ScriptablePlayer.player(for: deniedPlayers.first) {
            onEvent?(.health(.automationDenied(still.displayName)))
        } else {
            onEvent?(.health(.automationRestored))
        }
    }

    // MARK: Helpers

    /// Checked before every event so a quit player is never relaunched by asking it something.
    private func isRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    private func cancelJobs(where matches: (Job) -> Bool) {
        for (job, task) in jobs where matches(job) {
            task.cancel()
            jobs[job] = nil
        }
    }
}
