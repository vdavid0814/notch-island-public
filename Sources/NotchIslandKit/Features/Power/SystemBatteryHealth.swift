import Foundation

/// The battery's "Maximum Capacity" as macOS itself rates it — the figure System Settings ▸
/// Battery and System Information show.
///
/// No registry key an app can read gives it on every Mac (`BatteryDetails`), and the API macOS
/// takes it from answers only privileged callers, so it is read from `system_profiler
/// SPPowerDataType` (about 0.1 s, 20 ms of CPU, on a utility thread). The figure moves over weeks,
/// so one reading is kept for a day, or until the cycle count changes: the battery page and its
/// widgets read the details far more often than that.
nonisolated enum SystemBatteryHealth {
    static let key = "ni2.battery.maximumCapacity"
    static let lifetime: TimeInterval = 24 * 3600

    struct Reading: Codable, Equatable, Sendable {
        var percent: Int
        var cycleCount: Int?
        var date: Date
    }

    /// Off the main thread only: may run `system_profiler`.
    static func maximumCapacity(cycleCount: Int?, defaults: UserDefaults = .standard, now: Date = Date(),
                                read: () -> Int? = readFromSystem) -> Int? {
        if let data = defaults.data(forKey: key), let cached = try? JSONDecoder().decode(Reading.self, from: data),
           cached.cycleCount == cycleCount, now.timeIntervalSince(cached.date) < lifetime, now >= cached.date {
            return cached.percent
        }
        guard let percent = read() else { return nil }
        if let data = try? JSONEncoder().encode(Reading(percent: percent, cycleCount: cycleCount, date: now)) {
            defaults.set(data, forKey: key)
        }
        return percent
    }

    static func readFromSystem() -> Int? {
        DiagnosticsProbes.run("/usr/sbin/system_profiler", ["SPPowerDataType", "-json", "-detailLevel", "mini"], timeout: 5)
            .flatMap(parse)
    }

    /// `sppower_battery_health_maximum_capacity` ("98%") from `system_profiler SPPowerDataType -json`.
    static func parse(_ json: String) -> Int? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let sections = object["SPPowerDataType"] as? [[String: Any]] else { return nil }
        for section in sections {
            guard let health = section["sppower_battery_health_info"] as? [String: Any],
                  let text = health["sppower_battery_health_maximum_capacity"] as? String else { continue }
            let digits = text.filter(\.isNumber)
            if let percent = Int(digits), (1...100).contains(percent) { return percent }
        }
        return nil
    }
}
