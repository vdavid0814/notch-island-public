import Foundation
import Observation

/// The AirPods' batteries as last reported, for their widget: kept across launches, so the widget
/// has something to show while they are in their case.
///
/// Energy: every connection's reading lands here for free (`AirPodsMonitor` reads them for its
/// card). Beyond that the batteries are read again only while the widget is shown and the AirPods
/// are connected, and then at most every five minutes (`system_profiler`, off the main thread).
@Observable final class AirPodsBatteryStore {
    nonisolated struct Reading: Codable, Equatable, Sendable {
        var name: String
        var left: Int?
        var right: Int?
        var chargingCase: Int?
        var single: Int?
        var date: Date

        /// The lowest of the buds (or the one level a pair reports): what to worry about.
        var lowest: Int? { [left, right, single].compactMap { $0 }.min() }
    }

    private(set) var last: Reading?

    nonisolated static let key = "ni2.airpods.last"
    static let refreshInterval: TimeInterval = 300

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var holders = 0
    @ObservationIgnored private var task: Task<Void, Never>?
    /// The Bluetooth outputs connected now (from `AirPodsMonitor`).
    @ObservationIgnored var connectedOutputs: () -> Set<String> = { [] }
    /// Reads a set's batteries (`AirPodsMonitor.readInfo`); tests count the reads.
    @ObservationIgnored var read: @Sendable (String) async -> AirPodsInfo? = { await AirPodsMonitor.readInfo(named: $0) }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        last = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(Reading.self, from: $0) }
    }

    /// A reading made anyway (a connection's card).
    func note(_ info: AirPodsInfo, at date: Date = Date()) {
        guard info.hasBattery else { return }
        let reading = Reading(name: info.name, left: info.left, right: info.right, chargingCase: info.chargingCase,
                              single: info.single, date: date)
        guard reading != last else { return }
        last = reading
        if let data = try? JSONEncoder().encode(reading) { defaults.set(data, forKey: Self.key) }
    }

    /// Whether the AirPods last read are connected now.
    var isConnected: Bool { last.map { connectedOutputs().contains($0.name) } ?? !connectedOutputs().isEmpty }

    func acquire() {
        holders += 1
        guard holders == 1 else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.holders > 0 else { return }
                let wait = await self.refreshIfDue()
                try? await Task.sleep(for: .seconds(wait), tolerance: .seconds(20))
            }
        }
    }

    func release() {
        holders = max(holders - 1, 0)
        guard holders == 0 else { return }
        task?.cancel()
        task = nil
    }

    /// Reads the connected AirPods if the last reading is five minutes old; how long to wait
    /// before looking again.
    private func refreshIfDue() async -> TimeInterval {
        let outputs = connectedOutputs()
        // Not connected: nothing to read; looked at again when the widget is next shown.
        guard let name = last.flatMap({ outputs.contains($0.name) ? $0.name : nil }) ?? outputs.sorted().first else {
            return Self.refreshInterval
        }
        let age = last.map { $0.name == name ? Date().timeIntervalSince($0.date) : .infinity } ?? .infinity
        guard age >= Self.refreshInterval else { return Self.refreshInterval - age }
        if let info = await read(name) { note(info) }
        return Self.refreshInterval
    }
}
