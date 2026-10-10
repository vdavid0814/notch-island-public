import SwiftUI

/// What the version that runs brought (`ReleaseNotes.current`), in the notch after an update, on a
/// display three tenths smaller than Settings (`IslandLayout.size(for:)`): everything in one list to
/// scroll through — What's New, Fixed, Known Issues, each under its large title, set plainly in
/// white on the island's own surface — and over it a bar of the system's glass that, as the widget
/// gallery's does, shows All or one of them alone. Kept open until Done (or a click elsewhere).
struct WhatsNewPage: View {
    let scale: CGFloat

    @Environment(AppModel.self) private var model
    /// The section shown alone; nil: all of them.
    @State private var section: ReleaseNotes.Section?
    @State private var position = ScrollPosition(edge: .top)

    var body: some View {
        let notes = ReleaseNotes.current
        let sections = notes.sections
        let picked = section.flatMap { sections.contains($0) ? $0 : nil }
        VStack(spacing: Metrics.Spacing.small * scale) {
            HStack(spacing: Metrics.Spacing.small) {
                Picker("Section", selection: Binding(get: { picked }, set: { section = $0 })) {
                    Text("All").tag(ReleaseNotes.Section?.none)
                    ForEach(sections) { Text($0.title).tag(Optional($0)) }
                }
                .choiceBar()
                .labelsHidden()
                .fixedSize()
                Spacer(minLength: Metrics.Spacing.small)
                Text(verbatim: "NotchIsland \(notes.version)")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Button("Done", systemImage: "checkmark") { model.controller.collapse() }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .labelStyle(.iconOnly)
                    .help("Close")
            }
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 26 * scale) {
                    ForEach(sections.filter { picked == nil || $0 == picked }) { section in
                        VStack(alignment: .leading, spacing: 14 * scale) {
                            Text(section.title)
                                .font(.system(size: 28 * scale, weight: .bold))
                                .foregroundStyle(.white)
                            ForEach(notes.items(section)) { item in
                                row(item)
                            }
                        }
                        .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10 * scale)
                .padding(.top, 8 * scale)
                .padding(.bottom, 18 * scale)
            }
            .scrollIndicators(.automatic)
            // From the top again when another section is picked.
            .defaultScrollAnchor(.top)
            .scrollPosition($position)
            .onChange(of: picked) { position.scrollTo(edge: .top) }
        }
        .animation(.easeOut(duration: 0.18), value: picked)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("What's new in NotchIsland \(notes.version)"))
    }

    /// An item: its title large and white, what it is about under it — on the surface itself.
    private func row(_ item: ReleaseNotes.Item) -> some View {
        VStack(alignment: .leading, spacing: 3 * scale) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item.title)
                    .font(.system(size: 17 * scale, weight: .semibold))
                    .foregroundStyle(.white)
                if item.isChange {
                    Text("Changed")
                        .font(.system(size: 10 * scale, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(.white.opacity(0.14), in: .capsule)
                }
            }
            Text(item.detail)
                .font(.system(size: 14 * scale))
                .foregroundStyle(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
