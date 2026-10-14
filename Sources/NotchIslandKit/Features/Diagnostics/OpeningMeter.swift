import Darwin
import Foundation
import os

/// What each opening of the island costs, as Activity Monitor counts it: the app's own energy plus
/// what the system's daemons did for it and billed to it (Spotlight's search for Siri's first
/// keystroke was ~1.4 J of the latter, October 14), from the transition's start until it has
/// settled. Two counter reads per opening and one deferred read; nothing between openings.
///
/// The report gets each kind's count, median and worst tenth (`DiagnosticsMetric.openingMJ`…), so
/// a Mac where openings cost several times the reference shows it, with the kinds apart: an
/// opening from rest with the panel kept, one that built the panel anew, Siri, Settings, a close.
nonisolated final class OpeningMeter: Sendable {
    nonisolated enum Kind: String, Sendable, CaseIterable {
        /// The panel opened with its page kept from the last time (`IslandContentStack.keptPage`).
        case panelKept
        /// The panel opened and built its page.
        case panelBuilt
        /// Siri opened, until it has settled (its first search typed meanwhile counts too).
        case siri
        case settings
        /// Back to rest or a pill from any of the above.
        case close
        /// One of Siri's searches, from the keystroke until the next one or a second on (Spotlight's
        /// work for it billed to the app included).
        case siriSearch

        /// Searches are measured beside the transitions, not instead of them.
        var lane: Int { self == .siriSearch ? 1 : 0 }

        var title: String {
            switch self {
            case .panelKept: "Panel opening (page kept)"
            case .panelBuilt: "Panel opening (page built)"
            case .siri: "Siri opening"
            case .settings: "Settings opening"
            case .close: "Closing"
            case .siriSearch: "Siri search"
            }
        }
    }

    nonisolated struct Summary: Sendable, Equatable {
        var count: Int
        var medianMJ: Double
        var worstTenthMJ: Double
        var line: String { String(format: "%d, median %.0f mJ, worst tenth %.0f mJ", count, medianMJ, worstTenthMJ) }
    }

    static let shared = OpeningMeter()

    /// How long after its start an opening is measured: the growth (~0.5 s) and what follows it
    /// (the panel's other pages built 0.8 s in, Siri's first rows).
    static let window: TimeInterval = 1.6
    static let searchWindow: TimeInterval = 1.0
    /// The last ones of each kind kept.
    static let kept = 40

    private struct State {
        var running: [Int: (kind: Kind, start: UInt64, token: UInt64)] = [:]
        var token: UInt64 = 0
        var samples: [Kind: [Double]] = [:]
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private static let queue = DispatchQueue(label: "com.davidvarga.notchisland.openingmeter", qos: .utility)

    /// A transition begins: the one measured before it (if still running) ends here.
    func begin(_ kind: Kind) {
        let now = Self.energyNJ()
        let token: UInt64 = state.withLock { state in
            if let running = state.running[kind.lane] { Self.store(&state, running.kind, now &- running.start) }
            state.token &+= 1
            state.running[kind.lane] = (kind, now, state.token)
            return state.token
        }
        Self.queue.asyncAfter(deadline: .now() + (kind == .siriSearch ? Self.searchWindow : Self.window)) { [self] in
            let end = Self.energyNJ()
            state.withLock { state in
                guard let running = state.running[kind.lane], running.token == token else { return }
                Self.store(&state, running.kind, end &- running.start)
                state.running[kind.lane] = nil
            }
        }
    }

    func summaries() -> [Kind: Summary] {
        state.withLock { state in state.samples.compactMapValues(Self.summary) }
    }

    /// For tests.
    func reset() {
        state.withLock { $0 = State() }
    }

    static func summary(_ values: [Double]) -> Summary? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let median = sorted.count % 2 == 1 ? sorted[sorted.count / 2] : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
        let tenth = sorted[min(sorted.count - 1, Int((Double(sorted.count) * 0.9).rounded(.down)))]
        return Summary(count: values.count, medianMJ: median, worstTenthMJ: tenth)
    }

    private static func store(_ state: inout State, _ kind: Kind, _ nanojoules: UInt64) {
        // A counter that went back (it never should) is no reading.
        guard nanojoules < 1 << 62 else { return }
        var values = state.samples[kind, default: []]
        values.append(Double(nanojoules) / 1e6)
        if values.count > kept { values.removeFirst(values.count - kept) }
        state.samples[kind] = values
    }

    /// The app's energy so far plus what other processes billed to it, in nanojoules.
    static func energyNJ() -> UInt64 {
        var info = rusage_info_v6()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(getpid(), RUSAGE_INFO_V6, $0)
            }
        }
        guard result == 0 else { return 0 }
        return info.ri_energy_nj &+ info.ri_billed_energy
    }
}

extension OpeningMeter.Kind {
    /// The kind of a transition, or nil for one that is not measured (a banner coming and going).
    static func of(from: IslandPresentation, to: IslandPresentation, panelKept: Bool) -> Self? {
        if to.isSettings, !from.isSettings { return .settings }
        if to.isAssistant, !from.isAssistant, !from.isSettings { return .siri }
        if to.isExpanded, !from.isExpanded, !from.isAssistant, !from.isSettings { return panelKept ? .panelKept : .panelBuilt }
        if from.isOpen, !to.isOpen { return .close }
        return nil
    }
}
