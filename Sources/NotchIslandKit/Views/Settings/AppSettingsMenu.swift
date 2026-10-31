import AppKit
import SwiftUI

/// Beside Settings ▸ General's title: saving every setting of the app, and opening the saved ones —
/// as Save Notch Style and Open Notch Styles do on Widgets for the island's look (`NotchStyleButtons`).
struct AppSettingsButtons: View {
    @Environment(AppModel.self) private var model
    /// Just saved: the button says so for a moment.
    @State private var justSaved: UUID?

    var body: some View {
        @Bindable var studio = model.studio
        VStack(spacing: NotchStyleButtons.spacing) {
            Button {
                // A board change still waiting for its write goes with it.
                model.boards.flush()
                guard let saved = model.appSettings.save() else { return }
                withAnimation(.spring(duration: 0.3)) { justSaved = saved.id }
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    withAnimation(.spring(duration: 0.3)) { if justSaved == saved.id { justSaved = nil } }
                }
            } label: {
                Label(justSaved == nil ? "Save App Settings" : "Saved", systemImage: justSaved == nil ? "square.and.arrow.down" : "checkmark")
                    .frame(maxWidth: .infinity)
                    .contentTransition(.symbolEffect(.replace))
            }
            .help("Keep every setting of NotchIsland as it is now, widgets and look included, to open again")
            HeaderMenuButton(title: "Open App Settings", symbol: "rectangle.stack",
                             help: "The saved app settings: open one, rename or delete it",
                             isOpen: $studio.showsAppSettings, buttonFrame: $studio.appSettingsButton)
        }
        .buttonStyle(HeaderOutlineButtonStyle())
        .fixedSize()
        // Another page, or Settings closed: the list does not wait there.
        .onSettingsPageVisit(shown: {}, hidden: { model.studio.showsAppSettings = false })
    }
}

/// The saved app settings: each with its name (renamed in place), when it was saved, Open, and delete.
struct AppSettingsPanel: View {
    let close: () -> Void

    @Environment(AppModel.self) private var model
    @State private var confirmsDeleteAll = false

    var body: some View {
        let saved = model.appSettings.newestFirst
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Saved App Settings").font(.headline)
                    Text("Everything you've set in NotchIsland. Opening one restarts the app.")
                        .font(.caption)
                        .foregroundStyle(SettingsPalette.secondary)
                }
                Spacer(minLength: 8)
                Button("Close", systemImage: "xmark", action: close)
                    .labelStyle(.iconOnly)
                    .buttonBorderShape(.circle)
                    .controlSize(.small)
                    .help("Close")
            }
            if saved.isEmpty {
                Text("None yet. Save App Settings keeps every setting as it is, to open again here.")
                    .font(.callout)
                    .foregroundStyle(SettingsPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 6)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(saved) { settings in
                            AppSettingsRow(settings: settings, isCurrent: model.appSettings.isCurrent(settings),
                                           open: { model.open(settings) }, rename: { model.appSettings.rename(settings.id, to: $0) },
                                           delete: { withAnimation(.spring(duration: 0.3)) { model.appSettings.delete(settings.id) } })
                        }
                    }
                }
                .scrollIndicators(.automatic)
                .frame(maxHeight: WidgetVersionsPanel.maxListHeight)
                .fixedSize(horizontal: false, vertical: true)
                deleteAll(count: saved.count)
            }
        }
        .padding(14)
        .onChange(of: model.studio.showsAppSettings) { _, shown in
            if !shown { confirmsDeleteAll = false }
        }
    }

    /// Delete All, then asked once more in its place.
    @ViewBuilder private func deleteAll(count: Int) -> some View {
        HStack(spacing: 8) {
            if confirmsDeleteAll {
                Text(count == 1 ? "Delete the saved settings?" : "Delete all \(count) saved settings?")
                    .font(.caption)
                    .foregroundStyle(SettingsPalette.secondary)
                Spacer(minLength: 4)
                Button("Cancel") { withAnimation(.spring(duration: 0.3)) { confirmsDeleteAll = false } }
                    .controlSize(.small)
                Button("Delete", role: .destructive) {
                    withAnimation(.spring(duration: 0.3)) {
                        model.appSettings.deleteAll()
                        confirmsDeleteAll = false
                    }
                }
                .controlSize(.small)
                .tint(.red)
            } else {
                Spacer(minLength: 0)
                Button("Delete All") { withAnimation(.spring(duration: 0.3)) { confirmsDeleteAll = true } }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .foregroundStyle(SettingsPalette.secondary)
                    .help("Delete all saved app settings")
            }
        }
        .buttonBorderShape(.capsule)
        .frame(minHeight: 22)
    }
}

private struct AppSettingsRow: View {
    let settings: SavedAppSettings
    /// The app is set like this now: nothing to open.
    let isCurrent: Bool
    let open: () -> Void
    let rename: (String) -> Void
    let delete: () -> Void

    @State private var name = ""
    @State private var isHovered = false
    @FocusState private var isEditingName: Bool

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                TextField("Name", text: $name)
                    .textFieldStyle(.plain)
                    .font(.callout.weight(.medium))
                    .focused($isEditingName)
                    .onSubmit { rename(name) }
                    .onChange(of: isEditingName) { _, editing in
                        if !editing { rename(name) }
                    }
                    .help("Rename")
                Text(settings.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(SettingsPalette.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 6)
            if isCurrent {
                Text("Current")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(SettingsPalette.secondary)
            } else {
                Button("Open", action: open)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .help("NotchIsland restarts with these settings. What's set now is kept in this list.")
            }
            Button("Delete", systemImage: "trash", action: delete)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .controlSize(.small)
                .foregroundStyle(SettingsPalette.secondary)
                .help("Delete these settings")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(Color.white.opacity(isHovered ? 0.09 : isCurrent ? 0.06 : 0.03), in: .rect(cornerRadius: 10, style: .continuous))
        .onHover { isHovered = $0 }
        .onAppear { name = settings.name }
        .onChange(of: settings.name) { _, new in name = new }
    }
}
