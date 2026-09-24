import Foundation

nonisolated enum MediaSourceKind: Sendable, Hashable {
    /// ungive/mediaremote-adapter: every app registered with the system, artwork and position pushed.
    case adapter
    /// Music + Spotify through their distributed notifications, with a few Apple Events.
    case scriptable
}

nonisolated enum MediaSourceHealth: Sendable, Equatable {
    /// The adapter produced its first valid line for this run: it works.
    case running
    /// The adapter stopped restarting itself; the controller falls back and re-probes later.
    case gaveUp(String)
    /// A player refused Apple Events (-1743). Carries the player's display name.
    case automationDenied(String)
    /// Apple Events work again for every player that had refused them.
    case automationRestored
}

nonisolated enum MediaSourceEvent: Sendable, Equatable {
    /// nil = nothing playing.
    case nowPlaying(NowPlayingSnapshot?)
    case health(MediaSourceHealth)
}

/// A way of learning what is playing and of controlling it.
///
/// Events are delivered synchronously on the main actor through `onEvent`, set once by the
/// controller. Synchronous delivery keeps an optimistic update atomic with the command that caused it
/// and lets `stop()` guarantee that nothing arrives afterwards. Sources do their slow work (processes,
/// Apple Events, downloads) off the main actor and come back through `await` or a single explicit hop.
protocol MediaSource: AnyObject {
    var onEvent: ((MediaSourceEvent) -> Void)? { get set }
    /// Idempotent. Does no work while suspended; resumes when `setSuspended(false)` follows.
    func start()
    /// Idempotent; tears down every process, observer and in-flight pull. No events afterwards.
    func stop()
    func setSuspended(_ suspended: Bool)
    func send(_ command: MediaCommand)
    /// Pull the position once, where the source cannot get it pushed.
    func refreshPosition()
}

/// Which sources run and whose output is shown. Pure so the adaptation and recovery are testable.
///
/// Each kind of player is read the cheapest way it can be:
/// * **Music and Spotify** broadcast every change on their own; the scriptable source only listens,
///   so it runs whenever Now Playing is on and costs nothing while nothing changes.
/// * **Browsers and video apps** (YouTube in Safari, Chrome, IINA, QuickTime, …) have no such
///   broadcast. They are read from the system's Now Playing through the adapter, a resident child
///   process, which therefore runs only while the user wants web media *and* one of those apps is
///   open (`SystemPlayers`). Quitting the last browser stops it; opening one starts it again.
///
/// When both have something, whichever is playing is shown (`shown(adapter:scriptable:)`), so
/// switching from a YouTube video to Spotify follows the user without any setting.
///
/// When the adapter gives up, it is re-probed after a cooldown that doubles with each consecutive
/// give-up (a failure is often caused by a transient state such as a sleep transition, so it is never
/// written off for the whole session). Music and Spotify keep working meanwhile.
nonisolated struct MediaSourcePolicy: Sendable, Equatable {
    static let baseCooldown: TimeInterval = 300
    static let maxCooldown: TimeInterval = 3600
    /// An adapter that ran this long before giving up had a healthy run: its give-up history resets.
    static let healthyRunDuration: TimeInterval = 600

    let hasAdapter: Bool
    private(set) var isStarted = false
    /// The user's "Browser and video playback" preference.
    private(set) var webMediaEnabled = true
    /// A browser or video app is open (`SystemPlayerWatcher`).
    private(set) var systemPlayerRunning = false
    private(set) var consecutiveGiveUps = 0
    /// While set, the adapter is cooling down after a give-up.
    private(set) var reprobeAt: Date?
    private var healthySince: Date?
    private var lastGiveUp: Date?

    init(hasAdapter: Bool) { self.hasAdapter = hasAdapter }

    static func cooldown(afterGiveUps count: Int) -> TimeInterval {
        min(maxCooldown, baseCooldown * pow(2, Double(max(0, count - 1))))
    }

    /// Music and Spotify: always, while Now Playing is on.
    var runsScriptable: Bool { isStarted }

    /// The system's Now Playing: only while it can show something the scriptable source cannot.
    var runsAdapter: Bool {
        isStarted && wantsSystemPlayers && systemPlayerRunning && reprobeAt == nil
    }

    /// Whether browsers and video apps are worth watching for at all.
    var wantsSystemPlayers: Bool { isStarted && hasAdapter && webMediaEnabled }

    mutating func start() {
        isStarted = true
    }

    /// Everything but the user's preference resets.
    mutating func stop() {
        let enabled = webMediaEnabled
        self = MediaSourcePolicy(hasAdapter: hasAdapter)
        webMediaEnabled = enabled
    }

    mutating func setWebMediaEnabled(_ enabled: Bool) {
        webMediaEnabled = enabled
    }

    mutating func setSystemPlayerRunning(_ running: Bool) {
        systemPlayerRunning = running
    }

    mutating func adapterBecameHealthy(at now: Date) {
        guard runsAdapter else { return }
        healthySince = now
    }

    mutating func adapterGaveUp(at now: Date) {
        guard runsAdapter else { return }
        if let healthySince, now.timeIntervalSince(healthySince) >= Self.healthyRunDuration {
            consecutiveGiveUps = 0
        }
        healthySince = nil
        consecutiveGiveUps += 1
        lastGiveUp = now
        reprobeAt = now.addingTimeInterval(Self.cooldown(afterGiveUps: consecutiveGiveUps))
    }

    /// True when the cooldown just ended (the adapter may run again).
    mutating func reprobeIfDue(at now: Date) -> Bool {
        guard isStarted, let reprobeAt, now >= reprobeAt else { return false }
        self.reprobeAt = nil
        return true
    }

    /// Waking up is a natural moment to retry early (a crash is often caused by the sleep itself), but
    /// never sooner than `baseCooldown` after the last give-up, so frequent display sleeps cannot turn
    /// into a restart loop.
    mutating func resumed(at now: Date) -> Bool {
        guard isStarted, reprobeAt != nil, let lastGiveUp,
              now.timeIntervalSince(lastGiveUp) >= Self.baseCooldown else { return false }
        reprobeAt = nil
        return true
    }

    /// Whose snapshot the island shows: a playing one before a paused one, and the system's Now
    /// Playing before the scriptable source when both are equal (it is the system's own answer to
    /// "what is playing", with artwork and position pushed).
    static func shown(adapter: NowPlayingSnapshot?, scriptable: NowPlayingSnapshot?) -> MediaSourceKind? {
        if adapter?.isPlaying == true { return .adapter }
        if scriptable?.isPlaying == true { return .scriptable }
        if adapter != nil { return .adapter }
        if scriptable != nil { return .scriptable }
        return nil
    }

    /// What Settings shows.
    func status(automationIssue: String?) -> MediaSourceStatus {
        guard isStarted else { return .off }
        let web: WebMediaStatus
        if !webMediaEnabled {
            web = .off
        } else if !hasAdapter {
            web = .notInstalled
        } else if reprobeAt != nil {
            web = .retrying
        } else {
            web = systemPlayerRunning ? .listening : .standby
        }
        return .on(web: web, automationIssue: automationIssue)
    }
}
