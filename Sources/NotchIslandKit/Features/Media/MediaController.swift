import AppKit

/// The Now Playing store views read.
///
/// Owns the sources, decides which run and which one is shown (`MediaSourcePolicy`), dedupes their
/// output, decodes artwork once per image off the main actor, and derives `isActive` for the compact
/// island. Everything is event-driven: the only timers are one-shot `Task`s (pause grace, adapter
/// re-probe), and browsers are noticed from workspace launch/quit notifications.
@Observable final class MediaController {
    private(set) var item: NowPlayingItem?
    private(set) var isPlaying = false
    private(set) var clock: PlaybackClock?
    /// Decoded once per distinct image.
    private(set) var artwork: NSImage?
    /// The cover's colour, made readable as an accent (Now Playing widgets tint themselves with it).
    private(set) var artworkColor: ArtworkColor?
    /// The cover's leading colours as accents, most present first (the equalizer's bars run
    /// through them); empty without artwork.
    private(set) var artworkPalette: [ArtworkColor] = []
    private(set) var status: MediaSourceStatus = .off
    /// Playing, or paused less than `pauseGrace` ago.
    private(set) var isActive = false

    /// How long a paused track keeps the compact island: long enough to resume without the island
    /// collapsing and re-opening, short enough that a finished session gets out of the way.
    static let pauseGrace: Duration = .seconds(10)

    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private var isSuspended = false
    @ObservationIgnored private var didLocateAdapter = false
    @ObservationIgnored private var installation: AdapterInstallation?
    @ObservationIgnored private var adapter: MediaRemoteAdapterSource?
    @ObservationIgnored private var scriptable: ScriptablePlayersSource?
    @ObservationIgnored private var playerWatcher: SystemPlayerWatcher?
    /// The adapter has produced output in its current run (it reports Music and Spotify too).
    @ObservationIgnored private var adapterHealthy = false
    @ObservationIgnored private var policy = MediaSourcePolicy(hasAdapter: false)
    @ObservationIgnored private var snapshots: [MediaSourceKind: NowPlayingSnapshot] = [:]
    @ObservationIgnored private var automationIssue: String?
    /// Demo state wins over every real source until cleared.
    @ObservationIgnored private var demo: NowPlayingSnapshot?
    @ObservationIgnored private var published: NowPlayingSnapshot?
    @ObservationIgnored private var inactivityTask: Task<Void, Never>?
    @ObservationIgnored private var artworkTask: Task<Void, Never>?
    @ObservationIgnored private var artworkBytes: Data?
    @ObservationIgnored private var reprobeTask: Task<Void, Never>?
    @ObservationIgnored private var reprobeDate: Date?

    init() {}

    // MARK: Lifecycle

    func start() {
        guard !isStarted else { return }
        isStarted = true
        if !didLocateAdapter {
            didLocateAdapter = true
            installation = AdapterInstallation.locate()
            if let installation {
                Log.media.notice("MediaRemote adapter found at \(installation.scriptURL.deletingLastPathComponent().path, privacy: .public)")
                let script = installation.scriptURL.path
                Task.detached(priority: .background) { AdapterOrphans.terminate(runningScript: script) }
            }
        }
        var next = MediaSourcePolicy(hasAdapter: installation != nil)
        next.setWebMediaEnabled(policy.webMediaEnabled)
        next.start()
        policy = next
        applyPolicy()
    }

    /// Tears down every source (child process, observers, Apple Events) and clears what is shown.
    /// Idempotent.
    func stop() {
        trackGapTask?.cancel()
        trackGapTask = nil
        isStarted = false
        adapterHealthy = false
        adapter?.stop()
        scriptable?.stop()
        playerWatcher?.stop()
        policy.stop()
        snapshots.removeAll()
        automationIssue = nil
        demo = nil
        scheduleReprobe(at: nil)
        setStatus(policy.status(automationIssue: nil))
        publish()
    }

    func setSuspended(_ suspended: Bool) {
        guard suspended != isSuspended else { return }
        isSuspended = suspended
        adapter?.setSuspended(suspended)
        scriptable?.setSuspended(suspended)
        guard !suspended, isStarted else { return }
        let now = Date.now
        if policy.reprobeIfDue(at: now) || policy.resumed(at: now) { applyPolicy() }
    }

    /// "Browser and video playback" in Settings. Kept across stop/start.
    func setWebMediaEnabled(_ enabled: Bool) {
        guard enabled != policy.webMediaEnabled else { return }
        policy.setWebMediaEnabled(enabled)
        applyPolicy()
    }

    // MARK: Intents

    func send(_ command: MediaCommand) {
        if let demo {
            self.demo = demo.applying(command, at: .now)
            publish()
            return
        }
        guard isStarted else { return }
        activeSource?.send(command)
    }

    /// Back (negative) or forward by `seconds` from where the track is now, within the track.
    func skip(by seconds: TimeInterval) {
        guard let clock else { return }
        var target = max(clock.position(at: .now) + seconds, 0)
        if let duration = item?.duration, duration > 0 { target = min(target, max(duration - 1, 0)) }
        send(.seek(target))
    }

    /// Pulls the position once (the expanded card calls this when it appears).
    func refreshPosition() {
        guard isStarted, demo == nil else { return }
        activeSource?.refreshPosition()
    }

    /// Opens the player (Music when nothing is playing, for the empty state's "Open Music").
    func openPlayerApp() {
        let bundleID = item?.bundleIdentifier ?? ScriptablePlayer.music.bundleID
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error {
                Log.media.error("could not open \(bundleID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Demo state for screenshots and URL-driven checks; nil returns to the real sources.
    func injectDemo(_ item: NowPlayingItem?, playing: Bool) {
        guard let item else {
            demo = nil
            publish()
            return
        }
        let now = Date.now
        let elapsed = demo.flatMap { $0.item == item ? $0.clock?.position(at: now) : nil }
            ?? min(31, (item.duration ?? 62) / 2)
        demo = NowPlayingSnapshot(item: item, isPlaying: playing,
                                  clock: PlaybackClock(elapsed: elapsed, at: now, rate: playing ? 1 : 0))
        // A paused demo counts as "just paused" so it is visible in the compact island.
        publish(treatPauseAsFresh: !playing)
    }

    // MARK: Sources

    /// The source whose snapshot is on screen: commands go to the player the user is looking at.
    /// While the adapter is healthy the scriptable source only listens (no pulls): Music's own
    /// reports then carry no position, so for the track the adapter reports too, the adapter's
    /// snapshot is shown — Music saying "playing" a moment before it showed its stale clock (the
    /// line jumped to where it last read it, then back).
    private var shownKind: MediaSourceKind? {
        if adapterHealthy, let adapter = snapshots[.adapter], let scriptable = snapshots[.scriptable],
           adapter.item.title == scriptable.item.title, adapter.item.artist == scriptable.item.artist {
            return .adapter
        }
        return MediaSourcePolicy.shown(adapter: snapshots[.adapter], scriptable: snapshots[.scriptable])
    }

    private var activeSource: (any MediaSource)? {
        switch shownKind {
        case .adapter: adapter
        case .scriptable: scriptable
        case nil: nil
        }
    }

    private func applyPolicy() {
        guard isStarted else { return }
        updatePlayerWatcher()
        if policy.runsAdapter, let installation {
            let source = adapter ?? makeSource(MediaRemoteAdapterSource(installation: installation), kind: .adapter)
            adapter = source
            source.start()
        } else if let adapter {
            adapter.stop()
            adapterHealthy = false
            snapshots[.adapter] = nil
            // The resident child is the expensive part; drop it with the source.
            self.adapter = nil
        }
        if policy.runsScriptable {
            let source = scriptable ?? makeSource(ScriptablePlayersSource(), kind: .scriptable)
            scriptable = source
            source.start()
            // The healthy adapter reports Music and Spotify with artwork and position: the
            // scriptable source only listens meanwhile, and pulls again the moment it goes.
            source.setPullsEnabled(!(policy.runsAdapter && adapterHealthy))
        } else if let scriptable {
            scriptable.stop()
            snapshots[.scriptable] = nil
            automationIssue = nil
        }
        scheduleReprobe(at: policy.reprobeAt)
        setStatus(policy.status(automationIssue: automationIssue))
        publish()
    }

    /// Watches for browsers and video apps only while their playback is wanted and readable.
    private func updatePlayerWatcher() {
        guard policy.wantsSystemPlayers else {
            playerWatcher?.stop()
            if policy.systemPlayerRunning { policy.setSystemPlayerRunning(false) }
            return
        }
        let watcher = playerWatcher ?? {
            let watcher = SystemPlayerWatcher()
            watcher.onChange = { [weak self] running in self?.systemPlayersChanged(running) }
            playerWatcher = watcher
            return watcher
        }()
        let running = watcher.start()
        if running != policy.systemPlayerRunning { policy.setSystemPlayerRunning(running) }
    }

    private func systemPlayersChanged(_ running: Bool) {
        guard isStarted, running != policy.systemPlayerRunning else { return }
        Log.media.notice("browser or video app \(running ? "open: reading system Now Playing" : "gone: adapter off", privacy: .public)")
        policy.setSystemPlayerRunning(running)
        applyPolicy()
    }

    private func makeSource<Source: MediaSource>(_ source: Source, kind: MediaSourceKind) -> Source {
        source.setSuspended(isSuspended)
        source.onEvent = { [weak self] event in self?.handle(event, from: kind) }
        return source
    }

    private func handle(_ event: MediaSourceEvent, from kind: MediaSourceKind) {
        guard isStarted else { return }
        switch event {
        case .nowPlaying(let snapshot):
            guard kind == .adapter ? policy.runsAdapter : policy.runsScriptable else { return }
            snapshots[kind] = snapshot
            publish()
        case .health(.running):
            adapterHealthy = true
            policy.adapterBecameHealthy(at: .now)
            applyPolicy()
        case .health(.gaveUp(let reason)):
            adapterHealthy = false
            Log.media.notice("browser playback unavailable for now, Music + Spotify continue: \(reason, privacy: .public)")
            policy.adapterGaveUp(at: .now)
            applyPolicy()
        case .health(.automationDenied(let player)):
            automationIssue = "Automation permission denied for \(player)"
            setStatus(policy.status(automationIssue: automationIssue))
        case .health(.automationRestored):
            automationIssue = nil
            setStatus(policy.status(automationIssue: nil))
        }
    }

    /// One pending wake-up for the next adapter re-probe, with generous tolerance so the system can
    /// coalesce it with other work.
    private func scheduleReprobe(at date: Date?) {
        guard date != reprobeDate else { return }
        reprobeTask?.cancel()
        reprobeTask = nil
        reprobeDate = date
        guard let date else { return }
        reprobeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, date.timeIntervalSinceNow)), tolerance: .seconds(30))
            guard !Task.isCancelled, let self else { return }
            self.reprobeDate = nil
            // While suspended the re-probe waits for the wake-up (`setSuspended(false)`).
            guard !self.isSuspended, self.policy.reprobeIfDue(at: .now) else { return }
            Log.media.info("re-probing the MediaRemote adapter")
            self.applyPolicy()
        }
    }

    // MARK: Publishing

    private func setStatus(_ new: MediaSourceStatus) {
        if status != new { status = new }
    }

    private func publish(treatPauseAsFresh: Bool = false) {
        let next = demo ?? (isStarted ? shownKind.flatMap { snapshots[$0] } : nil)
        let previous = published
        // Between two tracks a player reports nothing for a moment: while that lasts less than
        // `trackGapGrace`, the last track stays. Published at once, the pill left the notch and came
        // back a quarter of a second later (two transitions, Energy Impact ~3 at rest, measured).
        if next == nil, demo == nil, isStarted, previous?.isPlaying == true, !trackGapElapsed {
            if trackGapTask == nil {
                trackGapTask = Task { [weak self] in
                    try? await Task.sleep(for: Self.trackGapGrace)
                    guard !Task.isCancelled, let self else { return }
                    self.trackGapTask = nil
                    self.trackGapElapsed = true
                    self.publish()
                    self.trackGapElapsed = false
                }
            }
            return
        }
        trackGapTask?.cancel()
        trackGapTask = nil
        if let previous, let next, previous.isEquivalent(to: next), !treatPauseAsFresh { return }
        published = next

        if item != next?.item { item = next?.item }
        let playing = next?.isPlaying ?? false
        if isPlaying != playing { isPlaying = playing }
        if clock != next?.clock { clock = next?.clock }
        updateArtwork(for: next?.item)
        updateActivity(playing: playing, hasItem: next != nil,
                       justPaused: treatPauseAsFresh || (previous?.isPlaying == true && !playing))
    }

    private func updateActivity(playing: Bool, hasItem: Bool, justPaused: Bool) {
        if playing || (hasItem && justPaused) {
            inactivityTask?.cancel()
            inactivityTask = nil
            if !isActive { isActive = true }
        }
        if playing { return }
        guard hasItem else {
            inactivityTask?.cancel()
            inactivityTask = nil
            if isActive { isActive = false }
            return
        }
        guard justPaused else { return }
        inactivityTask = Task { [weak self] in
            try? await Task.sleep(for: Self.pauseGrace, tolerance: .seconds(1))
            guard !Task.isCancelled, let self else { return }
            self.inactivityTask = nil
            self.isActive = false
        }
    }

    /// How long a player may report no track at all before the pill goes (see `publish`).
    static let trackGapGrace: Duration = .milliseconds(1500)
    @ObservationIgnored private var trackGapTask: Task<Void, Never>?
    @ObservationIgnored private var trackGapElapsed = false

    /// How long the previous cover waits for the next track's before giving way to none.
    static let artworkGrace: Duration = .seconds(2)

    /// A track and the cover last seen with it.
    private struct Cover {
        let title: String
        let artist: String
        let album: String
        let bytes: Data

        func belongs(to item: NowPlayingItem) -> Bool {
            item.title == title && item.artist == artist && item.album == album
        }
    }

    @ObservationIgnored private var lastCover: Cover?

    /// A report of the same track without its cover keeps the cover it had. After a while that is
    /// what the sources send: the adapter, restarted after sleep, starts over with a full report
    /// that may come without the image, and when the island moves between the adapter and Music's
    /// own reports (which fetch no cover while the adapter runs) the cover was gone for good after
    /// `artworkGrace`, until the next track.
    private func updateArtwork(for item: NowPlayingItem?) {
        guard let item else { return updateArtwork(nil) }
        if let bytes = item.artworkData {
            if lastCover?.bytes != bytes {
                lastCover = Cover(title: item.title, artist: item.artist, album: item.album, bytes: bytes)
            }
            updateArtwork(bytes)
        } else {
            updateArtwork(lastCover.flatMap { $0.belongs(to: item) ? $0.bytes : nil })
        }
    }

    private func updateArtwork(_ bytes: Data?) {
        guard bytes != artworkBytes else { return }
        artworkBytes = bytes
        artworkTask?.cancel()
        artworkTask = nil
        guard let bytes else {
            // A new track often arrives before its cover: the old cover stays up for a moment in
            // case the new one follows (it then cross-fades in, `ArtworkView`), rather than
            // flashing the placeholder in between.
            artworkTask = Task { [weak self] in
                try? await Task.sleep(for: Self.artworkGrace)
                guard !Task.isCancelled, let self, self.artworkBytes == nil else { return }
                self.artworkTask = nil
                if self.artwork != nil { self.artwork = nil }
                if self.artworkColor != nil { self.artworkColor = nil }
                if !self.artworkPalette.isEmpty { self.artworkPalette = [] }
            }
            return
        }
        // The previous image stays up for the few milliseconds the decode takes instead of flashing
        // the placeholder.
        artworkTask = Task { [weak self] in
            let image = await ArtworkDecoder.decode(bytes)
            let color = if let image { await ArtworkDecoder.averageColor(image)?.accent } else { ArtworkColor?.none }
            let palette = if let image { await ArtworkDecoder.palette(image) } else { [ArtworkColor]() }
            let shown: CGImage? = if let image { await ArtworkDecoder.displayReady(image) } else { nil }
            guard !Task.isCancelled, let self, self.artworkBytes == bytes else { return }
            self.artworkTask = nil
            self.artwork = shown.map { NSImage(cgImage: $0, size: .zero) }
            if self.artworkColor != color { self.artworkColor = color }
            if self.artworkPalette != palette { self.artworkPalette = palette }
        }
    }
}
