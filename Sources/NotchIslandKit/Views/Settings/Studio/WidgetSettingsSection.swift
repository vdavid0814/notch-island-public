import SwiftUI

/// Customize's Settings: what this one widget shows, where its kind asks (`WidgetKindSpec.settings`,
/// stored in `WidgetConfig`) — a world clock's city and its caption, a list's length. Each row a
/// native control; a change applies at once (the caption when it is typed out).
struct WidgetSettingsSection: View {
    let widget: IslandWidget

    @Environment(AppModel.self) private var model
    @State private var caption = ""
    @FocusState private var isEditingCaption: Bool

    var body: some View {
        let settings = widget.kind.spec.settings
        VStack(alignment: .leading, spacing: 10) {
            Text("Settings").font(.subheadline.weight(.semibold))
            if settings.contains(.timeZone) { city }
            if settings.contains(.label) { captionField }
            if settings.contains(.count) { count }
            if settings.contains(.files) { files }
            // How many rows have a symbol, while Symbols is on (off: none).
            if settings.contains(.symbols), widget.shows(.clipSymbols) { symbols }
        }
        .onAppear { caption = widget.config.label ?? "" }
        .onChange(of: widget.id) { caption = widget.config.label ?? "" }
        .onChange(of: widget.config.label) { _, label in if !isEditingCaption { caption = label ?? "" } }
    }

    private func update(_ change: (inout WidgetConfig) -> Void) {
        model.editedWidgets.update(widget.id) { change(&$0.config) }
    }

    // MARK: The city

    /// The time zones by region ("Europe" → Budapest, London…), each city once, by name.
    private static let regions: [(name: String, zones: [(city: String, id: String)])] = {
        var regions: [String: [(String, String)]] = [:]
        for id in TimeZone.knownTimeZoneIdentifiers {
            let parts = id.split(separator: "/")
            guard parts.count >= 2, let zone = TimeZone(identifier: id) else { continue }
            regions[String(parts[0]), default: []].append((WorldClockWidget.city(zone), id))
        }
        return regions.keys.sorted().map { region in
            (region.replacingOccurrences(of: "_", with: " "), regions[region]!.sorted { $0.0 < $1.0 })
        }
    }()

    /// Where a widget without a city of its own is: the world clock in Cupertino, the clock face here.
    private var homeCity: String {
        widget.kind == .worldClock ? "Cupertino" : String(localized: "This Mac")
    }

    private var city: some View {
        let current = widget.config.timeZone.flatMap(TimeZone.init(identifier:)).map(WorldClockWidget.city) ?? homeCity
        return HStack {
            Text("City")
            Spacer(minLength: 8)
            Menu(current) {
                Button(homeCity) { update { $0.timeZone = nil } }
                Divider()
                ForEach(Self.regions, id: \.name) { region in
                    Menu(region.name) {
                        ForEach(region.zones, id: \.id) { zone in
                            Button(zone.city) { update { $0.timeZone = zone.id } }
                        }
                    }
                }
            }
            .fixedSize()
        }
    }

    // MARK: The caption

    private var captionField: some View {
        HStack {
            Text("Caption")
            Spacer(minLength: 8)
            TextField("Caption", text: $caption, prompt: Text(defaultCaption))
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 150)
                .focused($isEditingCaption)
                .onSubmit(commitCaption)
                .onChange(of: isEditingCaption) { _, editing in if !editing { commitCaption() } }
                .labelsHidden()
        }
    }

    /// The city's own name, shown while none of the user's is set.
    private var defaultCaption: String {
        if widget.kind == .analogClock {
            var config = widget.config
            config.label = nil
            return ClockFaceWidget.caption(config, here: .current)
        }
        return widget.config.timeZone == nil ? "Cupertino" : WorldClockWidget.city(WorldClockWidget.zone(widget.config))
    }

    private func commitCaption() {
        let text = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        update { $0.label = text.isEmpty ? nil : text }
        caption = text
    }

    // MARK: The rows

    private var count: some View {
        let value = ClipboardWidget.count(widget)
        return Stepper(value: Binding(get: { value }, set: { new in withAnimation(Motion.content) { update { $0.count = new } } }),
                       in: WidgetConfig.countRange) {
            HStack {
                Text("Rows")
                Spacer(minLength: 8)
                Text("\(value)").monospacedDigit().foregroundStyle(SettingsPalette.secondary)
            }
        }
    }

    /// How many files share the shelf's row: they grow or shrink to fill it.
    private var files: some View {
        let value = ShelfWidget.fileCount(widget)
        return Stepper(value: Binding(get: { value }, set: { new in withAnimation(Motion.content) { update { $0.count = new } } }),
                       in: ShelfWidget.fileCounts) {
            HStack {
                Text("Files")
                Spacer(minLength: 8)
                Text("\(value)").monospacedDigit().foregroundStyle(SettingsPalette.secondary)
            }
        }
        .help("How many files the row shows at once; they are sized to fill it")
    }

    /// How many rows have a symbol: one more goes on the first row without one (styled as the last
    /// one added), one fewer takes the lowest away; a symbol deleted in the editor goes alone.
    private var symbols: some View {
        let rows = ClipboardWidget.count(widget)
        let value = widget.clipSymbolRows.count
        return Stepper(value: Binding(get: { value }, set: { new in
            withAnimation(Motion.content) {
                model.editedWidgets.update(widget.id) { widget in
                    if new > value {
                        let last = widget.clipSymbolRows.last.map(ElementID.clipSymbol)
                        let source = widget
                        widget.addClipSymbol(like: last, in: source)
                    } else if new < value, let lowest = widget.clipSymbolRows.last {
                        widget.removeClipSymbol(lowest)
                    }
                }
            }
        }), in: 1...max(rows, 1)) {
            HStack {
                Text("Symbols")
                Spacer(minLength: 8)
                Text(value == rows ? String(localized: "All \(value)") : "\(value)").monospacedDigit().foregroundStyle(SettingsPalette.secondary)
            }
        }
        .help("How many rows have a symbol; in the editor, ⌘C ⌘V adds one, Delete takes the picked one away")
    }
}
