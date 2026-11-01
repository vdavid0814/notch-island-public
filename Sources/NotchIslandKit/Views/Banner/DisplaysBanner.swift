import SwiftUI

/// A monitor was connected: which screen the island lives on, as the island's own choice bar (the
/// panel's page picker), centred under the notch. Picking a screen saves it (Live Activities ▸
/// Displays) and the island goes there; the notice stays for as long as Live Activities says, held
/// while the pointer is on it.
struct DisplaysBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let choices = model.displayChoices(includesAutomatic: false)
        let selection = IslandScreenPicker.selection(in: choices, current: model.currentScreenChoice)
        BannerLayout(kind: .displays(choices.count)) {
            Image(systemName: "display.2")
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
        } headerTrailing: {
            Text("Display")
                .foregroundStyle(.secondary)
        } row: {
            VStack(spacing: Metrics.Spacing.small) {
                Text("Show the island on")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Picker("Show the island on", selection: Binding {
                    selection
                } set: { choice in
                    model.preferences.islandScreen = choice
                }) {
                    ForEach(choices, id: \.self) { choice in
                        Label(choice.title, systemImage: choice.systemImage).tag(choice)
                    }
                }
                .choiceBar()
                .labelsHidden()
                .fixedSize()
            }
            .frame(maxWidth: .infinity)
        }
    }
}
