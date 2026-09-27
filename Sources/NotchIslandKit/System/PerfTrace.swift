import Foundation
import QuartzCore

/// `NI_TRACE=1`: logs every main run-loop turn longer than 2 ms (window category, "TURN"), for
/// finding the bursts that run on a performance core. Off, it installs nothing.
@MainActor enum PerfTrace {
    static let isOn = ProcessInfo.processInfo.environment["NI_TRACE"] == "1"

    static func install() {
        guard isOn else { return }
        nonisolated(unsafe) var woke: CFTimeInterval = 0
        let activities = CFRunLoopActivity.afterWaiting.rawValue | CFRunLoopActivity.beforeWaiting.rawValue
        let observer = CFRunLoopObserverCreateWithHandler(nil, activities, true, 0) { _, activity in
            let now = CACurrentMediaTime()
            if activity == .afterWaiting { woke = now; return }
            let ms = (now - woke) * 1000
            guard woke > 0, ms > 2 else { return }
            Log.window.notice("TURN \(String(format: "%.1f", ms), privacy: .public) at \(String(format: "%.3f", woke), privacy: .public)")
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
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
