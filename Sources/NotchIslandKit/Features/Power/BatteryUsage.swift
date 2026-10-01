import Foundation

/// One day of the battery's use, as the iPhone's Battery Usage shows it: how much of the battery
/// went (percentage points used on battery, which may pass 100 over a day of several charges), and
/// how long the displays were on and off.
nonisolated struct BatteryUsageDay: Sendable, Equatable, Identifiable {
    /// Its local midnight.
    var day: Date
    /// Percentage points used on battery.
    var used: Double
    /// The displays on while the Mac was awake.
    var screenActive: TimeInterval
    /// The displays off, or the Mac asleep.
    var screenIdle: TimeInterval
    /// Something was recorded that day.
    var hasData: Bool

    var id: Date { day }
}

/// How a day's use compares with the others' (the iPhone's "You used more battery on Saturday
/// than you usually do").
nonisolated enum BatteryUsageComparison: Sendable, Equatable {
    case more, similar, less
}

/// The days of the history, built from the records alone.
nonisolated enum BatteryUsage {
    /// The last `count` calendar days up to `now`'s, oldest first.
    static func days(records: [BatteryRecord], now: Date, calendar: Calendar, count: Int = 8) -> [BatteryUsageDay] {
        let today = calendar.startOfDay(for: now)
        let starts = (0..<count).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
        let sorted = records.sorted { $0.time < $1.time }
        let readings = sorted.filter(\.kind.carriesLevel)
        var used: [Date: Double] = [:]
        // Each drop on battery, counted on the day it was read.
        for (a, b) in zip(readings, readings.dropFirst()) where !a.isCharging && !b.isCharging && b.level < a.level {
            used[calendar.startOfDay(for: b.date), default: 0] += Double(a.level - b.level)
        }
        let first = sorted.first?.date
        return starts.map { start in
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
            let screen = screenTime(records: sorted, from: start, to: min(end, now), first: first, calendar: calendar, now: now)
            let hasData = sorted.contains { $0.date >= start && $0.date < end }
            return BatteryUsageDay(day: start, used: used[start] ?? 0, screenActive: screen.active, screenIdle: screen.idle,
                                   hasData: hasData)
        }
    }

    /// The displays on and off (or the Mac asleep) between `start` and `end`, over the part the
    /// history knows (from its first record on).
    static func screenTime(records: [BatteryRecord], from start: Date, to end: Date, first: Date?, calendar: Calendar,
                           now: Date) -> (active: TimeInterval, idle: TimeInterval) {
        guard let first, end > start else { return (0, 0) }
        let known = max(start, first)
        guard end > known else { return (0, 0) }
        let model = BatteryChartModel(records: records, range: .today, now: now, calendar: calendar,
                                      interval: DateInterval(start: start, end: end))
        let dark = model.segments.filter { $0.kind == .displayOff || $0.kind == .gap }
            .reduce(0) { $0 + $1.overlap(known, end) }
        let total = end.timeIntervalSince(known)
        return (max(total - dark, 0), min(dark, total))
    }

    /// `day` against the other days with data (today left out unless it is `day`): nil without two
    /// of them to compare with.
    static func comparison(_ day: BatteryUsageDay, among days: [BatteryUsageDay], today: Date) -> BatteryUsageComparison? {
        let others = days.filter { $0.day != day.day && $0.hasData && $0.used > 0 && $0.day != today }
        guard others.count >= 2, day.hasData else { return nil }
        let usual = others.map(\.used).reduce(0, +) / Double(others.count)
        guard usual > 0 else { return nil }
        let ratio = day.used / usual
        return ratio > 1.15 ? .more : ratio < 0.85 ? .less : .similar
    }

    /// The sentence over the chart.
    static func sentence(_ comparison: BatteryUsageComparison?, day: Date, isToday: Bool) -> String {
        let name = isToday ? String(localized: "today") : day.formatted(.dateTime.weekday(.wide))
        switch comparison {
        case .more?: return String(localized: "You used more battery \(isToday ? name : "on " + name) than you usually do.")
        case .less?: return String(localized: "You used less battery \(isToday ? name : "on " + name) than you usually do.")
        case .similar?: return String(localized: "You used a similar amount of battery \(name) as you usually do.")
        case nil: return String(localized: "Battery used each day, on battery.")
        }
    }
}
