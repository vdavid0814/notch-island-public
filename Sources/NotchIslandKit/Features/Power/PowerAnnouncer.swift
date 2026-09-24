import Foundation

/// Decides which power changes deserve to interrupt the user.
///
/// Pure and deterministic: it sees consecutive `PowerState`s and remembers only what it
/// has already said, so a battery hovering around a threshold cannot nag and a charger
/// held at its optimised-charging limit never claims to be charging or full.
nonisolated struct PowerAnnouncer: Sendable {

    /// Descending. Each one fires at most once per discharge.
    static let lowThresholds: [Int] = [20, 10, 5]

    /// Thresholds that are spent for the current discharge: announced, or already at or
    /// above the level when the discharge began (unplugging at 15% must not claim the
    /// battery just crossed 20%).
    private var spentThresholds: Set<Int> = []

    /// Whether reaching 100% has been accounted for during the current connection.
    /// Only unplugging clears it: on AC the battery may drift a few percent and top up
    /// again, and each top-up must not announce "Fully Charged" anew.
    private var fullAccountedFor = false

    init() {}

    mutating func events(from old: PowerState, to new: PowerState) -> [PowerEvent] {
        guard new.hasBattery else {
            // Desktop, or the battery vanished from IOKit: never any battery events.
            self = PowerAnnouncer()
            return []
        }

        guard old.hasBattery else {
            // First reading (launch, monitor restart). It describes the present, not a
            // change, so it only seeds the memory.
            self = PowerAnnouncer()
            if new.isPluggedIn {
                fullAccountedFor = Self.isFull(new)
            } else {
                _ = spendThresholds(atOrAbove: new.level)
            }
            return []
        }

        var events: [PowerEvent] = []

        if old.isPluggedIn != new.isPluggedIn {
            events.append(new.isPluggedIn ? .connected : .disconnected)
        }

        if new.isPluggedIn {
            // A discharge ends the moment external power arrives; the next one starts
            // with every threshold armed again. Re-arming on connection rather than on
            // the first "charging" reading behaves the same (a connection that never
            // charges cannot raise the level, and unplugging re-spends every threshold at
            // or above it) without depending on how promptly IOKit flips IsCharging.
            spentThresholds.removeAll()

            if Self.isFull(new) && !fullAccountedFor {
                fullAccountedFor = true
                // Plugging in an already-full battery is a connection, not a completed
                // charge: accounted for silently.
                if old.isPluggedIn {
                    events.append(.charged)
                }
            }
        } else {
            fullAccountedFor = false
            let crossed = spendThresholds(atOrAbove: new.level)
            // Only a crossing that happens on battery is announced; unplugging below a
            // threshold just spends it. Several can be crossed at once (a sleep in
            // between): only the most severe one is worth saying.
            if !old.isPluggedIn, let lowest = crossed.min() {
                events.append(.low(threshold: lowest))
            }
        }

        return events
    }

    /// Spends every armed threshold at or above `level` and returns the newly spent ones.
    private mutating func spendThresholds(atOrAbove level: Int) -> [Int] {
        let newlySpent = Self.lowThresholds.filter { level <= $0 && !spentThresholds.contains($0) }
        spentThresholds.formUnion(newlySpent)
        return newlySpent
    }

    /// "Full" means 100%, not merely "charge complete": with a charge limit or an
    /// optimised hold the firmware may call 80% complete, and a "Fully Charged" banner at
    /// 80% would be a lie.
    private static func isFull(_ state: PowerState) -> Bool {
        state.level >= 100
    }
}
