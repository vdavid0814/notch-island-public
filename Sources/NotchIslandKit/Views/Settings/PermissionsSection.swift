import AppKit
import SwiftUI

/// About ▸ Permissions: every permission on its own row that opens to the features it turns on,
/// each with its own state, where the switch is in System Settings, and the buttons that fix it.
/// Read live while on screen, so a switch flipped in System Settings shows here at once.
struct PermissionsSection: View {
    @Environment(AppModel.self) private var model
    @State private var statuses: [PermissionKind: PermissionStatus] = [:]
    @State private var expanded: Set<PermissionKind> = []
    @State private var resetting: PermissionKind?
    @State private var confirmingReset: PermissionKind?
    @State private var didExpandNeeded = false

    var body: some View {
        let rows = PermissionKind.allCases.map { kind in
            PermissionGuide.row(kind, status: statuses[kind] ?? .unknown, model: model)
        }
        let attention = rows.filter(\.needsAttention)
        Section {
            ForEach(rows) { row in
                DisclosureGroup(isExpanded: binding(row.kind)) {
                    details(row)
                } label: {
                    label(row)
                }
            }
        } header: {
            HStack {
                Text("Permissions")
                Spacer()
                if attention.isEmpty {
                    StatusLabel(title: String(localized: "Everything in use is allowed"), tone: .ok)
                        .font(.caption)
                } else {
                    StatusLabel(title: String(localized: "\(attention.count) need attention"), tone: .attention)
                        .font(.caption)
                }
            }
        } footer: {
            Text("Open a row to see what each permission turns on and where its switch is. NotchIsland works without any of them; each one only turns on the features it lists. Updates keep them: the same app, signed the same way, replaces itself in place.")
        }
        .task {
            // Read every couple of seconds while About is on screen (nothing pushes most of them).
            while !Task.isCancelled {
                refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func refresh() {
        var next: [PermissionKind: PermissionStatus] = [:]
        for kind in PermissionKind.allCases { next[kind] = PermissionProbe.status(kind) }
        if next != statuses { statuses = next }
        model.permissions.refresh()
        // The rows that need something open by themselves, once.
        if !didExpandNeeded {
            didExpandNeeded = true
            let needed = PermissionKind.allCases.filter {
                PermissionGuide.row($0, status: next[$0] ?? .unknown, model: model).needsAttention
            }
            expanded.formUnion(needed)
        }
    }

    private func binding(_ kind: PermissionKind) -> Binding<Bool> {
        Binding(get: { expanded.contains(kind) }, set: { open in
            if open { expanded.insert(kind) } else { expanded.remove(kind) }
        })
    }

    private func label(_ row: PermissionGuide.Row) -> some View {
        HStack(spacing: 12) {
            SettingsTile(systemImage: row.kind.systemImage, tint: row.tint, side: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.kind.title)
                Text(row.summary)
                    .font(.caption)
                    .foregroundStyle(SettingsPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            StatusLabel(title: row.statusTitle, tone: row.tone)
                .font(.callout)
                .fixedSize()
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private func details(_ row: PermissionGuide.Row) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(row.features) { feature in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: feature.state.symbol)
                            .foregroundStyle(feature.state.color)
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(feature.name)
                            if let note = feature.note {
                                Text(note)
                                    .font(.caption)
                                    .foregroundStyle(SettingsPalette.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: 8)
                        Text(feature.state.title)
                            .font(.caption)
                            .foregroundStyle(SettingsPalette.secondary)
                            .fixedSize()
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Label(row.kind.location, systemImage: "gearshape")
                    .font(.caption.weight(.medium))
                ForEach(Array(row.steps.enumerated()), id: \.offset) { index, step in
                    Text("\(index + 1). \(step)")
                        .font(.caption)
                        .foregroundStyle(SettingsPalette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            HStack(spacing: 8) {
                if !row.status.isAllowed {
                    Button(row.status == .notAsked ? "Allow…" : "Open System Settings…") { allow(row.kind) }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Open System Settings…") { row.kind.openSettings() }
                }
                Spacer()
                if row.kind.canReset, row.status != .notAsked {
                    if resetting == row.kind {
                        ProgressView().controlSize(.small)
                    }
                    Button("Reset…") { confirmingReset = row.kind }
                        .disabled(resetting != nil)
                        .help("Forgets NotchIsland's entry in this list, then asks again: for a switch that is on but does not work.")
                        .popover(isPresented: Binding(get: { confirmingReset == row.kind },
                                                      set: { if !$0 { confirmingReset = nil } }), arrowEdge: .trailing) {
                            resetConfirmation(row.kind)
                        }
                }
            }
        }
        .padding(.leading, 40)
        .padding(.vertical, 6)
    }

    private func resetConfirmation(_ kind: PermissionKind) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Reset \(kind.title)?").font(.headline)
            Text("NotchIsland's entry in \(kind.listName) is removed and macOS asks again. Use it when the switch is on but NotchIsland still says it is not allowed: the entry belongs to an older copy.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel") { confirmingReset = nil }
                    .keyboardShortcut(.cancelAction)
                Button("Reset") {
                    confirmingReset = nil
                    resetting = kind
                    Task {
                        await model.permissions.reset(kind)
                        resetting = nil
                        refresh()
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 300)
    }

    private func allow(_ kind: PermissionKind) {
        switch kind {
        case .accessibility: model.permissions.promptOrOpenAccessibilitySettings()
        case .inputMonitoring: model.permissions.requestInputMonitoring()
        case .screenRecording:
            if statuses[kind] == .notAsked { model.anchorMirror.requestAccess() } else { kind.openSettings() }
        case .calendars:
            if statuses[kind] == .notAsked { model.calendar.requestAccess() } else { kind.openSettings() }
        default: kind.openSettings()
        }
        refresh()
    }
}

/// What About says about each permission. Pure but for reading the model, so the copy stays in one
/// place.
@MainActor enum PermissionGuide {
    struct Feature: Identifiable {
        enum State {
            case working, off, waiting, failed

            var symbol: String {
                switch self {
                case .working: "checkmark.circle.fill"
                case .off: "minus.circle"
                case .waiting: "hourglass.circle.fill"
                case .failed: "exclamationmark.triangle.fill"
                }
            }

            var color: Color {
                switch self {
                case .working: .green
                case .off: .secondary
                case .waiting, .failed: .orange
                }
            }

            var title: String {
                switch self {
                case .working: String(localized: "Working")
                case .off: String(localized: "Off")
                case .waiting: String(localized: "Waiting for the permission")
                case .failed: String(localized: "Not working")
                }
            }
        }

        var id: String { name }
        let name: String
        var note: String?
        let state: State
    }

    struct Row: Identifiable {
        var id: PermissionKind { kind }
        let kind: PermissionKind
        let status: PermissionStatus
        let summary: String
        let features: [Feature]
        let steps: [String]

        /// A feature that is on uses it.
        var isUsed: Bool { features.contains { $0.state != .off } }
        /// Refused while something uses it, or a feature that should work does not. Never asked is
        /// not a problem: macOS asks when the feature first needs it.
        var needsAttention: Bool { (isUsed && status == .denied) || features.contains { $0.state == .failed } }

        var statusTitle: String {
            switch status {
            case .allowed: features.contains { $0.state == .failed } ? String(localized: "Allowed, not working") : String(localized: "Allowed")
            case .denied: isUsed ? String(localized: "Not allowed") : String(localized: "Not used")
            case .notAsked: isUsed ? String(localized: "Asked when first used") : String(localized: "Not used")
            case .unknown: String(localized: "Asked when needed")
            }
        }

        var tone: SettingsFormat.Tone {
            if needsAttention { return .attention }
            return status.isAllowed ? .ok : .neutral
        }

        var tint: Color {
            switch kind {
            case .accessibility, .bluetooth: .blue
            case .inputMonitoring: .gray
            case .screenRecording, .calendars: .red
            case .automation: .indigo
            case .systemAudio: .pink
            case .contacts: .brown
            }
        }
    }

    static func row(_ kind: PermissionKind, status: PermissionStatus, model: AppModel) -> Row {
        let prefs = model.preferences
        let allowed = status.isAllowed
        /// A feature that needs only this permission: off, waiting for it, or working.
        func plain(_ name: String, on: Bool, note: String? = nil) -> Feature {
            Feature(name: name, note: note, state: !on ? .off : allowed ? .working : .waiting)
        }
        /// A feature whose own state is known (a key tap).
        func tap(_ name: String, on: Bool, state: InterceptionState, note: String?) -> Feature {
            guard on else { return Feature(name: name, note: note, state: .off) }
            switch state {
            case .active: return Feature(name: name, note: note, state: .working)
            case .failed(let reason): return Feature(name: name, note: reason, state: .failed)
            case .needsPermission: return Feature(name: name, note: note, state: .waiting)
            case .off: return Feature(name: name, note: note, state: allowed ? .working : .waiting)
            }
        }
        let toggle = String(localized: "Find NotchIsland in the list and switch it on.")
        let missing = String(localized: "Not in the list? Click Allow… above (it adds it), or \u{201C}+\u{201D} and choose NotchIsland in Applications.")
        let stale = String(localized: "Switched on but still not working? The entry is an older copy's: click Reset…, then allow it again.")
        let restart = String(localized: "Nothing to restart: NotchIsland notices within a few seconds.")

        switch kind {
        case .accessibility:
            return Row(kind: kind, status: status,
                       summary: String(localized: "Lets NotchIsland catch keys before macOS does and move other apps' windows."),
                       features: [
                           tap(String(localized: "\(prefs.siri.shortcut.title) opens Spotlight in the notch"), on: prefs.commandSpaceOpensSiri,
                               state: model.commandSpaceState, note: String(localized: "Also needs Input Monitoring.")),
                           tap(String(localized: "Volume and brightness keys show the island"), on: prefs.replaceSystemHUD,
                               state: model.levels.interception, note: String(localized: "Instead of macOS's own overlay.")),
                           plain(String(localized: "Anchor a window under the notch"), on: prefs.anchorEnabled),
                           plain(String(localized: "Window names in Spotlight's Windows list"), on: true),
                       ],
                       steps: [String(localized: "Click Allow… (macOS shows its prompt, then the list)."), toggle, stale, restart])
        case .inputMonitoring:
            return Row(kind: kind, status: status,
                       summary: String(localized: "Lets NotchIsland see the shortcut while you type. macOS 27 needs it for any keyboard shortcut."),
                       features: [
                           tap(String(localized: "\(prefs.siri.shortcut.title) opens Spotlight in the notch"), on: prefs.commandSpaceOpensSiri,
                               state: model.commandSpaceState, note: String(localized: "NotchIsland reacts to this one shortcut only and stores no keys."))
                       ],
                       steps: [String(localized: "Click Allow… (macOS adds NotchIsland to the list, switched off)."), toggle, missing, stale])
        case .screenRecording:
            return Row(kind: kind, status: status,
                       summary: String(localized: "Only for the live picture of an anchored window."),
                       features: [plain(String(localized: "Mirror of the anchored window"), on: prefs.anchorEnabled && prefs.anchorMirror)],
                       steps: [String(localized: "Click Allow…"), toggle, String(localized: "macOS may ask to quit and reopen NotchIsland: choose Later, it is not needed.")])
        case .automation:
            let nowPlaying = prefs.showNowPlaying
            let features = PermissionProbe.automationTargets.map { target -> Feature in
                let state: Feature.State = switch PermissionProbe.automation(target.bundleID) {
                case _ where !nowPlaying: .off
                case .allowed: .working
                case .denied: .failed
                case .notAsked: .waiting
                case .unknown: .off
                }
                return Feature(name: String(localized: "Now Playing reads \(target.name)"),
                               note: state == .off && nowPlaying ? String(localized: "Asked the first time \(target.name) plays.") : nil,
                               state: state)
            }
            return Row(kind: kind, status: status,
                       summary: String(localized: "What Music and Spotify play, when the system's Now Playing is not available."),
                       features: features,
                       steps: [String(localized: "Open NotchIsland in the list."), String(localized: "Switch on Music and Spotify under it.")])
        case .systemAudio:
            return Row(kind: kind, status: status,
                       summary: String(localized: "Only the level of the sound, so the music bars move with it. Nothing is recorded."),
                       features: [plain(String(localized: "Music bars follow the sound"), on: nowPlayingOn(model))],
                       steps: [String(localized: "Under System Audio Recording Only, find NotchIsland and switch it on."), missing])
        case .calendars:
            return Row(kind: kind, status: status,
                       summary: String(localized: "Your coming events, read only while a widget or Spotlight shows them."),
                       features: [plain(String(localized: "Calendar widget and Spotlight's events"), on: true)],
                       steps: [String(localized: "Click Allow… and choose Allow Full Access."), toggle])
        case .contacts:
            return Row(kind: kind, status: status,
                       summary: String(localized: "Finding people by name in Spotlight."),
                       features: [plain(String(localized: "People in Spotlight"), on: true)],
                       steps: [toggle])
        case .bluetooth:
            return Row(kind: kind, status: status,
                       summary: String(localized: "Only the Bluetooth widget, to show and switch Bluetooth."),
                       features: [plain(String(localized: "Bluetooth widget"), on: true)],
                       steps: [String(localized: "Asked the first time the widget is used."), toggle])
        }
    }

    private static func nowPlayingOn(_ model: AppModel) -> Bool { model.preferences.showNowPlaying }
}
