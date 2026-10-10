import Foundation

/// One fan as the SMC reports it: its speed now, the range it runs in, and whether it is held at a
/// speed (manual) or left to macOS (automatic).
nonisolated struct FanReading: Sendable, Equatable {
    var index: Int
    var rpm: Double
    var minimum: Double
    var maximum: Double
    /// The speed it is held at while manual.
    var target: Double
    var isManual: Bool

    var range: Double { max(maximum - minimum, 1) }

    /// 0…1 of its range: how far between its slowest and its fastest it runs.
    func fraction(of rpm: Double) -> Double { min(max((rpm - minimum) / range, 0), 1) }

    /// The speed `fraction` of its range is, to the nearest 50 rpm.
    func rpm(at fraction: Double) -> Double {
        ((minimum + min(max(fraction, 0), 1) * range) / 50).rounded() * 50
    }
}

/// The fans, read from the SMC. MacBook Pros have one or two; a MacBook Air none (FNum is 0 or
/// missing), so Fan Control is offered only where there is a fan.
///
/// `NI_DEMO_FANS=1` or `2` in the environment (`open --env`) puts simulated fans in their place
/// (`FanSimulator`), so the widget can be tried and pictured on a Mac without one.
nonisolated enum FanSensors {
    /// The simulated fans' count, when asked for in the environment (a developer's switch: nothing
    /// kept on the Mac turns Fan Control on where there is no fan).
    static let demoCount: Int? = demoCount(environment: ProcessInfo.processInfo.environment["NI_DEMO_FANS"])

    static func demoCount(environment: String?) -> Int? {
        environment.flatMap(Int.init).flatMap { $0 > 0 ? min($0, 2) : nil }
    }

    static var isSimulated: Bool { demoCount != nil }

    /// How many fans the Mac has (one SMC read, once).
    static let count: Int = demoCount ?? Int(SMC.shared?.number("FNum") ?? 0)

    static var hasFans: Bool { count > 0 }

    /// The fans now. Touches the SMC: off the main thread.
    static func read() -> [FanReading] {
        if isSimulated { return FanSimulator.shared.read() }
        guard let smc = SMC.shared else { return [] }
        return (0..<count).compactMap { index in
            guard let rpm = smc.number("F\(index)Ac"), let minimum = smc.number("F\(index)Mn"),
                  let maximum = smc.number("F\(index)Mx") else { return nil }
            return FanReading(index: index, rpm: max(rpm, 0), minimum: minimum, maximum: max(maximum, minimum + 1),
                              target: smc.number("F\(index)Tg") ?? rpm, isManual: (smc.number(modeKey(index)) ?? 0) == 1)
        }
    }

    /// The key that holds a fan's mode (0 automatic, 1 manual): "F0md" on the newer chips, "F0Md"
    /// on the others; which one, asked once.
    static func modeKey(_ index: Int) -> String {
        "F\(index)\(lowerModeKey ? "md" : "Md")"
    }

    private static let lowerModeKey: Bool = SMC.shared?.read("F0md").map { !$0.bytes.isEmpty } ?? false
}

/// Fans that are not there (`NI_DEMO_FANS`): a MacBook Pro's, about as quick to speed up and slow
/// down, set by the widget directly instead of through the helper.
nonisolated final class FanSimulator: @unchecked Sendable {
    static let shared = FanSimulator()

    private let lock = NSLock()
    private var fans: [FanReading]
    private var last = Date.now

    private init() {
        let count = FanSensors.demoCount ?? 1
        fans = (0..<count).map { FanReading(index: $0, rpm: 2300 + Double($0) * 80, minimum: 1200 + Double($0) * 100,
                                            maximum: 5700 + Double($0) * 200, target: 0, isManual: false) }
    }

    func read() -> [FanReading] {
        lock.lock()
        defer { lock.unlock() }
        // Each second a fan gets a third of the way to where it is going.
        let step = min(Date.now.timeIntervalSince(last), 3)
        last = .now
        for index in fans.indices {
            let goal = fans[index].isManual ? fans[index].target : fans[index].minimum + fans[index].range * 0.24
            fans[index].rpm += (goal - fans[index].rpm) * min(step / 3, 1)
            fans[index].rpm = (fans[index].rpm + Double.random(in: -12...12)).rounded()
        }
        return fans
    }

    func set(_ rpms: [Double]) {
        lock.lock()
        defer { lock.unlock() }
        for (index, rpm) in rpms.enumerated() where fans.indices.contains(index) {
            fans[index].target = min(max(rpm, fans[index].minimum), fans[index].maximum)
            fans[index].isManual = true
        }
    }

    func setAutomatic() {
        lock.lock()
        defer { lock.unlock() }
        for index in fans.indices {
            fans[index].isManual = false
            fans[index].target = 0
        }
    }
}
