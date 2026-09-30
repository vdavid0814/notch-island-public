import AppKit
import SwiftUI

/// What one instance shows, where its kind asks for it (`WidgetConfig`): a world clock's city, a
/// countdown's date, a shortcut, a launcher's apps, a photo, how many entries a list shows.
struct WidgetConfigInspector: View {
    let session: EditorSession
    let widget: IslandWidget

    private var config: WidgetConfig { widget.config }

    private func set(_ change: @escaping (inout WidgetConfig) -> Void) {
        withAnimation(Motion.content) { session.change(\IslandWidget.config) { change(&$0.config) } }
    }

    var body: some View {
        let fields = widget.kind.configFields
        if !fields.isEmpty {
            InspectorSection("Shows") {
                ForEach(fields, id: \.self) { field in
                    row(field)
                }
            }
        }
    }

    @ViewBuilder private func row(_ field: WidgetConfigField) -> some View {
        switch field {
        case .timeZone:
            InspectorRow("City", isSet: config.timeZone != nil, reset: { set { $0.timeZone = nil } }) {
                TimeZonePicker(identifier: config.timeZone) { identifier in set { $0.timeZone = identifier } }
            }
        case .label:
            InspectorRow("Name", isSet: config.label != nil, reset: { set { $0.label = nil } }) {
                TextField(widget.kind == .countdown ? "Birthday" : "Name", text: Binding(get: { config.label ?? "" },
                                                                                          set: { text in set { $0.label = text } }))
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
            }
        case .date:
            InspectorRow("Date", isSet: config.date != nil, reset: { set { $0.date = nil } }) {
                DatePicker("", selection: Binding(get: { config.date ?? Calendar.current.date(byAdding: .day, value: 30, to: .now) ?? .now },
                                                  set: { date in set { $0.date = date } }),
                           displayedComponents: [.date])
                    .labelsHidden()
                    .datePickerStyle(.field)
                    .controlSize(.small)
            }
        case .shortcut:
            InspectorRow("Shortcut", isSet: config.shortcutName != nil, reset: { set { $0.shortcutName = nil } }) {
                ShortcutPicker(name: config.shortcutName) { name in set { $0.shortcutName = name } }
            }
        case .symbol:
            InspectorRow("Symbol", isSet: config.symbol != nil, reset: { set { $0.symbol = nil } }) {
                TextField("bolt.fill", text: Binding(get: { config.symbol ?? "" }, set: { text in set { $0.symbol = text } }))
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .help("An SF Symbol's name")
            }
        case .apps:
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array((config.apps ?? []).enumerated()), id: \.offset) { index, path in
                    HStack(spacing: 8) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                            .resizable()
                            .frame(width: 18, height: 18)
                        Text(URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Button {
                            set { $0.apps?.remove(at: index) }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove")
                    }
                }
                Button("Add App…", systemImage: "plus") {
                    if let app = ImageChooser.chooseApp() {
                        set { config in
                            var apps = config.apps ?? []
                            guard !apps.contains(app), apps.count < WidgetConfig.countRange.upperBound else { return }
                            apps.append(app)
                            config.apps = apps
                        }
                    }
                }
                .controlSize(.small)
                .disabled((config.apps?.count ?? 0) >= WidgetConfig.countRange.upperBound)
            }
        case .image:
            InspectorRow("Photo", isSet: config.imagePath != nil, reset: { set { $0.imagePath = nil } }) {
                HStack(spacing: 6) {
                    Text(config.imagePath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "None")
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .font(.caption)
                        .foregroundStyle(SettingsPalette.secondary)
                    Button("Choose…") {
                        if let path = ImageChooser.choose() { set { $0.imagePath = path } }
                    }
                    .controlSize(.small)
                }
            }
        case .count(let range):
            InspectorRow("Entries", isSet: config.count != nil, reset: { set { $0.count = nil } }) {
                Stepper(value: Binding(get: { config.count ?? widget.kind.spec.defaultConfig.count ?? range.lowerBound },
                                       set: { count in set { $0.count = count } }), in: range) {
                    Text("\(config.count ?? widget.kind.spec.defaultConfig.count ?? range.lowerBound)")
                        .monospacedDigit()
                }
                .controlSize(.small)
            }
        case .calendars:
            InspectorRow("Calendars", isSet: config.calendarIDs != nil, reset: { set { $0.calendarIDs = nil } }) {
                Text(config.calendarIDs.map { "\($0.count) chosen" } ?? "All")
                    .font(.caption)
                    .foregroundStyle(SettingsPalette.secondary)
            }
        }
    }
}

/// A field a kind's instance sets.
enum WidgetConfigField: Hashable {
    case timeZone, label, date, shortcut, symbol, apps, image, calendars
    case count(ClosedRange<Int>)
}

extension IslandWidgetKind {
    var configFields: [WidgetConfigField] {
        switch self {
        case .worldClock: [.timeZone, .label]
        case .analogClock: [.timeZone]
        case .countdown: [.label, .date]
        case .shortcut: [.shortcut, .symbol]
        case .appLauncher: [.apps]
        case .clipboard: [.count(1...5)]
        case .photoFrame: [.image]
        case .upNext: [.calendars, .count(1...4)]
        case .focus: [.shortcut]
        default: []
        }
    }
}

/// The time zones by city, searchable as the system's clock lists them.
struct TimeZonePicker: View {
    let identifier: String?
    let set: (String?) -> Void

    @State private var isOpen = false
    @State private var search = ""

    var body: some View {
        Button(identifier.map(TimeZonePicker.city) ?? "Here") { isOpen.toggle() }
            .controlSize(.small)
            .popover(isPresented: $isOpen, arrowEdge: .bottom) {
                VStack(spacing: 8) {
                    TextField("Search", text: $search)
                        .textFieldStyle(.roundedBorder)
                    List(Self.zones.filter { search.isEmpty || $0.localizedCaseInsensitiveContains(search) }, id: \.self) { zone in
                        Button {
                            set(zone)
                            isOpen = false
                        } label: {
                            HStack {
                                Text(Self.city(zone))
                                Spacer()
                                Text(TimeZone(identifier: zone)?.abbreviation() ?? "")
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(height: 260)
                }
                .padding(12)
                .frame(width: 280)
            }
    }

    static let zones = TimeZone.knownTimeZoneIdentifiers.filter { $0.contains("/") && !$0.hasPrefix("Etc/") }

    /// "America/New_York" → "New York".
    static func city(_ identifier: String) -> String {
        (identifier.split(separator: "/").last.map(String.init) ?? identifier).replacingOccurrences(of: "_", with: " ")
    }
}

/// The user's shortcuts, read from `shortcuts list` when the menu opens (not before).
struct ShortcutPicker: View {
    let name: String?
    let set: (String?) -> Void

    @State private var names: [String]?

    var body: some View {
        Menu(name ?? "Choose…") {
            if let names {
                if names.isEmpty { Text("No shortcuts") }
                ForEach(names, id: \.self) { shortcut in
                    Button(shortcut) { set(shortcut) }
                }
            } else {
                Text("Reading your shortcuts…")
            }
        }
        .controlSize(.small)
        .fixedSize()
        .onAppear {
            guard names == nil else { return }
            Task.detached(priority: .userInitiated) {
                let list = DiagnosticsProbes.run(AssistantSearch.shortcutsTool, ["list"], timeout: 5)?
                    .split(separator: "\n").map(String.init).filter { !$0.isEmpty }.sorted() ?? []
                await MainActor.run { names = list }
            }
        }
    }
}
