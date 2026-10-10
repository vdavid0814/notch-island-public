import Foundation
import QuartzCore

/// `NI_TRACE=1`: logs every main run-loop turn longer than 2 ms (`NI_TRACE_MIN=<ms>` for another
/// threshold; window category, "TURN"), for finding the bursts that run on a performance core.
/// Off, it installs nothing.
@MainActor enum PerfTrace {
    static let isOn = ProcessInfo.processInfo.environment["NI_TRACE"] == "1"

    static func install() {
        guard isOn else { return }
        nonisolated(unsafe) var woke: CFTimeInterval = 0
        let threshold = Double(ProcessInfo.processInfo.environment["NI_TRACE_MIN"] ?? "") ?? 2
        // Two observers: the wake-up first of all, the end after everything else (Core Animation's
        // commit, which draws the layers, runs in its own before-waiting observer).
        let woken = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.afterWaiting.rawValue, true, CFIndex.min) { _, _ in
            woke = CACurrentMediaTime()
        }
        let done = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, true, CFIndex.max) { _, _ in
            let now = CACurrentMediaTime()
            let ms = (now - woke) * 1000
            guard woke > 0, ms > threshold else { return }
            Log.window.notice("TURN \(String(format: "%.1f", ms), privacy: .public) at \(String(format: "%.3f", woke), privacy: .public)")
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), woken, .commonModes)
        CFRunLoopAddObserver(CFRunLoopGetMain(), done, .commonModes)
    }

    /// Times `body` into the same log ("TIME name ms").
    @discardableResult static func measure<T>(_ name: String, _ body: () -> T) -> T {
        guard isOn else { return body() }
        let start = CACurrentMediaTime()
        let result = body()
        Log.window.notice("TIME \(name, privacy: .public) \(String(format: "%.1f", (CACurrentMediaTime() - start) * 1000), privacy: .public) at \(String(format: "%.3f", start), privacy: .public)")
        return result
    }

    /// A marker in the same log, to line turns up with events.
    static func mark(_ what: String) {
        guard isOn else { return }
        Log.window.notice("MARK \(what, privacy: .public) at \(String(format: "%.3f", CACurrentMediaTime()), privacy: .public)")
    }
}
