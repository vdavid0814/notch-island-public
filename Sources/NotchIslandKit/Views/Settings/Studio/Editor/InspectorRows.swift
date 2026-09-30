import AppKit
import SwiftUI

// The Customize inspector's rows. Every row edits one optional property of the style (nil is the
// kind's own look): a dot marks a row whose property is set, and ⌥-click on its title resets it.

/// A row: its title (with the dot and the ⌥-click reset) on the left, its control on the right.
struct InspectorRow<Control: View>: View {
    let title: String
    let isSet: Bool
    let reset: () -> Void
    @ViewBuilder var control: Control

    init(_ title: String, isSet: Bool, reset: @escaping () -> Void, @ViewBuilder control: () -> Control) {
        self.title = title
        self.isSet = isSet
        self.reset = reset
        self.control = control()
    }

    var body: some View {
        // Beside its title where it fits; a control wider than the room there (a bar of four
        // choices) goes under it, the pane's whole width, so the pane never grows past its edge.
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 8) {
                titleView
                    .frame(width: InspectorLayout.titleWidth, alignment: .leading)
                control
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 6) {
                titleView
                control
                    .padding(.leading, 10)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private var titleView: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color.islandAccent)
                .frame(width: 5, height: 5)
                .opacity(isSet ? 1 : 0)
                .accessibilityHidden(true)
            Text(title)
                .font(.callout)
                .foregroundStyle(isSet ? .primary : SettingsPalette.secondary)
                .lineLimit(1)
        }
        .contentShape(.rect)
        .onTapGesture {
            // ⌥-click: back to the kind's own.
            if NSEvent.modifierFlags.contains(.option), isSet { reset() }
        }
        .help(isSet ? "\(title) is set. ⌥-click to reset it." : title)
    }
}

nonisolated enum InspectorLayout {
    static let titleWidth: CGFloat = 104
    static let width: CGFloat = 320
    static let narrowWidth: CGFloat = 300
}

/// A section of the inspector: a title and its rows, flat (the pane's corner is too tight for cards
/// to be concentric in), a divider above.
struct InspectorSection<Content: View>: View {
    let title: String
    var trailing: AnyView?
    @ViewBuilder var content: Content

    init(_ title: String, trailing: AnyView? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.trailing = trailing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider().opacity(0.6)
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SettingsPalette.secondary)
                Spacer(minLength: 0)
                trailing
            }
            .padding(.top, 4)
            content
        }
    }
}

/// A choice among an enum's cases, or the kind's own ("Automatic").
struct OptionalChoice<Value: Hashable>: View {
    @Binding var value: Value?
    let options: [Value]
    let title: (Value) -> String
    var automatic = "Automatic"

    var body: some View {
        Picker("", selection: $value) {
            Text(automatic).tag(Value?.none)
            Divider()
            ForEach(options, id: \.self) { Text(title($0)).tag(Optional($0)) }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .fixedSize()
    }
}

/// On, off, or the kind's own.
struct OptionalSwitch: View {
    @Binding var value: Bool?

    var body: some View {
        Picker("", selection: $value) {
            Text("Auto").tag(Bool?.none)
            Text("On").tag(Bool?.some(true))
            Text("Off").tag(Bool?.some(false))
        }
        .labelsHidden()
        .choiceBar()
        .fixedSize()
        .controlSize(.small)
    }
}

/// A number the style sets, or the kind's own: a slider with its value, and Automatic to go back.
/// A drag is one undo step (`EditorSession.beginEdit`).
struct OptionalSlider: View {
    @Binding var value: Double?
    let range: ClosedRange<Double>
    var step: Double = 1
    /// The value the kind draws when nothing is set: where the slider starts.
    var standard: Double
    var format: (Double) -> String = { $0.formatted(.number.precision(.fractionLength(0))) }
    let session: EditorSession

    var body: some View {
        HStack(spacing: 8) {
            Slider(value: Binding(get: { value ?? standard }, set: { new in
                let snapped = (new / step).rounded() * step
                if snapped != value { value = snapped }
            }), in: range) { editing in
                editing ? session.beginEdit() : session.endEdit()
            }
            .controlSize(.small)
            .tint(Color.islandAccent)
            Text(value.map(format) ?? "Auto")
                .font(.caption.monospacedDigit())
                .foregroundStyle(value == nil ? SettingsPalette.secondary : .primary)
                .frame(width: 44, alignment: .trailing)
        }
    }
}

/// A style colour, or the kind's own.
struct OptionalColor: View {
    @Binding var value: StyleColor?

    var body: some View {
        HStack(spacing: 8) {
            ColorWell(color: Binding(get: { value ?? .automatic }, set: { value = $0 == .automatic ? nil : $0 }))
            if let value, value != .automatic {
                Text(value.inspectorTitle)
                    .font(.caption)
                    .foregroundStyle(SettingsPalette.secondary)
            }
        }
    }
}

/// A text the style sets (a label, a template), empty for the kind's own.
struct OptionalTextField: View {
    @Binding var value: String?
    let prompt: String

    var body: some View {
        TextField(prompt, text: Binding(get: { value ?? "" }, set: { value = $0.isEmpty ? nil : $0 }))
            .textFieldStyle(.roundedBorder)
            .controlSize(.small)
    }
}

extension StyleColor {
    var inspectorTitle: String {
        switch self {
        case .automatic: "Automatic"
        case .accent: "Accent"
        case .theme: "Theme"
        case .artwork: "Artwork"
        case .semantic(let semantic): semantic.rawValue.capitalized
        case .named(let tint): tint.title
        case .rgb: "Custom"
        case .valueScale(let scale): scale == .rising ? "Charge scale" : "Load scale"
        }
    }
}

// MARK: - Titles of the style's choices

extension FontDesignChoice {
    var title: String {
        switch self {
        case .standard: "Default"
        case .rounded: "Rounded"
        case .serif: "Serif"
        case .monospaced: "Monospaced"
        }
    }
}

extension FontWeightChoice {
    var title: String {
        switch self {
        case .ultraLight: "Ultralight"
        case .thin: "Thin"
        case .light: "Light"
        case .regular: "Regular"
        case .medium: "Medium"
        case .semibold: "Semibold"
        case .bold: "Bold"
        case .heavy: "Heavy"
        case .black: "Black"
        }
    }
}

extension FontWidthChoice {
    var title: String { rawValue.capitalized }
}

extension TextCaseChoice {
    var title: String {
        switch self {
        case .asIs: "As Written"
        case .uppercase: "UPPERCASE"
        case .lowercase: "lowercase"
        }
    }
}

extension TextAlignmentChoice {
    var title: String { rawValue.capitalized }
    var systemImage: String {
        switch self {
        case .leading: "text.alignleft"
        case .center: "text.aligncenter"
        case .trailing: "text.alignright"
        }
    }
}

extension TruncationChoice {
    var title: String {
        switch self {
        case .head: "Cut the Start"
        case .middle: "Cut the Middle"
        case .tail: "Cut the End"
        case .shrink: "Shrink to Fit"
        }
    }
}

extension SymbolRenderingChoice {
    var title: String { rawValue.capitalized }
}

extension SymbolBacking {
    var title: String {
        switch self {
        case .none: "None"
        case .circle: "Circle"
        case .roundedSquare: "Rounded Square"
        case .capsule: "Capsule"
        }
    }
}

extension ImageContentMode {
    var title: String { self == .fill ? "Fill" : "Fit" }
}

extension LineCapChoice {
    var title: String {
        switch self {
        case .round: "Round"
        case .butt: "Flat"
        case .square: "Square"
        }
    }
}

extension LineFill {
    var title: String {
        switch self {
        case .solid: "One Colour"
        case .gradient: "Gradient"
        case .valueScale: "By Value"
        }
    }
}

extension ButtonLookChoice {
    var title: String {
        switch self {
        case .glass: "Glass"
        case .prominent: "Prominent"
        case .plain: "Plain"
        case .bordered: "Bordered"
        }
    }
}

extension ButtonShapeChoice {
    var title: String {
        switch self {
        case .circle: "Circle"
        case .capsule: "Capsule"
        case .roundedRectangle: "Rounded Rectangle"
        }
    }
}

extension ControlSizeChoice {
    var title: String { rawValue.capitalized }
}

extension NinePointAlignment {
    var title: String {
        switch self {
        case .topLeading: "Top Left"
        case .top: "Top"
        case .topTrailing: "Top Right"
        case .leading: "Left"
        case .center: "Centre"
        case .trailing: "Right"
        case .bottomLeading: "Bottom Left"
        case .bottom: "Bottom"
        case .bottomTrailing: "Bottom Right"
        }
    }

    var alignment: Alignment {
        switch self {
        case .topLeading: .topLeading
        case .top: .top
        case .topTrailing: .topTrailing
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        case .bottomLeading: .bottomLeading
        case .bottom: .bottom
        case .bottomTrailing: .bottomTrailing
        }
    }
}

extension LayoutAxis {
    var title: String { self == .horizontal ? "Row" : "Column" }
}

extension DurationStyleChoice {
    var title: String {
        switch self {
        case .positional: "1:05"
        case .abbreviated: "1 hr 5 min"
        case .narrow: "1h 5m"
        }
    }
}

extension TemperatureUnit {
    var title: String { self == .celsius ? "°C" : "°F" }
}
