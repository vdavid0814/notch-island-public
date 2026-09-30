import SwiftUI

/// A file drag is under way somewhere on screen: invite it to the shelf. The tray bounces when the
/// drag is actually over the island.
struct DropBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let count = model.shelf.items.count
        BannerLayout(kind: .dropTarget) {
            Image(systemName: "tray.and.arrow.down.fill")
                .foregroundStyle(model.island.isDropTargeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                .symbolEffect(.bounce, value: model.island.isDropTargeted)
                .accessibilityHidden(true)
        } headerTrailing: {
            if count > 0 {
                Text("^[\(count) item](inflect: true)")
                    .foregroundStyle(.secondary)
            }
        } row: {
            Text("Drop to Keep on the Shelf")
                .font(.headline)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A window is being dragged under the notch: letting go there anchors it (the drop banner's look).
struct AnchorBanner: View {
    var body: some View {
        BannerLayout(kind: .anchorTarget) {
            Image(systemName: "rectangle.topthird.inset.filled")
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
        } headerTrailing: {
            EmptyView()
        } row: {
            Text("Let Go to Anchor Under the Notch")
                .font(.headline)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}
