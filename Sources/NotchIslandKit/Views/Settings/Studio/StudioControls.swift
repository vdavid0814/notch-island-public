import SwiftUI

// The Widgets studio's controls, shared by its inspectors.

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

/// The faint line between the Customize panels' categories, and the room on either side of it.
struct StudioDivider: View {
    static let opacity = 0.55
    /// Between a category and the line over or under it.
    static let spacing: CGFloat = 14

    var body: some View {
        Divider().opacity(Self.opacity)
    }
}
