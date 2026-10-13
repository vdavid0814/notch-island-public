import AppKit
import Synchronization

/// How long a lowered main thread went without the processor, from readings of its CPU time.
///
/// At background quality of service a thread runs on the efficiency cores when they are free, and
/// hardly at all when the Mac is busy: with all ten cores taken by a build the same 2 s of work
/// took 10 s (measured, `Scripts/perf/thrift_watch.c`). Each reading says how much of the interval
/// the thread ran and whether it wanted to; what it missed while it wanted to adds up, fading
/// (`fade` a reading) so that the efficiency cores' ordinary sharing never does.
nonisolated struct StallMeter: Sendable, Equatable {
    enum Verdict: String, Sendable { case starved, blocked }

    /// Missed time, faded, past which the thread counts as starved: two readings with nothing, or
    /// four with a third of the processor.
    static let starvedLimit: TimeInterval = 0.05
    /// Unbroken time blocked (a page read in, an answer from another process awaited) past which
    /// the wait itself is taken as slowed by the low priority.
    static let blockedLimit: TimeInterval = 0.25
    static let fade = 0.8

    private(set) var starved: TimeInterval = 0
    private(set) var blocked: TimeInterval = 0

    /// One reading: over `interval` the thread ran for `ran`, and was `runnable` at its end.
    mutating func note(interval: TimeInterval, ran: TimeInterval, runnable: Bool) -> Verdict? {
        let missed = max(0, interval - max(0, ran))
        if runnable {
            starved = starved * Self.fade + missed
            blocked = 0
        } else {
            starved *= Self.fade
            blocked += missed
        }
        if starved >= Self.starvedLimit { return .starved }
        if blocked >= Self.blockedLimit { return .blocked }
        return nil
    }
}

/// Watches the main thread from outside while `MainThrift` has it at background quality of
/// service, and gives it its priority back the moment that goes wrong.
///
/// The main thread cannot do this for itself: what would raise it (`MainThrift.raise`, the timer
/// that ends a stretch) runs on the very thread that is not getting the processor. On a Mac whose
/// cores and memory were taken by builds, lowered turns of 0.1 s took 2 s and more, and the island
/// stood still meanwhile (16 hang reports from one Mac, October 10–13). `SystemLoad` keeps the
/// lowering from starting on such a Mac; this catches what that cannot foresee — a build that
/// starts during the turn, a load the one-minute average has not caught up with.
///
/// Every 30 ms while the thread is lowered and inside a turn, a thread of its own reads the main
/// thread's CPU time (`StallMeter`). Starved or blocked, or — for work nobody is at the Mac for —
/// the pointer arriving at the island, the main thread gets an override to user-interactive at
/// once, the stretch ends with its turn, and nothing is lowered for a while. A key the island
/// answers does the same from its event tap's thread (`demand`). At rest it does nothing: no
/// timer, two atomic reads a run-loop turn.
nonisolated enum ThriftWatch {
    static let interval: TimeInterval = 0.03
    /// Nothing is lowered for this long after a stall: the Mac is busy, whatever its load average.
    static let holdOffAfterStall: TimeInterval = 30
    /// After the pointer came: what the user starts next has the thread to itself.
    static let holdOffAfterPointer: TimeInterval = 2

    /// `NI_THRIFT_UNGUARDED=1` (measuring only, `Scripts/perf/hang.py`): no watch and no gate, the
    /// main thread lowered whatever the Mac is doing — what the guard is compared against.
    static let isOff = ProcessInfo.processInfo.environment["NI_THRIFT_UNGUARDED"] == "1"

    private struct State {
        var thread: pthread_t?
        var port: thread_t = 0
        var isLowered = false
        var yieldsToPointer = false
        var isTicking = false
        var turnStart: CFTimeInterval = 0
        var lastTick: CFTimeInterval = 0
        var lastCPU: TimeInterval = 0
        var meter = StallMeter()
        var override: pthread_override_t?
        /// Where the pointer counts as arriving, in Quartz display coordinates (top-left origin).
        var zone = CGRect.null
    }

    private static let state = Mutex(State())
    private static let isLowered = Atomic<Bool>(false)
    private static let isRescued = Atomic<Bool>(false)
    private static let heldOffUntil = Atomic<UInt64>(0)
    private static let rescueCount = Atomic<Int>(0)
    private static let queue = DispatchQueue(label: "com.davidvarga.notchisland.thrift-watch", qos: .userInteractive)

    /// Nothing may be lowered now: a stall or the pointer ended a stretch a moment ago.
    static var isHeldOff: Bool {
        CACurrentMediaTime() < Double(bitPattern: heldOffUntil.load(ordering: .relaxed))
    }

    /// Stretches ended early since launch (`demo/state`, the tests).
    static var rescues: Int { rescueCount.load(ordering: .relaxed) }

    /// The notch and a little around it, in AppKit's global coordinates: the pointer there is
    /// about to open the island. `primaryTop` is the first screen's top edge (Quartz's origin).
    static func setPointerZone(notch: CGRect, primaryTop: CGFloat) {
        let reach = notch.insetBy(dx: -70, dy: 0)
        let zone = CGRect(x: reach.minX, y: primaryTop - reach.maxY, width: reach.width, height: reach.height + 36)
        state.withLock { $0.zone = zone }
    }

    // MARK: From the main thread

    /// The main thread has just been lowered. `yieldsToPointer`, given at a stretch's start, for
    /// work nobody is at the Mac for; nil from the re-lowerings inside a stretch.
    static func lowered(yieldsToPointer: Bool? = nil) {
        guard !isOff else { return }
        if yieldsToPointer == nil, isLowered.load(ordering: .relaxed) { return }
        installObservers()
        let now = CACurrentMediaTime()
        let starts = state.withLock { state -> Bool in
            if state.thread == nil {
                state.thread = pthread_self()
                state.port = pthread_mach_thread_np(pthread_self())
            }
            if let yieldsToPointer { state.yieldsToPointer = yieldsToPointer }
            if !state.isLowered {
                state.isLowered = true
                state.meter = StallMeter()
            }
            if state.turnStart == 0 { beginTurn(&state, now) }
            guard !state.isTicking else { return false }
            state.isTicking = true
            return true
        }
        isLowered.store(true, ordering: .relaxed)
        if starts { queue.asyncAfter(deadline: .now() + interval) { tick() } }
    }

    /// The main thread is back at its own priority.
    static func raised() {
        guard isLowered.exchange(false, ordering: .relaxed) else { return }
        state.withLock { state in
            state.isLowered = false
            state.yieldsToPointer = false
            state.turnStart = 0
        }
    }

    private static let observersInstalled = Atomic<Bool>(false)

    /// Where the main thread's turns begin and end, and where a rescued stretch is wound up.
    private static func installObservers() {
        guard !observersInstalled.exchange(true, ordering: .relaxed) else { return }
        let woken = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.afterWaiting.rawValue, true, CFIndex.min) { _, _ in
            guard isLowered.load(ordering: .relaxed) else { return }
            let now = CACurrentMediaTime()
            state.withLock { beginTurn(&$0, now) }
        }
        let done = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, true, CFIndex.max) { _, _ in
            if isLowered.load(ordering: .relaxed) { state.withLock { $0.turnStart = 0 } }
            if isRescued.exchange(false, ordering: .relaxed) { finishRescue() }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), woken, .commonModes)
        CFRunLoopAddObserver(CFRunLoopGetMain(), done, .commonModes)
    }

    private static func beginTurn(_ state: inout State, _ now: CFTimeInterval) {
        state.turnStart = now
        state.lastTick = now
        state.lastCPU = cpuTime(of: state.port).seconds
    }

    /// The rescued turn is over: the thread's own priority back in place of the override, and
    /// whatever was left of the stretch called off.
    private static func finishRescue() {
        pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0)
        state.withLock { state in
            if let override = state.override { pthread_override_qos_class_end_np(override) }
            state.override = nil
            state.isLowered = false
            state.yieldsToPointer = false
            state.turnStart = 0
        }
        isLowered.store(false, ordering: .relaxed)
        MainActor.assumeIsolated { MainThrift.rescued() }
    }

    // MARK: On the watch's own thread

    private static func tick() {
        let now = CACurrentMediaTime()
        let again = state.withLock { state -> Bool in
            guard state.isLowered else {
                state.isTicking = false
                return false
            }
            // Between turns the thread waits for its next event; rescued, it already runs.
            guard state.override == nil, state.turnStart > 0, let thread = state.thread else {
                state.lastTick = now
                return true
            }
            let reading = cpuTime(of: state.port)
            let verdict = state.meter.note(interval: now - state.lastTick, ran: reading.seconds - state.lastCPU, runnable: reading.isRunnable)
            state.lastTick = now
            state.lastCPU = reading.seconds
            var why = verdict?.rawValue
            if why == nil, state.yieldsToPointer, !state.zone.isNull,
               let pointer = CGEvent(source: nil)?.location, state.zone.contains(pointer) {
                why = "met by the pointer"
            }
            guard let why else { return true }
            rescue(&state, thread: thread, why: why, holdOff: verdict == nil ? holdOffAfterPointer : holdOffAfterStall, now: now)
            return true
        }
        if again { queue.asyncAfter(deadline: .now() + interval) { tick() } }
    }

    /// Something the user did has come in on another thread and now waits for the main thread — a
    /// volume or brightness key, ⌘Space (their event taps' own threads): whatever is lowered gets
    /// its priority back at once. A key pressed while Settings was being built ahead showed its
    /// level up to a second late (the step's turn at background, measured: 0.4–1.7 s).
    static func demand() {
        guard !isOff, isLowered.load(ordering: .relaxed) else { return }
        let now = CACurrentMediaTime()
        state.withLock { state in
            guard state.isLowered, state.override == nil, let thread = state.thread else { return }
            rescue(&state, thread: thread, why: "met by a key", holdOff: holdOffAfterPointer, now: now)
        }
    }

    private static func rescue(_ state: inout State, thread: pthread_t, why: String, holdOff: TimeInterval, now: CFTimeInterval) {
        state.override = pthread_override_qos_class_start_np(thread, QOS_CLASS_USER_INTERACTIVE, 0)
        heldOffUntil.store((now + holdOff).bitPattern, ordering: .relaxed)
        rescueCount.add(1, ordering: .relaxed)
        isRescued.store(true, ordering: .relaxed)
        let ms = state.turnStart > 0 ? Int((now - state.turnStart) * 1000) : 0
        Log.window.notice("low-priority turn \(why, privacy: .public) \(ms, privacy: .public) ms in: the main thread's priority given back, none lowered for \(Int(holdOff), privacy: .public) s")
    }

    /// A thread's CPU time so far (user and system), and whether it is running or ready to.
    private static func cpuTime(of port: thread_t) -> (seconds: TimeInterval, isRunnable: Bool) {
        var info = thread_basic_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<thread_basic_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                thread_info(port, thread_flavor_t(THREAD_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, false) }
        let seconds = Double(info.user_time.seconds + info.system_time.seconds)
            + Double(info.user_time.microseconds + info.system_time.microseconds) / 1_000_000
        return (seconds, info.run_state == TH_STATE_RUNNING)
    }
}
