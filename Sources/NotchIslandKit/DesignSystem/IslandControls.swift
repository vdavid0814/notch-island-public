import SwiftUI

extension Color {
    /// The theme's colour for a control with a white knob (a switch): a white or near-white theme is
    /// taken down to a light grey, or the knob would vanish on it.
    @MainActor static var islandControlAccent: Color {
        let rgb = IslandThemeStore.shared.theme.rgb
        let luminance = 0.2126 * rgb.red + 0.7152 * rgb.green + 0.0722 * rgb.blue
        return luminance > 0.8 ? rgb.mixed(with: .init(red: 0, green: 0, blue: 0), by: 0.7).color : rgb.color
    }
}

/// Settings' switches in the theme's colour. Only the switch is tinted: a tint over the whole row
/// would colour the info buttons in the labels too (as it coloured every glass button, v0.4.8).
struct IslandSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        IslandSwitch(configuration: configuration)
    }
}

private struct IslandSwitch: View {
    let configuration: ToggleStyleConfiguration

    @Environment(\.isSettingsForm) private var isSettingsForm

    var body: some View {
        LabeledContent {
            Toggle(isOn: configuration.$isOn) { configuration.label }
                .labelsHidden()
                .toggleStyle(.switch)
                // Settings' form shows the small switch the system's grouped form has.
                .controlSize(isSettingsForm ? .mini : .regular)
                .tint(Color.islandControlAccent)
        } label: {
            configuration.label
        }
    }
}

extension ToggleStyle where Self == IslandSwitchStyle {
    static var islandSwitch: IslandSwitchStyle { IslandSwitchStyle() }
}
