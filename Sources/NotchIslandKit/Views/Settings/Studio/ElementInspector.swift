import SwiftUI

/// Customize's right panel: how the part picked in the editor is set. For a text part (Now
/// Playing's title, its artist): its size, style and typeface, how many lines it may take, how it is
/// aligned, its colour, and a background of its own with its corners (`TextStyle`). For a button
/// (play, previous, next): what it is made of, its shape and corners, its fill and its symbol's
/// colour (`ButtonLook`; the symbol is placed in the panel under the editor).
struct ElementInspector: View {
    let widget: IslandWidget
    let editing: ElementEditing

    @Environment(AppModel.self) private var model
    /// The colour whose mixer is open.
    @State private var mixing: Mixing?

    private enum Mixing: Hashable {
        /// A text's letters (the title's, a time's).
        case text(ElementID)
        case background, buttonFill, icon, track, played
        case chartLow, chartMedium, chartHigh
        case ruler, rulerFill
        case dayFill, gridFill
    }

    /// The panel's inside: its bars are made exactly as wide.
    static let innerWidth = WidgetCustomizeView.panelWidth - 32

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: StudioDivider.spacing) {
                if editing.group.count >= 2 {
                    groupSettings(editing.group)
                } else if let id = editing.selected, widget.kind.spec.texts.contains(id) {
                    text(id)
                } else if let id = editing.selected, widget.kind.spec.buttons.contains(id) {
                    button(id)
                } else if let id = editing.selected, widget.kind.spec.progressBars.contains(id) {
                    progress(id)
                } else if let id = editing.selected, widget.kind.spec.images.contains(id) {
                    image(id)
                } else if let id = editing.selected, widget.kind.spec.charts.contains(id) {
                    chart(id)
                } else if let id = editing.selected, widget.kind.spec.rulers.contains(id) {
                    ruler(id)
                } else if let id = editing.selected, widget.kind.spec.dayGrids.contains(id) {
                    dayGrid(id)
                } else if let id = editing.selected, let figure = widget.figure(id) {
                    figureSettings(figure)
                } else {
                    placeholder
                }
            }
            .frame(width: Self.innerWidth, alignment: .leading)
            .padding(16)
            .animation(.spring(duration: 0.35, bounce: 0.12), value: widget.textStyles)
            .animation(.spring(duration: 0.35, bounce: 0.12), value: widget.buttonLooks)
            .animation(.spring(duration: 0.35, bounce: 0.12), value: widget.progressLooks)
            .animation(.spring(duration: 0.35, bounce: 0.12), value: widget.imageLooks)
            .animation(.spring(duration: 0.35, bounce: 0.12), value: widget.chartLooks)
            .animation(.spring(duration: 0.35, bounce: 0.12), value: widget.rulerLooks)
            .animation(.spring(duration: 0.35, bounce: 0.12), value: widget.dayGridLooks)
            .animation(.spring(duration: 0.35, bounce: 0.12), value: widget.figures)
            .animation(.spring(duration: 0.35, bounce: 0.12), value: mixing)
        }
        .scrollIndicators(.never)
        .onChange(of: editing.selected) { mixing = nil }
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "textformat")
                .font(.system(size: 26))
                .foregroundStyle(SettingsPalette.secondary)
            Text("Pick a part in the editor to set how it looks.")
                .font(.callout)
                .foregroundStyle(SettingsPalette.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    // MARK: A text part

    @ViewBuilder private func text(_ id: ElementID) -> some View {
        let style = widget.textStyle(of: id)
        let element = widget.kind.spec.element(id)
        HStack(spacing: 10) {
            Image(systemName: element?.symbol ?? "textformat")
                .font(.system(size: 18))
                .foregroundStyle(SettingsPalette.secondary)
                .frame(width: 32, height: 32)
                .background(.white.opacity(0.06), in: .rect(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(element?.title ?? "Text").font(.headline)
                Text("Text").font(.caption).foregroundStyle(SettingsPalette.secondary)
            }
            Spacer(minLength: 8)
            if style != .plain {
                Button("Reset") {
                    withAnimation(.spring(duration: 0.4, bounce: 0.18)) { update(id) { $0 = .plain } }
                }
                .help("This text as the widget sets it")
            }
        }
        StudioDivider()
        font(id, style)
        StudioDivider()
        layout(id, style)
        StudioDivider()
        colour(id, style)
        StudioDivider()
        background(id, style)
    }

    /// Size, style and typeface.
    /// `showsSize`: its size slider (and Auto Size) too — not where it is sized elsewhere.
    @ViewBuilder private func font(_ id: ElementID, _ style: TextStyle, showsSize: Bool = true) -> some View {
        let automatic = Double(WidgetParts.textSize(of: id, in: widget, inner: inner))
        let size = style.size ?? automatic
        section("Font") {
            if showsSize {
                switchRow("Auto size", isOn: style.overflow == .shrink,
                          help: "On: the letters sized to fit, between the largest and smallest below. Off: always the size below; a longer text ends in “…”") { on in
                    update(id) { style in
                        style.overflow = on ? .shrink : .truncate
                        // Fitted to a box: one as large as the text is now, where it has none (its
                        // Largest and Smallest show at once, not after the box is first resized).
                        if on { giveBox(id, &style) }
                    }
                }
                // Its size, where it is not the box's (Auto size off, or no box of its own).
                if style.overflow != .shrink || style.box == nil {
                    // Fitting itself (no box of its own), its size is the largest it shrinks from.
                    let title: LocalizedStringKey = style.overflow == .shrink ? "Largest" : "Size"
                    HStack(spacing: 10) {
                        Text(title).font(.callout)
                        Slider(value: Binding(get: { size }, set: { new in
                            let points = new.rounded()
                            if points != size { update(id) { $0.size = points } }
                        }), in: TextStyle.sizes) { Text(title) }
                        .labelsHidden()
                        .tint(Color.islandAccent)
                        // Always its size: Auto is the switch above (whether it may fit itself).
                        ReservedWidthText("\(Int(size.rounded())) pt", fitting: ["48 pt"])
                            .foregroundStyle(SettingsPalette.secondary)
                            .monospacedDigit()
                    }
                }
                // Fitted to its box: from its smallest to its largest, in points, the largest as large
                // as one line of letters the box holds — the box's, whatever the text.
                if style.overflow == .shrink, style.box != nil {
                    let size = textSize(id, style)
                    let top = boxLargest(id, style)
                    let largest = min(style.maximumSize ?? top, top)
                    // As the label fits it: the one set, else its share of its size, no less than
                    // a text shrinks to on its own (a smallest set lower is the user's, and kept).
                    let smallest = min(style.minimumSize ?? max(Double(size) * style.effectiveMinimumScale, TextStyle.automaticLowest),
                                       largest)
                    pointSlider("Largest", value: largest, in: TextStyle.sizes.lowerBound...top,
                                help: "The largest the letters may grow to fill the box") { points in
                        update(id) { style in
                            style.maximumSize = points >= top - 0.25 ? nil : points
                            if let minimum = style.minimumSize, minimum > points { style.minimumSize = points }
                        }
                    }
                    pointSlider("Smallest", value: smallest, in: TextStyle.sizes.lowerBound...max(largest, TextStyle.sizes.lowerBound + 1),
                                help: "The smallest the letters may shrink to before a text too long is cut") { points in
                        update(id) { $0.minimumSize = points }
                    }
                } else if style.overflow == .shrink {
                    let smallest = style.effectiveMinimumScale
                    HStack(spacing: 10) {
                        Text("Smallest").font(.callout)
                        Slider(value: Binding(get: { smallest }, set: { new in
                            let snapped = (new * 20).rounded() / 20
                            if snapped != smallest { update(id) { $0.minimumScale = snapped } }
                        }), in: TextStyle.minimumScales) { Text("Smallest") }
                        .labelsHidden()
                        .tint(Color.islandAccent)
                        ReservedWidthText(smallest.formatted(.percent.precision(.fractionLength(0))),
                                          fitting: [Double(0.9).formatted(.percent.precision(.fractionLength(0)))])
                            .foregroundStyle(SettingsPalette.secondary)
                            .monospacedDigit()
                    }
                    .help("How small the letters may get before the text is cut, as a share of their size")
                }
            }
            HStack(spacing: 6) {
                styleToggle("Bold", "bold", id, \.isBold)
                styleToggle("Italic", "italic", id, \.isItalic)
                styleToggle("Underline", "underline", id, \.isUnderlined)
                styleToggle("Strikethrough", "strikethrough", id, \.isStruckThrough)
                Spacer(minLength: 0)
            }
            // The menu right after its name, as the other rows' controls are.
            HStack(spacing: 10) {
                Text("Typeface").font(.callout)
                Picker("Typeface", selection: Binding(get: { style.design }, set: { design in update(id) { $0.design = design } })) {
                    ForEach(TextStyle.Design.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
            }
        }
    }

    private func styleToggle(_ title: LocalizedStringKey, _ symbol: String, _ id: ElementID,
                             _ keyPath: WritableKeyPath<TextStyle, Bool>) -> some View {
        Toggle(isOn: Binding(get: { widget.textStyle(of: id)[keyPath: keyPath] },
                             set: { on in update(id) { $0[keyPath: keyPath] = on } })) {
            Image(systemName: symbol).frame(width: 18)
        }
        .toggleStyle(.button)
        .help(Text(title))
    }

    /// Lines and alignment: as many lines as set, or as the box holds (Auto).
    @ViewBuilder private func layout(_ id: ElementID, _ style: TextStyle) -> some View {
        let lines = style.maxLines ?? 1
        let auto = style.linesFillBox && style.box != nil
        section("Lines") {
            Stepper(value: Binding(get: { lines }, set: { new in
                update(id) { style in
                    // A box too low for the lines set: as tall as they are at the letters' size now
                    // (downwards), or the lines could never be taken.
                    roomForLines(new, id, &style)
                    style.maxLines = new == 1 ? nil : new
                }
            }),
                    in: TextStyle.lines) {
                Text(auto ? String(localized: "Lines to fill the box")
                     : lines == 1 ? String(localized: "1 line") : String(localized: "\(lines) lines"))
                    .font(.callout)
            }
            .disabled(auto)
            switchRow("Auto lines", isOn: auto,
                      help: "On: as many lines as the box holds, more or fewer as you size it in the editor. Off: the lines set above") { on in
                update(id) { style in
                    // Back to the lines set: room for them, as the stepper makes it.
                    if !on { roomForLines(style.maxLines ?? 1, id, &style) }
                    style.linesFillBox = on
                    // Lines follow a box: one as large as the text is now, where it has none.
                    if on { giveBox(id, &style) }
                }
            }
            Picker("Alignment", selection: Binding(get: { style.alignment }, set: { alignment in update(id) { $0.alignment = alignment } })) {
                ForEach(TextStyle.Alignment.allCases) { alignment in
                    Label(alignment.title, systemImage: alignment.symbol).labelStyle(.iconOnly).tag(alignment)
                }
            }
            .choiceBar(width: Self.innerWidth)
            .labelsHidden()
            .fixedSize()
            .help("Left, centre, right, or justified: every full line as wide as the box")
            // Letters sized to fit, the text on fewer lines than it may take: how a longer one would
            // look (in the editor only).
            if let preview = LabelFit.preview(text(of: id), style: style, size: textSize(id, style), weight: weight(of: id)) {
                let trying = editing.linePreview == id
                Button {
                    withAnimation(.spring(duration: 0.3)) { editing.linePreview = trying ? nil : id }
                } label: {
                    Label(trying ? String(localized: "Back to This Text") : String(localized: "Try How \(preview.lines) Lines Would Look"),
                          systemImage: trying ? "arrow.uturn.backward" : "text.line.first.and.arrowtriangle.forward")
                        .frame(maxWidth: .infinity)
                }
                .buttonBorderShape(.capsule)
                .help("In the editor only: the letters as large as a text on that many lines gets them, the room left in stronger dots")
            }
            Text("In the editor, dots show the room left at these lines.")
                .font(.caption)
                .foregroundStyle(SettingsPalette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A size in whole points, by a slider, shown beside it.
    private func pointSlider(_ title: LocalizedStringKey, value: Double, in range: ClosedRange<Double>,
                             help: LocalizedStringKey, set: @escaping (Double) -> Void) -> some View {
        HStack(spacing: 10) {
            Text(title).font(.callout)
            Slider(value: Binding(get: { min(max(value, range.lowerBound), range.upperBound) }, set: { new in
                let points = new.rounded()
                if points != value.rounded() { set(min(points, range.upperBound)) }
            }), in: range) { Text(title) }
            .labelsHidden()
            .tint(Color.islandAccent)
            ReservedWidthText("\(Int(value.rounded())) pt", fitting: ["48 pt"])
                .foregroundStyle(SettingsPalette.secondary)
                .monospacedDigit()
        }
        .help(help)
    }

    /// A row with its name and its switch right after it.
    private func switchRow(_ title: LocalizedStringKey, isOn: Bool, help: LocalizedStringKey,
                           set: @escaping (Bool) -> Void) -> some View {
        HStack(spacing: 10) {
            Text(title).font(.callout)
            Toggle(title, isOn: Binding(get: { isOn }, set: { on in
                withAnimation(.spring(duration: 0.35, bounce: 0.12)) { set(on) }
            }))
            .toggleStyle(.switch)
            .tint(Color.islandControlAccent)
            .labelsHidden()
            .controlSize(.small)
            Spacer(minLength: 0)
        }
        .help(help)
    }

    /// The text a part shows now (or the editor's sample).
    private func text(of id: ElementID) -> String { WidgetParts.text(of: id, in: widget, model: model) }

    private func weight(of id: ElementID) -> NSFont.Weight { WidgetParts.weight(of: id, in: widget) }

    /// The box as tall as `lines` lines of the letters as they are drawn now, where it is lower.
    private func roomForLines(_ lines: Int, _ id: ElementID, _ style: inout TextStyle) {
        guard var box = style.box else { return }
        let font = style.overflow == .shrink
            ? LabelFit.fitted(text(of: id), style: style, size: textSize(id, style), weight: weight(of: id)).font
            : style.font(size: textSize(id, style), weight: weight(of: id))
        let height = Double((CGFloat(lines) * font.lineHeight).rounded(.up))
        guard box.height < height else { return }
        box.height = height
        style.box = box
    }

    /// As large as one line of the letters fits the text's box, whatever the text: the top of the
    /// Largest slider is the box's, not the words' (every text part alike).
    private func boxLargest(_ id: ElementID, _ style: TextStyle) -> Double {
        let limit = LabelFit.boxLimit(style, size: textSize(id, style), weight: weight(of: id)).map(Double.init) ?? TextStyle.sizes.upperBound
        return min(max(limit, TextStyle.sizes.lowerBound + 1), TextStyle.sizes.upperBound)
    }

    /// A box of its own for the text, as large as it is now in the editor, where it has none.
    private func giveBox(_ id: ElementID, _ style: inout TextStyle) {
        guard style.box == nil, let box = editing.boxes[id] else { return }
        let insets = style.background?.insets ?? .zero
        style.box = TextStyle.BoxSize(width: Double(box.width - 2 * insets.width), height: Double(box.height - 2 * insets.height))
    }

    /// The size the part's letters are set at before they shrink.
    private func textSize(_ id: ElementID, _ style: TextStyle) -> CGFloat {
        CGFloat(style.size ?? Double(WidgetParts.textSize(of: id, in: widget, inner: inner)))
    }

    private enum ColourChoice: Hashable {
        case automatic, custom, artwork
    }

    /// The colour of the letters.
    @ViewBuilder private func colour(_ id: ElementID, _ style: TextStyle) -> some View {
        section("Colour", caption: "The colour of the letters.") {
            colourChoice(style.color, mixing: .text(id)) { color in update(id) { $0.color = color } }
        }
    }

    /// A background behind this text alone, and its corners.
    @ViewBuilder private func background(_ id: ElementID, _ style: TextStyle) -> some View {
        let background = style.background
        section("Background", caption: "Behind this text only, not the whole widget.") {
            HStack(spacing: 10) {
                Text("Own background").font(.callout)
                Toggle("Own background", isOn: Binding(get: { background != nil }, set: { on in
                    update(id) { $0.background = on ? ElementBackground() : nil }
                    if !on, mixing == .background { mixing = nil }
                }))
                .toggleStyle(.switch)
                .tint(Color.islandControlAccent)
                .labelsHidden()
                .controlSize(.small)
                Spacer(minLength: 0)
            }
            if let background {
                Picker("Background", selection: Binding(get: { background.kind }, set: { kind in
                    update(id) { $0.background?.kind = kind }
                    mixing = kind == .colour ? .background : nil
                })) {
                    ForEach(ElementBackground.Kind.allCases) { Text($0.title).tag($0) }
                }
                .choiceBar(width: Self.innerWidth)
                .labelsHidden()
                .fixedSize()
                if background.kind == .colour {
                    mixer(background.color ?? model.preferences.theme.rgb, isOpen: mixing == .background,
                          toggle: { mixing = mixing == .background ? nil : .background }) { rgb in
                        update(id) { $0.background?.color = rgb }
                    }
                }
                let opacity = background.effectiveOpacity
                HStack(spacing: 10) {
                    Text("Opacity").font(.callout)
                    Slider(value: Binding(get: { opacity }, set: { new in
                        let snapped = (new * 100).rounded() / 100
                        if snapped != opacity { update(id) { $0.background?.opacity = snapped } }
                    }), in: 0...1) { Text("Opacity") }
                    .labelsHidden()
                    .tint(Color.islandAccent)
                    ReservedWidthText(opacity.formatted(.percent.precision(.fractionLength(0))),
                                      fitting: [Double(1).formatted(.percent.precision(.fractionLength(0)))])
                        .foregroundStyle(SettingsPalette.secondary)
                        .monospacedDigit()
                }
            }
        }
        if let background {
            StudioDivider()
            section("Corners", caption: "The background's corners.") {
                Picker("Corners", selection: Binding(get: { background.corners }, set: { corners in
                    update(id) { $0.background?.corners = corners }
                })) {
                    ForEach(ElementBackground.Corners.allCases) { Text($0.title).tag($0) }
                }
                .choiceBar(width: Self.innerWidth)
                .labelsHidden()
                .fixedSize()
            }
        }
    }

    // MARK: A chart

    /// A chart's bars: their corners, their colour by how far the battery has run down, and the
    /// percentages beside it.
    @ViewBuilder private func chart(_ id: ElementID) -> some View {
        let look = widget.chartLook(of: id)
        let element = widget.kind.spec.element(id)
        HStack(spacing: 10) {
            Image(systemName: element?.symbol ?? "chart.bar")
                .font(.system(size: 18))
                .foregroundStyle(SettingsPalette.secondary)
                .frame(width: 32, height: 32)
                .background(.white.opacity(0.06), in: .rect(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(element?.title ?? "Chart").font(.headline)
                Text("Chart").font(.caption).foregroundStyle(SettingsPalette.secondary)
            }
            Spacer(minLength: 8)
            if look != .plain {
                Button("Reset") {
                    withAnimation(.spring(duration: 0.4, bounce: 0.18)) { updateChart(id) { $0 = .plain } }
                }
                .help("The chart as the widget draws it")
            }
        }
        StudioDivider()
        section("Corners", caption: "The bars' tops.") {
            Picker("Corners", selection: Binding(get: { look.corners }, set: { corners in updateChart(id) { $0.corners = corners } })) {
                ForEach(ChartLook.Corners.allCases) { Text($0.title).tag($0) }
            }
            .choiceBar(width: Self.innerWidth)
            .labelsHidden()
            .fixedSize()
        }
        // A day's use (Daily Usage), or how far the battery had run down (the charge chart).
        let usage = widget.kind == .batteryUsage
        StudioDivider()
        section(usage ? "Light Use" : "Run Down a Lot",
                caption: usage ? "Days that used under \(PowerState.lowLevel) % of the battery. Automatic: grey, the picked day in its colour."
                    : "Bars under \(PowerState.lowLevel) %.") {
            colourChoice(look.lowColor, mixing: .chartLow) { color in updateChart(id) { $0.lowColor = color } }
        }
        StudioDivider()
        section(usage ? "Some Use" : "Run Down Some",
                caption: usage ? "Days that used \(PowerState.lowLevel) to \(ChartLook.mediumLevel) %." : "Bars from \(PowerState.lowLevel) to \(ChartLook.mediumLevel) %.") {
            colourChoice(look.mediumColor, mixing: .chartMedium) { color in updateChart(id) { $0.mediumColor = color } }
        }
        StudioDivider()
        section(usage ? "Heavy Use" : "Run Down Little",
                caption: usage ? "Days that used \(ChartLook.mediumLevel) % or more." : "Bars from \(ChartLook.mediumLevel) % up.") {
            colourChoice(look.highColor, mixing: .chartHigh) { color in updateChart(id) { $0.highColor = color } }
        }
        StudioDivider()
        section("Percentages", caption: "Beside the chart, each with its line, where it is wide enough; ones too close to the next are left out.") {
            HStack(spacing: 10) {
                Text("Write").font(.callout)
                Picker("Percentages", selection: Binding(get: { look.percentStep }, set: { step in updateChart(id) { $0.percentStep = step } })) {
                    ForEach(ChartLook.percentSteps, id: \.self) { Text(ChartLook.title(ofStep: $0)).tag($0) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
            }
        }
    }

    // MARK: A ruler

    /// A ruler (the timer's): the colour of its ticks, their ends, and what is behind it — its
    /// material, corners and fill, as a button's.
    @ViewBuilder private func ruler(_ id: ElementID) -> some View {
        let look = widget.rulerLook(of: id)
        let element = widget.kind.spec.element(id)
        HStack(spacing: 10) {
            Image(systemName: element?.symbol ?? "ruler")
                .font(.system(size: 18))
                .foregroundStyle(SettingsPalette.secondary)
                .frame(width: 32, height: 32)
                .background(.white.opacity(0.06), in: .rect(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(element?.title ?? "Ruler").font(.headline)
                Text("Ruler").font(.caption).foregroundStyle(SettingsPalette.secondary)
            }
            Spacer(minLength: 8)
            if look != .plain {
                Button("Reset") {
                    withAnimation(.spring(duration: 0.4, bounce: 0.18)) { updateRuler(id) { $0 = .plain } }
                }
                .help("The ruler as the widget draws it")
            }
        }
        StudioDivider()
        frame(id)
        StudioDivider()
        section("Colour", caption: "The ticks, the marker under them and the numbers. Automatic is the timer's orange.") {
            colourChoice(look.color, mixing: .ruler) { color in updateRuler(id) { $0.color = color } }
        }
        StudioDivider()
        section("Ticks", caption: "The ends of the ticks.") {
            Picker("Ticks", selection: Binding(get: { look.ends }, set: { ends in
                withAnimation(.spring(duration: 0.4, bounce: 0.18)) { updateRuler(id) { $0.ends = ends } }
            })) {
                ForEach(ButtonLook.Corners.allCases) { Text($0.title).tag($0) }
            }
            .choiceBar(width: Self.innerWidth)
            .labelsHidden()
            .fixedSize()
        }
        StudioDivider()
        section("Material", caption: "What is behind the ruler. Regular is the ruler alone, as the widget draws it.") {
            Picker("Material", selection: Binding(get: { look.material }, set: { material in
                withAnimation(.spring(duration: 0.4, bounce: 0.18)) { updateRuler(id) { $0.material = material } }
            })) {
                ForEach(ButtonLook.Material.allCases) { Text($0.title).tag($0) }
            }
            .choiceBar(width: Self.innerWidth)
            .labelsHidden()
            .fixedSize()
        }
        if look.material.hasShape {
            StudioDivider()
            section("Corners", caption: "The background's corners: Round makes it a capsule.") {
                Picker("Corners", selection: Binding(get: { look.corners }, set: { corners in
                    withAnimation(.spring(duration: 0.4, bounce: 0.18)) { updateRuler(id) { $0.corners = corners } }
                })) {
                    ForEach(ButtonLook.Corners.allCases) { Text($0.title).tag($0) }
                }
                .choiceBar(width: Self.innerWidth)
                .labelsHidden()
                .fixedSize()
            }
            StudioDivider()
            section("Background", caption: "None: a faint grey edge only. Cover: the artwork's colour.") {
                Picker("Background", selection: Binding(get: { look.fill }, set: { fill in
                    updateRuler(id) { look in
                        look.fill = fill
                        if fill == .colour, look.fillColor == nil { look.fillColor = model.preferences.theme.rgb }
                    }
                    mixing = fill == .colour ? .rulerFill : nil
                })) {
                    ForEach(ButtonLook.Fill.allCases) { Text($0.title).tag($0) }
                }
                .choiceBar(width: Self.innerWidth)
                .labelsHidden()
                .fixedSize()
                if look.fill == .colour {
                    mixer(look.fillColor ?? model.preferences.theme.rgb, isOpen: mixing == .rulerFill,
                          toggle: { mixing = mixing == .rulerFill ? nil : .rulerFill }) { rgb in
                        updateRuler(id) { $0.fillColor = rgb }
                    }
                }
            }
        }
        if editing.picksRulerUnit, widget.shows(.rulerUnit) { rulerUnit() }
    }

    /// The ruler's unit name, picked in the panel under the editor: its type and colour (its size,
    /// box and place are set in that panel).
    @ViewBuilder private func rulerUnit() -> some View {
        let style = widget.textStyle(of: .rulerUnit)
        StudioDivider()
        HStack {
            Text("Unit Name").font(.subheadline.weight(.semibold))
            Spacer(minLength: 8)
            if style != .plain {
                Button("Reset") {
                    withAnimation(.spring(duration: 0.35, bounce: 0.12)) { update(.rulerUnit) { $0 = .plain } }
                }
                .controlSize(.small)
                .help("The unit's name as the ruler sets it")
            }
        }
        // From here on the unit's name is set: a faint line marks where.
        Capsule()
            .fill(Color.white.opacity(0.14))
            .frame(height: 1)
        font(.rulerUnit, style, showsSize: false)
        StudioDivider()
        section("Colour", caption: "The colour of the letters. Automatic is the ruler's.") {
            colourChoice(style.color, mixing: .text(.rulerUnit)) { color in update(.rulerUnit) { $0.color = color } }
        }
    }

    // MARK: A grid of days

    /// A grid of days (the calendar's): the numbers' type, size and colour, a background behind
    /// each day and one behind the whole grid.
    @ViewBuilder private func dayGrid(_ id: ElementID) -> some View {
        let look = widget.dayGridLook(of: id)
        let style = widget.textStyle(of: .monthDays)
        let element = widget.kind.spec.element(id)
        HStack(spacing: 10) {
            Image(systemName: element?.symbol ?? "calendar")
                .font(.system(size: 18))
                .foregroundStyle(SettingsPalette.secondary)
                .frame(width: 32, height: 32)
                .background(.white.opacity(0.06), in: .rect(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(element?.title ?? "Days").font(.headline)
                Text("Grid of days").font(.caption).foregroundStyle(SettingsPalette.secondary)
            }
            Spacer(minLength: 8)
            if look != .plain || style != .plain {
                Button("Reset") {
                    withAnimation(.spring(duration: 0.4, bounce: 0.18)) {
                        model.editedWidgets.update(widget.id) { widget in
                            widget.dayGridLooks[id] = nil
                            widget.textStyles[.monthDays] = nil
                        }
                    }
                }
                .help("The days as the widget draws them")
            }
        }
        StudioDivider()
        frame(id)
        StudioDivider()
        font(.monthDays, style, showsSize: false)
        let automatic = Double(WidgetParts.textSize(of: .monthDays, in: widget, inner: inner))
        let size = style.size ?? automatic
        HStack(spacing: 10) {
            Text("Size").font(.callout)
            Slider(value: Binding(get: { size }, set: { new in
                let points = new.rounded()
                if points != size { update(.monthDays) { $0.size = points } }
            }), in: TextStyle.sizes) { Text("Size") }
            .labelsHidden()
            .tint(Color.islandAccent)
            ReservedWidthText(style.size == nil ? "Auto" : "\(Int(size.rounded())) pt", fitting: ["48 pt", "Auto"])
                .foregroundStyle(SettingsPalette.secondary)
                .monospacedDigit()
        }
        .help("The numbers' size; Auto: as large as the cells allow")
        if style.size != nil {
            Button("Auto Size") { update(.monthDays) { $0.size = nil } }
                .buttonBorderShape(.capsule)
                .controlSize(.small)
        }
        StudioDivider()
        section("Colour", caption: "The days' numbers. Automatic is white; today stays white on its red disc.") {
            colourChoice(style.color, mixing: .text(.monthDays)) { color in update(.monthDays) { $0.color = color } }
        }
        StudioDivider()
        surface("Day Background", caption: "Behind each day of the month, today's under its disc.", look.day, mixing: .dayFill) { change in
            updateDayGrid(id) { change(&$0.day) }
        }
        StudioDivider()
        surface("Grid Background", caption: "Behind the whole grid, the weekdays included.", look.grid, mixing: .gridFill) { change in
            updateDayGrid(id) { change(&$0.grid) }
        }
    }

    /// What is behind a part, as a button's shape is set: its material, and with one its corners and
    /// its fill (with the colour mixer).
    @ViewBuilder private func surface(_ title: LocalizedStringKey, caption: LocalizedStringKey, _ look: SurfaceLook, mixing key: Mixing,
                                      update: @escaping ((inout SurfaceLook) -> Void) -> Void) -> some View {
        section(title, caption: caption) {
            Picker("Material", selection: Binding(get: { look.material }, set: { material in
                withAnimation(.spring(duration: 0.4, bounce: 0.18)) { update { $0.material = material } }
            })) {
                ForEach(ButtonLook.Material.allCases) { Text($0.title).tag($0) }
            }
            .choiceBar(width: Self.innerWidth)
            .labelsHidden()
            .fixedSize()
            if look.material.hasShape {
                Picker("Corners", selection: Binding(get: { look.corners }, set: { corners in
                    withAnimation(.spring(duration: 0.4, bounce: 0.18)) { update { $0.corners = corners } }
                })) {
                    ForEach(ButtonLook.Corners.allCases) { Text($0.title).tag($0) }
                }
                .choiceBar(width: Self.innerWidth)
                .labelsHidden()
                .fixedSize()
                .help("Its corners: Round makes a day a circle")
                Picker("Fill", selection: Binding(get: { look.fill }, set: { fill in
                    update { look in
                        look.fill = fill
                        if fill == .colour, look.fillColor == nil { look.fillColor = model.preferences.theme.rgb }
                    }
                    mixing = fill == .colour ? key : nil
                })) {
                    ForEach(ButtonLook.Fill.allCases) { Text($0.title).tag($0) }
                }
                .choiceBar(width: Self.innerWidth)
                .labelsHidden()
                .fixedSize()
                .help("Its fill. None: a faint grey edge only. Cover: the artwork's colour.")
                if look.fill == .colour {
                    mixer(look.fillColor ?? model.preferences.theme.rgb, isOpen: mixing == key,
                          toggle: { mixing = mixing == key ? nil : key }) { rgb in
                        update { $0.fillColor = rgb }
                    }
                }
            }
        }
    }

    private func updateDayGrid(_ id: ElementID, _ change: (inout DayGridLook) -> Void) {
        model.editedWidgets.update(widget.id) { widget in
            var look = widget.dayGridLook(of: id)
            change(&look)
            look.sanitize()
            widget.setDayGridLook(look, of: id)
        }
    }

    private func updateRuler(_ id: ElementID, _ change: (inout RulerLook) -> Void) {
        model.editedWidgets.update(widget.id) { widget in
            var look = widget.rulerLook(of: id)
            change(&look)
            look.sanitize()
            widget.setRulerLook(look, of: id)
        }
    }

    private func updateChart(_ id: ElementID, _ change: (inout ChartLook) -> Void) {
        model.editedWidgets.update(widget.id) { widget in
            var look = widget.chartLook(of: id)
            change(&look)
            look.sanitize()
            widget.setChartLook(look, of: id)
        }
    }

    // MARK: A button

    @ViewBuilder private func button(_ id: ElementID) -> some View {
        let look = widget.buttonLook(of: id)
        HStack(spacing: 10) {
            ButtonSymbolImage(symbol: buttonSymbol(id), points: 16)
                .foregroundStyle(SettingsPalette.secondary)
                .frame(width: 32, height: 32)
                .background(.white.opacity(0.06), in: .rect(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(WidgetParts.buttonTitle(of: id, in: widget)).font(.headline)
                Text("Button").font(.caption).foregroundStyle(SettingsPalette.secondary)
            }
            Spacer(minLength: 8)
            if look != .plain {
                Button("Reset") {
                    withAnimation(.spring(duration: 0.4, bounce: 0.18)) { updateLook(id) { $0 = .plain } }
                }
                .help("This button as the widget draws it")
            }
        }
        if id == .seekBackButton || id == .seekForwardButton {
            StudioDivider()
            // One setting for both: back and forward jump as far.
            section("Jump", caption: "How far back and forward jump, both alike.") {
                Picker("Jump", selection: Binding(get: { widget.effectiveSeekSeconds }, set: { seconds in
                    model.editedWidgets.update(widget.id) { $0.seekSeconds = seconds == 15 ? nil : seconds }
                })) {
                    ForEach(IslandWidget.seekChoices, id: \.self) { seconds in
                        Text("\(seconds) seconds").tag(seconds)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
            }
        }
        StudioDivider()
        frame(id)
        StudioDivider()
        section("Material", caption: "Regular is the symbol alone, as the widget draws it.") {
            Picker("Material", selection: Binding(get: { look.material }, set: { material in
                withAnimation(.spring(duration: 0.4, bounce: 0.18)) { updateLook(id) { $0.material = material } }
            })) {
                ForEach(ButtonLook.Material.allCases) { Text($0.title).tag($0) }
            }
            .choiceBar(width: Self.innerWidth)
            .labelsHidden()
            .fixedSize()
        }
        if look.material.hasShape {
            StudioDivider()
            section("Shape") {
                Picker("Shape", selection: Binding(get: { look.shape }, set: { shape in
                    withAnimation(.spring(duration: 0.4, bounce: 0.18)) { updateLook(id) { $0.shape = shape } }
                })) {
                    ForEach(ButtonLook.Shape.allCases) { Text($0.title).tag($0) }
                }
                .choiceBar(width: Self.innerWidth)
                .labelsHidden()
                .fixedSize()
            }
            StudioDivider()
            section("Corners", caption: "With sharp or rounded corners a circle is a square, a capsule a rectangle.") {
                Picker("Corners", selection: Binding(get: { look.corners }, set: { corners in
                    withAnimation(.spring(duration: 0.4, bounce: 0.18)) { updateLook(id) { $0.corners = corners } }
                })) {
                    ForEach(ButtonLook.Corners.allCases) { Text($0.title).tag($0) }
                }
                .choiceBar(width: Self.innerWidth)
                .labelsHidden()
                .fixedSize()
            }
            StudioDivider()
            section("Background") {
                Picker("Background", selection: Binding(get: { look.fill }, set: { fill in
                    updateLook(id) { look in
                        look.fill = fill
                        if fill == .colour, look.fillColor == nil { look.fillColor = model.preferences.theme.rgb }
                    }
                    mixing = fill == .colour ? .buttonFill : nil
                })) {
                    ForEach(ButtonLook.Fill.allCases) { Text($0.title).tag($0) }
                }
                .choiceBar(width: Self.innerWidth)
                .labelsHidden()
                .fixedSize()
                .help("None: a faint grey edge only. Cover: the artwork's colour.")
                if look.fill == .colour {
                    mixer(look.fillColor ?? model.preferences.theme.rgb, isOpen: mixing == .buttonFill,
                          toggle: { mixing = mixing == .buttonFill ? nil : .buttonFill }) { rgb in
                        updateLook(id) { $0.fillColor = rgb }
                    }
                }
                HStack(spacing: 10) {
                    Text("Size").font(.callout)
                    Slider(value: Binding(get: { look.size }, set: { new in
                        let snapped = (new * 20).rounded() / 20
                        if snapped != look.size { updateLook(id) { $0.size = snapped } }
                    }), in: ButtonLook.sizes) { Text("Size") }
                    .labelsHidden()
                    .tint(Color.islandAccent)
                    ReservedWidthText(look.size.formatted(.percent.precision(.fractionLength(0))),
                                      fitting: [Double(3).formatted(.percent.precision(.fractionLength(0)))])
                        .foregroundStyle(SettingsPalette.secondary)
                        .monospacedDigit()
                }
                .help("The button's shape larger or smaller; its symbol keeps its size")
            }
        }
        StudioDivider()
        section("Symbol") {
            Picker("Symbol colour", selection: Binding(get: { look.iconFill }, set: { fill in
                updateLook(id) { look in
                    look.iconFill = fill
                    if fill == .colour, look.iconColor == nil { look.iconColor = model.preferences.theme.rgb }
                }
                mixing = fill == .colour ? .icon : nil
            })) {
                ForEach(ButtonLook.IconFill.allCases) { Text($0.title).tag($0) }
            }
            .choiceBar(width: Self.innerWidth)
            .labelsHidden()
            .fixedSize()
            .help("None: its outline alone. Cover: the artwork's colour. Place and size it under the editor.")
            if look.iconFill == .colour {
                mixer(look.iconColor ?? model.preferences.theme.rgb, isOpen: mixing == .icon,
                      toggle: { mixing = mixing == .icon ? nil : .icon }) { rgb in
                    updateLook(id) { $0.iconColor = rgb }
                }
            }
        }
    }

    /// Where the part is drawn and how large, in the widget's points: the symbol's frame, or its
    /// shape's where it has one (as the editor's handles go round it). Its size can be copied, and
    /// another's pasted on it (it is drawn larger or smaller to match).
    @ViewBuilder private func frame(_ id: ElementID) -> some View {
        let drawn = editing.parts[id]
        section("Frame", caption: "As drawn in the widget, in px from its top-left corner.") {
            FramePair(title: "Size", first: ("W", drawn?.width, { setSize(id, width: $0) }),
                      second: ("H", drawn?.height, { setSize(id, height: $0) }))
            FramePair(title: "Position", first: ("X", drawn?.minX, { setPosition(id, x: $0) }),
                      second: ("Y", drawn?.minY, { setPosition(id, y: $0) }))
            HStack(spacing: Self.pairGap) {
                Button {
                    editing.copiedSize = drawn?.size
                } label: {
                    Label("Copy Size", systemImage: "doc.on.doc").frame(maxWidth: .infinity)
                }
                .disabled(drawn == nil)
                .help("Keep this part's width and height, to give another part")
                Button {
                    paste(id)
                } label: {
                    Label("Paste Size", systemImage: "doc.on.clipboard").frame(maxWidth: .infinity)
                }
                .disabled(editing.copiedSize == nil || drawn == nil || editing.copiedSize == drawn?.size)
                .help(editing.copiedSize.map { "Draw this part \(Self.points($0.width)) × \(Self.points($0.height)) px" }
                      ?? "Copy a part's size first")
            }
            .buttonBorderShape(.capsule)
        }
    }

    /// Between Copy Size and Paste Size: the line in the middle of the capsules above falls in it.
    static let pairGap: CGFloat = 8

    /// A length to a tenth, without a trailing ".0".
    static func points(_ value: CGFloat) -> String {
        Double(value).formatted(.number.precision(.fractionLength(0...1)))
    }

    /// The part drawn as large as the copied size.
    private func paste(_ id: ElementID) {
        guard let copied = editing.copiedSize else { return }
        withAnimation(.spring(duration: 0.4, bounce: 0.18)) { setSize(id, width: copied.width, height: copied.height) }
    }

    /// The part drawn this wide and tall (either left as it is where nil): its scale set from its
    /// size unscaled.
    private func setSize(_ id: ElementID, width: CGFloat? = nil, height: CGFloat? = nil) {
        guard let drawn = editing.parts[id] else { return }
        let scale = widget.scale(of: id)
        let base = CGSize(width: drawn.width / scale.x, height: drawn.height / scale.y)
        guard base.width > 0, base.height > 0 else { return }
        let range = ElementScale.range
        func clamped(_ value: CGFloat) -> Double { min(max(Double(value), range.lowerBound), range.upperBound) }
        var new = ElementScale(x: width.map { clamped(max($0, 1) / base.width) } ?? scale.x,
                               y: height.map { clamped(max($0, 1) / base.height) } ?? scale.y)
        // A picture kept in shape: the other side follows.
        if widget.imageLook(of: id).keepsShape {
            if width != nil { new.y = new.x } else if height != nil { new.x = new.y }
        }
        // Its top-left corner kept where it is: the scale grows it from its layout box's corner, so
        // the offset makes up the difference.
        var offset = widget.offset(of: id)
        if let box = editing.boxes[id] {
            let inkX = box.minX + (drawn.minX - offset.x - box.minX) / scale.x
            let inkY = box.minY + (drawn.minY - offset.y - box.minY) / scale.y
            offset.x = drawn.minX.rounded() - box.minX - (inkX - box.minX) * new.x
            offset.y = drawn.minY.rounded() - box.minY - (inkY - box.minY) * new.y
        }
        model.editedWidgets.update(widget.id) { stored in
            stored.adoptDrawn(id, from: widget)
            stored.scales[id] = new == .one ? nil : new
            stored.setOffset(offset, of: id)
        }
    }

    /// The part's top-left corner moved to `x`, `y` (either left as it is where nil).
    private func setPosition(_ id: ElementID, x: CGFloat? = nil, y: CGFloat? = nil) {
        guard let drawn = editing.parts[id] else { return }
        var offset = widget.offset(of: id)
        if let x { offset.x += x - drawn.minX }
        if let y { offset.y += y - drawn.minY }
        model.editedWidgets.update(widget.id) {
            $0.adoptDrawn(id, from: widget)
            $0.setOffset(offset, of: id)
        }
    }

    // MARK: Parts picked together

    /// Two or more parts picked with ⌘-click: one size for all of them (texts are sized by their
    /// box, in the editor, and left out), and Delete.
    @ViewBuilder private func groupSettings(_ group: Set<ElementID>) -> some View {
        let sized = group.filter { !widget.kind.spec.texts.contains($0) }
            .sorted { (widget.movableElements.firstIndex(of: $0) ?? 0) < (widget.movableElements.firstIndex(of: $1) ?? 0) }
        let frames = sized.compactMap { editing.parts[$0] }
        // A value all of them share, or none.
        let width = Set(frames.map { $0.width.rounded() }).count == 1 ? frames.first?.width : nil
        let height = Set(frames.map { $0.height.rounded() }).count == 1 ? frames.first?.height : nil
        HStack(spacing: 10) {
            Image(systemName: "square.on.square.dashed")
                .font(.system(size: 16))
                .foregroundStyle(SettingsPalette.secondary)
                .frame(width: 32, height: 32)
                .background(.white.opacity(0.06), in: .rect(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text("\(group.count) Parts").font(.headline)
                Text("Picked together").font(.caption).foregroundStyle(SettingsPalette.secondary)
            }
            Spacer(minLength: 8)
            Button("Delete", role: .destructive) {
                withAnimation(.spring(duration: 0.35, bounce: 0.12)) {
                    model.editedWidgets.update(widget.id) { $0.delete(group) }
                }
                editing.selected = nil
                editing.group = []
            }
            .help("Shapes go; the other parts are switched off (their switches bring them back)")
        }
        StudioDivider()
        section("Size", caption: sized.count < group.count ? "One size for all of them, texts aside: a text is sized by its box in the editor."
                    : "One size for all of them, each from its own top-left corner. ⌘-click a part to pick it or let it go.") {
            FramePair(title: "Size", first: ("W", width, { new in for id in sized { setSize(id, width: new) } }),
                      second: ("H", height, { new in for id in sized { setSize(id, height: new) } }))
                .disabled(sized.isEmpty)
        }
    }

    // MARK: A shape

    @ViewBuilder private func figureSettings(_ figure: WidgetFigure) -> some View {
        let id = figure.id
        HStack(spacing: 10) {
            Image(systemName: figure.kind.symbol)
                .font(.system(size: 16))
                .foregroundStyle(SettingsPalette.secondary)
                .frame(width: 32, height: 32)
                .background(.white.opacity(0.06), in: .rect(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(figure.kind.title).font(.headline)
                Text("Shape").font(.caption).foregroundStyle(SettingsPalette.secondary)
            }
            Spacer(minLength: 8)
            Button("Delete", role: .destructive) {
                withAnimation(.spring(duration: 0.35, bounce: 0.12)) {
                    model.editedWidgets.update(widget.id) { $0.removeFigure(id) }
                }
                editing.selected = nil
            }
            .help("Take this shape off the widget (or press Delete in the editor)")
        }
        StudioDivider()
        if figure.kind.hasCorners {
            StudioDivider()
            section(figure.kind == .line ? "Ends" : "Corners") {
                Picker("Corners", selection: Binding(get: { figure.effectiveCorners }, set: { corners in
                    withAnimation(.spring(duration: 0.35, bounce: 0.12)) {
                        updateFigure(id) { $0.corners = corners == $0.kind.corners ? nil : corners }
                    }
                })) {
                    ForEach(WidgetFigure.Corners.allCases) { Text($0.title).tag($0) }
                }
                .choiceBar(width: Self.innerWidth)
                .labelsHidden()
                .fixedSize()
                if figure.kind.canFill {
                    switchRow("Filled", isOn: figure.isFilled,
                              help: "On: the square drawn solid. Off: its outline alone") { on in
                        updateFigure(id) { $0.isFilled = on }
                    }
                }
            }
        }
        StudioDivider()
        section("Colour", caption: "The colour it is drawn in.") {
            colourChoice(figure.color, mixing: .text(id)) { color in
                updateFigure(id) { $0.color = color }
            }
        }
        StudioDivider()
        frame(id)
    }

    private func updateFigure(_ id: ElementID, _ change: (inout WidgetFigure) -> Void) {
        model.editedWidgets.update(widget.id) { widget in
            guard let index = widget.figures.firstIndex(where: { $0.id == id }) else { return }
            change(&widget.figures[index])
        }
    }

    // MARK: A picture

    @ViewBuilder private func image(_ id: ElementID) -> some View {
        let look = widget.imageLook(of: id)
        let element = widget.kind.spec.element(id)
        HStack(spacing: 10) {
            Image(systemName: element?.symbol ?? "photo")
                .font(.system(size: 16))
                .foregroundStyle(SettingsPalette.secondary)
                .frame(width: 32, height: 32)
                .background(.white.opacity(0.06), in: .rect(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(element?.title ?? "Picture").font(.headline)
                Text("Picture").font(.caption).foregroundStyle(SettingsPalette.secondary)
            }
            Spacer(minLength: 8)
            if look != .plain {
                Button("Reset") {
                    withAnimation(.spring(duration: 0.4, bounce: 0.18)) {
                        model.editedWidgets.update(widget.id) { $0.setImageLook(.plain, of: id) }
                    }
                }
                .help("Stretched as it is resized, at the size it was given")
            }
        }
        StudioDivider()
        section("Fit", caption: "To Edges grows it to the widget's edges, Fill over all of it, never stretched.") {
            Picker("Fit", selection: Binding(get: { look.fit }, set: { fit in
                withAnimation(.spring(duration: 0.4, bounce: 0.18)) { setFit(id, fit) }
            })) {
                ForEach(ImageLook.Fit.allCases) { Text($0.title).tag($0) }
            }
            .choiceBar(width: Self.innerWidth)
            .labelsHidden()
            .fixedSize()
        }
        StudioDivider()
        section("Opacity") {
            HStack(spacing: 10) {
                Text("Opacity").font(.callout)
                Slider(value: Binding(get: { look.opacity }, set: { new in
                    let snapped = (new * 100).rounded() / 100
                    if snapped != look.opacity { updateImage(id) { $0.opacity = snapped } }
                }), in: 0...1) { Text("Opacity") }
                .labelsHidden()
                .tint(Color.islandAccent)
                ReservedWidthText(look.opacity.formatted(.percent.precision(.fractionLength(0))),
                                  fitting: [Double(1).formatted(.percent.precision(.fractionLength(0)))])
                    .foregroundStyle(SettingsPalette.secondary)
                    .monospacedDigit()
            }
            .help("How strongly the picture is drawn: less lets the widget's background show through")
        }
        StudioDivider()
        section("Resize") {
            switchRow("Keep shape", isOn: look.keepsShape,
                      help: "On: resized, it only grows or shrinks, never stretched out of shape. Off: it stretches as it is resized") { on in
                setKeepsShape(id, on)
            }
        }
        StudioDivider()
        frame(id)
    }

    /// Grown to the edges or over the widget, or back at its own size: as it was before it grew.
    private func setFit(_ id: ElementID, _ fit: ImageLook.Fit) {
        updateImage(id) { $0.fit = fit }
    }

    private func updateImage(_ id: ElementID, _ change: (inout ImageLook) -> Void) {
        model.editedWidgets.update(widget.id) { widget in
            var look = widget.imageLook(of: id)
            change(&look)
            look.sanitize()
            widget.setImageLook(look, of: id)
        }
    }

    /// Kept in shape from now on: one stretched gets its proportions back (as wide as it is, as
    /// tall as that makes it; a picture grown to the edges or over the widget has them already).
    private func setKeepsShape(_ id: ElementID, _ on: Bool) {
        let scale = widget.scale(of: id)
        if on, widget.imageLook(of: id).fit == .own, scale.x != scale.y, let drawn = editing.parts[id] {
            setSize(id, height: drawn.height / scale.y * scale.x)
        }
        updateImage(id) { $0.keepsShape = on }
    }

    // MARK: A playback line

    @ViewBuilder private func progress(_ id: ElementID) -> some View {
        let look = widget.progressLook(of: id)
        let inner = ProgressLook.Part.allCases.compactMap { $0.textID(in: id) }
        HStack(spacing: 10) {
            Image(systemName: "slider.horizontal.below.rectangle")
                .font(.system(size: 16))
                .foregroundStyle(SettingsPalette.secondary)
                .frame(width: 32, height: 32)
                .background(.white.opacity(0.06), in: .rect(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(widget.kind.spec.element(id)?.title ?? "Progress").font(.headline)
                Text(id == .progress ? "Playback line" : "Line").font(.caption).foregroundStyle(SettingsPalette.secondary)
            }
            Spacer(minLength: 8)
            if look != .plain || inner.contains(where: { widget.textStyles[$0] != nil }) {
                Button("Reset") {
                    withAnimation(.spring(duration: 0.4, bounce: 0.18)) {
                        model.editedWidgets.update(widget.id) { widget in
                            widget.progressLooks[id] = nil
                            for text in inner { widget.textStyles[text] = nil }
                        }
                    }
                }
                .help("This line as the widget draws it")
            }
        }
        StudioDivider()
        frame(id)
        StudioDivider()
        section("Bar", caption: "The whole line, under the part played.") {
            colourChoice(look.trackColor, mixing: .track) { color in updateLine(id) { $0.trackColor = color } }
        }
        StudioDivider()
        section("Progress", caption: "The part played.") {
            colourChoice(look.fillColor, mixing: .played) { color in updateLine(id) { $0.fillColor = color } }
        }
        StudioDivider()
        section("Ends") {
            Picker("Ends", selection: Binding(get: { look.ends }, set: { ends in
                withAnimation(.spring(duration: 0.35, bounce: 0.12)) { updateLine(id) { $0.ends = ends } }
            })) {
                ForEach(ProgressLook.Ends.allCases) { Text($0.title).tag($0) }
            }
            .choiceBar(width: Self.innerWidth)
            .labelsHidden()
            .fixedSize()
        }
        StudioDivider()
        section("Knob") {
            Picker("Knob", selection: Binding(get: { look.knob }, set: { knob in
                withAnimation(.spring(duration: 0.35, bounce: 0.12)) { updateLine(id) { $0.knob = knob } }
            })) {
                ForEach(ProgressLook.Knob.allCases) { knob in
                    Label(knob.title, systemImage: knob.symbol).labelStyle(.iconOnly).tag(knob)
                }
            }
            .choiceBar(width: Self.innerWidth)
            .labelsHidden()
            .fixedSize()
            .help("What marks the position: the end of the part played alone, a circle, a capsule or a square")
        }
        // The time picked in the panel under the editor: its type and colour.
        if let part = editing.progressPart, let text = part.textID(in: id) {
            let style = widget.textStyle(of: text)
            StudioDivider()
            HStack {
                Text(part.title(in: id)).font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                if style != .plain {
                    Button("Reset") {
                        withAnimation(.spring(duration: 0.35, bounce: 0.12)) { update(text) { $0 = .plain } }
                    }
                    .controlSize(.small)
                    .help("This time as the line sets it")
                }
            }
            // From here on the time's text is set: a faint line marks where.
            Capsule()
                .fill(Color.white.opacity(0.14))
                .frame(height: 1)
            // Sized in the panel under the editor.
            font(text, style, showsSize: false)
            colour(text, style)
        }
    }

    private func updateLine(_ id: ElementID, _ change: (inout ProgressLook) -> Void) {
        model.editedWidgets.update(widget.id) { widget in
            var look = widget.progressLook(of: id)
            change(&look)
            widget.setProgressLook(look, of: id)
        }
    }

    /// The button's symbol in the inspector's header (the one it shows now, but play and pause as one).
    private func buttonSymbol(_ id: ElementID) -> String {
        switch id {
        case .playbackButtons, .stopwatchButton: "playpause.fill"
        case .seekBackButton: "gobackward"
        case .seekForwardButton: "goforward"
        default: WidgetParts.buttonSymbol(of: id, in: widget, model: model)
        }
    }

    private func updateLook(_ id: ElementID, _ change: (inout ButtonLook) -> Void) {
        model.editedWidgets.update(widget.id) { widget in
            var look = widget.buttonLook(of: id)
            change(&look)
            look.sanitize()
            widget.setButtonLook(look, of: id)
        }
    }

    /// Automatic, Custom (with its mixer) or Artwork: every colour picked the same way.
    @ViewBuilder private func colourChoice(_ color: TextStyle.TextColor, mixing key: Mixing,
                                           set: @escaping (TextStyle.TextColor) -> Void) -> some View {
        let choice: ColourChoice = switch color {
        case .automatic: .automatic
        case .custom: .custom
        case .artwork: .artwork
        }
        Picker("Colour", selection: Binding(get: { choice }, set: { choice in
            switch choice {
            case .automatic: set(.automatic)
            case .artwork: set(.artwork)
            case .custom:
                if case .custom = color { break }
                set(.custom(model.preferences.theme.rgb))
            }
            mixing = choice == .custom ? key : nil
        })) {
            Text("Automatic").tag(ColourChoice.automatic)
            Text("Custom").tag(ColourChoice.custom)
            Text("Artwork").tag(ColourChoice.artwork)
        }
        .choiceBar(width: Self.innerWidth)
        .labelsHidden()
        .fixedSize()
        if case .custom(let rgb) = color {
            mixer(rgb, isOpen: mixing == key, toggle: { mixing = mixing == key ? nil : key }) { rgb in set(.custom(rgb)) }
        }
    }

    // MARK: Pieces

    private func section(_ title: LocalizedStringKey, caption: LocalizedStringKey? = nil,
                         @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                if let caption {
                    Text(caption).font(.caption).foregroundStyle(SettingsPalette.secondary)
                }
            }
            content()
        }
    }

    /// A colour's swatch and hex, the button that opens its mixer, and the mixer.
    @ViewBuilder private func mixer(_ rgb: IslandTheme.RGB, isOpen: Bool, toggle: @escaping () -> Void,
                                    set: @escaping (IslandTheme.RGB) -> Void) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(rgb.color)
                .overlay { Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1) }
                .frame(width: 24, height: 24)
            Text(rgb.hex).font(.callout).monospaced()
            Spacer(minLength: 8)
            Button(action: toggle) {
                Label(isOpen ? "Done" : "Mix", systemImage: isOpen ? "checkmark" : "paintpalette.fill")
            }
            .controlSize(.small)
        }
        if isOpen {
            ColorMixer(rgb: Binding(get: { rgb }, set: set), compact: true)
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(Color.white.opacity(0.04), in: .rect(cornerRadius: 16, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1) }
                .transition(.scale(scale: 0.9, anchor: .top).combined(with: .opacity))
        }
    }

    /// The widget's inside, as the board draws it.
    private var inner: CGSize {
        let geometry = WidgetBoardGeometry(size: WidgetsSettingsPage.boardSize(model.layout), grid: model.editedWidgets.board.grid)
        let natural = geometry.frame(for: widget.frame).size
        let padding = WidgetMetrics.padding(for: widget)
        return CGSize(width: max(0, natural.width - 2 * padding), height: max(0, natural.height - 2 * padding))
    }

    private func update(_ id: ElementID, _ change: (inout TextStyle) -> Void) {
        model.editedWidgets.update(widget.id) { widget in
            var style = widget.textStyle(of: id)
            change(&style)
            style.sanitize()
            widget.setTextStyle(style, of: id)
        }
    }
}
