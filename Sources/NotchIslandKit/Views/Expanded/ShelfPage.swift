import SwiftUI

/// Files dropped on the notch, waiting to be dragged somewhere else.
struct ShelfPage: View {
    let scale: CGFloat
    let thumbnails: ThumbnailCache

    @Environment(AppModel.self) private var model

    var body: some View {
        let items = model.shelf.items
        if items.isEmpty {
            IslandEmptyState(
                title: "Drop Files Here",
                systemImage: "tray.and.arrow.down",
                message: "Files you drop on the notch wait here until you drag them out."
            )
        } else {
            VStack(spacing: Metrics.Spacing.medium) {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: Metrics.Spacing.large * scale) {
                        ForEach(items) { item in
                            FileTile(item: item, thumbnails: thumbnails, scale: scale)
                                .transition(.scale(scale: 0.8).combined(with: .opacity))
                        }
                    }
                    .animation(Motion.content, value: items)
                }
                .scrollIndicators(.never)
                .frame(maxHeight: .infinity)

                ShelfActions(items: items)
            }
        }
    }
}

/// Count on the leading side; AirDrop, Share and Clear on the trailing side.
private struct ShelfActions: View {
    let items: [ShelfItem]

    @Environment(AppModel.self) private var model
    @Environment(\.controlSize) private var controlSize

    var body: some View {
        HStack(spacing: Metrics.Spacing.medium) {
            Text("^[\(items.count) item](inflect: true)")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)
            Spacer(minLength: 0)
            Button {
                model.shelf.airDrop()
            } label: {
                Label("AirDrop", systemImage: "dot.radiowaves.up.forward")
            }
            .help("Send with AirDrop")
            ShareLink(items: items.map(\.url)) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .help("Share")
            Button(role: .destructive) {
                model.shelf.clear()
            } label: {
                Label("Clear", systemImage: "xmark")
            }
            .help("Remove everything from the shelf")
        }
        .buttonStyle(.islandGlass)
        // Secondary to the files: one control size down, like the home page's side column.
        .controlSize(Metrics.Control.smaller(controlSize))
        .animation(Motion.content, value: items.count)
    }
}
