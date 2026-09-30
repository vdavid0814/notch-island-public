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
            TintSwatches(selection: look.tint, automaticHint: "Colourless") { tint in
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

/// The colours as round swatches, like the accent colour picker; automatic is a colour wheel.
struct TintSwatches: View {
    /// nil: several widgets with different colours (nothing marked).
    let selection: WidgetTint?
    let automaticHint: String
    let set: (WidgetTint) -> Void

    var body: some View {
        HStack(spacing: 7) {
            ForEach(WidgetTint.allCases) { tint in
                Button {
                    set(tint)
                } label: {
                    Circle()
                        .fill(tint.color.map { AnyShapeStyle($0.gradient) }
                              ?? AnyShapeStyle(AngularGradient(colors: [.red, .orange, .yellow, .green, .blue, .purple, .red],
                                                               center: .center)))
                        .frame(width: 20, height: 20)
                        .overlay {
                            if tint == selection {
                                Circle().fill(.white).frame(width: 7, height: 7)
                            }
                        }
                        .padding(2)
                        .overlay { Circle().strokeBorder(tint == selection ? .white.opacity(0.8) : .clear, lineWidth: 1.5) }
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(tint == .automatic ? "Automatic — \(automaticHint)" : tint.title)
                .accessibilityLabel(tint.title)
                .accessibilityAddTraits(tint == selection ? .isSelected : [])
            }
        }
    }
}
