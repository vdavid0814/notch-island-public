import SwiftUI

// Settings' grouped form. Laid out as the system's (section titles, rows on a card with lines
// between them, a footnote under it; a title on the left of its control), but with the card's
// corners concentric with what is in them: the system rounds its card 12 pt around 24 pt capsules
// set 6–10 pt in, so the capsules' curve ran into the card's corner (asked for, with screenshots).
// Its corner radius has no setting (tried: container shapes, row backgrounds, control sizes).

nonisolated enum SettingsForm {
    /// Between a row's contents and the card's edges, on every side.
    static let inset: CGFloat = 10
    /// A regular capsule (a button, a choice bar, a pop-up): 24 pt high.
    static let controlRadius: CGFloat = 12
    /// The card's corners: concentric with a capsule the inset away from them.
    static let cardRadius: CGFloat = controlRadius + inset
    /// Between a section's title and its card, and between one section and the next title.
    static let headerGap: CGFloat = 10
    static let sectionGap: CGFloat = 26
    static let footerGap: CGFloat = 6
    /// Between a row's title and its control.
    static let titleGap: CGFloat = 16

    static let cardFill = Color.white.opacity(0.05)
}

extension EnvironmentValues {
    /// Inside Settings' form, where a switch is the small one the system's form shows.
    @Entry var isSettingsForm = false
}

extension ContainerValues {
    /// The corner radius of something in a row that sits the inset from the card's corner: the
    /// card is rounded concentric with it instead of with a capsule.
    @Entry var settingsCornerElementRadius: CGFloat?
}

extension View {
    /// This row holds something rounded `radius` at the card's corner (a picture, a big button):
    /// the section's card is rounded concentric with it.
    func settingsCornerElement(radius: CGFloat) -> some View {
        containerValue(\.settingsCornerElementRadius, radius)
    }
}

extension FormStyle where Self == SettingsFormStyle {
    static var settings: SettingsFormStyle { SettingsFormStyle() }
}

struct SettingsFormStyle: FormStyle {
    func makeBody(configuration: Configuration) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsForm.sectionGap) {
                ForEach(sections: configuration.content) { section in
                    SettingsFormSection(section: section)
                }
            }
            .padding(20)
        }
        .labeledContentStyle(SettingsRowStyle())
        .environment(\.isSettingsForm, true)
    }
}

private struct SettingsFormSection: View {
    let section: SectionConfiguration

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !section.header.isEmpty {
                section.header
                    .font(.headline)
                    .padding(.horizontal, SettingsForm.inset)
                    .padding(.bottom, SettingsForm.headerGap)
            }
            Group(subviews: section.content) { rows in
                if !rows.isEmpty {
                    let radius = rows.compactMap(\.containerValues.settingsCornerElementRadius).max()
                        .map { $0 + SettingsForm.inset } ?? SettingsForm.cardRadius
                    VStack(spacing: 0) {
                        ForEach(rows.indices, id: \.self) { index in
                            if index > 0 {
                                Divider().padding(.horizontal, SettingsForm.inset)
                            }
                            rows[index]
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(SettingsForm.inset)
                        }
                    }
                    .background(SettingsForm.cardFill, in: .rect(cornerRadius: radius, style: .continuous))
                }
            }
            if !section.footer.isEmpty {
                section.footer
                    .font(.callout)
                    .foregroundStyle(SettingsPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, SettingsForm.inset)
                    .padding(.top, SettingsForm.footerGap)
            }
        }
    }
}

/// A title (and the lines under it, secondary) on the left, its control on the right, as the
/// system's grouped form lays out a labelled control; switches, pickers and sliders come here too.
private struct SettingsRowStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        SettingsRow(configuration: configuration)
    }
}

private struct SettingsRow: View {
    let configuration: LabeledContentStyleConfiguration

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        SettingsRowLayout {
            Group(subviews: configuration.label) { lines in
                VStack(alignment: .leading, spacing: 2) {
                    lines.first
                    ForEach(lines.dropFirst()) { line in
                        line.font(.subheadline).foregroundStyle(SettingsPalette.secondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                // A setting that cannot be changed now reads dimmed, title and all.
                .opacity(isEnabled ? 1 : 0.5)
            }
            HStack(spacing: 8) { configuration.content }
        }
    }
}

/// The title takes what the control leaves, at least 40 % of the row unless it is shorter; the
/// control its own width (a text field: all the rest). Both centred on the row's height.
///
/// Every measurement is kept in the layout's cache (which SwiftUI rebuilds whenever the row or
/// its subviews change): measured afresh in every call, a row measured its native controls eight
/// times per layout pass, the largest piece of our own code when a page opens (~50 ms a page).
private struct SettingsRowLayout: Layout {
    struct Cache {
        var ideals: (title: CGFloat, control: CGFloat)?
        var widths: [CGFloat: (title: CGFloat, control: CGFloat)] = [:]
        var sizes: [CGFloat?: CGSize] = [:]
    }

    func makeCache(subviews: Subviews) -> Cache { Cache() }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        guard subviews.count == 2 else { return .zero }
        if let size = cache.sizes[proposal.width] { return size }
        let (title, control) = widths(proposal.width, subviews, &cache)
        let height = max(subviews[0].sizeThatFits(ProposedViewSize(width: title, height: nil)).height,
                         subviews[1].sizeThatFits(ProposedViewSize(width: control, height: nil)).height)
        let size = CGSize(width: proposal.width ?? title + SettingsForm.titleGap + control, height: height)
        cache.sizes[proposal.width] = size
        return size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        guard subviews.count == 2 else { return }
        let (title, control) = widths(bounds.width, subviews, &cache)
        subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading,
                          proposal: ProposedViewSize(width: title, height: nil))
        subviews[1].place(at: CGPoint(x: bounds.maxX, y: bounds.midY), anchor: .trailing,
                          proposal: ProposedViewSize(width: control, height: nil))
    }

    private func widths(_ width: CGFloat?, _ subviews: Subviews, _ cache: inout Cache) -> (title: CGFloat, control: CGFloat) {
        let ideals = cache.ideals ?? (subviews[0].sizeThatFits(.unspecified).width, subviews[1].sizeThatFits(.unspecified).width)
        cache.ideals = ideals
        let (titleIdeal, controlIdeal) = ideals
        guard let width else { return (titleIdeal, controlIdeal) }
        if let widths = cache.widths[width] { return widths }
        let room = max(0, width - SettingsForm.titleGap)
        let controlWidest = subviews[1].sizeThatFits(ProposedViewSize(width: room, height: nil)).width
        let control = max(0, min(max(controlIdeal, controlWidest), room - min(titleIdeal, room * 0.4)))
        cache.widths[width] = (room - control, control)
        return (room - control, control)
    }
}

/// A text field in a row: its title on the left, the text on the right without a box, as the
/// system's grouped form shows one (a field alone in a row lost its title).
struct SettingsTextField: View {
    let title: Text
    @Binding var text: String
    var prompt: Text?
    var axis: Axis = .horizontal

    init(_ title: LocalizedStringKey, text: Binding<String>, prompt: Text? = nil, axis: Axis = .horizontal) {
        self.init(title: Text(title), text: text, prompt: prompt, axis: axis)
    }

    init(_ title: some StringProtocol, text: Binding<String>, prompt: Text? = nil, axis: Axis = .horizontal) {
        self.init(title: Text(title), text: text, prompt: prompt, axis: axis)
    }

    private init(title: Text, text: Binding<String>, prompt: Text?, axis: Axis) {
        self.title = title
        _text = text
        self.prompt = prompt
        self.axis = axis
    }

    var body: some View {
        LabeledContent {
            TextField(text: $text, prompt: prompt, axis: axis) { title }
                .labelsHidden()
                .textFieldStyle(.plain)
                // Several lines (a description) read from the left.
                .multilineTextAlignment(axis == .vertical ? .leading : .trailing)
        } label: {
            title
        }
    }
}
