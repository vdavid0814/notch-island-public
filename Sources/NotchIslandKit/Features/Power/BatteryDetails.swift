import Foundation
import IOKit.ps

/// The battery's health and the power flowing through it: what the battery page and its widgets
/// show beyond the level. Read from the gauge (`BatteryProbe`) and the adapter, off the main
/// thread; `BatteryCenter` decides when.
///
/// On macOS 27 an app sees fewer of the gauge's keys than root does: the permanent failure status
/// and the top-level capacities are absent on Apple silicon, so those fields are optional and the
/// capacities come from `BatteryData`. The temperature is on the pack below the gauge
/// (`AppleSmartBatteryPack`), where a MacBook Air M5 shows it and older Macs may not.
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
    /// System Settings' "Maximum Capacity": macOS's own figure (`SystemBatteryHealth`), else nominal
    /// over design capacity, at most 100.
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

    /// The IOKit reads, and macOS's maximum capacity (cached for a day); nil without a battery.
    static func read(power: PowerState) -> BatteryDetails? {
        guard let properties = BatteryProbe.properties() else { return nil }
        let adapter = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any]
        let cycles = BatteryProbe.signed(properties["CycleCount"])
        return BatteryDetails(properties: properties, pack: BatteryProbe.packData(), adapter: adapter, power: power,
                              systemMaximumCapacity: SystemBatteryHealth.maximumCapacity(cycleCount: cycles))
    }

    /// - Parameters:
    ///   - properties: `AppleSmartBattery`'s registry properties.
    ///   - pack: `AppleSmartBatteryPack`'s `BatteryData` (the temperature).
    ///   - adapter: `IOPSCopyExternalPowerAdapterDetails`.
    ///   - power: the monitor's state; its estimate is the one the menu bar shows, the gauge's
    ///     averages stand in while it has none.
    ///   - systemMaximumCapacity: the percentage System Settings shows, when macOS gave it.
    init(properties: [String: Any], pack: [String: Any]? = nil, adapter: [String: Any]?, power: PowerState,
         systemMaximumCapacity: Int? = nil) {
        let data = properties["BatteryData"] as? [String: Any] ?? [:]
        func value(_ key: String) -> Int? { BatteryProbe.signed(data[key] ?? properties[key]) }

        cycleCount = BatteryProbe.signed(properties["CycleCount"])
        designCycleCount = BatteryProbe.signed(properties["DesignCycleCount9C"] ?? properties["DesignCycleCount70"])
        designCapacity = value("DesignCapacity")
        fullChargeCapacity = BatteryProbe.signed(data["FullChargeCapacity"] ?? properties["AppleRawMaxCapacity"])
        nominalChargeCapacity = value("NominalChargeCapacity")
        // Apple silicon pins `MaxCapacity` at 100, and no key an app can read gives System
        // Settings' figure on every Mac: on a MacBook Air M5 (bq40z651, 58 cycles) it says 98 %
        // while nominal over design is 4591 / 4629 mAh (99 %) and full charge over design 4464 /
        // 4629 (96 %). So macOS's own figure is taken where it gives one, and nominal over design
        // (the one that matched on a MacBook Pro at 38 cycles) stands in otherwise.
        if let systemMaximumCapacity {
            maximumCapacityPercent = min(max(systemMaximumCapacity, 0), 100)
        } else if let design = designCapacity, design > 0, let held = nominalChargeCapacity ?? fullChargeCapacity {
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

        temperature = BatteryProbe.temperature(properties: properties, pack: pack)
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
