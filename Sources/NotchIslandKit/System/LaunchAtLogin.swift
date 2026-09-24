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

    func refresh() {
        let current = SMAppService.mainApp.status
        if current != status { status = current }
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
        refresh()
    }
}
