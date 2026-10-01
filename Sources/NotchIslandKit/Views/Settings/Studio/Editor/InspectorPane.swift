import AppKit
import SwiftUI

/// The Customize editor's inspector: every look the picked element (or, with nothing picked, the
/// widget itself) can take, in flat sections. Each control writes through the session, so every
/// change is one undo step and redraws the canvas at once.
struct InspectorPane: View {
    let session: EditorSession
    /// The editor is at its narrowest.
    var isNarrow = false

    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let widget = session.widget {
                        header(widget)
                        if let id = session.selectedElement, let element = session.elementSpec(id) {
                            // Its place on the grid inside the widget first, then its look.
                            FrameInspector(session: session, id: id)
                            if element.id == id || id.isCustom {
                                ElementInspector(session: session, widget: widget, element: element)
                            }
                        } else if session.selection.count > 1 {
                            ArrangeInspector(session: session)
                        } else {
                            LayoutGridInspector(session: session)
                            WidgetLookInspector(session: session, widget: widget)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                // Never wider than the pane: a row too wide wraps or shrinks inside it.
                .frame(width: isNarrow ? InspectorLayout.narrowWidth : InspectorLayout.width, alignment: .leading)
            }
            .scrollIndicators(.automatic)
            footer
        }
        .frame(width: isNarrow ? InspectorLayout.narrowWidth : InspectorLayout.width)
    }

    private func header(_ widget: IslandWidget) -> some View {
        let element = session.selectedElement.flatMap { session.elementSpec($0) }
        return HStack(spacing: 10) {
            if let element {
                Image(systemName: element.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .background(.white.opacity(0.08), in: .rect(cornerRadius: 8, style: .continuous))
            } else {
                WidgetIcon(kind: widget.kind, side: 28)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(element?.title ?? widget.kind.title).font(.headline)
                Text(element.map { "\($0.role.title) · \(widget.kind.title)" } ?? "\(widget.kind.category.title) · \(widget.frame.width) × \(widget.frame.height)")
                    .font(.caption)
                    .foregroundStyle(SettingsPalette.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let id = session.selectedElement {
                // At once: animated, the inspector's rows for the old look and the new one were drawn
                // over each other while they faded (and the outline lagged a frame behind).
                Button("Reset Element") { session.resetElement(id) }
                    .disabled(session.style.elements[id] == nil && session.widget?.sizes[id] == nil)
            }
            Spacer(minLength: 0)
            Button("Reset Widget", role: .destructive) { session.resetWidget() }
        }
        .controlSize(.small)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(alignment: .top) { Divider().opacity(0.6) }
    }
}

// MARK: - One element

private struct ElementInspector: View {
    let session: EditorSession
    let widget: IslandWidget
    let element: ElementSpec

    var body: some View {
        let id = element.id
        VStack(alignment: .leading, spacing: 12) {
            // An added divider or shape: a box filled with a colour, whatever its role.
            let isBox = widget.style.layout.arrangement?.decoration(id).map(\.isBox) ?? false
            switch element.role {
            case .text:
                TextInspector(session: session, widget: widget, element: element)
            case .symbol:
                SymbolInspector(session: session, widget: widget, element: element)
            case .image where isBox, .line where isBox:
                InspectorSection(element.role == .image ? "Shape" : "Divider") {
                    ColorRows(session: session, id: id, slots: element.role == .image ? [.fill, .border] : [.fill])
                }
            case .image:
                EmptyView()
            case .line, .chart:
                InspectorSection("Colours") {
                    ColorRows(session: session, id: id, slots: element.colorSlots.filter { $0 != .fillEnd })
                }
            case .button:
                InspectorSection("Button") {
                    ColorRows(session: session, id: id, slots: [.tint])
                }
            case .feature:
                if element.isBlock {
                    Text("Drawn as one piece: its place and size are set on the canvas.")
                        .font(.caption)
                        .foregroundStyle(SettingsPalette.secondary)
                }
            }
            // Laid out by the kind, S, M and L; laid out freely, its rectangle is its size.
            if element.isSizable, element.role != .text, element.role != .symbol, !session.layoutState.isCustom {
                SizeChips(session: session, widget: widget, id: id)
            }
        }
    }
}

/// Small, Medium, Large: the element's size where the room lets it be (`IslandWidget.sizes`).
private struct SizeChips: View {
    let session: EditorSession
    let widget: IslandWidget
    let id: ElementID

    var body: some View {
        InspectorRow("Size", isSet: widget.sizes[id] != nil, reset: { session.change(\IslandWidget.sizes) { $0.sizes[id] = nil } }) {
            Picker("", selection: Binding(get: { widget.size(of: id) }, set: { size in
                withAnimation(Motion.content) { session.change(\IslandWidget.sizes) { $0.sizes[id] = size } }
            })) {
                ForEach(ElementSize.allCases) { Text($0.title).tag($0).help($0.accessibilityTitle) }
            }
            .labelsHidden()
            .choiceBar()
            .controlSize(.small)
            .fixedSize()
        }
    }
}

// MARK: Text

private struct TextInspector: View {
    let session: EditorSession
    let widget: IslandWidget
    let element: ElementSpec

    private func text<Value: Equatable>(_ keyPath: WritableKeyPath<TextStyle, Value>) -> Binding<Value> {
        let base: WritableKeyPath<WidgetStyle, TextStyle> = \.[element: element.id].text
        return session.binding(for: base.appending(path: keyPath))
    }

    private var style: TextStyle { session.style.elements[element.id]?.text ?? TextStyle() }

    /// The battery's percentage drawn inside it, cut out of it: its type is all that applies (its
    /// size is the battery's, its colour the hole's).
    private var isCutOut: Bool { widget.kind == .battery && element.id == .percentage && widget.shows(.batteryGlyph) }

    /// Laid out freely: its size and lines are its rectangle's (`ElementFrame.points`, `lines`).
    private var isFree: Bool { session.layoutItem(element.id) != nil }

    var body: some View {
        let id = element.id
        if isCutOut {
            fontSection
            Text("Drawn inside the battery: its size follows the battery, and its colour is the battery's own.")
                .font(.caption)
                .foregroundStyle(SettingsPalette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            if !isFree {
                InspectorSection("Size") {
                    TextSizeControl(session: session, widget: widget, id: id)
                }
            }
            textSection(id)
            fontSection
        }
    }

    /// A change of the font: laid out freely, its rectangle made its lines' height in the new one.
    private func refitting<Value: Equatable>(_ binding: Binding<Value>) -> Binding<Value> {
        Binding(get: { binding.wrappedValue }, set: { value in
            let before = session.textType(element.id)
            binding.wrappedValue = value
            if isFree, let before {
                session.refitText(element.id, type: before.applying(session.style.elements[element.id]?.text ?? TextStyle()))
            }
        })
    }

    private var fontSection: some View {
        InspectorSection("Font") {
            InspectorRow("Style", isSet: style.design != nil, reset: { refitting(text(\.design)).wrappedValue = nil }) {
                OptionalChoice(value: refitting(text(\.design)), options: FontDesignChoice.allCases, title: \.title)
            }
            InspectorRow("Weight", isSet: style.weight != nil, reset: { refitting(text(\.weight)).wrappedValue = nil }) {
                OptionalChoice(value: refitting(text(\.weight)), options: FontWeightChoice.allCases, title: \.title)
            }
            InspectorRow("Italic", isSet: style.italic != nil, reset: { refitting(text(\.italic)).wrappedValue = nil }) {
                OptionalSwitch(value: refitting(text(\.italic)))
            }
            if isFree, let points = session.textType(element.id)?.points {
                InspectorRow("Size", isSet: false, reset: {}) {
                    let shown = (Double(points) * 4).rounded() / 4
                    let size = Binding(get: { shown }, set: { value in
                        if abs(value - shown) >= 0.25 { withAnimation(Motion.content) { session.setTextPoints(CGFloat(value), of: element.id) } }
                    })
                    HStack(spacing: 6) {
                        TextField("", value: size, format: .number.precision(.fractionLength(0...2)))
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 56)
                        Stepper("", value: size, step: 1)
                            .labelsHidden()
                        Text("pt").foregroundStyle(SettingsPalette.secondary)
                    }
                    .controlSize(.small)
                }
            }
            if !isCutOut {
                InspectorRow("Colour", isSet: session.style.elements[element.id]?.colors[.primary] != nil,
                             reset: { session.set(\WidgetStyle.[element: element.id].colors[.primary], to: nil) }) {
                    OptionalColor(value: session.binding(for: \WidgetStyle.[element: element.id].colors[.primary]))
                }
            }
        }
    }

    private func textSection(_ id: ElementID) -> some View {
        InspectorSection("Text") {
            if element.acceptsLabel {
                InspectorRow("Wording", isSet: style.labelOverride != nil, reset: { text(\.labelOverride).wrappedValue = nil }) {
                    OptionalTextField(value: text(\.labelOverride), prompt: element.samples.first ?? element.title)
                }
            }
            InspectorRow("Most Lines", isSet: isFree ? session.layoutItem(id)?.lines != nil : style.lineLimit != nil, reset: {
                if isFree { withAnimation(Motion.content) { session.setTextLines(1, of: id) } } else { text(\.lineLimit).wrappedValue = nil }
            }) {
                let lines = isFree ? session.textLines(id) : style.lineLimit ?? 1
                Stepper(value: Binding(get: { lines }, set: { value in
                    if isFree { withAnimation(Motion.content) { session.setTextLines(value, of: id) } } else { text(\.lineLimit).wrappedValue = value }
                }), in: ElementFrame.lineRange) {
                    Text("\(lines)").monospacedDigit()
                }
                .controlSize(.small)
                .help("The most lines it wraps to: its frame is that many lines tall, the text centred in it")
            }
            InspectorRow("Too Long", isSet: style.truncation != nil, reset: { text(\.truncation).wrappedValue = nil }) {
                Picker("", selection: Binding<Bool>(get: { style.truncation == .shrink }, set: { shrinks in
                    text(\.truncation).wrappedValue = shrinks ? .shrink : .tail
                })) {
                    Text("Cut").tag(false)
                    Text("Shrink").tag(true)
                }
                .labelsHidden()
                .choiceBar()
                .controlSize(.small)
                .fixedSize()
                .help("Cut: ends in “…”. Shrink: smaller letters, the frame's height kept.")
            }
            if isFree {
                InspectorRow("Adds Lines", isSet: session.layoutItem(id)?.growsLines != nil,
                             reset: { session.editLayout { LayoutEdit.setGrowsLines(true, [id], in: &$0) } }) {
                    Toggle("", isOn: Binding(get: { session.growsLines(id) }, set: { on in
                        session.editLayout { LayoutEdit.setGrowsLines(on, [id], in: &$0) }
                    }))
                    .labelsHidden()
                    .toggleStyle(.islandSwitch)
                    .help("On: made taller by a handle, it takes more lines. Off: its letters grow instead.")
                }
            }
            InspectorRow("Alignment", isSet: style.alignment != nil, reset: { text(\.alignment).wrappedValue = nil }) {
                Picker("", selection: text(\.alignment)) {
                    Text("Auto").tag(TextAlignmentChoice?.none)
                    ForEach(TextAlignmentChoice.allCases, id: \.self) { choice in
                        Image(systemName: choice.systemImage).tag(Optional(choice)).help(choice.title)
                    }
                }
                .labelsHidden()
                .choiceBar()
                .controlSize(.small)
                .fixedSize()
            }
        }
    }
}

/// The type size: S, M and L (fitted to the room), or a size of its own in points, as large as the
/// room lets it be: the range is what the widget's layout gives it now, every step visibly larger.
struct TextSizeControl: View {
    let session: EditorSession
    let widget: IslandWidget
    let id: ElementID
    var isSymbol = false

    private var fixed: Double? {
        let element = session.style.elements[id]
        return isSymbol ? element?.symbol.points : element?.text.points
    }

    private var binding: Binding<Double?> {
        isSymbol ? session.binding(for: \WidgetStyle.[element: id].symbol.points)
                 : session.binding(for: \WidgetStyle.[element: id].text.points)
    }

    /// What the canvas drew it at, and the most the room gives it.
    private var measured: (points: CGFloat, fit: CGFloat?)? {
        switch session.drawn[id] {
        case .text(let type, _, let fit)?: (type.points, fit)
        case .symbol(_, let points, let fit)?: (points, fit)
        default: nil
        }
    }

    var body: some View {
        let range = sizeRange
        // Laid out freely, the size comes from its rectangle (S, M and L are the stacks' sizes).
        let isFree = session.layoutState.isCustom
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: Binding<String>(get: {
                fixed != nil ? "custom" : isFree ? "frame" : widget.size(of: id).rawValue
            }, set: { choice in
                withAnimation(Motion.content) {
                    if choice == "custom" {
                        binding.wrappedValue = Double(measured?.points ?? 13)
                    } else if let size = choice == "frame" ? ElementSize.medium : ElementSize(rawValue: choice) {
                        session.change(\IslandWidget.self) { widget in
                            widget.sizes[id] = size == .medium ? nil : size
                            if isSymbol { widget.style.elements[id]?.symbol.points = nil } else { widget.style.elements[id]?.text.points = nil }
                        }
                    }
                }
            })) {
                if isFree {
                    Text("Fit Frame").tag("frame").help("As large as its rectangle on the canvas lets it be")
                } else {
                    ForEach(ElementSize.allCases) { Text($0.title).tag($0.rawValue).help("\($0.accessibilityTitle), fitted to the room") }
                }
                Text("pt").tag("custom").help("A size of its own")
            }
            .labelsHidden()
            .choiceBar()
            .fixedSize()
            if let fixed {
                HStack(spacing: 8) {
                    Stepper(value: Binding(get: { fixed }, set: { binding.wrappedValue = min(max($0, range.lowerBound), range.upperBound) }),
                            in: range, step: 0.5) {
                        TextField("", value: Binding(get: { fixed }, set: { binding.wrappedValue = min(max($0, range.lowerBound), range.upperBound) }),
                                  format: .number.precision(.fractionLength(0...1)))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 52)
                            .multilineTextAlignment(.trailing)
                    }
                    Text("pt").foregroundStyle(SettingsPalette.secondary)
                    Spacer(minLength: 0)
                }
                .controlSize(.small)
                if let measured, measured.points + 0.01 < CGFloat(fixed) {
                    Label("Drawn at \(String(format: "%g", Double(measured.points))) pt — limited by room",
                          systemImage: "arrow.down.right.and.arrow.up.left")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if fixed >= range.upperBound - 0.01 {
                    HStack(spacing: 8) {
                        Text("Enlarge the widget for bigger text.")
                            .font(.caption)
                            .foregroundStyle(SettingsPalette.secondary)
                        Button("Make Room") { withAnimation(Motion.content) { _ = session.makeRoom() } }
                            .controlSize(.small)
                    }
                }
            }
        }
    }

    /// From the smallest size to the most the room gives it now.
    private var sizeRange: ClosedRange<Double> {
        let lower = Double(TextFit.minimumPoints)
        guard let fit = measured?.fit, fit.isFinite else { return lower...Double(TextFit.maximumPoints) }
        return lower...max(Double(min(fit, TextFit.maximumPoints)).rounded(.down), lower + 1)
    }
}

// MARK: Symbol

private struct SymbolInspector: View {
    let session: EditorSession
    let widget: IslandWidget
    let element: ElementSpec

    private func symbol<Value: Equatable>(_ keyPath: WritableKeyPath<SymbolStyle, Value>) -> Binding<Value> {
        let base: WritableKeyPath<WidgetStyle, SymbolStyle> = \.[element: element.id].symbol
        return session.binding(for: base.appending(path: keyPath))
    }

    private var style: SymbolStyle { session.style.elements[element.id]?.symbol ?? SymbolStyle() }

    var body: some View {
        let id = element.id
        // Laid out freely, it is as large as its rectangle holds.
        if session.layoutItem(id) == nil {
            InspectorSection("Size") {
                TextSizeControl(session: session, widget: widget, id: id, isSymbol: true)
            }
        }
        // The battery is drawn, not a symbol: its colours are all that apply.
        let isDrawn = widget.kind == .battery && id == .batteryGlyph
        InspectorSection("Symbol") {
            if !isDrawn {
                InspectorRow("Weight", isSet: style.weight != nil, reset: { symbol(\.weight).wrappedValue = nil }) {
                    OptionalChoice(value: symbol(\.weight), options: FontWeightChoice.allCases, title: \.title)
                }
            }
            ColorRows(session: session, id: id, slots: element.colorSlots.filter { slot in
                slot != .backing && (slot != .secondary || isDrawn || style.rendering == .palette)
            })
        }
    }
}

// MARK: Image

private struct ImageInspector: View {
    let session: EditorSession
    let element: ElementSpec

    private func image<Value: Equatable>(_ keyPath: WritableKeyPath<ImageStyle, Value>) -> Binding<Value> {
        let base: WritableKeyPath<WidgetStyle, ImageStyle> = \.[element: element.id].image
        return session.binding(for: base.appending(path: keyPath))
    }

    private var style: ImageStyle { session.style.elements[element.id]?.image ?? ImageStyle() }

    var body: some View {
        let kind = session.widget?.kind
        if kind == .shelf {
            // The files' own thumbnails, drawn as the shelf draws them.
            Text("Drawn as the shelf's file thumbnails: their place and size are set on the canvas.")
                .font(.caption)
                .foregroundStyle(SettingsPalette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            pictureSection(fills: kind != .nowPlaying)
        }
    }

    /// `fills`: Fill or Fit is offered (a cover always fills its square).
    private func pictureSection(fills: Bool) -> some View {
        InspectorSection("Picture") {
            InspectorRow("Corners", isSet: style.corners != nil, reset: { image(\.corners).wrappedValue = nil }) {
                Picker("", selection: Binding<String>(get: {
                    switch style.corners {
                    case nil: "auto"
                    case .concentric?: "concentric"
                    case .custom?: "custom"
                    case .circle?: "circle"
                    }
                }, set: { choice in
                    let corners: ImageCorners? = switch choice {
                    case "concentric": .concentric
                    case "custom": .custom(8)
                    case "circle": .circle
                    default: nil
                    }
                    image(\.corners).wrappedValue = corners
                })) {
                    Text("Automatic").tag("auto")
                    Text("Concentric").tag("concentric")
                    Text("Radius").tag("custom")
                    Text("Circle").tag("circle")
                }
                .labelsHidden()
                .fixedSize()
            }
            if case .custom(let radius)? = style.corners {
                InspectorRow("Radius", isSet: true, reset: { image(\.corners).wrappedValue = nil }) {
                    OptionalSlider(value: Binding(get: { radius }, set: { image(\.corners).wrappedValue = $0.map(ImageCorners.custom) }),
                                   range: ImageCorners.radiusRange, step: 1, standard: radius, session: session)
                }
            }
            InspectorRow("Border", isSet: style.borderWidth != nil, reset: { image(\.borderWidth).wrappedValue = nil }) {
                OptionalSlider(value: image(\.borderWidth), range: ImageStyle.borderRange, step: 0.5, standard: 0,
                               format: { $0.formatted(.number.precision(.fractionLength(0...1))) + " pt" }, session: session)
            }
            if (style.borderWidth ?? 0) > 0 {
                ColorRows(session: session, id: element.id, slots: [.border])
            }
            InspectorRow("Opacity", isSet: style.opacity != nil, reset: { image(\.opacity).wrappedValue = nil }) {
                OptionalSlider(value: image(\.opacity), range: 0.1...1, step: 0.05, standard: 1,
                               format: { $0.formatted(.percent.precision(.fractionLength(0))) }, session: session)
            }
            // Laid out freely, it is moved on the canvas instead.
            if !session.layoutState.isCustom {
                InspectorRow("Nudge X", isSet: style.offsetX != nil, reset: { image(\.offsetX).wrappedValue = nil }) {
                    OptionalSlider(value: image(\.offsetX), range: ImageStyle.offsetRange, step: 1, standard: 0,
                                   format: { "\(Int($0)) pt" }, session: session)
                }
                InspectorRow("Nudge Y", isSet: style.offsetY != nil, reset: { image(\.offsetY).wrappedValue = nil }) {
                    OptionalSlider(value: image(\.offsetY), range: ImageStyle.offsetRange, step: 1, standard: 0,
                                   format: { "\(Int($0)) pt" }, session: session)
                }
            }
            if fills {
                InspectorRow("Fill", isSet: style.contentMode != nil, reset: { image(\.contentMode).wrappedValue = nil }) {
                    OptionalChoice(value: image(\.contentMode), options: ImageContentMode.allCases, title: \.title)
                }
            }
        }
    }
}

// MARK: Divider and shape

/// An added divider or shape (`DecorationView`): its fill, a shape's border, how strongly it is drawn.
private struct BoxInspector: View {
    let session: EditorSession
    let element: ElementSpec

    private func image<Value: Equatable>(_ keyPath: WritableKeyPath<ImageStyle, Value>) -> Binding<Value> {
        let base: WritableKeyPath<WidgetStyle, ImageStyle> = \.[element: element.id].image
        return session.binding(for: base.appending(path: keyPath))
    }

    private var style: ImageStyle { session.style.elements[element.id]?.image ?? ImageStyle() }

    var body: some View {
        let isShape = element.role == .image
        InspectorSection(isShape ? "Shape" : "Divider") {
            ColorRows(session: session, id: element.id, slots: [.fill])
            if isShape {
                InspectorRow("Border", isSet: style.borderWidth != nil, reset: { image(\.borderWidth).wrappedValue = nil }) {
                    OptionalSlider(value: image(\.borderWidth), range: ImageStyle.borderRange, step: 0.5, standard: 0,
                                   format: { $0.formatted(.number.precision(.fractionLength(0...1))) + " pt" }, session: session)
                }
                if (style.borderWidth ?? 0) > 0 {
                    ColorRows(session: session, id: element.id, slots: [.border])
                }
            }
            InspectorRow("Opacity", isSet: style.opacity != nil, reset: { image(\.opacity).wrappedValue = nil }) {
                OptionalSlider(value: image(\.opacity), range: 0.1...1, step: 0.05, standard: 1,
                               format: { $0.formatted(.percent.precision(.fractionLength(0))) }, session: session)
            }
        }
    }
}

// MARK: Line

private struct LineInspector: View {
    let session: EditorSession
    let element: ElementSpec

    private func line<Value: Equatable>(_ keyPath: WritableKeyPath<LineStyle, Value>) -> Binding<Value> {
        let base: WritableKeyPath<WidgetStyle, LineStyle> = \.[element: element.id].line
        return session.binding(for: base.appending(path: keyPath))
    }

    private var style: LineStyle { session.style.elements[element.id]?.line ?? LineStyle() }

    /// The battery's chart: bars, filled. A level's slider (not its ring): the system's slider,
    /// which takes a colour alone.
    private var isBars: Bool { session.widget?.kind == .batteryChart && element.id == .chart }
    private var isSlider: Bool {
        guard element.id == .levelSlider, let widget = session.widget else { return false }
        if let frame = session.elementFrame(.levelSlider) { return frame.width >= frame.height * 1.6 }
        return widget.layout != .ring
    }

    var body: some View {
        if isSlider {
            InspectorSection("Line") {
                ColorRows(session: session, id: element.id, slots: [.fill])
            }
        } else {
            lineSection
        }
    }

    private var lineSection: some View {
        InspectorSection(element.role == .chart ? "Chart" : "Line") {
            if !isBars {
                InspectorRow("Thickness", isSet: style.thickness != nil, reset: { line(\.thickness).wrappedValue = nil }) {
                    OptionalSlider(value: line(\.thickness), range: LineStyle.thicknessRange, step: 0.5, standard: 4,
                                   format: { $0.formatted(.number.precision(.fractionLength(0...1))) + " pt" }, session: session)
                }
                InspectorRow("Ends", isSet: style.cap != nil, reset: { line(\.cap).wrappedValue = nil }) {
                    OptionalChoice(value: line(\.cap), options: LineCapChoice.allCases, title: \.title)
                }
            }
            // How it is filled (one colour, a gradient, by its value); the colours are the rows under it.
            InspectorRow("Fill Style", isSet: style.fill != nil, reset: { line(\.fill).wrappedValue = nil }) {
                OptionalChoice(value: line(\.fill), options: isBars ? [.solid, .gradient] : LineFill.allCases, title: \.title)
            }
            switch style.fill {
            case .valueScale?:
                InspectorRow("Scale", isSet: true, reset: { line(\.fill).wrappedValue = nil }) {
                    Picker("", selection: Binding<ValueScale>(get: {
                        if case .valueScale(let scale)? = session.style.elements[element.id]?.colors[.fill] { scale } else { .rising }
                    }, set: { scale in
                        session.set(\WidgetStyle.[element: element.id].colors[.fill], to: .valueScale(scale))
                    })) {
                        Text("Red when low").tag(ValueScale.rising)
                        Text("Red when high").tag(ValueScale.falling)
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            case .gradient?:
                ColorRows(session: session, id: element.id, slots: [.fill, .fillEnd])
            default:
                ColorRows(session: session, id: element.id, slots: [.fill])
            }
            if !isBars {
                ColorRows(session: session, id: element.id, slots: [.track])
                InspectorRow("Track", isSet: style.trackOpacity != nil, reset: { line(\.trackOpacity).wrappedValue = nil }) {
                    OptionalSlider(value: line(\.trackOpacity), range: 0...1, step: 0.05, standard: 0.16,
                                   format: { $0.formatted(.percent.precision(.fractionLength(0))) }, session: session)
                }
            }
        }
    }
}

// MARK: Button

private struct ButtonInspector: View {
    let session: EditorSession
    let element: ElementSpec

    private func button<Value: Equatable>(_ keyPath: WritableKeyPath<ButtonSpec, Value>) -> Binding<Value> {
        let base: WritableKeyPath<WidgetStyle, ButtonSpec> = \.[element: element.id].button
        return session.binding(for: base.appending(path: keyPath))
    }

    private var style: ButtonSpec { session.style.elements[element.id]?.button ?? ButtonSpec() }

    var body: some View {
        InspectorSection("Button") {
            InspectorRow("Look", isSet: style.look != nil, reset: { button(\.look).wrappedValue = nil }) {
                OptionalChoice(value: button(\.look), options: ButtonLookChoice.allCases, title: \.title)
            }
            InspectorRow("Shape", isSet: style.shape != nil, reset: { button(\.shape).wrappedValue = nil }) {
                OptionalChoice(value: button(\.shape), options: ButtonShapeChoice.allCases, title: \.title)
            }
            // Laid out freely, the button is as large as its rectangle.
            if !session.layoutState.isCustom {
                InspectorRow("Size", isSet: style.size != nil, reset: { button(\.size).wrappedValue = nil }) {
                    OptionalChoice(value: button(\.size), options: ControlSizeChoice.allCases, title: \.title)
                }
            }
            ColorRows(session: session, id: element.id, slots: [.tint])
            if session.style.elements[element.id]?.colors[.tint] != nil {
                InspectorRow("Strength", isSet: style.tintStrength != nil, reset: { button(\.tintStrength).wrappedValue = nil }) {
                    OptionalSlider(value: button(\.tintStrength), range: 0.1...1, step: 0.05, standard: 1,
                                   format: { $0.formatted(.percent.precision(.fractionLength(0))) }, session: session)
                }
            }
            InspectorRow("Label", isSet: style.iconOnly != nil, reset: { button(\.iconOnly).wrappedValue = nil }) {
                Picker("", selection: button(\.iconOnly)) {
                    Text("Automatic").tag(Bool?.none)
                    Text("Symbol").tag(Bool?.some(true))
                    Text("Symbol and Title").tag(Bool?.some(false))
                }
                .labelsHidden()
                .fixedSize()
            }
        }
    }
}

/// Colour rows for an element's slots.
private struct ColorRows: View {
    let session: EditorSession
    let id: ElementID
    let slots: [ColorSlot]

    var body: some View {
        ForEach(slots, id: \.self) { slot in
            InspectorRow(slot.title, isSet: session.style.elements[id]?.colors[slot] != nil,
                         reset: { session.set(\WidgetStyle.[element: id].colors[slot], to: nil) }) {
                OptionalColor(value: session.binding(for: \WidgetStyle.[element: id].colors[slot]))
            }
        }
    }
}

extension ColorSlot {
    var title: String {
        switch self {
        case .primary: "Colour"
        case .secondary: "Second Colour"
        case .fill: "Fill"
        case .fillEnd: "Fill End"
        case .track: "Track Colour"
        case .backing: "Backing Colour"
        case .border: "Border Colour"
        case .tint: "Tint"
        }
    }
}

extension ElementRole {
    var title: String {
        switch self {
        case .text: "Text"
        case .symbol: "Symbol"
        case .image: "Picture"
        case .line: "Line"
        case .chart: "Chart"
        case .button: "Button"
        case .feature: "Part"
        }
    }
}

// MARK: - The widget

/// With nothing picked: the widget's own look — colour, background, surface, layout, behaviour,
/// formats.
private struct WidgetLookInspector: View {
    let session: EditorSession
    let widget: IslandWidget

    @Environment(AppModel.self) private var model

    private func surface<Value: Equatable>(_ keyPath: WritableKeyPath<SurfaceStyle, Value>) -> Binding<Value> {
        let base: WritableKeyPath<WidgetStyle, SurfaceStyle> = \.surface
        return session.binding(for: base.appending(path: keyPath))
    }

    private func layout<Value: Equatable>(_ keyPath: WritableKeyPath<LayoutStyle, Value>) -> Binding<Value> {
        let base: WritableKeyPath<WidgetStyle, LayoutStyle> = \.layout
        return session.binding(for: base.appending(path: keyPath))
    }

    private func behaviour<Value: Equatable>(_ keyPath: WritableKeyPath<BehaviourStyle, Value>) -> Binding<Value> {
        let base: WritableKeyPath<WidgetStyle, BehaviourStyle> = \.behaviour
        return session.binding(for: base.appending(path: keyPath))
    }

    private func format<Value: Equatable>(_ keyPath: WritableKeyPath<FormatStyle, Value>) -> Binding<Value> {
        let base: WritableKeyPath<WidgetStyle, FormatStyle> = \.format
        return session.binding(for: base.appending(path: keyPath))
    }

    var body: some View {
        let kind = widget.kind
        let style = session.style
        VStack(alignment: .leading, spacing: 12) {
            InspectorSection("Accent Colour") {
                TintWell(selection: widget.tint, automaticHint: kind == .nowPlaying ? "from the artwork" : "the system's accent",
                         purpose: kind.accentPurpose) { tint in
                    withAnimation(Motion.content) { session.change(\IslandWidget.tint) { $0.tint = tint } }
                }
            }
            InspectorSection("Background") {
                Picker("", selection: Binding(get: { widget.background }, set: { background in
                    withAnimation(Motion.content) {
                        session.change(\IslandWidget.background) {
                            $0.background = background
                            $0.backgroundOpacity = nil
                        }
                    }
                })) {
                    ForEach(kind.backgrounds) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                if widget.background.hasOpacity {
                    InspectorRow("Strength", isSet: widget.backgroundOpacity != nil,
                                 reset: { session.change(\IslandWidget.backgroundOpacity) { $0.backgroundOpacity = nil } }) {
                        OptionalSlider(value: session.widgetBinding(for: \.backgroundOpacity, fallback: nil), range: 0.05...1, step: 0.01,
                                       standard: widget.background.defaultOpacity,
                                       format: { $0.formatted(.percent.precision(.fractionLength(0))) }, session: session)
                    }
                }
                if widget.background == .gradient {
                    InspectorRow("From", isSet: style.surface.fill != nil, reset: { surface(\.fill).wrappedValue = nil }) {
                        OptionalColor(value: surface(\.fill))
                    }
                    InspectorRow("To", isSet: style.surface.fillEnd != nil, reset: { surface(\.fillEnd).wrappedValue = nil }) {
                        OptionalColor(value: surface(\.fillEnd))
                    }
                }
                if widget.background == .image {
                    InspectorRow("Picture", isSet: style.surface.imagePath != nil, reset: { surface(\.imagePath).wrappedValue = nil }) {
                        HStack(spacing: 6) {
                            Text(style.surface.imagePath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "None")
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .font(.caption)
                                .foregroundStyle(SettingsPalette.secondary)
                            Button("Choose…") {
                                if let path = ImageChooser.choose() { surface(\.imagePath).wrappedValue = path }
                            }
                            .controlSize(.small)
                        }
                    }
                }
                if widget.background == .artwork {
                    InspectorRow("Dim", isSet: style.surface.artworkDim != nil, reset: { surface(\.artworkDim).wrappedValue = nil }) {
                        OptionalSlider(value: surface(\.artworkDim), range: 0...1, step: 0.05, standard: 0.35,
                                       format: { $0.formatted(.percent.precision(.fractionLength(0))) }, session: session)
                    }
                }
                InspectorRow("Border", isSet: style.surface.borderWidth != nil, reset: { surface(\.borderWidth).wrappedValue = nil }) {
                    OptionalSlider(value: surface(\.borderWidth), range: SurfaceStyle.borderRange, step: 0.5, standard: 0,
                                   format: { $0.formatted(.number.precision(.fractionLength(0...1))) + " pt" }, session: session)
                }
                if (style.surface.borderWidth ?? 0) > 0 {
                    InspectorRow("Border Colour", isSet: style.surface.border != nil, reset: { surface(\.border).wrappedValue = nil }) {
                        OptionalColor(value: surface(\.border))
                    }
                }
                InspectorRow("Corners", isSet: style.surface.cornerRadius != nil, reset: { surface(\.cornerRadius).wrappedValue = nil }) {
                    OptionalSlider(value: surface(\.cornerRadius), range: SurfaceStyle.cornerRange, step: 1, standard: WidgetMetrics.cornerRadius,
                                   format: { "\(Int($0)) pt" }, session: session)
                }
            }
            InspectorSection("Layout") {
                // The kind's own arrangements; laid out freely, the canvas is the arrangement.
                if !kind.layouts.isEmpty, !style.layout.arrangement.isCustom {
                    HStack(spacing: 6) {
                        ForEach(kind.layouts) { layout in
                            LayoutOption(layout: layout, isSelected: widget.layout == layout) {
                                withAnimation(Motion.content) { session.change(\IslandWidget.layout) { $0.layout = layout } }
                            }
                        }
                    }
                }
                // A custom layout is mirrored as a whole (Custom Layout ▸ Flip Horizontally).
                if kind.canMirror, !style.layout.arrangement.isCustom {
                    InspectorRow("Swap Sides", isSet: widget.mirrored,
                                 reset: { session.change(\IslandWidget.mirrored) { $0.mirrored = false } }) {
                        Toggle("", isOn: Binding(get: { widget.mirrored }, set: { on in
                            withAnimation(Motion.content) { session.change(\IslandWidget.mirrored) { $0.mirrored = on } }
                        }))
                        .labelsHidden()
                        .toggleStyle(.islandSwitch)
                    }
                }
                InspectorRow("Padding", isSet: style.layout.padding != nil, reset: { layout(\.padding).wrappedValue = nil }) {
                    // No more than the widget's size leaves room for (`WidgetMetrics.maximumPadding`).
                    OptionalSlider(value: layout(\.padding), range: 0...Double(WidgetMetrics.maximumPadding(for: widget)), step: 1,
                                   standard: Double(WidgetMetrics.standardPadding(for: kind)), format: { "\(Int($0)) pt" }, session: session)
                }
                InspectorRow("Scale", isSet: style.layout.contentScale != nil, reset: { layout(\.contentScale).wrappedValue = nil }) {
                    // Laid out freely, nothing is drawn past its rectangle: no larger than 100%.
                    OptionalSlider(value: layout(\.contentScale),
                                   range: style.layout.arrangement.isCustom ? LayoutStyle.contentScaleRange.lowerBound...1
                                                                             : LayoutStyle.contentScaleRange, step: 0.05, standard: 1,
                                   format: { $0.formatted(.percent.precision(.fractionLength(0))) }, session: session)
                }
                if kind.spec.stacksElements {
                    InspectorRow("Spacing", isSet: style.layout.spacing != nil, reset: { layout(\.spacing).wrappedValue = nil }) {
                        OptionalSlider(value: layout(\.spacing), range: LayoutStyle.spacingRange, step: 1, standard: 4,
                                       format: { "\(Int($0)) pt" }, session: session)
                    }
                    .disabled(style.layout.arrangement.isCustom)
                    InspectorRow("Direction", isSet: style.layout.axis != nil, reset: { layout(\.axis).wrappedValue = nil }) {
                        OptionalChoice(value: layout(\.axis), options: LayoutAxis.allCases, title: \.title)
                    }
                    .disabled(style.layout.arrangement.isCustom)
                    InspectorRow("Alignment", isSet: style.layout.alignment != nil, reset: { layout(\.alignment).wrappedValue = nil }) {
                        OptionalChoice(value: layout(\.alignment), options: NinePointAlignment.allCases, title: \.title)
                    }
                    .disabled(style.layout.arrangement.isCustom)
                }
            }
            InspectorSection("Behaviour") {
                InspectorRow("Click", isSet: style.behaviour.tap != nil, reset: { behaviour(\.tap).wrappedValue = nil }) {
                    TapActionControl(tap: behaviour(\.tap))
                }
                InspectorRow("Only Active", isSet: style.behaviour.showsOnlyWhenActive != nil,
                             reset: { behaviour(\.showsOnlyWhenActive).wrappedValue = nil }) {
                    Toggle("", isOn: Binding(get: { style.behaviour.showsOnlyWhenActive == true },
                                             set: { behaviour(\.showsOnlyWhenActive).wrappedValue = $0 ? true : nil }))
                        .labelsHidden()
                        .toggleStyle(.islandSwitch)
                        .help("Shown on the island only while it has something to do (music, a timer, files)")
                }
                InspectorRow("Dim Inactive", isSet: style.behaviour.dimsWhenInactive != nil,
                             reset: { behaviour(\.dimsWhenInactive).wrappedValue = nil }) {
                    Toggle("", isOn: Binding(get: { style.behaviour.dimsWhenInactive == true },
                                             set: { behaviour(\.dimsWhenInactive).wrappedValue = $0 ? true : nil }))
                        .labelsHidden()
                        .toggleStyle(.islandSwitch)
                }
                InspectorRow("Haptic", isSet: style.behaviour.haptic != nil, reset: { behaviour(\.haptic).wrappedValue = nil }) {
                    Toggle("", isOn: Binding(get: { style.behaviour.haptic == true },
                                             set: { behaviour(\.haptic).wrappedValue = $0 ? true : nil }))
                        .labelsHidden()
                        .toggleStyle(.islandSwitch)
                }
            }
            let formats = kind.formatOptions
            if !formats.isEmpty {
                InspectorSection("Format") {
                    if formats.contains(.clock) {
                        InspectorRow("Clock", isSet: style.format.clock24Hour != nil, reset: { format(\.clock24Hour).wrappedValue = nil }) {
                            Picker("", selection: format(\.clock24Hour)) {
                                Text("System").tag(Bool?.none)
                                Text("24-Hour").tag(Bool?.some(true))
                                Text("12-Hour").tag(Bool?.some(false))
                            }
                            .labelsHidden()
                            .fixedSize()
                        }
                        InspectorRow("Seconds", isSet: style.format.showsSeconds != nil, reset: { format(\.showsSeconds).wrappedValue = nil }) {
                            Toggle("", isOn: Binding(get: { style.format.showsSeconds == true },
                                                     set: { format(\.showsSeconds).wrappedValue = $0 ? true : nil }))
                                .labelsHidden()
                                .toggleStyle(.islandSwitch)
                        }
                    }
                    if formats.contains(.date) {
                        InspectorRow("Date", isSet: style.format.dateTemplate != nil, reset: { format(\.dateTemplate).wrappedValue = nil }) {
                            OptionalChoice(value: format(\.dateTemplate), options: DateTemplates.all, title: DateTemplates.title)
                        }
                    }
                    if formats.contains(.percent) {
                        InspectorRow("Decimals", isSet: style.format.percentDecimals != nil,
                                     reset: { format(\.percentDecimals).wrappedValue = nil }) {
                            Picker("", selection: format(\.percentDecimals)) {
                                Text("Auto").tag(Int?.none)
                                ForEach(Array(FormatStyle.percentDecimalsRange), id: \.self) { Text("\($0)").tag(Optional($0)) }
                            }
                            .labelsHidden()
                            .choiceBar()
                            .controlSize(.small)
                            .fixedSize()
                        }
                    }
                    if formats.contains(.duration) {
                        InspectorRow("Durations", isSet: style.format.durationStyle != nil,
                                     reset: { format(\.durationStyle).wrappedValue = nil }) {
                            OptionalChoice(value: format(\.durationStyle), options: DurationStyleChoice.allCases, title: \.title)
                        }
                    }
                    if formats.contains(.temperature) {
                        InspectorRow("Degrees", isSet: style.format.temperature != nil, reset: { format(\.temperature).wrappedValue = nil }) {
                            OptionalChoice(value: format(\.temperature), options: TemperatureUnit.allCases, title: \.title, automatic: "System")
                        }
                    }
                }
            }
            WidgetConfigInspector(session: session, widget: widget)
        }
    }
}

/// What a click on the widget does.
private struct TapActionControl: View {
    @Binding var tap: TapAction?

    private enum Choice: String, CaseIterable, Identifiable {
        case standard, app, url, shortcut, page, none
        var id: Self { self }
        var title: String {
            switch self {
            case .standard: "Its Own"
            case .app: "Open an App"
            case .url: "Open a Link"
            case .shortcut: "Run a Shortcut"
            case .page: "Show a Page"
            case .none: "Nothing"
            }
        }
    }

    private var choice: Choice {
        switch tap {
        case nil, .standard?: .standard
        case .app?: .app
        case .url?: .url
        case .shortcut?: .shortcut
        case .page?: .page
        case .none?: .none
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("", selection: Binding(get: { choice }, set: { new in
                tap = switch new {
                case .standard: nil
                case .app: .app("")
                case .url: .url("https://")
                case .shortcut: .shortcut("")
                case .page: .page(ExpandedPage.home.rawValue)
                case .none: TapAction.none
                }
            })) {
                ForEach(Choice.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
            switch tap {
            case .app(let path)?:
                HStack(spacing: 6) {
                    Text(path.isEmpty ? "None" : URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(SettingsPalette.secondary)
                    Button("Choose…") { if let app = ImageChooser.chooseApp() { tap = .app(app) } }
                        .controlSize(.small)
                }
            case .url(let link)?:
                TextField("https://", text: Binding(get: { link }, set: { tap = .url($0) }))
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
            case .shortcut(let name)?:
                TextField("Shortcut name", text: Binding(get: { name }, set: { tap = .shortcut($0) }))
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
            case .page(let name)?:
                Picker("", selection: Binding(get: { name }, set: { tap = .page($0) })) {
                    ForEach(ExpandedPage.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .labelsHidden()
                .fixedSize()
            default:
                EmptyView()
            }
        }
    }
}

/// The date's wordings a style offers (`FormatStyle.dateTemplate`).
enum DateTemplates {
    static let all = ["EEEEdMMMM", "EEEdMMM", "EEEd", "dMMMM", "dMMyy", "d"]

    static func title(_ template: String) -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: Date(timeIntervalSince1970: 1_790_235_660))
    }
}

/// Open panels for a picture and an app.
@MainActor enum ImageChooser {
    static func choose() -> String? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url?.path : nil
    }

    static func chooseApp() -> String? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        return panel.runModal() == .OK ? panel.url?.path : nil
    }
}

/// The formats a kind reads (`FormatStyle`): the editor offers only those.
enum FormatOption: Hashable {
    case clock, date, percent, duration, temperature
}

extension IslandWidgetKind {
    var formatOptions: Set<FormatOption> {
        switch self {
        case .dateTime: [.clock, .date]
        case .worldClock: [.clock]
        case .analogClock, .monthCalendar: []
        case .upNext: [.clock]
        case .countdown: [.duration]
        // Whole percentages (a charge, a health, AirPods) have no decimals to show.
        case .battery, .batteryTime: [.duration]
        case .volume, .brightness, .keyboardBrightness, .systemStats: [.percent]
        case .batteryTemperature: [.temperature]
        case .uptime: [.duration]
        default: []
        }
    }
}

extension ElementArrangement? {
    /// The widget's elements placed freely (its own custom layout).
    var isCustom: Bool {
        if case .custom? = self { true } else { false }
    }
}
