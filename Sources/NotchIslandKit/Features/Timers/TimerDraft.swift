import Foundation

/// One of the timer's settable units. The ruler edits one at a time.
nonisolated enum TimerUnit: String, Sendable, CaseIterable, Identifiable {
    case hours, minutes, seconds

    var id: String { rawValue }

    /// Under the ruler's marker.
    var shortTitle: String {
        switch self {
        case .hours: String(localized: "hr")
        case .minutes: String(localized: "min")
        case .seconds: String(localized: "sec")
        }
    }

    var accessibilityTitle: String {
        switch self {
        case .hours: String(localized: "hours")
        case .minutes: String(localized: "minutes")
        case .seconds: String(localized: "seconds")
        }
    }
}

/// Which units the timer is set in (the timer widget's Hours and Seconds options), and how a
/// duration splits into them and back. Pure.
///
/// Minutes only is the ruler as it always was: 1 to 120 minutes. With seconds the minutes still go
/// to 120 and 0 is allowed (0:45); with hours the minutes wrap at 59 under up to 23 hours.
nonisolated struct TimerDraftUnits: Sendable, Equatable {
    var hours = false
    var seconds = false

    /// In the order they are set: the ruler starts on minutes, the next unit comes after it.
    var units: [TimerUnit] {
        (hours ? [.hours] : []) + [.minutes] + (seconds ? [.seconds] : [])
    }

    var isMinutesOnly: Bool { !hours && !seconds }

    func range(of unit: TimerUnit) -> ClosedRange<Int> {
        switch unit {
        case .hours: 0...23
        case .minutes: hours ? 0...59 : (seconds ? 0...120 : 1...120)
        case .seconds: 0...59
        }
    }

    /// The unit after `unit`, wrapping (the readout and the unit label step through them).
    func next(after unit: TimerUnit) -> TimerUnit {
        let units = units
        guard let index = units.firstIndex(of: unit) else { return .minutes }
        return units[(index + 1) % units.count]
    }

    func value(of unit: TimerUnit, in duration: TimeInterval) -> Int {
        let total = Int(draft(duration))
        switch unit {
        case .hours: return total / 3600
        case .minutes: return hours ? total % 3600 / 60 : total / 60
        case .seconds: return total % 60
        }
    }

    /// `duration` with `unit` set to `value` (clamped to its range), the other units kept.
    func duration(setting unit: TimerUnit, to value: Int, in duration: TimeInterval) -> TimeInterval {
        var parts = Dictionary(uniqueKeysWithValues: units.map { ($0, self.value(of: $0, in: duration)) })
        let range = range(of: unit)
        parts[unit] = min(max(value, range.lowerBound), range.upperBound)
        let total = (parts[.hours] ?? 0) * 3600 + (parts[.minutes] ?? 0) * 60 + (parts[.seconds] ?? 0)
        return draft(TimeInterval(total))
    }

    /// What the ruler may be set to: as `normalized`, except that with more units than minutes it
    /// may read 0:00 on the way (the minutes passing 0 while the seconds are 0). Snapping that to
    /// 0:01 left the seconds at 1 once the minutes moved on; 0:00 simply cannot be started.
    func draft(_ duration: TimeInterval) -> TimeInterval {
        guard !isMinutesOnly, duration.isFinite, duration.rounded() <= 0 else { return normalized(duration) }
        return 0
    }

    /// The draft can be started (it is not 0:00).
    func canStart(_ duration: TimeInterval) -> Bool {
        draft(duration) >= 1
    }

    /// What these units can express: whole minutes without seconds, at most 120 minutes without
    /// hours, and never less than a second (or a minute, minutes only).
    func normalized(_ duration: TimeInterval) -> TimeInterval {
        guard duration.isFinite else { return 60 }
        var total = max(0, duration.rounded())
        if !seconds { total = (total / 60).rounded() * 60 }
        let maximum: TimeInterval = hours ? 23 * 3600 + 59 * 60 + (seconds ? 59 : 0) : 120 * 60 + (seconds ? 59 : 0)
        total = min(total, maximum)
        return max(total, isMinutesOnly ? 60 : 1)
    }
}
