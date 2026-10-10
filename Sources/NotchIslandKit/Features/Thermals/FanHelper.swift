import Foundation
import Security

/// What the app asks of the fan helper, over XPC.
@objc(NIFanHelperProtocol) nonisolated protocol FanHelperProtocol {
    /// Holds each fan at its speed (rpm, by fan; clamped to the fan's own range). Replies nil, or
    /// why it could not.
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
/// through `SMAppService.daemon` and allowed by the user in Login Items). Only root may write the
/// SMC's fan keys, so this is the one place that does.
///
/// It takes requests only from a process signed as it is (the app; `setCodeSigningRequirement`),
/// and keeps nothing for long: when the app's connection ends — it quit or crashed — the fans go
/// back to macOS at once; while they are held, a hot chip (95 °C) gives them back too; and with no
/// connection it quits after a minute.
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

    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0" }
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

    func start() {
        writer = SMC.shared.map(FanWriter.init)
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
        Log.fans.notice("fan helper \(FanHelper.build, privacy: .public) started; \(FanSensors.count) fans")
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
        if writer.isHolding, let chip = ChipSensors.read(), chip.hottest >= 95 {
            Log.fans.notice("fan helper: chip at \(Int(chip.hottest)) °C; fans back to automatic")
            _ = writer.setAutomatic()
        }
        if connections == 0, !writer.isHolding, Date.now.timeIntervalSince(idleSince) > 60 { exit(0) }
    }

    func setSpeeds(_ rpms: [Double], reply: @escaping @Sendable (String?) -> Void) {
        queue.async { [self] in
            guard let writer else { return reply("The fans cannot be reached.") }
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

/// One connection's view of the helper.
nonisolated private final class FanHelperSession: NSObject, FanHelperProtocol, @unchecked Sendable {
    private let service: FanHelperService

    init(service: FanHelperService) { self.service = service }

    func setSpeeds(_ rpms: [NSNumber], withReply reply: @escaping @Sendable (String?) -> Void) {
        service.setSpeeds(rpms.map(\.doubleValue), reply: reply)
    }

    func setAutomatic(withReply reply: @escaping @Sendable (String?) -> Void) { service.setAutomatic(reply: reply) }

    func build(withReply reply: @escaping @Sendable (String) -> Void) { reply(FanHelper.build) }

    func quit(withReply reply: @escaping @Sendable () -> Void) { service.quit(reply: reply) }
}

/// The SMC writes that hold a fan at a speed and give it back, as Apple silicon wants them: the
/// fan's mode key set to 1 (manual) and its target to the speed. The newer chips (M5) take that as
/// it is; on M1–M4 macOS's thermal daemon keeps the fans until "Ftst" is set to 1, which takes it a
/// few seconds to notice. Given back: the mode 0, the target 0, and Ftst 0 again if it was set.
nonisolated private final class FanWriter: @unchecked Sendable {
    private let smc: SMC
    private(set) var isHolding = false
    private var setTest = false

    init(smc: SMC) { self.smc = smc }

    /// Holds fan by fan at `rpms`. Nil, or why not.
    func set(_ rpms: [Double]) -> String? {
        for (index, rpm) in rpms.enumerated() where index < FanSensors.count {
            guard let minimum = smc.number("F\(index)Mn"), let maximum = smc.number("F\(index)Mx") else {
                return "Fan \(index + 1) cannot be read."
            }
            let mode = FanSensors.modeKey(index)
            if smc.number(mode) != 1, !holdManual(mode) {
                Log.fans.error("fan helper: fan \(index) would not switch to manual")
                return "macOS would not give up the fans."
            }
            isHolding = true
            let speed = min(max(rpm, minimum), maximum)
            guard retry(10, { self.smc.write("F\(index)Tg", number: speed) }) else {
                Log.fans.error("fan helper: fan \(index) target refused")
                return "The fan's speed could not be set."
            }
        }
        return nil
    }

    func setAutomatic() -> String? {
        var failed = false
        for index in 0..<FanSensors.count {
            let mode = FanSensors.modeKey(index)
            if smc.number(mode) != 0, !retry(10, { self.smc.write(mode, bytes: [0]) }) { failed = true }
            _ = smc.write("F\(index)Tg", number: 0)
        }
        if setTest || smc.number("Ftst") == 1 {
            if retry(10, { self.smc.write("Ftst", bytes: [0]) }) { setTest = false } else { failed = true }
        }
        isHolding = failed
        if failed { Log.fans.error("fan helper: fans not all back to automatic") }
        return failed ? "The fans could not all be given back to macOS." : nil
    }

    private func holdManual(_ mode: String) -> Bool {
        if smc.write(mode, bytes: [1]) { return true }
        // M1–M4: ask the thermal daemon to let go first.
        guard smc.read("Ftst") != nil else { return false }
        if smc.number("Ftst") != 1 {
            guard retry(100, { self.smc.write("Ftst", bytes: [1]) }) else { return false }
            setTest = true
            Thread.sleep(forTimeInterval: 3)
        }
        return retry(200) { self.smc.write(mode, bytes: [1]) }
    }

    private func retry(_ attempts: Int, _ body: () -> Bool) -> Bool {
        for attempt in 0..<attempts {
            if body() { return true }
            if attempt < attempts - 1 { Thread.sleep(forTimeInterval: 0.05) }
        }
        return false
    }
}
