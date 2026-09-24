import AppKit
import QuickLookThumbnailing
import SwiftUI

/// One file on the shelf: a Quick Look thumbnail and its name. Drag it out to move it on; the
/// context menu has the Finder verbs.
struct FileTile: View {
    let item: ShelfItem
    let thumbnails: ThumbnailCache
    let scale: CGFloat
    /// Small shelf widgets show the thumbnail alone.
    var showsName = true

    @Environment(AppModel.self) private var model
    @Environment(\.displayScale) private var displayScale
    @State private var thumbnail: ThumbnailCache.Thumbnail?

    private var side: CGFloat { (Metrics.Expanded.thumbnailSize * scale).rounded() }
    private var width: CGFloat { (Metrics.Expanded.fileTileWidth * scale).rounded() }

    var body: some View {
        VStack(spacing: Metrics.Spacing.xSmall) {
            preview
                .frame(width: side, height: side)
            if showsName {
                Text(item.displayName)
                    .font(.caption)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .multilineTextAlignment(.center)
                    .frame(width: width)
            }
        }
        .frame(width: showsName ? width : side, alignment: .top)
        .contentShape(.rect)
        .onDrag {
            // Flag the drag as ours so the drag monitor does not answer it with a drop banner.
            model.shelf.isDraggingOut = true
            return NSItemProvider(contentsOf: item.url) ?? NSItemProvider()
        }
        .onDragSessionUpdated { session in
            switch session.phase {
            case .ended, .dataTransferCompleted: model.shelf.isDraggingOut = false
            default: break
            }
        }
        .contextMenu {
            Button("Open", systemImage: "arrow.up.forward.app") { model.shelf.open(item) }
            Button("Show in Finder", systemImage: "folder") { model.shelf.reveal(item) }
            Divider()
            Button("Remove from Shelf", systemImage: "minus.circle", role: .destructive) {
                model.shelf.remove(item.id)
            }
        }
        .help(item.displayName)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.displayName)
        .accessibilityAddTraits(.isButton)
        .task(id: ThumbnailCache.Key(url: item.url, side: side, scale: displayScale)) {
            thumbnail = await thumbnails.thumbnail(for: item.url, side: side, scale: displayScale)
        }
    }

    @ViewBuilder private var preview: some View {
        if let thumbnail {
            let image = Image(nsImage: thumbnail.image).resizable().interpolation(.high)
            if thumbnail.isIcon {
                image.aspectRatio(contentMode: .fit)
            } else {
                // Real content (photos, pages) gets the same soft corners Finder gives thumbnails.
                image
                    .aspectRatio(contentMode: .fit)
                    .clipShape(.rect(cornerRadius: Metrics.Expanded.thumbnailRadius, style: .continuous))
            }
        } else {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path(percentEncoded: false)))
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
    }
}

/// Quick Look thumbnails for shelf tiles, generated once per file and size and kept for the life of
/// the island. Tiles are torn down whenever the shelf page is left; without the cache every visit
/// would regenerate every thumbnail.
final class ThumbnailCache {
    struct Thumbnail {
        let image: NSImage
        /// Quick Look fell back to the file's icon (no content preview available).
        let isIcon: Bool
    }

    nonisolated struct Key: Hashable, Sendable {
        let url: URL
        let side: CGFloat
        let scale: CGFloat
    }

    /// Small on purpose: the shelf holds a handful of files, and thumbnails are cheap to regenerate.
    static let capacity = 48

    private var entries: [Key: Thumbnail] = [:]
    private var order: [Key] = []

    func thumbnail(for url: URL, side: CGFloat, scale: CGFloat) async -> Thumbnail {
        let key = Key(url: url, side: side, scale: scale)
        if let hit = entries[key] { return hit }
        let rendered = await Self.render(url: url, side: side, scale: scale)
        let thumbnail: Thumbnail
        if let rendered {
            thumbnail = Thumbnail(image: NSImage(cgImage: rendered.image, size: .zero), isIcon: rendered.isIcon)
        } else {
            thumbnail = Thumbnail(image: NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false)), isIcon: true)
        }
        store(thumbnail, for: key)
        return thumbnail
    }

    private func store(_ thumbnail: Thumbnail, for key: Key) {
        if entries.updateValue(thumbnail, forKey: key) == nil { order.append(key) }
        while order.count > Self.capacity {
            entries[order.removeFirst()] = nil
        }
    }

    /// Runs Quick Look off the main actor and hands back only Sendable pieces.
    @concurrent
    nonisolated private static func render(url: URL, side: CGFloat, scale: CGFloat) async -> (image: CGImage, isIcon: Bool)? {
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: side, height: side),
            scale: scale,
            representationTypes: .all
        )
        guard let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
        else { return nil }
        return (representation.cgImage, representation.type == .icon)
    }
}
