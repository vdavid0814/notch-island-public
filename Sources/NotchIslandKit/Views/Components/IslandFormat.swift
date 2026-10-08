import Foundation
import Synchronization

/// Pure text and symbol choices for the island, kept out of the views so they can be tested.
nonisolated enum IslandFormat {
    /// Clock-style duration: "3:07", "1:02:03". Hours appear only when needed, seconds always.
    ///
    /// Remembered per whole second and locale while among the last 256: formatting a `Duration`
    /// builds its format style anew, and the timer asks for the same time several times in each
    /// evaluation (its readout, sized to fit, in three sizes).
    static func clock(_ seconds: TimeInterval) -> String {
        let whole = max(0, Int(seconds.isFinite ? seconds.rounded(.down) : 0))
        let key = ClockKey(seconds: whole, hours: seconds >= 3600, locale: Locale.current.identifier)
        if let text = clocks.withLock({ $0[key] }) { return text }
        let text = key.hours
            ? Duration.seconds(whole).formatted(.time(pattern: .hourMinuteSecond))
            : Duration.seconds(whole).formatted(.time(pattern: .minuteSecond))
        clocks.withLock { $0[key] = text }
        return text
    }

    /// Minutes and seconds however many minutes there are: "5:00", "120:16" (the timer without
    /// hours, as its ruler sets it).
    static func minutesClock(_ seconds: TimeInterval) -> String {
        let whole = max(0, Int(seconds.isFinite ? seconds.rounded(.down) : 0))
        return "\(whole / 60):" + String(format: "%02d", whole % 60)
    }

    private struct ClockKey: Hashable {
        var seconds: Int
        var hours: Bool
        var locale: String
    }

    private static let clocks = Mutex(MeasureCache<ClockKey, String>())

    /// "62%".
    static func percent(_ fraction: Double) -> String {
        min(max(fraction, 0), 1).formatted(.percent.precision(.fractionLength(0)))
    }

    /// Whole percent as a number: an animation value that changes only when the shown text does.
    static func percentValue(_ fraction: Double) -> Double {
        (min(max(fraction, 0), 1) * 100).rounded()
    }

    /// "1 hr, 12 min" / "45 min" — system abbreviated units, localised.
    static func minutes(_ minutes: Int) -> String {
        Duration.seconds(max(0, minutes) * 60)
            .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    /// Short preset label: "5m", "25m".
    static func preset(minutes: Int) -> String {
        Duration.seconds(minutes * 60).formatted(.units(allowed: [.minutes], width: .narrow))
    }

    /// Symbol for a level reading. Derived here from the kind rather than read from the reading,
    /// because a `LevelReading` does not know whether it is a volume or a brightness.
    static func levelSymbol(_ kind: LevelKind, reading: LevelReading) -> String {
        switch kind {
        case .volume:
            if reading.isMuted || reading.value <= 0 { return "speaker.slash.fill" }
            if reading.value < 1.0 / 3.0 { return "speaker.wave.1.fill" }
            if reading.value < 2.0 / 3.0 { return "speaker.wave.2.fill" }
            return "speaker.wave.3.fill"
        case .brightness:
            return reading.value < 0.5 ? "sun.min.fill" : "sun.max.fill"
        }
    }

    /// Battery symbol for a charge level. The charging variant only exists at full, which is how
    /// the system menu bar item draws it too.
    static func batterySymbol(level: Int, charging: Bool) -> String {
        if charging { return "battery.100percent.bolt" }
        switch level {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}

/// Meaning carried by a symbol's colour. Only these three hues are ever used, and only for this.
nonisolated enum StatusTint: Sendable, Equatable {
    case none, charging, low, lowPower
}

/// What a power banner says. Derived from the event (why the banner is up) and the current state
/// (what is true now) — the state can move on while the banner is up, and the copy follows it. The
/// percentage is not repeated here: the banner's header shows it beside the notch.
nonisolated struct PowerCopy: Sendable, Equatable {
    let title: String
    let detail: String
    let systemImage: String
    let tint: StatusTint

    init(event: PowerEvent, state: PowerState) {
        let level = min(max(state.level, 0), 100)
        let time = state.minutesRemaining.flatMap { $0 > 0 ? IslandFormat.minutes($0) : nil }

        switch event {
        case .connected where state.isCharging:
            title = String(localized: "Charging")
            detail = time.map { String(localized: "\($0) until full") } ?? ""
            systemImage = "battery.100percent.bolt"
            tint = .charging
        case .connected:
            // Plugged in but held by optimised charging: saying "Charging" would be a lie.
            title = String(localized: "Plugged In")
            detail = String(localized: "Not Charging")
            systemImage = "powerplug.fill"
            tint = .none
        case .charged:
            title = String(localized: "Fully Charged")
            detail = ""
            systemImage = "battery.100percent"
            tint = .charging
        case .disconnected:
            title = String(localized: "On Battery")
            detail = time.map { String(localized: "\($0) left") } ?? ""
            systemImage = IslandFormat.batterySymbol(level: level, charging: false)
            tint = state.isLowPowerMode ? .lowPower : .none
        case .low:
            title = String(localized: "Low Battery")
            detail = time.map { String(localized: "\($0) left") } ?? String(localized: "Connect to power")
            systemImage = IslandFormat.batterySymbol(level: level, charging: false)
            tint = .low
        }
    }
}
/// The last 256 measurements, oldest out first.
nonisolated struct MeasureCache<Key: Hashable, Value> {
    static var capacity: Int { 256 }

    private var values: [Key: Value] = [:]
    private var order: [Key] = []
    private var next = 0

    subscript(key: Key) -> Value? {
        get { values[key] }
        set {
            guard let newValue else { return }
            if values.updateValue(newValue, forKey: key) != nil { return }
            if order.count < Self.capacity {
                order.append(key)
            } else {
                values[order[next]] = nil
                order[next] = key
                next = (next + 1) % Self.capacity
            }
        }
    }

    var count: Int { values.count }
}

