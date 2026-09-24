import Foundation
import IOKit.ps

/// A snapshot of the Mac's power situation, as IOKit reports it.
nonisolated struct PowerState: Sendable, Equatable {
    /// False on desktop Macs. When false, no battery UI may be shown anywhere and every
    /// other battery field is meaningless.
    var hasBattery: Bool
    /// 0...100.
    var level: Int
    /// Energy is actually flowing into the battery. False during an optimised-charging
    /// hold even though the charger is connected — the UI then says "Plugged In".
    var isCharging: Bool
    /// The Mac runs from an external supply.
    var isPluggedIn: Bool
    /// The battery firmware considers the charge complete.
    var isCharged: Bool
    /// To full while charging, to empty on battery; nil while IOKit is still estimating,
    /// during a charging hold, and when there is no battery.
    var minutesRemaining: Int?
    /// Low Power Mode. Exists on desktops too, so it is meaningful without a battery.
    var isLowPowerMode: Bool

    static let unknown = PowerState(
        hasBattery: false, level: 0, isCharging: false, isPluggedIn: false,
        isCharged: false, minutesRemaining: nil, isLowPowerMode: false
    )
}

/// Turns IOKit's power-source dictionaries into a `PowerState`.
///
/// Kept apart from the IOKit calls so the interpretation — which is where the subtle
/// cases live (charging holds, "still calculating" sentinels, desktops) — is testable
/// with fixture dictionaries.
nonisolated enum PowerSourceParser {

    /// - Parameters:
    ///   - descriptions: one dictionary per power source (`IOPSGetPowerSourceDescription`).
    ///   - providingType: `IOPSGetProvidingPowerSourceType` — "AC Power", "Battery Power"
    ///     or "UPS Power"; nil if IOKit could not say.
    ///   - isLowPowerMode: `ProcessInfo.isLowPowerModeEnabled`.
    static func state(
        descriptions: [[String: Any]],
        providingType: String?,
        isLowPowerMode: Bool
    ) -> PowerState {
        guard let battery = descriptions.first(where: isInternalBattery) else {
            var state = PowerState.unknown
            state.isLowPowerMode = isLowPowerMode
            return state
        }

        let current = integer(battery[kIOPSCurrentCapacityKey]) ?? 0
        let maximum = integer(battery[kIOPSMaxCapacityKey]) ?? 100
        // Apple silicon already reports a percentage (max 100); Intel machines report
        // mAh, so always normalise.
        let percent = maximum > 0
            ? Int((Double(current) / Double(maximum) * 100).rounded())
            : current
        let level = min(100, max(0, percent))

        // The providing type is the system's own answer to "what powers the Mac right
        // now". The battery's state key says the same thing and is the fallback.
        let isPluggedIn: Bool
        if let providingType {
            isPluggedIn = providingType == kIOPMACPowerKey
        } else {
            isPluggedIn = battery[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
        }

        // Only trust "charging" while connected: it is how an optimised-charging hold is
        // told apart from real charging (plugged in, IsCharging false).
        let isCharging = isPluggedIn && boolean(battery[kIOPSIsChargingKey])

        let minutes: Int?
        if isCharging {
            minutes = estimate(battery[kIOPSTimeToFullChargeKey])
        } else if !isPluggedIn {
            minutes = estimate(battery[kIOPSTimeToEmptyKey])
        } else {
            minutes = nil   // held or charged: there is nothing to count down to
        }

        return PowerState(
            hasBattery: true,
            level: level,
            isCharging: isCharging,
            isPluggedIn: isPluggedIn,
            isCharged: boolean(battery[kIOPSIsChargedKey]),
            minutesRemaining: minutes,
            isLowPowerMode: isLowPowerMode
        )
    }

    /// An internal battery that is physically present. `Is Present` is absent on some
    /// machines, so only an explicit `false` rules the battery out.
    private static func isInternalBattery(_ description: [String: Any]) -> Bool {
        guard description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { return false }
        return (description[kIOPSIsPresentKey] as? Bool) ?? true
    }

    /// IOKit reports minutes, `-1` while it is still calculating and `0` when it has no
    /// estimate. 65535 is the gas gauge's raw "unknown" and is rejected in case it leaks
    /// through.
    private static func estimate(_ value: Any?) -> Int? {
        guard let minutes = integer(value), minutes > 0, minutes < 0xFFFF else { return nil }
        return minutes
    }

    private static func integer(_ value: Any?) -> Int? {
        (value as? NSNumber)?.intValue
    }

    private static func boolean(_ value: Any?) -> Bool {
        (value as? NSNumber)?.boolValue ?? false
    }
}
