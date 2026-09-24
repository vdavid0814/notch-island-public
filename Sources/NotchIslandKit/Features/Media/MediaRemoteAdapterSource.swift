import Foundation

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
        restartPolicy = AdapterRestartPolicy()
        track = AdapterTrackState()
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
        let arguments: [String] = switch command {
        // MediaRemote MRCommand values.
        case .play: ["send", "0"]
        case .pause: ["send", "1"]
        case .togglePlayPause: ["send", "2"]
        case .next: ["send", "4"]
        case .previous: ["send", "5"]
        // Microseconds.
        case .seek(let seconds): ["seek", String(Int((max(0, seconds) * 1_000_000).rounded()))]
        }
        if let current = track.snapshot {
            track.adopt(current.applying(command, at: .now))
            onEvent?(.nowPlaying(track.snapshot))
        }
        runCommand(arguments)
    }

    private func runCommand(_ arguments: [String]) {
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
        } catch {
            Log.media.error("adapter command failed to launch: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func commandExited(_ id: ObjectIdentifier) {
        commands[id] = nil
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
        track.apply(update, receivedAt: .now)
        // The snapshot goes first: when this run is a re-probe, the controller switches over on
        // `.running` and must already hold the adapter's state, or it would publish an empty frame.
        onEvent?(.nowPlaying(track.snapshot))
        if !reportedOutputThisRun, generation == self.generation {
            reportedOutputThisRun = true
            restartPolicy.receivedOutput()
            onEvent?(.health(.running))
        }
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
        { [weak owner] _ in
            Task { @MainActor [weak owner] in owner?.commandExited(id) }
        }
    }
}
