import AppKit
import ApplicationServices
import os

/// Swallows the volume/brightness media keys so macOS never draws its centre-screen OSD, and hands
/// them to the main actor to be applied by us instead.
///
/// Suppressing the OSD is only possible by keeping the key event from reaching the system (the
/// alternative, unloading OSDUIHelper, needs SIP off). That takes an *active* `CGEventTap` on
/// `NX_SYSDEFINED` (a listen-only tap cannot swallow), which requires Accessibility trust.
///
/// The tap sits in the system input path: anything slower than microseconds stalls keyboard and
/// mouse for every app. So it runs on its own thread and run loop, the callback only decodes, reads a
/// lock-protected policy and returns; the action reaches the main actor asynchronously.
///
/// Lifecycle: one owner (the main actor), a generation per start. The state is reported `.active`
/// only after the thread has actually installed the tap; late reports from an older generation are
/// ignored; a stop that races the thread's start-up is honoured (see `MediaKeyTapShared`).
@MainActor final class MediaKeyInterceptor {
    private(set) var state: InterceptionState = .off {
        didSet { if state != oldValue { onStateChange?(state) } }
    }
    var onStateChange: ((InterceptionState) -> Void)?
    /// A key the policy allowed, key-down only (and no mute repeats).
    var onKey: ((MediaKeyEvent) -> Void)?

    private let shared = MediaKeyTapShared()
    private var generation: UInt64 = 0
    private var isRunning = false

    func setPolicy(_ policy: MediaKeyPolicy) {
        shared.setPolicy(policy)
    }

    /// Idempotent. Never prompts: without trust it only reports `.needsPermission` (prompting is
    /// PermissionCenter's job, at most once per launch).
    /// Set between `start()` and `stop()`: the owner wants the tap, even while it is being restarted.
    private var wantsRunning = false
    private var restart: Task<Void, Never>?
    private var lastRestart: ContinuousClock.Instant?
    static let restartInterval: Duration = .seconds(30)

    func start() {
        wantsRunning = true
        guard !isRunning else { return }
        guard AXIsProcessTrusted() else {
            state = .needsPermission
            return
        }
        isRunning = true
        generation &+= 1
        let generation = generation
        shared.begin(generation: generation)

        let deliver: @Sendable (MediaKeyEvent) -> Void = { [weak self] event in
            Task { @MainActor in self?.onKey?(event) }
        }
        let report: @Sendable (TapReport) -> Void = { [weak self] report in
            Task { @MainActor in self?.received(report) }
        }
        let shared = shared
        let thread = Thread {
            MediaKeyTapThread.run(generation: generation, shared: shared, deliver: deliver, report: report)
        }
        thread.name = "com.davidvarga.notchisland.mediakeys"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    /// Idempotent. The thread tears the tap down itself (it created it); we only ask it to stop.
    func stop() {
        wantsRunning = false
        restart?.cancel()
        restart = nil
        retries.reset()
        if isRunning {
            isRunning = false
            generation &+= 1
            shared.end()
            Log.levels.notice("media key tap stopped — system HUD restored")
        }
        state = .off
    }

    private func received(_ report: TapReport) {
        guard report.generation == generation, isRunning else { return }
        switch report {
        case .installed:
            Log.levels.notice("media key tap armed — system HUD suppressed")
            retries.reset()
            state = .active
        case .failed:
            isRunning = false
            shared.end()
            state = .failed("The media-key event tap could not be created.")
            if let delay = scheduleRetry() {
                Log.levels.notice("media key tap refused: trying again in \(delay.components.seconds, privacy: .public) s")
            } else {
                Log.levels.error("media key tap could not be created")
            }
        case .ended:
            Log.levels.error("media key tap run loop ended unexpectedly")
            isRunning = false
            shared.end()
            state = .failed("The media-key event tap stopped unexpectedly.")
            scheduleRestart()
        }
    }

    /// A refused tap is tried again (`KeyTapRetries`): the wait, or nil when it is left failed.
    private var retries = KeyTapRetries()

    private func scheduleRetry() -> Duration? {
        guard wantsRunning, restart == nil, let delay = retries.next() else { return nil }
        restart = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled else { return }
            self.restart = nil
            guard self.wantsRunning, !self.isRunning else { return }
            self.start()
        }
        return delay
    }

    /// A permission changed: a failed tap gets a fresh set of attempts.
    func retryIfFailed() {
        guard wantsRunning, !isRunning, case .failed = state else { return }
        restart?.cancel()
        restart = nil
        retries.reset()
        start()
    }

    /// A permission Reset is under way: the tap will be refused until the user allows the app again.
    func expectRefusals() {
        retries.expectRefusals()
    }

    /// One restart a second after an unexpected end, at most once per `restartInterval`, so a tap
    /// that keeps dying cannot turn into a restart loop.
    private func scheduleRestart() {
        let now = ContinuousClock.now
        guard wantsRunning, restart == nil,
              lastRestart.map({ now - $0 >= Self.restartInterval }) ?? true else { return }
        lastRestart = now
        restart = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, !Task.isCancelled else { return }
            self.restart = nil
            guard self.wantsRunning, !self.isRunning else { return }
            Log.levels.notice("media key tap restarting after an unexpected end")
            self.start()
        }
    }
}

/// What the tap thread tells the main actor, tagged with the generation it belongs to.
nonisolated private enum TapReport: Sendable {
    case installed(UInt64)
    case failed(UInt64)
    case ended(UInt64)

    var generation: UInt64 {
        switch self {
        case .installed(let g), .failed(let g), .ended(let g): g
        }
    }
}

/// State shared between the main actor and the tap thread, behind one unfair lock.
///
/// Start/stop protocol: `begin(generation:)` marks a generation active; the thread `attach`es its run
/// loop only if its generation is still active (so a stop issued before the thread got going makes it
/// clean up and exit instead of running untracked); `end()` deactivates and asks an attached run loop
/// to stop with `CFRunLoopPerformBlock` + `CFRunLoopWakeUp`, which — unlike `CFRunLoopStop` — is not
/// lost when the thread has attached but not yet entered `CFRunLoopRunInMode`.
nonisolated private final class MediaKeyTapShared: Sendable {
    private struct State {
        var policy = MediaKeyPolicy.passThrough
        var activeGeneration: UInt64?
        var runLoop: CFRunLoop?
    }

    /// `uncheckedState` because `CFRunLoop` is not annotated `Sendable`; the only calls made on it
    /// from another thread (`CFRunLoopPerformBlock`, `CFRunLoopWakeUp`) are documented thread-safe.
    private let lock = OSAllocatedUnfairLock(uncheckedState: State())

    /// Hot path: called from the tap callback for every system-defined event.
    var policy: MediaKeyPolicy {
        lock.withLockUnchecked { $0.policy }
    }

    func setPolicy(_ policy: MediaKeyPolicy) {
        lock.withLockUnchecked { $0.policy = policy }
    }

    func begin(generation: UInt64) {
        lock.withLockUnchecked {
            $0.activeGeneration = generation
            $0.runLoop = nil
        }
    }

    func end() {
        let runLoop = lock.withLockUnchecked { state -> CFRunLoop? in
            state.activeGeneration = nil
            defer { state.runLoop = nil }
            return state.runLoop
        }
        guard let runLoop else { return }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) {
            CFRunLoopStop(CFRunLoopGetCurrent())
        }
        CFRunLoopWakeUp(runLoop)
    }

    /// Tap thread: publish our run loop if this generation is still wanted.
    func attach(_ runLoop: CFRunLoop, generation: UInt64) -> Bool {
        lock.withLockUnchecked { state in
            guard state.activeGeneration == generation else { return false }
            state.runLoop = runLoop
            return true
        }
    }

    func isActive(_ generation: UInt64) -> Bool {
        lock.withLockUnchecked { $0.activeGeneration == generation }
    }

    /// Tap thread, on exit: forget our run loop unless a newer generation replaced it already.
    func detach(generation: UInt64) {
        lock.withLockUnchecked { state in
            if state.activeGeneration == generation { state.runLoop = nil }
        }
    }
}

/// Everything that runs on the tap thread.
nonisolated private enum MediaKeyTapThread {
    /// The thread body: create, install, run, tear down — all on this one thread.
    static func run(
        generation: UInt64,
        shared: MediaKeyTapShared,
        deliver: @escaping @Sendable (MediaKeyEvent) -> Void,
        report: @Sendable (TapReport) -> Void
    ) {
        let session = TapSession(shared: shared, deliver: deliver)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            return Unmanaged<TapSession>.fromOpaque(refcon).takeUnretainedValue().handle(type, event)
        }
        // `session` outlives every callback: the port is invalidated below, on this thread, before
        // `withExtendedLifetime` ends, and callbacks only ever run inside this thread's run loop.
        withExtendedLifetime(session) {
            guard let port = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: CGEventMask(1) << CGEventMask(MediaKeyDecoder.systemDefinedEventType),
                callback: callback,
                userInfo: Unmanaged.passUnretained(session).toOpaque()
            ) else {
                report(.failed(generation))
                return
            }
            guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0),
                  let runLoop = CFRunLoopGetCurrent()
            else {
                CFMachPortInvalidate(port)
                report(.failed(generation))
                return
            }
            session.port = port
            CFRunLoopAddSource(runLoop, source, .commonModes)
            CGEvent.tapEnable(tap: port, enable: true)

            var endedOnItsOwn = false
            if shared.attach(runLoop, generation: generation) {
                report(.installed(generation))
                // No timeout: a finite one would wake this thread periodically forever.
                while shared.isActive(generation) {
                    if CFRunLoopRunInMode(.defaultMode, .greatestFiniteMagnitude, false) == .finished {
                        endedOnItsOwn = shared.isActive(generation)
                        break
                    }
                }
            }

            CGEvent.tapEnable(tap: port, enable: false)
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
            CFMachPortInvalidate(port)
            session.port = nil
            shared.detach(generation: generation)
            if endedOnItsOwn { report(.ended(generation)) }
        }
    }
}

/// Per-tap context handed to the C callback. Confined to the tap thread: created, used and dropped
/// there, which is why it needs no `Sendable` conformance.
nonisolated private final class TapSession {
    let shared: MediaKeyTapShared
    let deliver: @Sendable (MediaKeyEvent) -> Void
    var port: CFMachPort?
    private var presses = MediaKeyPressTracker()

    init(shared: MediaKeyTapShared, deliver: @escaping @Sendable (MediaKeyEvent) -> Void) {
        self.shared = shared
        self.deliver = deliver
    }

    /// Returns `nil` to swallow. Must return within microseconds.
    func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // The system switches off a tap it considers slow, or after certain input; these arrive
            // even though they are not in the mask. Re-enabling is the documented recovery, but not
            // once the permission is gone (`CommandSpaceTap.mayReenable`).
            guard CommandSpaceTap.mayReenable(after: type) else {
                Log.levels.error("media key tap timed out without Accessibility: left off")
                return Unmanaged.passUnretained(event)
            }
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            Log.levels.notice("media key tap re-enabled after \(type == .tapDisabledByTimeout ? "a timeout" : "user input", privacy: .public)")
            return Unmanaged.passUnretained(event)
        default:
            break
        }
        guard type.rawValue == MediaKeyDecoder.systemDefinedEventType else { return Unmanaged.passUnretained(event) }
        // Read straight from the CGEvent: making an NSEvent of it here, off the main thread, runs
        // HIToolbox's Caps Lock handling, which asserts the main queue and crashed the app on a Caps
        // Lock press (crash reports, v0.3.1 and v0.3.3).
        let (subtype, data1) = MediaKeyDecoder.fields(of: event)
        let key = MediaKeyDecoder.decode(subtype: subtype, data1: data1, flags: event.flags)
        guard let key else { return Unmanaged.passUnretained(event) }

        switch presses.action(for: key, policy: shared.policy) {
        case .passThrough:
            return Unmanaged.passUnretained(event)
        case .swallow:
            return nil
        case .handle:
            deliver(key)
            return nil
        }
    }
}
