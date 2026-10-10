import Foundation
import ServiceManagement

/// The fans for Fan Control: read every second while the widget shows them, held at a speed or
/// given back to macOS through the fan helper (`FanHelper`).
///
/// The helper needs the user's yes once: the first time a speed is set it is registered
/// (`SMAppService.daemon`) and macOS lists it under System Settings ▸ General ▸ Login Items, where
/// it is switched on; until then `access` says so and the widget points there. Where macOS will not
/// register it (a build that is not notarized, on a Mac it was downloaded to), it is installed with
/// an administrator's password instead (`FanInstaller`), asked for then and there.
@Observable final class FanCenter {
    /// Whether the helper may be used.
    nonisolated enum Access: Equatable, Sendable {
        /// Not asked yet (nothing has been set).
        case unknown
        /// Registered; waiting for the switch in Login Items.
        case needsApproval
        /// Being installed: macOS is asking for an administrator's password.
        case installing
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

    /// Each reading's average speed (for the speed graph, `ThermalMonitor.record`).
    @ObservationIgnored var onRead: ((Double) -> Void)?

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
    /// When the request on its way was sent: one never answered is given up (`answerTimeout`).
    @ObservationIgnored private var sentAt: Date?
    /// The helper was registered again after it could not be reached (once a run).
    @ObservationIgnored private var repaired = false
    /// The installed copy was replaced in this run (once: one that still answers another revision
    /// is used as it is).
    @ObservationIgnored private var reinstalled = false

    /// The helper answers within this (holding a fan the first time takes M1–M4 up to fifteen
    /// seconds); past it the connection is dropped and the next request starts over.
    static let answerTimeout: TimeInterval = 30

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
        if isSending, let sentAt, Date.now.timeIntervalSince(sentAt) > Self.answerTimeout {
            Log.fans.error("fan helper did not answer")
            unreachable(String(localized: "The fan helper did not answer."))
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
            if !read.isEmpty { onRead?(read.map(\.rpm).reduce(0, +) / Double(read.count)) }
            // The fans hold what was asked: the dial follows them again. Given up after five
            // seconds (unless still sending, or waiting for the yes in Login Items).
            if let requested, let fan = read.first, !isSending, pending == nil, access != .needsApproval, access != .installing,
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
        // A click on the fan after a failure: the next turn of the dial starts over.
        if case .failed = access { access = .unknown }
        if FanSensors.isSimulated {
            FanSimulator.shared.setAutomatic()
            return sample()
        }
        guard access == .ready || FanInstaller.isInstalled || daemon.status == .enabled else { return }
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
        sentAt = .now
        let sent = rpms
        pending = nil
        withHelper { helper in
            helper.setSpeeds(sent.map { NSNumber(value: $0) }) { error in
                Task { @MainActor in
                    self.isSending = false
                    self.sentAt = nil
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

    /// Whether the helper can be used now; registers it the first time, points at Login Items
    /// while it waits for the user's yes, and installs it with a password where macOS will not
    /// register it.
    private func prepare() -> Bool {
        if access == .installing { return false }
        // Installed with a password before: used as it is.
        if FanInstaller.isInstalled {
            access = .ready
            return true
        }
        switch daemon.status {
        case .enabled:
            access = .ready
            return true
        case .requiresApproval:
            if access != .needsApproval { SMAppService.openSystemSettingsLoginItems() }
            access = .needsApproval
            return false
        default:
            // Not registered yet. macOS reports a daemon it has never seen as `.notFound`, not
            // `.notRegistered` (0.8.4 took that for a build without the helper and gave up: Fan
            // Control said Unavailable on every MacBook Pro), so both are registered here.
            var failure: NSError?
            do {
                try daemon.register()
                Log.fans.notice("fan helper registered")
            } catch {
                // Registering asks for the user's yes and throws meanwhile ("Operation not
                // permitted"): the status says whether it went through.
                failure = error as NSError
            }
            switch daemon.status {
            case .enabled:
                access = .ready
            case .requiresApproval:
                Log.fans.notice("fan helper registered; waiting for Login Items")
                access = .needsApproval
                SMAppService.openSystemSettingsLoginItems()
            default:
                // macOS will not register it (not notarized, it says no more than "not found"):
                // installed with a password instead.
                let reason = failure.map { "\($0.domain) \($0.code): \($0.localizedDescription)" } ?? "status \(daemon.status.rawValue)"
                Log.fans.notice("fan helper not registered (\(reason, privacy: .public)); installing it with a password")
                install()
            }
            return access == .ready
        }
    }

    /// Installs the helper with an administrator's password (macOS asks), then sends the speed asked
    /// for. Cancelled: nothing is held, and the next turn of the dial asks again.
    private func install() {
        guard access != .installing else { return }
        access = .installing
        connection?.invalidate()
        connection = nil
        checkedBuild = false
        let daemon = daemon
        Task {
            // Never both: the registered one and the installed one share a Mach service.
            if daemon.status != .notFound && daemon.status != .notRegistered { try? await daemon.unregister() }
            let outcome = await FanInstaller.install()
            switch outcome {
            case .done:
                Log.fans.notice("fan helper installed")
                access = .ready
                if let pending { send(pending) }
            case .cancelled:
                Log.fans.notice("fan helper: the password was not given")
                access = .unknown
                requested = nil
                pending = nil
            case .failed(let reason):
                Log.fans.error("fan helper install failed: \(reason, privacy: .public)")
                access = .failed(reason)
                requested = nil
                pending = nil
            }
        }
    }

    /// Removes the helper, however it was put there (the fans back to macOS first): the registered
    /// one unregistered, the installed one removed with an administrator's password.
    func removeHelper() {
        setAutomatic()
        connection?.invalidate()
        connection = nil
        checkedBuild = false
        let daemon = daemon
        Task {
            if daemon.status != .notFound && daemon.status != .notRegistered { try? await daemon.unregister() }
            if FanInstaller.isInstalled {
                let outcome = await FanInstaller.remove()
                Log.fans.notice("fan helper removed: \(String(describing: outcome), privacy: .public)")
            }
            access = .unknown
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
        let installed = FanInstaller.isInstalled
        // An installed copy of another revision: replaced (the password again), once a run; the
        // speed asked for is sent when it is in.
        if installed, build != FanHelper.installedBuild, !reinstalled {
            reinstalled = true
            Log.fans.notice("fan helper \(build, privacy: .public) is not revision \(FanHelper.revision); installing this one")
            waiting.removeAll()
            isSending = false
            sentAt = nil
            if pending == nil, let requested {
                pending = (fans.isEmpty ? FanSensors.read() : fans).map { $0.rpm(at: requested) }
            }
            return install()
        }
        if installed || build == FanHelper.build {
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
                self.unreachable(error.localizedDescription)
            }
        } as? any FanHelperProtocol
    }

    /// The helper could not be reached, or never answered: the connection is dropped. The first
    /// time in a run it is registered again and the speed asked for sent once more — a registration
    /// left by another copy of the app (moved, or replaced by hand) points at an executable that is
    /// gone; after that the widget says why.
    private func unreachable(_ reason: String) {
        let wasSending = isSending
        connection?.invalidate()
        connection = nil
        checkedBuild = false
        isSending = false
        sentAt = nil
        waiting.removeAll()
        guard wasSending else { return }
        guard !repaired, let last = requested, !FanInstaller.isInstalled, daemon.status == .enabled else {
            access = .failed(reason)
            requested = nil
            pending = nil
            return
        }
        repaired = true
        Log.fans.notice("fan helper unreachable; registering it again")
        let daemon = daemon
        Task {
            try? await daemon.unregister()
            try? await Task.sleep(for: .milliseconds(500))
            guard requested == last else { return }
            setSpeed(last)
        }
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
