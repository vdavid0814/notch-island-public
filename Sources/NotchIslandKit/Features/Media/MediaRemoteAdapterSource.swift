import AppKit

/// Now Playing for every app registered with the system (Music, Spotify, Safari, YouTube, VLC, IINA)
/// through the optional, vendored ungive/mediaremote-adapter.
///
/// One long-lived child — `/usr/bin/perl mediaremote-adapter.pl <framework> stream` — sits blocked on a
/// mach port and prints newline-delimited JSON only when something changes: no timer, no polling, no
/// permission prompt. Artwork and position are pushed too, so nothing is ever pulled.
///
/// Process discipline (each point is a legacy bug that must not come back):
/// * At most one child. Every spawn gets a new generation; callbacks from an older generation are
///   ignored, and a pending restart is a single cancellable `Task` that is the only path to a respawn.
/// * An intentional kill (stop/suspend) clears the termination handler first so it never counts as a
///   crash, and closes both pipe handlers (they are also cleared at EOF).
/// * Framing, JSON parsing and base64 artwork decoding run off the main actor; only typed updates hop.
final class MediaRemoteAdapterSource: MediaSource {
    var onEvent: ((MediaSourceEvent) -> Void)?

    private let installation: AdapterInstallation

    /// Browsers report in bursts (an ad ending, a seek, the next video loading its artwork). The
    /// adapter coalesces a burst into one line, so the app wakes and decodes artwork once per burst;
    /// short enough that a play/pause from the keyboard still feels immediate.
    static let debounceMilliseconds = 150

    private struct Child {
        let process: Process
        /// The write end of the watchdog's stdin. Nothing is ever written; when this process ends
        /// for any reason (quit, crash, `kill -9`) the kernel closes it and the watchdog takes the
        /// adapter down with it.
        let lifeline: FileHandle
        let output: FileHandle
        let errors: FileHandle
        let chunks: AsyncStream<Data>.Continuation
        let reader: Task<Void, Never>
    }

    private enum Phase {
        case idle
        case running(Child)
        case waitingToRestart(Task<Void, Never>)
    }

    private var phase = Phase.idle
    private var generation = 0
    private var isStarted = false
    private var isSuspended = false
    private var restartPolicy = AdapterRestartPolicy()
    private var reportedOutputThisRun = false
    private var track = AdapterTrackState()
    /// One-shot command children, retained until they exit.
    private var commands: [ObjectIdentifier: Process] = [:]
    /// Whether the player itself last said it was playing (not an optimistic guess of ours).
    private var reportedPlaying: Bool?
    /// Play or pause just sent, and until when a report saying otherwise is taken for a late one
    /// (MediaRemote often repeats the old state once right after a command: the button flipped back
    /// and forth, and the island fell back on Music's own clock for a moment).
    private var commandedPlaying: (playing: Bool, until: Date)?
    /// The player's own state held back meanwhile, applied when the time is up unless it has said
    /// what was asked for by then.
    private var heldPlaying: Bool?
    private var heldTask: Task<Void, Never>?
    /// How long a report contrary to a play or pause just sent is held back.
    static let commandSettle: TimeInterval = 1.5
    /// A command waiting for the player's answer, and its deadline.
    private var check: AdapterCommandCheck?
    private var checkTask: Task<Void, Never>?

    init(installation: AdapterInstallation) {
        self.installation = installation
    }

    // MARK: Lifecycle

    func start() {
        guard !isStarted else { return }
        isStarted = true
        spawnIfNeeded()
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        haltChild()
        disarm()
        wakeTask?.cancel()
        wakeTask = nil
        wokeFrom = nil
        wokeBrowser = nil
        restartPolicy = AdapterRestartPolicy()
        track = AdapterTrackState()
        reportedPlaying = nil
        release()
    }

    /// Nothing is visible while suspended, and the adapter re-sends a full snapshot as soon as it
    /// reconnects, so the child is killed outright rather than left running.
    func setSuspended(_ suspended: Bool) {
        guard suspended != isSuspended else { return }
        isSuspended = suspended
        if suspended {
            haltChild()
        } else {
            spawnIfNeeded()
        }
    }

    /// The position is pushed with every change; there is nothing to pull.
    func refreshPosition() {}

    // MARK: Commands

    /// Each command is a short-lived `perl … send <id>` child (~30 ms of CPU): the stream child does
    /// not read commands, and a user tap is rare enough that a second resident process is not worth it.
    func send(_ command: MediaCommand) {
        guard isStarted else { return }
        // Toggle becomes the explicit command for the state the user sees. A browser that paused a
        // while ago can drift from what MediaRemote last heard, and a toggle then "pauses" the
        // paused video: the play button did nothing.
        let command: MediaCommand = switch command {
        case .togglePlayPause: (reportedPlaying ?? track.isPlaying ?? false) ? .pause : .play
        default: command
        }
        let arguments = Self.arguments(for: command)
        let baseline = track
        switch command {
        case .play, .pause: hold(playing: command == .play)
        default: release()
        }
        if let current = track.snapshot {
            track.adopt(current.applying(command, at: .now))
            onEvent?(.nowPlaying(track.snapshot))
        }
        let id = runCommand(arguments)
        // Play, next and previous are checked: the player must answer, or the command is sent the
        // way it can take it (`AdapterCommandCheck`).
        if let kind = AdapterCommandCheck.Kind(command) {
            arm(AdapterCommandCheck(kind: kind, baseline: baseline, at: .now, commandID: id))
        } else {
            disarm()
        }
    }

    nonisolated static func arguments(for command: MediaCommand) -> [String] {
        switch command {
        // MediaRemote MRCommand values.
        case .play: ["send", "0"]
        case .pause: ["send", "1"]
        case .togglePlayPause: ["send", "2"]
        case .next: ["send", "4"]
        case .previous: ["send", "5"]
        // Microseconds.
        case .seek(let seconds): ["seek", String(Int((max(0, seconds) * 1_000_000).rounded()))]
        }
    }

    @discardableResult private func runCommand(_ arguments: [String]) -> ObjectIdentifier? {
        let process = Process()
        process.executableURL = AdapterInstallation.perlURL
        process.arguments = [installation.scriptURL.path, installation.frameworkURL.path] + arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let id = ObjectIdentifier(process)
        process.terminationHandler = Self.commandFinished(id: id, owner: self)
        do {
            try process.run()
            commands[id] = process
            return id
        } catch {
            Log.media.error("adapter command failed to launch: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func commandExited(_ id: ObjectIdentifier, status: Int32) {
        commands[id] = nil
        // MediaRemote refused it ("Failed to send command"): no point waiting for an answer.
        if status != 0, let check, check.commandID == id {
            Log.media.notice("adapter command refused (status \(status, privacy: .public))")
            followUp()
        }
    }

    // MARK: Command checks

    private func arm(_ new: AdapterCommandCheck) {
        checkTask?.cancel()
        check = new
        checkTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(new.patience), tolerance: .milliseconds(100))
            guard !Task.isCancelled else { return }
            self?.followUp()
        }
    }

    private func disarm() {
        checkTask?.cancel()
        checkTask = nil
        check = nil
    }

    /// The player did not answer in time (or refused): the next way of sending the command.
    private func followUp() {
        guard let current = check else { return }
        checkTask?.cancel()
        checkTask = nil
        check = nil
        guard let step = current.followUp() else {
            releaseWake()
            return
        }
        Log.media.notice("\(current.kind.name, privacy: .public) unanswered: sending \(step.arguments.joined(separator: " "), privacy: .public)")
        if step.wakesPlayer, let bundleID = track.parentBundleIdentifier ?? track.bundleIdentifier {
            wake(bundleID) { [weak self] in
                guard let self else { return }
                let id = self.runCommand(step.arguments)
                if var next = step.next {
                    next.commandID = id
                    self.arm(next)
                } else {
                    self.releaseWake()
                }
            }
            return
        }
        let id = runCommand(step.arguments)
        if var next = step.next {
            next.commandID = id
            arm(next)
        } else {
            releaseWake()
        }
    }

    // MARK: Waking a browser

    /// The app that had the focus before a browser was brought forward, to give it back.
    private var wokeFrom: NSRunningApplication?
    private var wokeBrowser: String?
    private var wakeTask: Task<Void, Never>?

    /// Brings the browser forward (its suspended page resumes), then sends. The focus goes back once
    /// the player answers or gives up (`releaseWake`).
    private func wake(_ bundleID: String, then send: @escaping () -> Void) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            send()
            return
        }
        let front = NSWorkspace.shared.frontmostApplication
        if front?.bundleIdentifier != bundleID {
            wokeFrom = front
            wokeBrowser = bundleID
        }
        Log.media.notice("waking \(bundleID, privacy: .public): its page did not answer")
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in }
        wakeTask?.cancel()
        wakeTask = Task { [weak self] in
            // The page resumes as its window comes on screen.
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, self != nil else { return }
            send()
        }
    }

    /// Gives the focus back to the app the user was in, unless they have moved on meanwhile.
    private func releaseWake() {
        wakeTask?.cancel()
        wakeTask = nil
        guard let previous = wokeFrom, let browser = wokeBrowser else { return }
        wokeFrom = nil
        wokeBrowser = nil
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == browser, !previous.isTerminated,
              let url = previous.bundleURL else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in }
    }

    // MARK: Child process

    private func spawnIfNeeded() {
        guard isStarted, !isSuspended, case .idle = phase else { return }
        generation &+= 1
        let generation = generation
        reportedOutputThisRun = false

        let process = Process()
        process.executableURL = AdapterInstallation.perlURL
        process.arguments = ["-e", Self.watchdog, "--", AdapterInstallation.perlURL.path] + [
            installation.scriptURL.path, installation.frameworkURL.path, "stream",
            "--debounce=\(Self.debounceMilliseconds)",
        ]
        let lifeline = Pipe()
        process.standardInput = lifeline
        // Background QoS: the adapter only relays what changed; it never needs a performance core.
        process.qualityOfService = .background
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let (chunks, continuation) = AsyncStream.makeStream(of: Data.self)
        let output = outputPipe.fileHandleForReading
        let errors = errorPipe.fileHandleForReading
        output.readabilityHandler = Self.chunkForwarder(continuation)
        errors.readabilityHandler = Self.errorLogger()
        process.terminationHandler = Self.childTerminated(generation: generation, owner: self)

        let reader = Task.detached(priority: .utility) { [weak self] in
            var framer = LineFramer()
            var dropped = 0
            for await chunk in chunks {
                for line in framer.append(chunk) {
                    guard let update = AdapterUpdate.parse(line) else { continue }
                    await self?.receive(update, generation: generation)
                }
                if framer.droppedLines != dropped {
                    dropped = framer.droppedLines
                    Log.media.error("adapter: skipped an oversized line (\(dropped, privacy: .public) so far)")
                }
            }
        }

        let child = Child(process: process, lifeline: lifeline.fileHandleForWriting, output: output, errors: errors,
                          chunks: continuation, reader: reader)
        do {
            try process.run()
        } catch {
            close(child)
            restartPolicy.launched(at: .now)
            handle(restartPolicy.exited(.launchFailed(error.localizedDescription), at: .now))
            return
        }
        phase = .running(child)
        restartPolicy.launched(at: .now)
        Log.media.notice("adapter stream started (pid \(process.processIdentifier, privacy: .public))")
    }

    private func receive(_ update: AdapterUpdate, generation: Int) {
        guard generation == self.generation, case .running = phase else { return }
        var update = update
        if let commanded = commandedPlaying, case .value(let playing) = update.playing {
            if playing == commanded.playing {
                release()
            } else if Date.now < commanded.until {
                // A late report of the state before the command: the rest of it stands.
                heldPlaying = playing
                update.playing = .value(commanded.playing)
            } else {
                release()
            }
        }
        track.apply(update, receivedAt: .now)
        if case .value(let playing) = update.playing { reportedPlaying = playing }
        if !update.isDiff, case .absent = update.playing { reportedPlaying = nil }
        if let check, check.isAnswered(by: update, now: track) {
            disarm()
            releaseWake()
        }
        // The snapshot goes first: when this run is a re-probe, the controller switches over on
        // `.running` and must already hold the adapter's state, or it would publish an empty frame.
        onEvent?(.nowPlaying(track.snapshot))
        if !reportedOutputThisRun, generation == self.generation {
            reportedOutputThisRun = true
            restartPolicy.receivedOutput()
            onEvent?(.health(.running))
        }
    }

    /// Holds back reports contrary to `playing` for `commandSettle`; then applies the player's own
    /// state if it said something else meanwhile and has not come round since.
    private func hold(playing: Bool) {
        release()
        commandedPlaying = (playing, Date.now.addingTimeInterval(Self.commandSettle))
        heldTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.commandSettle))
            guard !Task.isCancelled, let self else { return }
            self.heldTask = nil
            self.commandedPlaying = nil
            guard let held = self.heldPlaying else { return }
            self.heldPlaying = nil
            var update = AdapterUpdate()
            update.isDiff = true
            update.playing = .value(held)
            self.track.apply(update, receivedAt: .now)
            self.reportedPlaying = held
            self.onEvent?(.nowPlaying(self.track.snapshot))
        }
    }

    private func release() {
        heldTask?.cancel()
        heldTask = nil
        commandedPlaying = nil
        heldPlaying = nil
    }

    private func childExited(_ exit: AdapterExit, generation: Int) {
        guard generation == self.generation, case .running(let child) = phase else { return }
        close(child)
        phase = .idle
        handle(restartPolicy.exited(exit, at: .now))
    }

    private func handle(_ decision: AdapterRestartDecision) {
        switch decision {
        case .restart(let delay):
            Log.media.notice("adapter stopped, retrying in \(delay, privacy: .public) s")
            phase = .waitingToRestart(Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                self?.restartAfterBackoff()
            })
        case .giveUp(let reason):
            Log.media.error("adapter gave up: \(reason, privacy: .public)")
            phase = .idle
            track = AdapterTrackState()
            onEvent?(.health(.gaveUp(reason)))
        }
    }

    private func restartAfterBackoff() {
        guard case .waitingToRestart = phase else { return }
        phase = .idle
        spawnIfNeeded()
    }

    /// Stops the child or the pending restart without counting it as a failure.
    private func haltChild() {
        switch phase {
        case .idle:
            break
        case .waitingToRestart(let task):
            task.cancel()
        case .running(let child):
            child.process.terminationHandler = nil
            close(child)
            if child.process.isRunning { child.process.terminate() }
        }
        phase = .idle
        // Anything already in flight from the old child is now stale.
        generation &+= 1
    }

    private func close(_ child: Child) {
        try? child.lifeline.close()
        child.output.readabilityHandler = nil
        child.errors.readabilityHandler = nil
        child.chunks.finish()
        child.reader.cancel()
    }

    /// Runs the adapter as its child and ties its life to this app's: it ends the adapter when its
    /// stdin (the app's lifeline) reaches end-of-file or when it is itself terminated, and exits the
    /// way the adapter did (same status, same signal), so the restart policy sees the adapter's own
    /// exit. Without it an adapter outlived every quit and crash of the app, still subscribed to the
    /// system's Now Playing feed.
    static let watchdog = """
        my $pid = fork; exit 70 unless defined $pid;
        if ($pid == 0) { open STDIN, '<', '/dev/null'; exec { $ARGV[0] } @ARGV; exit 127 }
        sub finish { kill 'TERM', $pid; waitpid $pid, 0; exit 0 }
        $SIG{TERM} = $SIG{INT} = $SIG{HUP} = \\&finish;
        $SIG{CHLD} = sub {
            return unless waitpid($pid, 1) == $pid;
            my $status = $?;
            if (my $signal = $status & 127) { $SIG{TERM} = 'DEFAULT'; kill $signal, $$; sleep 1 }
            exit($status >> 8);
        };
        while (1) {
            my $read = sysread STDIN, my $buffer, 64;
            next if !defined $read && $!{EINTR};
            last;
        }
        finish();
        """

    // MARK: Off-main callbacks
    //
    // Built by nonisolated factories so the closures are provably not main-actor code: FileHandle and
    // Process call them on their own background threads.

    private nonisolated static func chunkForwarder(_ continuation: AsyncStream<Data>.Continuation) -> @Sendable (FileHandle) -> Void {
        { handle in
            let data = handle.availableData
            if data.isEmpty {
                // EOF: an uncleared handler keeps firing with empty reads.
                handle.readabilityHandler = nil
                continuation.finish()
            } else {
                continuation.yield(data)
            }
        }
    }

    /// Every stderr line is an error by the adapter's contract.
    private nonisolated static func errorLogger() -> @Sendable (FileHandle) -> Void {
        { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { Log.media.error("adapter stderr: \(text, privacy: .public)") }
        }
    }

    private nonisolated static func childTerminated(generation: Int, owner: MediaRemoteAdapterSource) -> @Sendable (Process) -> Void {
        { [weak owner] process in
            let exit: AdapterExit = process.terminationReason == .uncaughtSignal
                ? .signal(process.terminationStatus)
                : .status(process.terminationStatus)
            Task { @MainActor [weak owner] in owner?.childExited(exit, generation: generation) }
        }
    }

    private nonisolated static func commandFinished(id: ObjectIdentifier, owner: MediaRemoteAdapterSource) -> @Sendable (Process) -> Void {
        { [weak owner] process in
            let status = process.terminationStatus
            Task { @MainActor [weak owner] in owner?.commandExited(id, status: status) }
        }
    }
}

/// A command sent to a player through MediaRemote, waiting for the player's answer. Pure, so the
/// follow-ups are testable.
///
/// Browsers are the reason:
/// * A page in a background tab paused for a few minutes is suspended and answers nothing (play,
///   toggle, seek, the keyboard's play key) until its window comes forward. So a browser's
///   unanswered command is sent again with the browser woken (`Step.wakesPlayer`): brought forward
///   for a moment, then the user's app gets the focus back.
/// * A page answers only the commands it registered (YouTube has "next" for its autoplay queue
///   but rarely "previous"). An unanswered next goes to the end of this video (a web player moves
///   on to the next one), an unanswered previous back to its start — tried first, since a seek
///   needs no window to come forward, and only then the wake.
/// * Other players get one more play, never a toggle (a player that did start but did not say so
///   would stop).
nonisolated struct AdapterCommandCheck: Sendable, Equatable {
    nonisolated enum Kind: Sendable, Equatable {
        case play, next, previous

        init?(_ command: MediaCommand) {
            switch command {
            case .play: self = .play
            case .next: self = .next
            case .previous: self = .previous
            default: return nil
            }
        }

        var command: MediaCommand {
            switch self {
            case .play: .play
            case .next: .next
            case .previous: .previous
            }
        }

        var name: String {
            switch self {
            case .play: "play"
            case .next: "next"
            case .previous: "previous"
            }
        }
    }

    /// What was just sent: the command itself, or the seek standing in for next or previous.
    nonisolated enum Stage: Sendable, Equatable {
        case command
        case seek(TimeInterval)
    }

    /// One follow-up: what to send, whether the player must be woken first, and the check after it.
    struct Step: Sendable, Equatable {
        var arguments: [String]
        var wakesPlayer = false
        var next: AdapterCommandCheck?
    }

    var kind: Kind
    var stage = Stage.command
    var title: String?
    var uniqueIdentifier: String?
    var elapsed: TimeInterval?
    var duration: TimeInterval?
    /// The player is a browser (its pages can be suspended).
    var isBrowser = false
    /// The browser has been brought forward for this command.
    var woke = false
    /// The stand-in seek has been tried since the last wake.
    var seekTried = false
    var attempt = 1
    var commandID: ObjectIdentifier?

    init(kind: Kind, baseline: AdapterTrackState, at now: Date, commandID: ObjectIdentifier? = nil) {
        self.kind = kind
        title = baseline.title
        uniqueIdentifier = baseline.uniqueIdentifier
        duration = baseline.duration
        elapsed = baseline.snapshot?.clock?.position(at: now)
        isBrowser = SystemPlayers.isBrowser(baseline.parentBundleIdentifier ?? baseline.bundleIdentifier)
        self.commandID = commandID
    }

    /// How long the player gets to answer (a browser loading the next video takes longer; a woken
    /// one needs a moment to resume its page).
    var patience: Double {
        if case .seek = stage { return 1.5 }
        return (kind == .play ? 1.2 : 2.5) + (woke ? 1 : 0)
    }

    /// The player's report that the command (or the seek standing in for it) worked.
    func isAnswered(by update: AdapterUpdate, now state: AdapterTrackState) -> Bool {
        if case .seek(let target) = stage {
            if movedToAnotherItem(state) { return true }
            if case .value(let position) = update.elapsed { return abs(position - target) < 3 }
            return false
        }
        switch kind {
        case .play:
            if case .value(true) = update.playing { return true }
            return false
        case .next:
            return movedToAnotherItem(state)
        case .previous:
            if movedToAnotherItem(state) { return true }
            if case .value(let position) = update.elapsed, position < 3, (elapsed ?? 0) >= 3 { return true }
            return false
        }
    }

    private func movedToAnotherItem(_ state: AdapterTrackState) -> Bool {
        if let uniqueIdentifier, let now = state.uniqueIdentifier { return now != uniqueIdentifier }
        return state.title != title
    }

    /// Where next or previous stand in by seeking (nil: no stand-in — a live stream, or already at
    /// the start).
    var seekTarget: TimeInterval? {
        switch kind {
        case .play: nil
        case .next: duration.flatMap { $0 > 1 ? $0 - 0.25 : nil }
        case .previous: (elapsed ?? 0) >= 3 ? 0 : nil
        }
    }

    /// The next way to send it (nil: nothing more to try).
    func followUp() -> Step? {
        switch kind {
        case .play:
            if isBrowser {
                guard !woke else { return nil }
                return Step(arguments: MediaRemoteAdapterSource.arguments(for: .play), wakesPlayer: true, next: woken())
            }
            guard attempt < 2 else { return nil }
            var again = self
            again.attempt += 1
            return Step(arguments: MediaRemoteAdapterSource.arguments(for: .play), next: again)
        case .next, .previous:
            if !seekTried, let target = seekTarget {
                var seek = self
                seek.stage = .seek(target)
                seek.seekTried = true
                return Step(arguments: MediaRemoteAdapterSource.arguments(for: .seek(target)), next: seek)
            }
            guard isBrowser, !woke else { return nil }
            return Step(arguments: MediaRemoteAdapterSource.arguments(for: kind.command), wakesPlayer: true, next: woken())
        }
    }

    private func woken() -> AdapterCommandCheck {
        var next = self
        next.woke = true
        next.stage = .command
        next.seekTried = false
        return next
    }
}
