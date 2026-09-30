import Foundation
import IOKit.ps

/// The battery's health and the power flowing through it: what the battery page and its widgets
/// show beyond the level. Read from the gauge (`BatteryProbe`) and the adapter, off the main
/// thread; `BatteryCenter` decides when.
///
/// On macOS 27 an app sees fewer of the gauge's keys than root does: temperature, the permanent
/// failure status and the top-level capacities are absent on Apple silicon, so those fields are
/// optional and the capacities come from `BatteryData`.
nonisolated struct BatteryDetails: Sendable, Equatable {
    nonisolated enum Condition: Sendable, Equatable {
        case normal
        /// The gauge reports a permanent failure (its status code): System Settings says "Service
        /// Recommended".
        case serviceRecommended(Int)
    }

    var cycleCount: Int?
    /// The cycles the battery is rated for (1000 on current MacBooks).
    var designCycleCount: Int?
    /// mAh, as built.
    var designCapacity: Int?
    /// mAh the gauge expects the next full charge to hold, after its own adjustments.
    var fullChargeCapacity: Int?
    /// mAh the cells hold at full charge now: the figure macOS rates health by.
    var nominalChargeCapacity: Int?
    /// System Settings' "Maximum Capacity": nominal over design capacity, at most 100.
    var maximumCapacityPercent: Int?
    var condition: Condition
    /// Volts.
    var voltage: Double?
    /// mA; positive while charging, negative on battery.
    var amperage: Int?
    /// Watts flowing into the battery; nil unless it is charging.
    var chargeWatts: Double?
    /// The whole Mac's draw in watts: the power telemetry's system load, else the battery's own
    /// output (on battery only).
    var systemDrawWatts: Double?
    /// The connected adapter's rating; nil without one.
    var adapterWatts: Int?
    var minutesToFull: Int?
    var minutesToEmpty: Int?
    /// °C, when the system shows it to apps.
    var temperature: Double?

    /// Both IOKit reads; nil without a battery.
    static func read(power: PowerState) -> BatteryDetails? {
        guard let properties = BatteryProbe.properties() else { return nil }
        let adapter = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any]
        return BatteryDetails(properties: properties, adapter: adapter, power: power)
    }

    /// - Parameters:
    ///   - properties: `AppleSmartBattery`'s registry properties.
    ///   - adapter: `IOPSCopyExternalPowerAdapterDetails`.
    ///   - power: the monitor's state; its estimate is the one the menu bar shows, the gauge's
    ///     averages stand in while it has none.
    init(properties: [String: Any], adapter: [String: Any]?, power: PowerState) {
        let data = properties["BatteryData"] as? [String: Any] ?? [:]
        func value(_ key: String) -> Int? { BatteryProbe.signed(data[key] ?? properties[key]) }

        cycleCount = BatteryProbe.signed(properties["CycleCount"])
        designCycleCount = BatteryProbe.signed(properties["DesignCycleCount9C"] ?? properties["DesignCycleCount70"])
        designCapacity = value("DesignCapacity")
        fullChargeCapacity = BatteryProbe.signed(data["FullChargeCapacity"] ?? properties["AppleRawMaxCapacity"])
        nominalChargeCapacity = value("NominalChargeCapacity")
        // Apple silicon pins `MaxCapacity` at 100 and rates health by the nominal capacity. On the
        // development Mac (bq40z651, 38 cycles) nominal 6460 over design 6249 mAh is what
        // `system_profiler SPPowerDataType` shows as "Maximum Capacity: 100%" (full charge, 6308,
        // would say the same while new; the nominal figure is the one macOS follows as it wears).
        if let design = designCapacity, design > 0, let held = nominalChargeCapacity ?? fullChargeCapacity {
            maximumCapacityPercent = min(100, Int((Double(held) / Double(design) * 100).rounded()))
        }
        let failure = BatteryProbe.signed(properties["PermanentFailureStatus"]) ?? 0
        condition = failure == 0 ? .normal : .serviceRecommended(failure)

        let millivolts = BatteryProbe.signed(properties["Voltage"])
        voltage = millivolts.map { Double($0) / 1000 }
        amperage = BatteryProbe.signed(properties["InstantAmperage"] ?? properties["Amperage"])
        if let millivolts, let amperage, amperage > 0 {
            chargeWatts = Double(millivolts) * Double(amperage) / 1_000_000
        }
        let telemetry = properties["PowerTelemetryData"] as? [String: Any]
        let systemLoad = BatteryProbe.signed(telemetry?["SystemLoad"]).map(Double.init)
        systemDrawWatts = (systemLoad ?? BatteryProbe.systemDrawMW(properties)).map { $0 / 1000 }
        adapterWatts = BatteryProbe.signed(adapter?["Watts"]).flatMap { $0 > 0 ? $0 : nil }

        minutesToFull = power.isCharging
            ? power.minutesRemaining ?? Self.estimate(properties["AvgTimeToFull"]) : nil
        minutesToEmpty = power.isOnBattery
            ? power.minutesRemaining ?? Self.estimate(properties["AvgTimeToEmpty"] ?? data["AvgTimeToEmpty"]) : nil

        temperature = BatteryProbe.signed(properties["Temperature"] ?? properties["VirtualTemperature"])
            .map { Double($0) / 100 }
    }

    /// `demo/batteryhistory`'s: a battery a year and a half old, on a 96 W adapter while plugged in.
    static func demo(power: PowerState) -> BatteryDetails {
        BatteryDetails(properties: ["CycleCount": 212, "DesignCycleCount9C": 1000,
                                    "BatteryData": ["DesignCapacity": 6249, "NominalChargeCapacity": 5870]],
                       adapter: power.isPluggedIn ? ["Watts": 96] : nil, power: power)
    }

    /// The gauge's averages are minutes; 65535 is its "unknown".
    static func estimate(_ value: Any?) -> Int? {
        guard let minutes = BatteryProbe.signed(value), minutes > 0, minutes < 0xFFFF else { return nil }
        return minutes
    }
}
