import SwiftUI
import UniformTypeIdentifiers

// MARK: - Bug reports and feature requests

/// About's "Report a Problem or Suggest a Feature": two buttons, each opening its form in place.
struct FeedbackSection: View {
    @Environment(AppModel.self) private var model
    /// The form being filled in; nil shows the two buttons.
    @State private var draft: DiagnosticsFeedback?
    @State private var attachDiagnostics = true
    @State private var isSending = false
    @State private var sent: DiagnosticsFeedback.Kind?
    @State private var failure: String?
    /// Screenshots and videos attached to the form, ready to send.
    @State private var media: [DiagnosticsMediaFile] = []
    /// Files being made ready (a video is re-encoded, which takes a few seconds).
    @State private var preparing: [String] = []
    @State private var mediaFailure: String?
    @State private var isDropTargeted = false

    var body: some View {
        @Bindable var diagnostics = model.diagnostics
        Section {
            if let kind = draft?.kind {
                form(kind, name: $diagnostics.name)
            } else {
                HStack(spacing: 10) {
                    choice(.bug)
                    choice(.feature)
                }
                .padding(.vertical, 4)
                if let sent {
                    Label(sent == .bug ? "Thank you! Your bug report was sent to the developer."
                                       : "Thank you! Your idea was sent to the developer.",
                          systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
        } header: {
            Text("Report a Problem or Suggest a Feature")
        } footer: {
            if !diagnostics.isConfigured {
                Text("This build cannot send reports (it was made without the developer's address).")
            } else if draft == nil {
                Text("Your report goes straight to the developer. Something not working? Report a bug. Missing something? Request a feature.")
            }
        }
    }

    private func choice(_ kind: DiagnosticsFeedback.Kind) -> some View {
        Button {
            draft = DiagnosticsFeedback(kind: kind)
            sent = nil
            failure = nil
            // Its report (a day of log, ~12 s) is collected while the form is filled in.
            if attachDiagnostics { model.diagnostics.prepareFeedback(kind) }
        } label: {
            HStack(spacing: 10) {
                SettingsTile(systemImage: kind == .bug ? "ladybug.fill" : "lightbulb.fill",
                             tint: kind == .bug ? .red : .green, side: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(kind == .bug ? "Report a Bug" : "Request a Feature").font(.headline)
                    Text(kind == .bug ? "Something doesn't work" : "An idea or a wish")
                        .font(.caption)
                        .foregroundStyle(SettingsPalette.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.bordered)
        .disabled(!model.diagnostics.isConfigured)
    }

    @ViewBuilder
    private func form(_ kind: DiagnosticsFeedback.Kind, name: Binding<String>) -> some View {
        let isBug = kind == .bug
        HStack(spacing: 10) {
            SettingsTile(systemImage: isBug ? "ladybug.fill" : "lightbulb.fill", tint: isBug ? .red : .green, side: 28)
            Text(isBug ? "Bug Report" : "Feature Request").font(.headline)
        }
        TextField("Title", text: field(\.title),
                  prompt: Text(isBug ? "In a few words, e.g. “Siri finds no apps”" : "In a few words, e.g. “A weather widget”"))
        TextField(isBug ? "What happened?" : "Your idea", text: field(\.details),
                  prompt: Text(isBug ? "Describe what went wrong" : "What would you like NotchIsland to do?"),
                  axis: .vertical)
            .lineLimit(3...8)
        if isBug {
            TextField("What did you expect?", text: field(\.expected), prompt: Text("Optional"), axis: .vertical)
                .lineLimit(2...5)
            TextField("How can it be repeated?", text: field(\.steps), prompt: Text("Optional: 1. Open … 2. Click …"), axis: .vertical)
                .lineLimit(2...6)
            Picker("How often?", selection: field(\.frequency)) {
                ForEach(DiagnosticsFeedback.Frequency.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
        } else {
            TextField("Why would it help?", text: field(\.why), prompt: Text("Optional"), axis: .vertical)
                .lineLimit(2...5)
        }
        attachments(isBug: isBug)
        TextField("Your name", text: name, prompt: Text("Optional"))
        Toggle(isOn: $attachDiagnostics) {
            Text("Attach diagnostics")
            Text("The app's state, its log and details of this Mac, so the problem can be found. See Diagnostics below for what is included.")
        }
        if let failure {
            Label(failure, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
        HStack {
            if isSending { ProgressView().controlSize(.small) }
            Spacer()
            Button("Cancel") {
                draft = nil
                failure = nil
                DiagnosticsMedia.discard(media)
                media = []
                mediaFailure = nil
                model.diagnostics.discardPreparedFeedback()
            }
            .disabled(isSending)
            Button(isBug ? "Send Bug Report" : "Send Request") { send() }
                .keyboardShortcut(.defaultAction)
                .disabled(isSending || !preparing.isEmpty || !(draft?.isComplete ?? false))
        }
        .onChange(of: attachDiagnostics) { _, attach in
            if attach, let kind = draft?.kind { model.diagnostics.prepareFeedback(kind) }
        }
    }

    // MARK: Screenshots and videos

    @ViewBuilder
    private func attachments(isBug: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(media) { file in
                HStack(spacing: 8) {
                    Image(systemName: file.isVideo ? "film" : "photo")
                        .foregroundStyle(SettingsPalette.secondary)
                        .frame(width: 18)
                    Text(file.name).lineLimit(1).truncationMode(.middle)
                    Text(ByteCountFormatter.string(fromByteCount: Int64(file.bytes), countStyle: .file)
                         + (file.wasTrimmed ? " · cut to fit" : ""))
                        .font(.caption)
                        .foregroundStyle(SettingsPalette.secondary)
                    Spacer(minLength: 0)
                    Button {
                        DiagnosticsMedia.discard([file])
                        media.removeAll { $0.id == file.id }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(SettingsPalette.secondary)
                    .disabled(isSending)
                    .accessibilityLabel("Remove \(file.name)")
                }
            }
            ForEach(preparing, id: \.self) { name in
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).frame(width: 18)
                    Text("Preparing \(name)…").lineLimit(1).truncationMode(.middle)
                        .foregroundStyle(SettingsPalette.secondary)
                }
            }
            HStack {
                Button {
                    chooseMedia()
                } label: {
                    Label(isBug ? "Add Screenshot or Video…" : "Add Picture or Video…", systemImage: "paperclip")
                }
                .disabled(isSending || media.count + preparing.count >= DiagnosticsMedia.maxFiles)
                Text("or drop them here · up to \(DiagnosticsMedia.maxFiles)")
                    .font(.caption)
                    .foregroundStyle(SettingsPalette.secondary)
            }
            if let mediaFailure {
                Label(mediaFailure, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(isDropTargeted ? 0.8 : 0), lineWidth: 2)
        }
        .dropDestination(for: URL.self) { urls, _ in
            let usable = urls.filter(DiagnosticsMedia.isSupported)
            add(usable)
            if usable.count < urls.count { mediaFailure = "Only pictures and videos can be attached." }
            return !usable.isEmpty
        } isTargeted: { isDropTargeted = $0 }
    }

    private func chooseMedia() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .movie]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "Choose screenshots or screen recordings that show the problem."
        panel.prompt = "Attach"
        // Above the island, which lies over the menu bar.
        panel.level = NSWindow.Level(rawValue: IslandPanel.restingLevel.rawValue + 1)
        panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        let island = NSApp.keyWindow
        panel.begin { response in
            island?.makeKey()
            guard response == .OK else { return }
            add(panel.urls)
        }
    }

    private func add(_ urls: [URL]) {
        mediaFailure = nil
        let room = DiagnosticsMedia.maxFiles - media.count - preparing.count
        if urls.count > room { mediaFailure = "At most \(DiagnosticsMedia.maxFiles) pictures or videos." }
        for url in urls.prefix(max(0, room)) {
            let name = url.lastPathComponent
            preparing.append(name)
            Task {
                do {
                    let file = try await DiagnosticsMedia.prepare(url)
                    if draft == nil {
                        DiagnosticsMedia.discard([file])
                    } else {
                        media.append(file)
                    }
                } catch {
                    mediaFailure = error.localizedDescription
                }
                if let index = preparing.firstIndex(of: name) { preparing.remove(at: index) }
            }
        }
    }

    /// A binding into the draft (which is non-nil while the form shows).
    private func field<Value>(_ path: WritableKeyPath<DiagnosticsFeedback, Value>) -> Binding<Value> {
        Binding(
            get: { draft?[keyPath: path] ?? DiagnosticsFeedback(kind: .bug)[keyPath: path] },
            set: { draft?[keyPath: path] = $0 }
        )
    }

    private func send() {
        guard let feedback = draft, feedback.isComplete else { return }
        isSending = true
        failure = nil
        Task {
            let attached = media
            let delivered = await model.diagnostics.sendFeedback(feedback, attachDiagnostics: attachDiagnostics, media: attached)
            isSending = false
            // Sent, or kept in the outbox with the report: either way no longer the form's.
            media = []
            mediaFailure = nil
            if delivered {
                sent = feedback.kind
                draft = nil
            } else {
                // Kept in the outbox: it goes with the next report, so the text is not lost.
                failure = "Could not send it now (no connection?). It was saved and will be sent automatically later."
                sent = nil
                draft = nil
            }
        }
    }
}

// MARK: - Diagnostics

/// About's "Diagnostics": the switch for automatic reports, and what they contain.
struct DiagnosticsSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var diagnostics = model.diagnostics
        Section {
            Toggle(isOn: $diagnostics.isEnabled) {
                Text("Send Diagnostics to the Developer")
                Text("At launch, every 6 hours, when NotchIsland crashes and when it uses unusually much energy. Uses a little more battery.")
            }
            .disabled(!diagnostics.isConfigured)
            TextField("Your name", text: $diagnostics.name, prompt: Text("Optional, so the developer knows who you are"))
            LabeledContent("Status") {
                status(diagnostics)
            }
            if let power = diagnostics.ownPowerMW {
                LabeledContent("NotchIsland's energy use") {
                    Text(Self.energy(power, reference: diagnostics.referencePowerMW))
                }
            }
            if let latest = diagnostics.latestVersion {
                LabeledContent("Version") {
                    if DiagnosticsVersions.isOlder(diagnostics.version, than: latest) {
                        StatusLabel(title: "\(latest) is out (you have \(diagnostics.version))", tone: .attention)
                    } else {
                        StatusLabel(title: "Up to date", tone: .ok)
                    }
                }
            }
            HStack {
                Button("Preview Report…") { Task { await diagnostics.preview() } }
                Spacer()
                Button("Send Report Now") { Task { await diagnostics.sendReport(.manual) } }
                    .disabled(!diagnostics.isConfigured || diagnostics.state == .sending)
            }
        } header: {
            Text("Diagnostics")
        } footer: {
            Text("""
                Sent: NotchIsland's version, where it runs from and its permissions; the Mac's model, macOS \
                version, language, displays and sound devices; the battery's health and charge; how much \
                energy, CPU and memory NotchIsland uses (a reading every 10 minutes), and the apps using the \
                most energy; every NotchIsland setting and feature's state; whether Spotlight finds your apps \
                (with the names of those it misses); the names of running apps; NotchIsland's log and crash \
                reports. The numbers are compared with the developer's Mac, and anything unusual is reported \
                at once. \
                Never sent: your clipboard, the files on the Shelf, what you search for, or what is playing.
                """)
        }
        .task { await diagnostics.refreshStatus() }
    }

    static func energy(_ power: Double, reference: Double?) -> String {
        let own = String(format: "%.1f mW on average", power)
        guard let reference, reference > 0 else { return own }
        return own + String(format: " (developer's Mac: %.1f mW)", reference)
    }

    @ViewBuilder
    private func status(_ diagnostics: DiagnosticsCenter) -> some View {
        HStack(spacing: 6) {
            switch diagnostics.state {
            case .sending:
                ProgressView().controlSize(.small)
                Text("Collecting and sending…")
            case .failed(let reason):
                StatusLabel(title: reason, tone: .attention)
            case .idle, .sent:
                if let last = diagnostics.lastSent {
                    StatusLabel(title: "Last sent \(last.formatted(.relative(presentation: .named)))", tone: .ok)
                } else {
                    StatusLabel(title: diagnostics.isEnabled ? "Nothing sent yet" : "Off", tone: .neutral)
                }
            }
            if diagnostics.pending > 0 {
                Text("· \(diagnostics.pending) waiting").foregroundStyle(SettingsPalette.secondary)
            }
        }
        .lineLimit(2)
    }
}
