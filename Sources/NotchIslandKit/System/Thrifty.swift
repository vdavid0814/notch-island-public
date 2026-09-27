import AppKit
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
    /// Background, not utility: at utility the scheduler still put a burst of decoding on a
    /// performance core; on the efficiency cores the same work costs about a quarter of the energy,
    /// and nothing here is waited on more than a frame or two.
    private static let queue = DispatchQueue(label: "com.davidvarga.notchisland.thrifty", qos: .background)

    /// Background quality of service: efficiency cores only, for work nobody is waiting for.
    private static let backgroundQueue = DispatchQueue(label: "com.davidvarga.notchisland.thrifty.background", qos: .background)

    static func runInBackground<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            backgroundQueue.async { continuation.resume(returning: work()) }
        }
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

    /// Off for a while after a build at background quality of service turned out slow: then the
    /// system is keeping everything on the efficiency cores anyway (seen on battery below ~30 %),
    /// where the lower quality of service saves nothing and only runs at their lowest clock
    /// (a safety net: well past what any page takes at background quality of service, ~0.6 s).
    private static var slowUntil: ContinuousClock.Instant?
    static let slowBuild: Duration = .milliseconds(1500)

    static var isOn: Bool {
        guard isEnabled else { return false }
        if let slowUntil, ContinuousClock.now < slowUntil { return false }
        return true
    }

    /// Runs `body` and, still at background quality of service, the view and layer update it
    /// causes in `window` (done here and now rather than at the end of the turn: the dispatch queue
    /// running this puts the thread's quality of service back when the job ends, before the run
    /// loop's own update).
    static func run(in window: NSWindow?, _ body: () -> Void) {
        guard isOn, let window else { return body() }
        let started = ContinuousClock.now
        pthread_set_qos_class_self_np(QOS_CLASS_BACKGROUND, 0)
        body()
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        CATransaction.flush()
        pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0)
        if ContinuousClock.now - started > slowBuild {
            slowUntil = .now + .seconds(600)
            Log.app.notice("efficiency cores slow: large updates at full speed for 10 minutes")
        }
    }

    private static var restore: Timer?

    /// The main thread at background quality of service for the next `seconds`: for a change whose
    /// work spreads over several turns (an opening: views, then the keyboard and the text field).
    /// Set from a run-loop block, not a dispatch job (a job's end puts the thread's quality of
    /// service back), and restored by a run-loop timer.
    static func lowPower(for seconds: TimeInterval) {
        guard isOn else { return }
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
}
