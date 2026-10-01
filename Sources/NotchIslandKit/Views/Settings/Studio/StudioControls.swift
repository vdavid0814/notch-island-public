import SwiftUI

// The Widgets studio's controls, shared by its inspectors and the Customize editor.

/// A titled card of the inspector.
struct StudioCard<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var content: Content

    init(_ title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.headline)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(SettingsPalette.secondary)
                }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Rounded as the form's cards on the other pages.
        .background(SettingsPalette.card, in: .rect(cornerRadius: SettingsForm.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SettingsForm.cardRadius, style: .continuous).strokeBorder(SettingsPalette.cardStroke)
        }
    }
}

/// A strength (a background's or a button's), 0–100 %, snapped to whole percents so a slow drag does
/// not rewrite the board for every pixel.
struct BackgroundOpacitySlider: View {
    let value: Double
    let set: (Double) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "circle.lefthalf.filled")
                .foregroundStyle(SettingsPalette.secondary)
                .accessibilityHidden(true)
            Slider(value: Binding(get: { value }, set: { new in
                let snapped = (new * 100).rounded() / 100
                if snapped != value { set(snapped) }
            }), in: 0...1) {
                Text("Opacity")
            }
            .labelsHidden()
            .tint(Color.islandAccent)
            .frame(maxWidth: 260)
            ReservedWidthText(value.formatted(.percent.precision(.fractionLength(0))),
                              fitting: [Double(0).formatted(.percent.precision(.fractionLength(0))),
                                        Double(1).formatted(.percent.precision(.fractionLength(0)))])
                .foregroundStyle(SettingsPalette.secondary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Opacity")
    }
}

/// One Now Playing button's look: its colour (automatic = colourless) and strength.
struct ButtonLookRow: View {
    let button: TransportButton
    let look: ButtonLook
    let set: (ButtonLook) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(button.title, systemImage: button.systemImage)
                .font(.callout.weight(.medium))
            TintWell(selection: look.tint, automaticHint: "colourless", purpose: "The button's circle.") { tint in
                var new = look
                new.tint = tint
                withAnimation(Motion.content) { set(new) }
            }
            BackgroundOpacitySlider(value: look.opacity) { value in
                var new = look
                new.opacity = value
                set(new)
            }
        }
    }
}

/// A caption over a control.
struct LabeledSetting<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.medium)).foregroundStyle(SettingsPalette.secondary)
            content
        }
    }
}

struct LayoutOption: View {
    let layout: WidgetLayout
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: layout.systemImage)
                    .font(.system(size: 17))
                    .frame(height: 20)
                Text(layout.title).font(.caption.weight(.medium)).lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 50)
            .foregroundStyle(isSelected ? .primary : SettingsPalette.secondary)
            .background(isSelected ? Color.islandAccent.opacity(0.18) : .white.opacity(0.04),
                        in: .rect(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? Color.islandAccent : .clear, lineWidth: 1.5)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A widget's accent colour, as one row: its swatch, what it is and what it colours. A click opens
/// the colours — automatic, each tint, and the ones picked lately.
struct TintWell: View {
    /// nil: several widgets with different colours.
    let selection: WidgetTint?
    /// Where automatic takes its colour from ("from the artwork").
    let automaticHint: String
    /// What it colours.
    var purpose = "Its buttons, bars and rings, and the Colour and Gradient backgrounds."
    let set: (WidgetTint) -> Void
    @State private var isOpen = false

    var body: some View {
        Button { isOpen.toggle() } label: {
            HStack(spacing: 10) {
                TintSwatch(tint: selection, side: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(selection.map { $0 == .automatic ? "Automatic — \(automaticHint)" : $0.title } ?? "Mixed")
                        .font(.callout)
                        .foregroundStyle(.primary)
                    Text(purpose)
                        .font(.caption)
                        .foregroundStyle(SettingsPalette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SettingsPalette.secondary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Accent colour")
        .accessibilityValue(selection?.title ?? "Mixed")
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            TintPanel(selection: selection, automaticHint: automaticHint) { tint in
                RecentTints.add(tint)
                set(tint)
            }
        }
    }
}

/// The tints picked lately (newest first), offered again where a widget's colour is picked.
@MainActor enum RecentTints {
    static let limit = 5
    private static let key = "recentWidgetTints"

    static var all: [WidgetTint] {
        (UserDefaults.standard.stringArray(forKey: key) ?? []).compactMap(WidgetTint.init(rawValue:))
    }

    static func add(_ tint: WidgetTint) {
        guard tint != .automatic else { return }
        let kept = all.filter { $0 != tint }
        UserDefaults.standard.set(([tint] + kept).prefix(limit).map(\.rawValue), forKey: key)
    }
}

/// The colours a widget's accent can be, in the well's popover: automatic, the tints, the recent.
struct TintPanel: View {
    let selection: WidgetTint?
    let automaticHint: String
    let set: (WidgetTint) -> Void
    /// Read as it opens.
    @State private var recents = RecentTints.all

    private let columns = Array(repeating: GridItem(.fixed(28), spacing: 10), count: 5)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { set(.automatic) } label: {
                HStack(spacing: 10) {
                    TintSwatch(tint: .automatic, side: 28, isSelected: selection == .automatic)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Automatic").font(.callout.weight(.medium))
                        Text(automaticHint.prefix(1).uppercased() + automaticHint.dropFirst())
                            .font(.caption)
                            .foregroundStyle(SettingsPalette.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            Divider().opacity(0.6)
            section("Colours", WidgetTint.allCases.filter { $0 != .automatic })
            if !recents.isEmpty {
                section("Recent", recents)
            }
        }
        .padding(16)
        .frame(width: 5 * 28 + 4 * 10 + 32)
    }

    private func section(_ title: String, _ tints: [WidgetTint]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(SettingsPalette.secondary)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                ForEach(tints) { tint in
                    Button { set(tint) } label: { TintSwatch(tint: tint, side: 28, isSelected: tint == selection) }
                        .buttonStyle(.plain)
                        .help(tint.title)
                        .accessibilityLabel(tint.title)
                        .accessibilityAddTraits(tint == selection ? .isSelected : [])
                }
            }
        }
    }
}

/// A tint as a circle; automatic as a colour wheel, several (nil) as a grey one. Ringed when picked.
struct TintSwatch: View {
    let tint: WidgetTint?
    var side: CGFloat
    var isSelected = false

    var body: some View {
        Circle()
            .fill(tint.map { tint in
                tint.color.map { AnyShapeStyle($0.gradient) }
                    ?? AnyShapeStyle(AngularGradient(colors: [.red, .orange, .yellow, .green, .blue, .purple, .red], center: .center))
            } ?? AnyShapeStyle(Color.gray.opacity(0.4)))
            .overlay { Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1) }
            .padding(isSelected ? 3 : 0)
            .overlay { Circle().strokeBorder(Color.white.opacity(isSelected ? 0.9 : 0), lineWidth: 2) }
            .frame(width: side, height: side)
            .contentShape(Circle())
    }
}

extension IslandWidgetKind {
    /// What the accent colours in this kind: its buttons, bars and rings where it has any it
    /// colours, else the Colour and Gradient backgrounds alone (it changed nothing on a plate).
    var accentPurpose: String {
        let colours: Set<IslandWidgetKind> = [.nowPlaying, .timer, .stopwatch, .shortcut, .volume, .brightness, .keyboardBrightness,
                                              .wifi, .bluetooth, .darkMode, .nightShift, .keepAwake, .microphone, .outputMute,
                                              .trueTone, .stageManager, .lowPowerMode]
        return colours.contains(self)
            ? "Its buttons, bars and rings, and the Colour and Gradient backgrounds."
            : "The Colour and Gradient backgrounds (this widget has no buttons, bars or rings it colours)."
    }
}
