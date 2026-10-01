import ServiceManagement

/// "Open at login" through `SMAppService.mainApp`.
///
/// The system owns the truth (the user can flip the item in System Settings ▸ General ▸ Login Items
/// at any time), so nothing is persisted here: the toggle mirrors `SMAppService.mainApp.status`,
/// re-read by `refresh()` whenever Settings appears or the app becomes active.
@Observable final class LaunchAtLogin {
    private(set) var status: SMAppService.Status = .notRegistered
    /// The last register/unregister failure, shown under the toggle; nil after a success.
    private(set) var lastError: String?

    /// On while registered, including while the registration waits for the user's approval — the
    /// app did its part and the Settings row explains the missing step.
    var isEnabled: Bool {
        get { status == .enabled || status == .requiresApproval }
        set { setEnabled(newValue) }
    }

    /// Registered, but the user has to allow it in Login Items before it takes effect.
    var requiresApproval: Bool { status == .requiresApproval }

    init() {}

    /// Re-read in the background: the status is a synchronous request to the system's service
    /// manager (~20 ms on the main thread, measured in every Settings opening). At background
    /// priority, on the efficiency cores: nobody waits for it (20–37 ms of a performance core in
    /// every Settings opening otherwise, measured).
    func refresh() {
        refreshTask?.cancel()
        refreshTask = Task(priority: .background) { [weak self] in
            let current = await Self.readStatus()
            guard !Task.isCancelled, let self else { return }
            self.refreshTask = nil
            if current != self.status { self.status = current }
        }
    }

    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    @concurrent private static func readStatus() async -> SMAppService.Status {
        SMAppService.mainApp.status
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            Log.system.error("launch at login \(enabled ? "register" : "unregister", privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
        // At once: the switch the user just moved shows the outcome, not the old state for a moment.
        refreshTask?.cancel()
        refreshTask = nil
        let current = SMAppService.mainApp.status
        if current != status { status = current }
    }
}
