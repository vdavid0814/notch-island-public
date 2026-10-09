import Foundation
import os

/// A system service Siri reads (Spotlight, Contacts, the dictionary) waited for at most a deadline.
///
/// The root's hits land together, so one service that never answers kept every row back: "xcode"
/// listed only Search the Web and Ask ChatGPT, with Xcode installed, until a permission Reset
/// (v0.8.1; each keystroke reads Spotlight, Contacts and the dictionary, all synchronous). The
/// call runs on a Dispatch queue, not on Swift's few pool threads, so a call that hangs takes no
/// pool thread with it; after `limit` the caller goes on with `fallback`. While a call of the same
/// source is overdue, later ones get `fallback` at once instead of piling up behind it.
nonisolated enum SourceDeadline {
    static let standard: Duration = .seconds(2)

    fileprivate static let overdue = OSAllocatedUnfairLock(initialState: Set<String>())
    fileprivate static let queue = DispatchQueue(label: "com.davidvarga.notchisland.siri-sources", qos: .utility,
                                             attributes: .concurrent)

    /// `source` names it in the log and the report's flow ("Spotlight", "Contacts").
    static func value<T: Sendable>(_ source: String, within limit: Duration = standard, fallback: T,
                                   _ work: @escaping @Sendable () -> T) async -> T {
        if overdue.withLock({ $0.contains(source) }) { return fallback }
        return await withCheckedContinuation { continuation in
            let once = ResumeOnce(continuation)
            queue.async {
                let value = work()
                if overdue.withLock({ $0.remove(source) != nil }) {
                    Log.app.notice("siri source \(source, privacy: .public) answered again")
                }
                once.resume(value)
            }
            let seconds = Double(limit.components.seconds) + Double(limit.components.attoseconds) / 1e18
            queue.asyncAfter(deadline: .now() + seconds) {
                guard once.resume(fallback) else { return }
                overdue.withLock { _ = $0.insert(source) }
                Log.app.error("siri source \(source, privacy: .public) did not answer in \(seconds, privacy: .public) s: left out")
                Task { @MainActor in DiagnosticsFlow.record("siri: \(source) did not answer in \(seconds) s, left out") }
            }
        }
    }
}

extension SourceDeadline {
    /// The same for a source that is itself asynchronous (`AssistantSources`' closures): `work`
    /// runs in a task of its own, so one that never returns is left behind instead of waited for.
    /// `owner` keeps one caller's overdue sources apart from another's (each Siri model has its own).
    static func value<T: Sendable>(_ source: String, owner: String = "", within limit: Duration = standard, fallback: T,
                                   async work: @escaping @Sendable () async -> T) async -> T {
        let key = owner + source
        if overdue.withLock({ $0.contains(key) }) { return fallback }
        return await withCheckedContinuation { continuation in
            let once = ResumeOnce(continuation)
            Task.detached(priority: .utility) {
                let value = await work()
                if overdue.withLock({ $0.remove(key) != nil }) {
                    Log.app.notice("siri source \(source, privacy: .public) answered again")
                }
                once.resume(value)
            }
            let seconds = Double(limit.components.seconds) + Double(limit.components.attoseconds) / 1e18
            queue.asyncAfter(deadline: .now() + seconds) {
                guard once.resume(fallback) else { return }
                overdue.withLock { _ = $0.insert(key) }
                Log.app.error("siri source \(source, privacy: .public) did not answer in \(seconds, privacy: .public) s: left out")
                Task { @MainActor in DiagnosticsFlow.record("siri: \(source) did not answer in \(seconds) s, left out") }
            }
        }
    }
}

/// Resumes a continuation once, from whichever side comes first.
nonisolated private final class ResumeOnce<T: Sendable>: @unchecked Sendable {
    private let lock: OSAllocatedUnfairLock<CheckedContinuation<T, Never>?>

    init(_ continuation: CheckedContinuation<T, Never>) {
        lock = OSAllocatedUnfairLock(uncheckedState: continuation)
    }

    /// False when it was resumed already.
    @discardableResult func resume(_ value: T) -> Bool {
        guard let continuation = lock.withLockUnchecked({ state -> CheckedContinuation<T, Never>? in
            defer { state = nil }
            return state
        }) else { return false }
        continuation.resume(returning: value)
        return true
    }
}
