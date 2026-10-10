import ServiceManagement
import SwiftUI

/// About ▸ Permissions ▸ Fan Control: the helper that sets the fans (`FanHelper`), as the
/// permissions are shown — whether it is switched on and whether it answers, where its switch is
/// (System Settings ▸ General ▸ Login Items), and the buttons that open it there and reset it.
/// Only on a Mac with a fan.
struct FanHelperRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.settingsPageVisit) private var visit
    @State private var isExpanded = false
    /// Whether the helper answered the last time it was asked; nil: not asked yet.
    @State private var answers: Bool?
    @State private var isAsking = false
    @State private var isResetting = false
    @State private var confirmingReset = false
    /// Counted up to read the state again (Login Items says nothing when its switch flips).
    @State private var reads = 0

    var body: some View {
        let _ = reads
        let state = model.fans.helperState
        DisclosureGroup(isExpanded: $isExpanded) {
            details(state)
        } label: {
            HStack(spacing: 12) {
                SettingsTile(systemImage: "fan.fill", tint: .cyan, side: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Fan Control")
                    Text("The helper that sets the fans' speed for the Fan Control widget.")
                        .font(.caption)
                        .foregroundStyle(SettingsPalette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                StatusLabel(title: Self.title(state, answers: answers), tone: Self.tone(state, answers: answers))
                    .font(.callout)
                    .fixedSize()
            }
            .padding(.vertical, 2)
        }
        // Asked whether it answers when the row opens, and again when its state changes.
        .task(id: Ask(state: state, open: isExpanded && (visit?.isShown ?? true))) {
            guard isExpanded, visit?.isShown ?? true else { return }
            await ask()
        }
        // Waiting for its switch: read again every two seconds while the row is open.
        .task(id: isExpanded && (visit?.isShown ?? true) && state == .needsApproval) {
            guard isExpanded, visit?.isShown ?? true, state == .needsApproval else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                reads += 1
            }
        }
        .onSettingsPageVisit(shown: { reads += 1 })
    }

    private struct Ask: Equatable {
        var state: FanCenter.HelperState
        var open: Bool
    }

    static func title(_ state: FanCenter.HelperState, answers: Bool?) -> String {
        switch state {
        case .notSetUp: String(localized: "Set up when first used")
        case .needsApproval: String(localized: "Switched off")
        case .ready: answers == false ? String(localized: "On, not working") : answers == true ? String(localized: "Working") : String(localized: "On")
        case .failed: String(localized: "Not working")
        }
    }

    static func tone(_ state: FanCenter.HelperState, answers: Bool?) -> SettingsFormat.Tone {
        switch state {
        case .notSetUp: .neutral
        case .needsApproval, .failed: .attention
        case .ready: answers == false ? .attention : .ok
        }
    }

    /// What the row says under its name: how the helper stands, in a sentence.
    static func note(_ state: FanCenter.HelperState, answers: Bool?) -> String {
        switch state {
        case .notSetUp:
            String(localized: "Not set up yet. Turn the Fan Control widget's dial, or set it up here.")
        case .needsApproval:
            String(localized: "Its switch in Login Items is off: the fans cannot be set until it is on.")
        case .ready(let installed):
            switch answers {
            case true?: installed ? String(localized: "Installed with an administrator's password, and answering.")
                : String(localized: "Switched on in Login Items, and answering.")
            case false?: String(localized: "It is on but does not answer. Reset it, then set it up again.")
            case nil: String(localized: "Checking whether it answers…")
            }
        case .failed(let reason):
            String(localized: "The fans could not be set: \(reason)")
        }
    }

    @ViewBuilder private func details(_ state: FanCenter.HelperState) -> some View {
        let working = state != .notSetUp && state != .needsApproval && answers == true
        let failed = { if case .failed = state { true } else { answers == false } }()
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: working ? "checkmark.circle.fill" : failed ? "exclamationmark.triangle.fill"
                      : state == .needsApproval ? "hourglass.circle.fill" : "minus.circle")
                    .foregroundStyle(working ? Color.green : failed || state == .needsApproval ? .orange : .secondary)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Setting the fans' speed")
                    Text(Self.note(state, answers: answers))
                        .font(.caption)
                        .foregroundStyle(SettingsPalette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if isAsking { ProgressView().controlSize(.small) }
            }

            VStack(alignment: .leading, spacing: 4) {
                Label("System Settings ▸ General ▸ Login Items & Extensions", systemImage: "gearshape")
                    .font(.caption.weight(.medium))
                Text("1. Under Allow in the Background, switch NotchIsland on.")
                Text("2. Come back and turn the Fan Control widget's dial.")
                Text("The fans go back to macOS by themselves when NotchIsland quits, and when the chip reaches 95 °C.")
            }
            .font(.caption)
            .foregroundStyle(SettingsPalette.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            HStack(spacing: 8) {
                if state == .notSetUp {
                    Button("Set Up…") {
                        model.fans.setUpHelper()
                        reads += 1
                    }
                    .buttonStyle(.borderedProminent)
                    .help("Registers the helper and opens Login Items for its switch")
                } else if state == .needsApproval {
                    Button("Open Login Items…") { SMAppService.openSystemSettingsLoginItems() }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Open Login Items…") { SMAppService.openSystemSettingsLoginItems() }
                    Button("Check Again") { Task { await ask() } }
                        .disabled(isAsking)
                }
                Spacer()
                if state != .notSetUp {
                    if isResetting { ProgressView().controlSize(.small) }
                    Button("Reset…") { confirmingReset = true }
                        .disabled(isResetting)
                        .help("Gives the fans back to macOS and removes the helper; setting it up again starts over.")
                        .popover(isPresented: $confirmingReset, arrowEdge: .trailing) { resetConfirmation }
                }
            }
        }
        .padding(.leading, 40)
        .padding(.vertical, 6)
    }

    private var resetConfirmation: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Reset the fan helper?").font(.headline)
            Text("The fans go back to macOS and the helper is removed. Use it when the helper is on but the fans cannot be set; Set Up, or the next turn of the dial, puts it back.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel") { confirmingReset = false }
                    .keyboardShortcut(.cancelAction)
                Button("Reset") {
                    confirmingReset = false
                    isResetting = true
                    Task {
                        await model.fans.removeHelper()
                        isResetting = false
                        answers = nil
                        reads += 1
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 300)
    }

    private func ask() async {
        guard case .ready = model.fans.helperState else {
            answers = nil
            return
        }
        isAsking = true
        answers = await model.fans.helperAnswers()
        isAsking = false
    }
}
