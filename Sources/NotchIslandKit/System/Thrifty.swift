import Foundation
import QuartzCore

/// Work that can wait a moment — decoding pictures, drawing icons — run one piece at a time on a
/// single thread at utility QoS.
///
/// On Apple silicon the same CPU time costs far more energy on several performance cores at full
/// clock than on one core that may run slowly: drawing Siri's app icons in parallel from the
/// gallery's cells took 2.2 W for half a second (Activity Monitor ~250), for ~0.3 s of CPU
/// (measured). One at a time at utility QoS, the icons arrive a little later for a fraction of the
/// energy.
nonisolated enum Thrifty {
    /// Utility, not background: at background, with the Mac busy (Xcode building), the queue was
    /// starved and Siri's gallery showed empty tiles for seconds, filling in one by one (seen on
    /// video, v0.4.5). Still one piece at a time, so a gallery never runs several cores at once;
    /// work nobody is looking at goes to `runInBackground`.
    private static let queue = DispatchQueue(label: "com.davidvarga.notchisland.thrifty", qos: .utility)

    /// Background quality of service: efficiency cores only, for work nobody is waiting for.
    private static let backgroundQueue = DispatchQueue(label: "com.davidvarga.notchisland.thrifty.background", qos: .background)

    static func runInBackground<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            backgroundQueue.async { continuation.resume(returning: work()) }
        }
    }

    /// `run` when someone waits on the result (`seen`), `runInBackground` when not: Settings built
    /// ahead, unseen, decoded its wallpapers at utility on the performance cores (~140 ms of a
    /// preparation, the largest part of its worst second).
    static func run<T: Sendable>(seen: Bool, _ work: @escaping @Sendable () -> T) async -> T {
        seen ? await run(work) : await runInBackground(work)
    }

    static func run<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: work()) }
        }
    }
}

/// The main thread's large one-off updates (a page built or torn down) on the efficiency cores.
///
/// One uninterrupted burst of main-thread work above ~40 ms is run on a performance core at full
/// clock; at background quality of service the same 100 ms burst used ~6× less energy (72 → 12 mJ,
/// measured) and no performance core. Only for updates nobody is waiting on within the frame: the
/// work takes about twice as long.
@MainActor enum MainThrift {
    static let isEnabled = ProcessInfo.processInfo.environment["NI_NO_THRIFT"] != "1"

    private static var restore: Timer?

    /// The main thread at background quality of service for the next `seconds`: for a change whose
    /// work spreads over several turns (an opening: views, then the keyboard and the text field).
    /// Set from a run-loop block, not a dispatch job (a job's end puts the thread's quality of
    /// service back), and restored by a run-loop timer.
    static func lowPower(for seconds: TimeInterval) {
        guard isEnabled else { return }
        CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) {
            pthread_set_qos_class_self_np(QOS_CLASS_BACKGROUND, 0)
        }
        CFRunLoopWakeUp(CFRunLoopGetMain())
        restore?.invalidate()
        let timer = Timer(timeInterval: seconds, repeats: false) { _ in
            pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0)
            MainActor.assumeIsolated { restore = nil }
        }
        RunLoop.main.add(timer, forMode: .common)
        restore = timer
    }

    /// `work` in a turn of its own with the main thread at background quality of service until
    /// that turn's layout and commit are done: for what a click sets off and nobody watches the
    /// first frame of (a close). In the click's own turn it runs at the click's priority whatever
    /// the thread's quality of service is — on a performance core: closing Settings by a click
    /// outside was one ~105 ms turn there, ~200 mJ for that second; here ~105 (measured with
    /// `NI_TRACE` and `stress.py settings-gear`, A B A B), the close starting ~0.1 s later.
    /// Utility instead of background changed nothing (still a performance core). A run-loop
    /// timer, not a dispatch job or a task (their end puts the thread's quality of service back);
    /// the frames after the turn run at the thread's own priority again, so the motion is as
    /// smooth as before.
    /// `lowPowerTurn`, with the thread kept at background quality of service until `hold` seconds
    /// after the turn: what the turn changed is laid out, drawn and committed by AppKit's display
    /// cycle in the frames after it, from the display link's source, and those frames ran at the
    /// thread's own priority on a performance core — Settings' preparation: ~25 frames of 8–56 ms
    /// after its steps, Activity Monitor 150–600 for seconds after every launch (measured with
    /// `NI_TRACE`). Anything the user starts meanwhile takes the priority back at once (`raise`).
    static func lowPowerTurn(holding hold: TimeInterval, _ work: @escaping @MainActor () -> Void) {
        guard isEnabled else { return work() }
        let timer = Timer(timeInterval: 0, repeats: false) { _ in
            // Held until `hold` after the work: a step can itself take longer than that.
            holdUntil = .infinity
            pthread_set_qos_class_self_np(QOS_CLASS_BACKGROUND, 0)
            // Lowered again before every layout and commit until the hold is over (a dispatch job
            // run meanwhile restores the thread's own), raised after the first one past it.
            let lower = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, true, CFIndex.min) { observer, _ in
                if CACurrentMediaTime() < holdUntil {
                    pthread_set_qos_class_self_np(QOS_CLASS_BACKGROUND, 0)
                } else {
                    CFRunLoopObserverInvalidate(observer)
                }
            }
            let raise = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, true, CFIndex.max) { observer, _ in
                guard CACurrentMediaTime() >= holdUntil else { return }
                if MainActor.assumeIsolated({ restore == nil }) { pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0) }
                CFRunLoopObserverInvalidate(observer)
            }
            CFRunLoopAddObserver(CFRunLoopGetMain(), lower, .commonModes)
            CFRunLoopAddObserver(CFRunLoopGetMain(), raise, .commonModes)
            MainActor.assumeIsolated { work() }
            // Raised meanwhile (`raise`): not held again.
            if holdUntil == .infinity { holdUntil = CACurrentMediaTime() + hold }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    /// Until when a `lowPowerTurn(holding:)` keeps the thread at background.
    /// Read by the run-loop observers on the main thread only.
    nonisolated(unsafe) private static var holdUntil: CFTimeInterval = 0

    /// The user started something (the pointer came onto the island): any held low priority ends now.
    static func raise() {
        guard holdUntil > CACurrentMediaTime() else { return }
        holdUntil = 0
        if restore == nil { pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0) }
    }

    static func lowPowerTurn(_ work: @escaping @MainActor () -> Void) {
        guard isEnabled else { return work() }
        let timer = Timer(timeInterval: 0, repeats: false) { _ in
            pthread_set_qos_class_self_np(QOS_CLASS_BACKGROUND, 0)
            // Again just before the layout and the commit (a dispatch job run meanwhile restores
            // the thread's own), and back after them — unless a longer stretch was asked for.
            let lower = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, false, CFIndex.min) { _, _ in
                pthread_set_qos_class_self_np(QOS_CLASS_BACKGROUND, 0)
            }
            let raise = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, false, CFIndex.max) { _, _ in
                MainActor.assumeIsolated {
                    if restore == nil { pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0) }
                }
            }
            CFRunLoopAddObserver(CFRunLoopGetMain(), lower, .commonModes)
            CFRunLoopAddObserver(CFRunLoopGetMain(), raise, .commonModes)
            MainActor.assumeIsolated { work() }
        }
        RunLoop.main.add(timer, forMode: .common)
    }
}
