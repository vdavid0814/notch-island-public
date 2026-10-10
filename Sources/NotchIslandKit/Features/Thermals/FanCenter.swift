import Foundation
import ServiceManagement

/// The fans for Fan Control: read every second while the widget shows them, held at a speed or
/// given back to macOS through the fan helper (`FanHelper`).
///
/// The helper needs the user's yes once: the first time a speed is set it is registered
/// (`SMAppService.daemon`) and macOS lists it under System Settings ▸ General ▸ Login Items, where
/// it is switched on. Until then `access` says so and the widget points there.
@Observable final class FanCenter {
    /// Whether the helper may be used.
    nonisolated enum Access: Equatable, Sendable {
        /// Not asked yet (nothing has been set).
        case unknown
        /// Registered; waiting for the switch in Login Items.
        case needsApproval
        case ready
        /// It cannot be used: why.
        case failed(String)
    }

    private(set) var fans: [FanReading] = []
    /// The speed asked for, 0…1 of each fan's range, from the moment it is asked until the fans read
    /// it back (or it is given up): the dial shows it at once.
    private(set) var requested: Double?
    private(set) var access: Access = .unknown

    var hasFans: Bool { FanSensors.hasFans }
    var isManual: Bool { requested != nil || fans.contains(where: \.isManual) }

    /// The speed held, 0…1 of the range (the first fan's; they are set alike).
    var heldFraction: Double? {
        if let requested { return requested }
        guard let fan = fans.first(where: \.isManual) else { return nil }
        return fan.fraction(of: fan.target)
    }

    static let interval: TimeInterval = 1

    @ObservationIgnored private var observers = 0
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var isReading = false
    @ObservationIgnored private var connection: NSXPCConnection?
    /// The latest speed waiting to be sent (one request at a time while dragging).
    @ObservationIgnored private var pending: [Double]?
    @ObservationIgnored private var isSending = false
    @ObservationIgnored private var checkedBuild = false
    /// Requests waiting for the helper to say which build it runs.
    @ObservationIgnored private var waiting: [(any FanHelperProtocol) -> Void] = []
    @ObservationIgnored private var requestedAt = Date.distantPast

    private var daemon: SMAppService { .daemon(plistName: FanHelper.plistName) }

    // MARK: Reading

    func startObserving() {
        observers += 1
        guard timer == nil, hasFans else { return }
        sample()
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        timer.tolerance = Self.interval / 4
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stopObserving() {
        observers = max(0, observers - 1)
        guard observers == 0 else { return }
        timer?.invalidate()
        timer = nil
    }

    private func sample() {
        // Switched on in Login Items meanwhile: ready, and the speed asked for is sent now.
        if access == .needsApproval, daemon.status == .enabled {
            access = .ready
            if let pending { send(pending) }
        }
        guard !isReading else { return }
        isReading = true
        Task {
            let read = await Task.detached(priority: .utility) { FanSensors.read() }.value
            isReading = false
            // Steps of under 20 rpm are noise: left out, so the dial redraws only when it moves.
            let same = read.count == fans.count && zip(read, fans).allSatisfy {
                abs($0.rpm - $1.rpm) < 20 && $0.isManual == $1.isManual && abs($0.target - $1.target) < 20
                    && $0.minimum == $1.minimum && $0.maximum == $1.maximum
            }
            if !same { fans = read }
            // The fans hold what was asked: the dial follows them again. Given up after five
            // seconds (unless still sending, or waiting for the yes in Login Items).
            if let requested, let fan = read.first, !isSending, pending == nil, access != .needsApproval,
               fan.isManual && abs(fan.fraction(of: fan.target) - requested) < 0.02 || Date.now.timeIntervalSince(requestedAt) > 5 {
                self.requested = nil
            }
        }
    }

    // MARK: Setting

    /// Holds every fan at `fraction` of its range (0 its slowest, 1 its fastest).
    func setSpeed(_ fraction: Double) {
        guard hasFans else { return }
        let fraction = min(max(fraction, 0), 1)
        requested = fraction
        requestedAt = .now
        let rpms = (fans.isEmpty ? FanSensors.read() : fans).map { $0.rpm(at: fraction) }
        guard !rpms.isEmpty else { return }
        send(rpms)
    }

    /// Gives the fans back to macOS: its own curve, as from the factory.
    func setAutomatic() {
        requested = nil
        pending = nil
        if FanSensors.isSimulated {
            FanSimulator.shared.setAutomatic()
            return sample()
        }
        guard access == .ready || daemon.status == .enabled else { return }
        withHelper { helper in
            helper.setAutomatic { error in
                Task { @MainActor in
                    if let error { Log.fans.error("fans to automatic: \(error, privacy: .public)") }
                    self.sample()
                }
            }
        }
    }

    private func send(_ rpms: [Double]) {
        if FanSensors.isSimulated {
            FanSimulator.shared.set(rpms)
            access = .ready
            return
        }
        pending = rpms
        guard prepare(), !isSending else { return }
        isSending = true
        let sent = rpms
        pending = nil
        withHelper { helper in
            helper.setSpeeds(sent.map { NSNumber(value: $0) }) { error in
                Task { @MainActor in
                    self.isSending = false
                    if let error {
                        Log.fans.error("fan speed: \(error, privacy: .public)")
                        self.access = .failed(error)
                        self.requested = nil
                        self.pending = nil
                    } else if let next = self.pending {
                        self.send(next)
                    }
                }
            }
        }
    }

    /// Whether the helper can be used now; registers it the first time, and points at Login Items
    /// while it waits for the user's yes.
    private func prepare() -> Bool {
        switch daemon.status {
        case .enabled:
            access = .ready
            return true
        case .requiresApproval:
            if access != .needsApproval { SMAppService.openSystemSettingsLoginItems() }
            access = .needsApproval
            return false
        case .notFound:
            // A build without the helper's plist (`swift run`): nothing to register.
            access = .failed(String(localized: "This build has no fan helper."))
            return false
        default:
            do {
                try daemon.register()
                Log.fans.notice("fan helper registered")
                access = daemon.status == .enabled ? .ready : .needsApproval
            } catch {
                // Registered, but waiting for the switch in Login Items.
                if daemon.status == .requiresApproval {
                    access = .needsApproval
                } else {
                    Log.fans.error("fan helper registration failed: \(error.localizedDescription, privacy: .public)")
                    access = .failed(error.localizedDescription)
                    return false
                }
            }
            if access == .needsApproval { SMAppService.openSystemSettingsLoginItems() }
            return access == .ready
        }
    }

    /// The helper's proxy, connected on first use; a helper of another build (the app updated since
    /// it started) is asked to quit first, so launchd starts the current one.
    private func withHelper(_ body: @escaping (any FanHelperProtocol) -> Void) {
        guard let helper = proxy() else { return }
        if checkedBuild { return body(helper) }
        waiting.append(body)
        guard waiting.count == 1 else { return }
        helper.build { build in
            Task { @MainActor in self.helperRuns(build) }
        }
    }

    /// The helper said which build it runs: the requests waiting go to it, or — another build —
    /// it is asked to quit first and they go to the one launchd starts next.
    private func helperRuns(_ build: String) {
        guard let helper = proxy() else { return waiting.removeAll() }
        if build == FanHelper.build {
            checkedBuild = true
            let bodies = waiting
            waiting.removeAll()
            return bodies.forEach { $0(helper) }
        }
        Log.fans.notice("fan helper \(build, privacy: .public) is not this build; restarting it")
        helper.quit {
            Task { @MainActor in
                self.connection?.invalidate()
                self.connection = nil
                try? await Task.sleep(for: .milliseconds(400))
                let bodies = self.waiting
                self.waiting.removeAll()
                self.checkedBuild = true
                bodies.forEach { self.withHelper($0) }
            }
        }
    }

    private func proxy() -> (any FanHelperProtocol)? {
        let connection = connection ?? connect()
        return connection.remoteObjectProxyWithErrorHandler { error in
            Task { @MainActor in
                Log.fans.error("fan helper connection: \(error.localizedDescription, privacy: .public)")
                self.connection?.invalidate()
                self.connection = nil
                self.isSending = false
                self.waiting.removeAll()
            }
        } as? any FanHelperProtocol
    }

    private func connect() -> NSXPCConnection {
        let connection = NSXPCConnection(machServiceName: FanHelper.label, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: (any FanHelperProtocol).self)
        connection.invalidationHandler = { [weak self] in
            Task { @MainActor in
                self?.connection = nil
                self?.checkedBuild = false
            }
        }
        connection.resume()
        self.connection = connection
        return connection
    }
}
