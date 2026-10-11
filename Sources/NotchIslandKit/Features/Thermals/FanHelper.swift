import Foundation
import Security

/// What the app asks of the fan helper, over XPC.
@objc(NIFanHelperProtocol) nonisolated protocol FanHelperProtocol {
    /// Holds each fan at its speed (rpm, by fan; from nothing — a fan stopped — to its fastest).
    /// Replies nil, or why it could not (`FanHelper.tooHot` while the chip is at its limit).
    func setSpeeds(_ rpms: [NSNumber], withReply reply: @escaping @Sendable (String?) -> Void)
    /// Gives the fans back to macOS.
    func setAutomatic(withReply reply: @escaping @Sendable (String?) -> Void)
    /// The build it runs (CFBundleVersion), so an app updated since starts it again.
    func build(withReply reply: @escaping @Sendable (String) -> Void)
    /// Quits after replying (fans back to macOS first); launchd starts it again, from the app's
    /// current executable, at the next request.
    func quit(withReply reply: @escaping @Sendable () -> Void)
}

/// The fan helper: the app's own executable, started by launchd as root
/// (`NotchIsland --fan-helper`, from the bundle's `Contents/Library/LaunchDaemons` plist, registered
/// through `SMAppService.daemon` and allowed by the user in Login Items — or, where macOS will not
/// register it, a copy installed with an administrator's password, `FanInstaller`). Only root may
/// write the SMC's fan keys, so this is the one place that does.
///
/// It takes requests only from a process signed as it is (the app; `setCodeSigningRequirement`),
/// and keeps nothing for long: when the app's connection ends — it quit or crashed — the fans go
/// back to macOS at once; and with no connection it quits after a minute. While they are held it
/// looks every three seconds that they still are (macOS takes them back over sleep), and holds them
/// again (`FanWriter.maintain`).
///
/// A speed set by hand stays (a fan may be held still): the one thing that gives the fans back by
/// itself is the chip at its limit — its hottest core at 105 °C three looks in a row (`HeatGuard`;
/// under a heavy load cores read 95–100 °C with macOS's own fan curve too, so nothing lower may
/// count). They stay with macOS, and a new speed is refused (`tooHot`), until it is under 95 °C.
nonisolated public enum FanHelper {
    public static let flag = "--fan-helper"
    static let label = "com.davidvarga.notchisland.fanhelper"
    static let plistName = label + ".plist"

    /// Runs the helper when the process was started as one; returns otherwise.
    public static func runIfAsked() {
        guard CommandLine.arguments.contains(flag) else { return }
        guard getuid() == 0 else {
            Log.fans.error("fan helper: not started as root")
            exit(1)
        }
        let service = FanHelperService()
        service.start()
        dispatchMain()
    }

    /// Started from the copy `FanInstaller` put in /Library/PrivilegedHelperTools.
    static let installedFlag = "--installed"
    /// The helper's own code, counted: an installed copy of another revision is replaced.
    static let revision = 3

    /// What `setSpeeds` replies while the chip is at its limit: the fans stay with macOS.
    static let tooHot = "too hot"

    /// The app's build (CFBundleVersion).
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0" }
    /// What an installed copy answers for its build (it has no bundle to read one from).
    static var installedBuild: String { "r\(revision)" }
    /// What this process, as the helper, answers.
    static var running: String { CommandLine.arguments.contains(installedFlag) ? installedBuild : build }
}

/// The helper's listener and its state: the connections open, whether the fans are held.
nonisolated private final class FanHelperService: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
    private let listener = NSXPCListener(machServiceName: FanHelper.label)
    /// Every SMC write and every change of state, one at a time.
    private let queue = DispatchQueue(label: "com.davidvarga.notchisland.fanhelper.smc", qos: .userInitiated)
    private var connections = 0
    private var writer: FanWriter?
    private var idleSince = Date.now
    private var watch: (any DispatchSourceTimer)?
    private var signals: [any DispatchSourceSignal] = []
    private var heat = HeatGuard()

    func start() {
        writer = SMC.shared.map { FanWriter(smc: $0) }
        listener.delegate = self
        listener.resume()
        // Stopped by launchd (or an uninstall): the fans back to macOS first.
        for number in [SIGTERM, SIGINT, SIGHUP] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: queue)
            source.setEventHandler { [weak self] in
                _ = self?.writer?.setAutomatic()
                exit(0)
            }
            source.resume()
            signals.append(source)
        }
        // Every three seconds: the chip while the fans are held, and quitting once idle.
        let watch = DispatchSource.makeTimerSource(queue: queue)
        watch.schedule(deadline: .now() + 3, repeating: 3, leeway: .seconds(1))
        watch.setEventHandler { [weak self] in self?.check() }
        watch.resume()
        self.watch = watch
        Log.fans.notice("fan helper \(FanHelper.running, privacy: .public) started; \(FanSensors.count) fans")
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        // Only the app: signed exactly as this executable is (it is the app's own).
        guard let requirement = Self.ownRequirement else { return false }
        connection.setCodeSigningRequirement(requirement)
        connection.exportedInterface = NSXPCInterface(with: (any FanHelperProtocol).self)
        connection.exportedObject = FanHelperSession(service: self)
        connection.invalidationHandler = { [weak self] in self?.connectionEnded() }
        queue.sync { connections += 1 }
        connection.resume()
        return true
    }

    private func connectionEnded() {
        queue.async { [self] in
            connections = max(0, connections - 1)
            guard connections == 0 else { return }
            idleSince = .now
            // The app is gone: nobody is left to give the fans back.
            if writer?.isHolding == true {
                Log.fans.notice("fan helper: the app went away; fans back to automatic")
                _ = writer?.setAutomatic()
            }
        }
    }

    private func check() {
        guard let writer else { return }
        if writer.isHolding || heat.isTripped, let chip = ChipSensors.read(), heat.check(hottest: chip.hottest, holding: writer.isHolding) {
            Log.fans.notice("fan helper: chip at \(Int(chip.hottest)) °C; fans back to automatic")
            _ = writer.setAutomatic()
        }
        writer.maintain()
        if connections == 0, !writer.isHolding, Date.now.timeIntervalSince(idleSince) > 60 { exit(0) }
    }

    func setSpeeds(_ rpms: [Double], reply: @escaping @Sendable (String?) -> Void) {
        queue.async { [self] in
            guard let writer else { return reply("The fans cannot be reached.") }
            // Given back for the heat: left with macOS until the chip has cooled.
            if heat.isTripped, let chip = ChipSensors.read() { _ = heat.check(hottest: chip.hottest, holding: false) }
            guard !heat.isTripped else { return reply(FanHelper.tooHot) }
            reply(writer.set(rpms))
        }
    }

    func setAutomatic(reply: @escaping @Sendable (String?) -> Void) {
        queue.async { [self] in reply(writer?.setAutomatic()) }
    }

    func quit(reply: @escaping @Sendable () -> Void) {
        queue.async { [self] in
            _ = writer?.setAutomatic()
            reply()
            queue.asyncAfter(deadline: .now() + 0.2) { exit(0) }
        }
    }

    /// The designated requirement of this executable's signature: the app's.
    private static let ownRequirement: String? = {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var requirement: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(staticCode, [], &requirement) == errSecSuccess, let requirement else { return nil }
        var text: CFString?
        guard SecRequirementCopyString(requirement, [], &text) == errSecSuccess else { return nil }
        return text as String?
    }()
}

/// The one thing that takes held fans back by itself: the chip at its limit. Its hottest core at
/// `limit` for `patience` looks in a row (three seconds apart) trips it; it stays tripped — the fans
/// with macOS, a new speed refused — until the chip is under `cooled`.
nonisolated struct HeatGuard: Sendable {
    static let limit = 105.0
    static let cooled = 95.0
    static let patience = 3

    private(set) var isTripped = false
    private var hotLooks = 0

    /// A look at the chip. True when the fans, held, are to be given back now.
    mutating func check(hottest: Double, holding: Bool) -> Bool {
        if isTripped {
            if hottest < Self.cooled { isTripped = false }
            return false
        }
        hotLooks = holding && hottest >= Self.limit ? hotLooks + 1 : 0
        guard hotLooks >= Self.patience else { return false }
        hotLooks = 0
        isTripped = true
        return true
    }
}

/// One connection's view of the helper.
nonisolated private final class FanHelperSession: NSObject, FanHelperProtocol, @unchecked Sendable {
    private let service: FanHelperService

    init(service: FanHelperService) { self.service = service }

    func setSpeeds(_ rpms: [NSNumber], withReply reply: @escaping @Sendable (String?) -> Void) {
        service.setSpeeds(rpms.map(\.doubleValue), reply: reply)
    }

    func setAutomatic(withReply reply: @escaping @Sendable (String?) -> Void) { service.setAutomatic(reply: reply) }

    func build(withReply reply: @escaping @Sendable (String) -> Void) { reply(FanHelper.running) }

    func quit(withReply reply: @escaping @Sendable () -> Void) { service.quit(reply: reply) }
}

/// What the fan writer needs of the SMC (`SMC`; a test's stands in for a Mac's).
nonisolated protocol FanKeys: AnyObject {
    func read(_ key: String) -> SMC.Value?
    func number(_ key: String) -> Double?
    func write(_ key: String, bytes: [UInt8]) -> Bool
    func result(ofWriting key: String, bytes: [UInt8]) -> UInt8?
}

nonisolated extension SMC: FanKeys {}

/// The SMC writes that hold a fan at a speed and give it back, as Apple silicon wants them: the
/// fan's mode key set to 1 (manual) and its target to the speed.
///
/// What is known of it (Apple documents none; from the tools that do it — Macs Fan Control, Stats,
/// TG Pro, and agoodkind/macos-smc-fan's notes):
/// - M5 takes the mode as it is ("F0md", lower case; it has no "Ftst").
/// - M1–M4 ("F0Md"): macOS's thermal daemon holds the fans in its own mode (3) and the SMC refuses
///   the mode (0x82), or takes it and puts it back, until "Ftst" is set to 1; the daemon lets go
///   three to six seconds later. Given back: the mode 0, and Ftst 0 once no fan is held.
/// - A write the SMC says it took may not have been (and one it says it refused, 0x87 on a target,
///   may have been): every write is read back, and only what reads back counts.
/// - Sleep clears the mode and Ftst, and the firmware may take the fans back at any time: `maintain`
///   (every three seconds while held) writes them again, and gives up when they will not hold.
nonisolated final class FanWriter: @unchecked Sendable {
    private let smc: any FanKeys
    private let count: Int
    private let modeKey: (Int) -> String
    /// Waiting between tries (a test does not wait).
    private let pause: (TimeInterval) -> Void
    /// The speeds held, fan by fan; empty while macOS runs them.
    private(set) var held: [Double] = []
    /// Giving back failed: still to be given back.
    private var unreleased = false
    private var setTest = false
    /// `maintain` in a row that could not hold the fans again.
    private var failures = 0
    /// Fans the SMC will not hold slower than their slowest: held there instead, not tried again.
    private var keepsTurning: Set<Int> = []

    var isHolding: Bool { !held.isEmpty || unreleased }

    /// A target reads back within this many rpm of what was written.
    private static let tolerance = 2.0
    /// The fans not holding this many times in a row are given back for good.
    private static let patience = 5

    init(smc: any FanKeys, count: Int = FanSensors.count, modeKey: @escaping (Int) -> String = FanSensors.modeKey,
         pause: @escaping (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }) {
        self.smc = smc
        self.count = count
        self.modeKey = modeKey
        self.pause = pause
    }

    /// Holds fan by fan at `rpms`. Nil, or why not (the fans back with macOS then).
    func set(_ rpms: [Double]) -> String? {
        var speeds: [Double] = []
        for (index, rpm) in rpms.enumerated() where index < count {
            guard let minimum = smc.number("F\(index)Mn"), let maximum = smc.number("F\(index)Mx"), maximum > minimum else {
                _ = setAutomatic()
                return "Fan \(index + 1) cannot be read."
            }
            // From nothing (the fan stopped) to its fastest. Slower than macOS itself turns it, a Mac
            // may not have it: the fan is held at its slowest there.
            var speed = min(max(rpm, 0), maximum)
            if speed < minimum, keepsTurning.contains(index) { speed = minimum }
            var error = hold(index, at: speed)
            if error != nil, speed < minimum, hold(index, at: minimum) == nil {
                Log.fans.notice("fan helper: fan \(index) is not held under \(Int(minimum)) rpm (\(error ?? "", privacy: .public)); held there")
                keepsTurning.insert(index)
                speed = minimum
                error = nil
            }
            if let error {
                Log.fans.error("fan helper: fan \(index): \(error, privacy: .public)")
                _ = setAutomatic()
                return error
            }
            speeds.append(speed)
        }
        guard !speeds.isEmpty else { return "This Mac has no fan to set." }
        held = speeds
        failures = 0
        return nil
    }

    /// The fans held are still held as asked: one macOS took back (after sleep, or its thermal
    /// daemon) is held again. Given back for good when it will not hold.
    func maintain() {
        guard !held.isEmpty else {
            if unreleased { _ = setAutomatic() }
            return
        }
        var lost = false
        for (index, speed) in held.enumerated() {
            if smc.number(modeKey(index)) == 1, let target = smc.number("F\(index)Tg"),
               abs(target - speed) <= Self.tolerance { continue }
            Log.fans.notice("fan helper: fan \(index) was taken back; holding it again")
            if let error = hold(index, at: speed) {
                Log.fans.error("fan helper: fan \(index) would not hold again: \(error, privacy: .public)")
                lost = true
            }
        }
        failures = lost ? failures + 1 : 0
        if failures >= Self.patience {
            Log.fans.error("fan helper: the fans will not hold; back to automatic")
            _ = setAutomatic()
        }
    }

    func setAutomatic() -> String? {
        held = []
        failures = 0
        var failed = false
        for index in 0..<count {
            let mode = modeKey(index)
            // The mode alone: macOS sets the target from then on (a target of 0 written here would
            // stop a fan whose mode had not gone back).
            guard smc.number(mode) == 1 else { continue }
            let released = retry(20) { _ = self.smc.write(mode, bytes: [0]); return self.smc.number(mode) != 1 }
            if !released { failed = true }
        }
        if setTest || smc.number("Ftst") == 1 {
            let cleared = retry(20) { _ = self.smc.write("Ftst", bytes: [0]); return self.smc.number("Ftst") != 1 }
            if cleared { setTest = false } else { failed = true }
        }
        unreleased = failed
        if failed { Log.fans.error("fan helper: fans not all back to automatic") }
        return failed ? "The fans could not all be given back to macOS." : nil
    }

    /// One fan in manual at `speed`, read back. Nil, or why not.
    private func hold(_ index: Int, at speed: Double) -> String? {
        let mode = modeKey(index), target = "F\(index)Tg"
        if smc.number(mode) != 1, let error = takeManual(mode) { return error }
        // The target, until it reads back (a read just after a write may still be the old one).
        var answer: UInt8?
        let written = retry(20) {
            answer = self.smc.read(target).flatMap { SMC.encode(speed, type: $0.type) }
                .flatMap { self.smc.result(ofWriting: target, bytes: $0) }
            self.pause(0.05)
            return self.smc.number(target).map { abs($0 - speed) <= Self.tolerance } ?? false
        }
        guard written else { return "The fan's speed could not be set (\(Self.text(answer)))." }
        // Taken back meanwhile: not held.
        guard smc.number(mode) == 1 else { return "macOS took the fans back." }
        return nil
    }

    /// The fan's mode to manual, read back: as it is, or after asking the thermal daemon to let go.
    private func takeManual(_ mode: String) -> String? {
        var answer = smc.result(ofWriting: mode, bytes: [1])
        if answer == SMC.success, holds(mode) { return nil }
        guard answer != nil else { return "The fan helper may not write to the SMC." }
        // M1–M4: ask the thermal daemon to let go first; it does within about six seconds.
        guard smc.read("Ftst") != nil else { return "macOS would not give up the fans (\(Self.text(answer)))." }
        if smc.number("Ftst") != 1 {
            guard retry(100, { self.smc.write("Ftst", bytes: [1]) }) else { return "macOS would not give up the fans (Ftst)." }
            setTest = true
        }
        let taken = retry(120, every: 0.1) {
            answer = self.smc.result(ofWriting: mode, bytes: [1])
            return answer == SMC.success && self.smc.number(mode) == 1
        }
        guard taken, holds(mode) else { return "macOS would not give up the fans (\(Self.text(answer)))." }
        return nil
    }

    /// The mode still manual a moment after it was written (one put back at once was never taken).
    private func holds(_ mode: String) -> Bool {
        pause(0.15)
        return smc.number(mode) == 1
    }

    private static func text(_ answer: UInt8?) -> String {
        answer.map { "SMC 0x" + String($0, radix: 16) } ?? "not allowed"
    }

    private func retry(_ attempts: Int, every pause: TimeInterval = 0.05, _ body: () -> Bool) -> Bool {
        for attempt in 0..<attempts {
            if body() { return true }
            if attempt < attempts - 1 { self.pause(pause) }
        }
        return false
    }
}
