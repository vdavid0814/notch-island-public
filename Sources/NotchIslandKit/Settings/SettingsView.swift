import AppKit
import SwiftUI

nonisolated enum SettingsSection: String, CaseIterable, Identifiable, Sendable {
    case general, activities, permissions, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .activities: "Activities"
        case .permissions: "Permissions"
        case .about: "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .activities: "square.grid.2x2"
        case .permissions: "hand.raised"
        case .about: "info.circle"
        }
    }
}

/// Settings: a native sidebar and one grouped form per section. Only stock controls, so the
/// window takes the system's Liquid Glass sidebar, accent colour, Dynamic Type and accessibility
/// behaviour without any styling of ours.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.appearsActive) private var appearsActive
    /// Remembered across launches so Settings reopens where the user left it.
    @AppStorage("ni2.settings.section") private var section: SettingsSection = .general

    var body: some View {
        NavigationSplitView {
            List(selection: selection) {
                ForEach(SettingsSection.allCases) { section in
                    Label(section.title, systemImage: section.systemImage)
                        .tag(section)
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
            // A settings window keeps its sidebar, like System Settings.
            .toolbar(removing: .sidebarToggle)
        } detail: {
            detail
                .navigationTitle(section.title)
        }
        .onAppear(perform: refreshSystemState)
        // The user may have flipped a switch in System Settings while this window was in the
        // background; re-read whenever it comes forward.
        .onChange(of: appearsActive) { _, active in
            if active { refreshSystemState() }
        }
    }

    /// Clicking the empty part of a sidebar clears a `List` selection; keep the current section.
    private var selection: Binding<SettingsSection?> {
        Binding(
            get: { section },
            set: { if let newValue = $0 { section = newValue } }
        )
    }

    @ViewBuilder private var detail: some View {
        switch section {
        case .general: GeneralSettings()
        case .activities: ActivitiesSettings()
        case .permissions: PermissionsSettings()
        case .about: AboutSettings()
        }
    }

    private func refreshSystemState() {
        model.permissions.refresh()
        model.launchAtLogin.refresh()
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var preferences = model.preferences
        @Bindable var launchAtLogin = model.launchAtLogin

        Form {
            Section("Island") {
                LabeledContent {
                    Button("Customize Island…") { model.showCustomize() }
                } label: {
                    Text("Widgets")
                    Text("Choose what the open island shows, and arrange and size each widget.")
                }
                Toggle(isOn: $preferences.openOnHover) {
                    Text("Open on hover")
                    Text("Rest the pointer on the notch to open the island. Clicking always opens it.")
                }
                LabeledContent("Hover delay") {
                    HStack {
                        Slider(value: hoverDelay, in: Preferences.hoverDelayRange)
                            .labelsHidden()
                        Text(SettingsFormat.hoverDelay(preferences.hoverDelay))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 56, alignment: .trailing)
                    }
                }
                .disabled(!preferences.openOnHover)
                LabeledContent {
                    HStack {
                        Slider(value: animationDuration, in: Motion.durationRange)
                            .labelsHidden()
                        Text(SettingsFormat.hoverDelay(preferences.animationDuration))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 56, alignment: .trailing)
                    }
                } label: {
                    Text("Animation length")
                    Text("How long the island takes to grow out of the notch and to shrink back into it.")
                }
                Picker("Size when open", selection: $preferences.scale) {
                    ForEach(IslandScale.allCases) { scale in
                        Text(scale.title).tag(scale)
                    }
                }
                Picker(selection: $preferences.glassStyle) {
                    ForEach(IslandGlassStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                } label: {
                    Text("Surface")
                    Text("Liquid Glass, solid black like the hardware island, or black at the notch fading into glass.")
                }
                Toggle(isOn: $preferences.commandSpaceOpensSiri) {
                    Text("Open Siri with ⌘Space")
                    Text("Siri opens in the notch instead of the system's search. Needs Accessibility.")
                }
                Toggle(isOn: $preferences.hideInFullscreen) {
                    Text("Hide during full-screen video")
                    // A playing video is recognised through Now Playing (and, for browsers, web media).
                    Text(preferences.showNowPlaying && preferences.showWebMedia
                         ? "While a playing video fills the screen, nothing appears by itself. Hovering the notch still opens the island."
                         : "Needs Now Playing and browser playback: that is how a playing video is recognised.")
                }
                .disabled(!preferences.showNowPlaying)
                Toggle(isOn: $preferences.hapticsEnabled) {
                    Text("Haptic feedback")
                    Text("A light tap on the trackpad when the island opens or closes and when a level changes.")
                }
            }

            Section("Startup") {
                Toggle("Open at login", isOn: $launchAtLogin.isEnabled)
                if launchAtLogin.requiresApproval {
                    LabeledContent {
                        Button("Open Login Items…") {
                            launchAtLogin.openLoginItemsSettings()
                        }
                    } label: {
                        Text("Waiting for approval")
                        Text("Allow NotchIsland in Login Items to open it at login.")
                    }
                }
                if let error = launchAtLogin.lastError {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Toggle("Show in menu bar", isOn: $preferences.showMenuBarIcon)
            } footer: {
                Text("With the icon hidden, open NotchIsland again from Finder or Spotlight to return to Settings.")
            }
        }
        .formStyle(.grouped)
    }

    /// Snaps to 10 ms, like the hover delay.
    private var animationDuration: Binding<Double> {
        let preferences = model.preferences
        return Binding(
            get: { preferences.animationDuration },
            set: { newValue in
                let snapped = (newValue * 100).rounded() / 100
                if snapped != preferences.animationDuration { preferences.animationDuration = snapped }
            }
        )
    }

    /// Snaps to 10 ms and skips writes that would not change the stored value, so a slow drag does
    /// not rewrite the same default dozens of times.
    private var hoverDelay: Binding<Double> {
        let preferences = model.preferences
        return Binding(
            get: { preferences.hoverDelay },
            set: { newValue in
                let snapped = (newValue * 100).rounded() / 100
                if snapped != preferences.hoverDelay { preferences.hoverDelay = snapped }
            }
        )
    }
}

// MARK: - Activities

private struct ActivitiesSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var preferences = model.preferences

        Form {
            Section("Now Playing") {
                Toggle(isOn: $preferences.showNowPlaying) {
                    Text("Show what's playing")
                    Text("Artwork beside the notch, with playback controls when the island opens.")
                }
                Toggle(isOn: $preferences.showWebMedia) {
                    Text("Browser and video playback")
                    Text("YouTube and other videos in Safari and other browsers, and video apps like QuickTime or IINA. Read only while one of them is open, to save battery; Music and Spotify always report on their own.")
                }
                .disabled(!preferences.showNowPlaying)
            }

            Section("Volume and Brightness") {
                Toggle(isOn: $preferences.showLevelHUD) {
                    Text("Show volume and brightness changes")
                    Text("Changes appear in the island.")
                }
                Toggle(isOn: $preferences.replaceSystemHUD) {
                    Text("Replace the system HUD")
                    Text("Handles the volume and brightness keys so only the island appears. Needs Accessibility.")
                }
                .disabled(!preferences.showLevelHUD)
                if preferences.showLevelHUD, preferences.replaceSystemHUD, !model.permissions.accessibilityTrusted {
                    LabeledContent {
                        Button("Open System Settings…") {
                            model.permissions.promptOrOpenAccessibilitySettings()
                        }
                    } label: {
                        StatusLabel(title: "Accessibility access needed", tone: .attention)
                    }
                }
            }

            // Desktop Macs have no battery, so there is nothing to alert about.
            if model.power.state.hasBattery {
                Section("Battery") {
                    Toggle(isOn: $preferences.showPowerAlerts) {
                        Text("Power alerts")
                        Text("Charger connected or removed, fully charged, and low battery at 20, 10 and 5 %.")
                    }
                }
            }

            Section("Shelf") {
                Toggle(isOn: $preferences.shelfEnabled) {
                    Text("Shelf")
                    Text("Drag files onto the notch to keep them at hand, then drag them out or AirDrop them.")
                }
            }

            Section("Timer") {
                Toggle("Play a sound when a timer ends", isOn: $preferences.timerSound)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Permissions

private struct PermissionsSettings: View {
    @Environment(AppModel.self) private var model

    /// Privacy & Security ▸ Automation, where Music/Spotify access is granted or revoked.
    private static let automationSettingsURL =
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!

    var body: some View {
        let trusted = model.permissions.accessibilityTrusted
        let media = SettingsFormat.mediaStatus(model.media.status, enabled: model.preferences.showNowPlaying)
        let keys = SettingsFormat.interceptionStatus(model.levels.interception)

        Form {
            Section("Accessibility") {
                LabeledContent {
                    HStack {
                        StatusLabel(title: trusted ? "Allowed" : "Not allowed", tone: trusted ? .ok : .attention)
                        if !trusted {
                            Button("Open System Settings…") {
                                model.permissions.promptOrOpenAccessibilitySettings()
                            }
                        }
                    }
                } label: {
                    Text("Accessibility")
                    Text("Needed to replace the system volume and brightness HUD.")
                }
            }

            Section("Now Playing") {
                LabeledContent {
                    StatusLabel(title: media.title, tone: media.tone)
                } label: {
                    Text("Source")
                    Text(media.detail)
                }
                if case .on(_, .some) = model.media.status, model.preferences.showNowPlaying {
                    LabeledContent {
                        Link("Open Automation Settings…", destination: Self.automationSettingsURL)
                    } label: {
                        Text("Music and Spotify")
                        Text("If access was denied, allow NotchIsland under Automation.")
                    }
                }
            }

            Section("Volume and Brightness Keys") {
                LabeledContent {
                    StatusLabel(title: keys.title, tone: keys.tone)
                } label: {
                    Text("HUD replacement")
                    Text(keys.detail)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - About

private struct AboutSettings: View {
    @Environment(AppModel.self) private var model
    @State private var isConfirmingClear = false

    var body: some View {
        let count = model.shelf.items.count

        Form {
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 64, height: 64)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("NotchIsland")
                            .font(.title2.weight(.semibold))
                        Text(SettingsFormat.version(Bundle.main.infoDictionary))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                Text("NotchIsland turns the notch into a Liquid Glass island for what's playing, timers, volume and brightness, charging, and a shelf for the files you are moving around.")
                    .foregroundStyle(.secondary)
            }

            Section("Shelf") {
                LabeledContent("Items on the Shelf", value: count.formatted())
                Button("Clear Shelf…", role: .destructive) {
                    isConfirmingClear = true
                }
                .disabled(count == 0)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Clear the Shelf?", isPresented: $isConfirmingClear) {
            Button("Clear Shelf", role: .destructive) {
                model.shelf.clear()
            }
        } message: {
            Text("All items are removed from the Shelf. The files themselves are not touched.")
        }
    }
}

// MARK: - Shared pieces

/// A status word with a meaningful system colour on the symbol only; the text stays primary.
private struct StatusLabel: View {
    let title: String
    let tone: SettingsFormat.Tone

    var body: some View {
        Label {
            Text(title)
        } icon: {
            switch tone {
            case .ok: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .attention: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            case .neutral: Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
            }
        }
    }
}

/// The words Settings shows for system state. Pure, so the copy is testable.
nonisolated enum SettingsFormat {
    nonisolated enum Tone: Sendable, Equatable { case ok, attention, neutral }

    nonisolated struct Status: Sendable, Equatable {
        var title: String
        var detail: String
        var tone: Tone
    }

    /// "220 ms": a hover delay (or an animation length) reads better in milliseconds than in
    /// fractions of a second.
    static func hoverDelay(_ seconds: Double, locale: Locale = .autoupdatingCurrent) -> String {
        let milliseconds = (seconds * 1000).rounded()
        return Measurement(value: milliseconds, unit: UnitDuration.milliseconds).formatted(
            .measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0)))
                .locale(locale)
        )
    }

    static func mediaStatus(_ status: MediaSourceStatus, enabled: Bool) -> Status {
        guard enabled, case .on(let web, let automationIssue) = status else {
            return Status(title: "Off", detail: "Now Playing is turned off in Activities.", tone: .neutral)
        }
        if let automationIssue {
            return Status(title: "Needs permission", detail: automationIssue, tone: .attention)
        }
        switch web {
        case .listening:
            return Status(
                title: "Music, Spotify and browsers",
                detail: "A browser or video app is open, so the system's Now Playing is read too. It stops when they quit.",
                tone: .ok
            )
        case .standby:
            return Status(
                title: "Music and Spotify",
                detail: "Browsers and video apps are picked up as soon as one opens; nothing runs for them until then.",
                tone: .ok
            )
        case .off:
            return Status(
                title: "Music and Spotify",
                detail: "Browser and video playback is turned off in Activities.",
                tone: .ok
            )
        case .notInstalled:
            return Status(
                title: "Music and Spotify",
                detail: "This build has no MediaRemote adapter, so browser and video playback can't be read. Run Scripts/vendor-mediaremote.sh and rebuild.",
                tone: .attention
            )
        case .retrying:
            return Status(
                title: "Music and Spotify",
                detail: "Reading browser playback failed; it is retried automatically.",
                tone: .attention
            )
        }
    }

    static func interceptionStatus(_ state: InterceptionState) -> Status {
        switch state {
        case .off:
            Status(title: "Off", detail: "The system volume and brightness HUD is shown.", tone: .neutral)
        case .needsPermission:
            Status(title: "Waiting for Accessibility", detail: "Allow NotchIsland under Accessibility to replace the system HUD.", tone: .attention)
        case .active:
            Status(title: "Active", detail: "The island replaces the system volume and brightness HUD.", tone: .ok)
        case .failed(let reason):
            Status(title: "Failed", detail: reason, tone: .attention)
        }
    }

    /// "Version 2.0.0 (1)"; a binary run outside its bundle has no Info.plist values.
    static func version(_ info: [String: Any]?) -> String {
        guard let short = info?["CFBundleShortVersionString"] as? String else { return "Development build" }
        guard let build = info?["CFBundleVersion"] as? String, !build.isEmpty else { return "Version \(short)" }
        return "Version \(short) (\(build))"
    }
}
