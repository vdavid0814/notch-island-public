import SwiftUI

/// Two of a part's numbers in one small capsule (width and height, or X and Y), a faint line
/// between them at its middle, each typed over to set it: a whole number of px.
struct FramePair: View {
    /// One value: its name, its number and what typing one sets.
    typealias Value = (name: String, number: CGFloat?, set: (CGFloat) -> Void)

    let title: LocalizedStringKey
    let first: Value
    let second: Value
    /// The number's field: narrower where the capsule is.
    var fieldWidth: CGFloat = 44

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(SettingsPalette.secondary)
            HStack(spacing: 0) {
                value(first).frame(maxWidth: .infinity)
                Rectangle()
                    .fill(Color.white.opacity(0.14))
                    .frame(width: 1, height: 14)
                value(second).frame(maxWidth: .infinity)
            }
            .frame(height: 26)
            .background(Color.white.opacity(0.06), in: .capsule)
            .overlay { Capsule().strokeBorder(SettingsPalette.cardStroke) }
        }
    }

    private func value(_ value: Value) -> some View {
        HStack(spacing: 4) {
            Text(value.name).font(.caption.weight(.semibold)).foregroundStyle(SettingsPalette.secondary)
            // Typed over, and set on Return or on leaving it: a whole number of points.
            TextField(value.name, value: Binding(get: { Double((value.number ?? 0).rounded()) }, set: { new in
                guard value.number != nil, new.isFinite else { return }
                value.set(CGFloat(new.rounded()))
            }), format: .number.precision(.fractionLength(0)).grouping(.never))
            .textFieldStyle(.plain)
            .font(.callout)
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
            .frame(width: fieldWidth)
            .disabled(value.number == nil)
            .help("Type a number of px and press Return")
            Text("px").font(.callout).foregroundStyle(SettingsPalette.secondary)
        }
    }
}
