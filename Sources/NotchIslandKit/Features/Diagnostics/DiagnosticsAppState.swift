import AppKit
import ServiceManagement

/// The readings that need the app's own state, taken on the main actor: the island, the screens,
/// every feature's status, the preferences and what else is running.
enum DiagnosticsAppState {
    static let islandTitle = "Island"
    static let featuresTitle = DiagnosticsAppStateKeys.features
    static let copiesTitle = DiagnosticsAppStateKeys.copies
    static let instancesKey = DiagnosticsAppStateKeys.instances
    static let copiesKey = DiagnosticsAppStateKeys.copiesOnDisk
    static let otherNotchAppsKey = DiagnosticsAppStateKeys.otherNotchApps

    static func sections(_ model: AppModel) -> [DiagnosticsReport.Section] {
        [island(model), internals(model), screens(), windows(), features(model), effectiveSettings(model), copies(),
         preferences(), runningApps()]
    }

    private static func island(_ model: AppModel) -> DiagnosticsReport.Section {
        var section = DiagnosticsReport.Section(islandTitle)
        section.add("Presentation", String(describing: model.island.presentation))
        section.add("Page", String(describing: model.island.page))
        section.add("Pinned", model.island.isPinned)
        section.add("Pointer over it", model.island.isHovering)
        if let metrics = model.metrics {
            section.add("Display", metrics.displayID)
            section.add("Notch", "\(DiagnosticsFormat.rect(metrics.notchRect)), physical: \(metrics.isPhysical)")
            section.add("Screen", DiagnosticsFormat.rect(metrics.screenFrame))
        } else {
            section.add("Display", "none (no screen to anchor on)")
        }
        section.add("Glass style", "\(model.preferences.glassStyle) (drawn: \(model.effectiveGlassStyle))")
        section.add("Scale", String(describing: model.preferences.scale))
        section.add("Applied features", model.diagnosticsFeatureState)
        section.add("⌘Space tap running", model.diagnosticsCommandSpaceTapRunning)
        section.add("Hidden for full-screen video", model.hidesForFullscreenVideo)
        return section
    }

    private static func screens() -> DiagnosticsReport.Section {
        var section = DiagnosticsReport.Section("Screens")
        for (index, screen) in NSScreen.screens.enumerated() {
            let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            let left = screen.auxiliaryTopLeftArea.map { String(format: "%.0f", $0.width) } ?? "—"
            let right = screen.auxiliaryTopRightArea.map { String(format: "%.0f", $0.width) } ?? "—"
            section.add("\(index) \(screen.localizedName)",
                        "id \(id), \(DiagnosticsFormat.rect(screen.frame)) @\(screen.backingScaleFactor)x, safe-area top \(screen.safeAreaInsets.top), aux widths \(left) | \(right)\(screen == NSScreen.main ? ", main" : "")")
        }
        if NSScreen.screens.isEmpty { section.add("Screens", "none") }
        let workspace = NSWorkspace.shared
        section.add("Reduce transparency / motion", "\(workspace.accessibilityDisplayShouldReduceTransparency) / \(workspace.accessibilityDisplayShouldReduceMotion)")
        section.add("Increase contrast / invert", "\(workspace.accessibilityDisplayShouldIncreaseContrast) / \(workspace.accessibilityDisplayShouldInvertColors)")
        section.add("Appearance", NSApp.effectiveAppearance.name.rawValue)
        return section
    }

    private static func features(_ model: AppModel) -> DiagnosticsReport.Section {
        var section = DiagnosticsReport.Section(featuresTitle)
        section.add("Accessibility trusted", model.permissions.accessibilityTrusted)
        section.add("Launch at login", "\(launchAtLogin(model.launchAtLogin.status))\(model.launchAtLogin.lastError.map { ", error: \($0)" } ?? "")")
        section.add("Suspended", model.activity.isSuspended)
        section.add("Low Power Mode", model.activity.isLowPowerMode)
        section.add("Thermally constrained", model.activity.isThermallyConstrained)
        section.add("Reduce Motion", model.activity.reduceMotion)
        section.add("Media status", String(describing: model.media.status))
        section.add("Media player", model.media.item?.bundleIdentifier ?? "none")
        if let item = model.media.item {
            section.add("Now playing", "\(item.title) — \(item.artist) — \(item.album)\(item.duration.map { " (\(DiagnosticsFormat.duration($0)))" } ?? "")")
        }
        section.add("Media playing / active", "\(model.media.isPlaying) / \(model.media.isActive)")
        section.add("Key interception", String(describing: model.levels.interception))
        section.add("Volume", String(describing: model.levels.volume))
        section.add("Brightness", String(describing: model.levels.brightness))
        section.add("Power", String(describing: model.power.state))
        section.add("Full-screen apps", model.fullscreen.fullscreenApps.sorted().joined(separator: ", "))
        section.add("Countdown", String(describing: model.timers.countdown))
        section.add("Stopwatch", String(describing: model.timers.stopwatch))
        section.add("Shelf items", model.shelf.items.count)
        if !model.shelf.items.isEmpty {
            section.add("Shelf", model.shelf.items.map { "\($0.displayName) — \($0.url.path)" }.joined(separator: "\n"))
        }
        // How many and how old only: what was copied may be a password.
        section.add("Clipboard items", "\(model.clipboard.items.count)\(model.clipboard.items.first.map { ", newest \(DiagnosticsFormat.date($0.copied))" } ?? "")")
        section.add("Siri's app list (in memory)", model.assistant.allApps.count)
        section.add("Siri query / category", "\"\(model.assistant.query)\" / \(model.assistant.category.map { String(describing: $0) } ?? "root")")
        section.add("Siri hits (apps / files / selection)", "\(model.assistant.apps.count) / \(model.assistant.files.count) / \(model.assistant.selection)")
        section.add("Widgets", model.widgets.board.widgets.map { String(describing: $0.kind) }.joined(separator: ", "))
        section.add("Bluetooth outputs now", model.airPods.connectedOutputs.sorted().joined(separator: ", "))
        section.add("AirPods events", model.airPods.recent.isEmpty ? "none since launch" : model.airPods.recent.joined(separator: "\n"))
        section.add("Siri reads files", UserDefaults.standard.bool(forKey: AssistantModel.filesKey))
        return section
    }

    static func launchAtLogin(_ status: SMAppService.Status) -> String {
        switch status {
        case .notRegistered: "off (not registered)"
        case .enabled: "on"
        case .requiresApproval: "waiting for approval in Login Items"
        case .notFound: "off (not found)"
        @unknown default: "unknown (\(status.rawValue))"
        }
    }

    /// The island's policy flags, the banner up now and why the app is (not) suspended.
    private static func internals(_ model: AppModel) -> DiagnosticsReport.Section {
        var section = DiagnosticsReport.Section("Island internals")
        for (key, value) in model.controller?.diagnosticsSnapshot ?? [] { section.add(key, value) }
        section.add("Interacting / drop targeted", "\(model.island.isInteracting) / \(model.island.isDropTargeted)")
        section.add("Surface hold", model.island.surfaceHold.map { String(describing: $0) } ?? "—")
        section.add("Revision", model.island.revision)
        section.add("Banner", model.banners.current.map { String(describing: $0) } ?? "none")
        section.add("Banner held", model.banners.isHeld)
        section.add("Activity signals", model.activity.diagnosticsSignals)
        section.add("⌘Space tap wanted / running", "\(model.diagnosticsCommandSpaceWanted) / \(model.diagnosticsCommandSpaceTapRunning)")
        return section
    }

    /// Every window the app has: which is up, where, at what level.
    private static func windows() -> DiagnosticsReport.Section {
        var section = DiagnosticsReport.Section("Windows")
        for (index, window) in NSApp.windows.enumerated() {
            let name = "\(index) \(type(of: window))\(window.title.isEmpty ? "" : " “\(window.title)”")"
            section.add(name, "\(DiagnosticsFormat.rect(window.frame)), level \(window.level.rawValue), visible \(window.isVisible), "
                        + "on screen \(window.occlusionState.contains(.visible)), alpha \(window.alphaValue), "
                        + "ignores mouse \(window.ignoresMouseEvents), key \(window.isKeyWindow), screen \(window.screen?.localizedName ?? "—")")
        }
        return section
    }

    /// Every setting as the app uses it now, defaults included (the `ni2.` keys hold only what was
    /// changed).
    private static func effectiveSettings(_ model: AppModel) -> DiagnosticsReport.Section {
        var section = DiagnosticsReport.Section("Settings (effective)")
        for child in Mirror(reflecting: model.preferences).children {
            // Settings only: not the observation registrar or the store they are saved in.
            guard var label = child.label, !label.hasPrefix("_$"), !(child.value is UserDefaults) else { continue }
            if label.hasPrefix("_") { label.removeFirst() }
            section.add(label, String(describing: child.value))
        }
        return section
    }

    /// Every copy of NotchIsland Launch Services knows, and how many run: an older copy that
    /// launches at login, or two at once, explain "the same version behaves differently".
    private static func copies() -> DiagnosticsReport.Section {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.davidvarga.notchisland"
        var section = DiagnosticsReport.Section(copiesTitle)
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        section.add(instancesKey, running.count)
        section.add("Running from", running.compactMap { $0.bundleURL?.path }.joined(separator: "\n"))
        let copies = NSWorkspace.shared.urlsForApplications(withBundleIdentifier: bundleID)
        section.add(copiesKey, copies.count)
        section.add("Copies", copies.map { url in
            let version = Bundle(url: url)?.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
            let build = Bundle(url: url)?.infoDictionary?["CFBundleVersion"] as? String ?? "?"
            return "\(url.path) (\(version) (\(build)))"
        }.joined(separator: "\n"))
        return section
    }

    /// Every `ni2.` preference. The Shelf's list is in Features (its bookmarks are binary); the
    /// clipboard lives in its own file and is never read here.
    private static func preferences() -> DiagnosticsReport.Section {
        var section = DiagnosticsReport.Section("Preferences")
        let all = UserDefaults.standard.dictionaryRepresentation()
        for key in all.keys.filter({ $0.hasPrefix(Preferences.Key.prefix) }).sorted() {
            guard key != DiagnosticsCenter.nameKey else { continue }
            let value = all[key]
            if key == ShelfStore.defaultsKey, let data = value as? Data {
                section.add(key, "<\(data.count) bytes, not sent>")
            } else if let data = value as? Data {
                let text = String(data: data, encoding: .utf8)
                section.add(key, text.map { DiagnosticsFormat.head($0, limit: 4000) } ?? "<\(data.count) bytes>")
            } else {
                section.add(key, value.map { String(describing: $0) } ?? "—")
            }
        }
        return section
    }

    private static func runningApps() -> DiagnosticsReport.Section {
        var section = DiagnosticsReport.Section("Running apps")
        let own = Bundle.main.bundleIdentifier
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy != .prohibited }
            .compactMap(\.bundleIdentifier)
        let notchApps = Set(apps.filter { $0.localizedCaseInsensitiveContains("notch") && $0 != own }).sorted()
        section.add(otherNotchAppsKey, notchApps.isEmpty ? "none" : notchApps.joined(separator: ", "))
        section.add("Apps with windows or menu-bar items", Set(apps).sorted().joined(separator: ", "))
        return section
    }
}
