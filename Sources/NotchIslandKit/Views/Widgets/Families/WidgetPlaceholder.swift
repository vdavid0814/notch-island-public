import SwiftUI

/// A kind reserved but not built yet (`WidgetKindSpec.isImplemented`): its symbol and name, quiet.
/// It is never offered, so it only shows on a board saved by a build that has the kind.
struct WidgetPlaceholder: View {
    let kind: IslandWidgetKind
    let size: CGSize

    var body: some View {
        Label(kind.title, systemImage: kind.systemImage)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(width: size.width, height: size.height)
    }
}
