import SwiftUI

/// The shelf, the base of a row of files: the files dropped on the notch as previews to drag out
/// (two rows tall and more), over a row of the tray, the count ("3 items", "Drop files here") and,
/// where there is room and something on it, AirDrop and Clear. The tray or the count opens the
/// shelf page.
///
/// Each part is moved in Customize: the files as a part of their own (their look comes later), the
/// count as a text (`WidgetLabel`), the tray, AirDrop and Clear as buttons (`ButtonLook`). A
/// picture (the gallery, the editor) shows three sample files and reads nothing from the disk.
struct ShelfWidget: View {
    let widget: IslandWidget
    let size: CGSize

    @Environment(AppModel.self) private var model
    @Environment(\.isWidgetPreview) private var isPreview
    @Environment(\.isElementEditing) private var isEditing
    @Environment(\.shelfThumbnails) private var sharedThumbnails
    @State private var ownThumbnails = ThumbnailCache()

    /// A picture's files (as many as the row holds are shown).
    static let sampleCount = 3
    static let sampleSymbols = ["doc.richtext.fill", "photo.fill", "folder.fill", "doc.text.fill"]

    /// The previews' side: what the widget's height leaves over the row; shown from 22 points.
    static func previewSide(inner: CGSize) -> CGFloat { min(inner.height - 34, 64).rounded(.down) }

    static func hasPreviewRoom(inner: CGSize) -> Bool { previewSide(inner: inner) >= 22 }

    /// How many files the row has room for (Customize's Settings): they share its width.
    static let fileCounts = 2...4
    static let defaultFileCount = 3

    static func fileCount(_ widget: IslandWidget) -> Int {
        min(max(widget.config.count ?? defaultFileCount, fileCounts.lowerBound), fileCounts.upperBound)
    }

    /// The files in a row `row` large holding `count`: square (never stretched), as large as the
    /// row's height allows with at least a small gap between them, the rest of the width shared
    /// out between them, so the first starts at the row's leading edge and the last ends at its
    /// trailing one.
    static func fileLayout(row: CGSize, count: Int) -> (side: CGFloat, gap: CGFloat) {
        let least = Metrics.Spacing.small
        let side = max(min(row.height, (row.width - CGFloat(count - 1) * least) / CGFloat(count)), 1).rounded(.down)
        return (side, count > 1 ? (row.width - CGFloat(count) * side) / CGFloat(count - 1) : 0)
    }

    /// AirDrop and Clear beside the count, from a widget this wide (four columns; not three).
    static func hasActionRoom(inner: CGSize) -> Bool { inner.width >= 160 }

    /// The row of the tray, the count and the buttons.
    static func rowHeight(showsPreviews: Bool, inner: CGSize) -> CGFloat {
        showsPreviews ? max(20, inner.height - previewSide(inner: inner) - Metrics.Spacing.small) : inner.height
    }

    static func countPoints(inner: CGSize, showsPreviews: Bool = true) -> CGFloat {
        let row = rowHeight(showsPreviews: showsPreviews && hasPreviewRoom(inner: inner), inner: inner)
        return WidgetMetrics.points(row, ratio: 0.42, min: 11, max: 15)
    }

    static func symbolPoints(inner: CGSize) -> CGFloat { countPoints(inner: inner) }

    /// "3 items", or "Drop files here" on an empty shelf.
    static func countText(_ count: Int) -> String {
        count == 0 ? String(localized: "Drop files here")
            : String(AttributedString(localized: "^[\(count) item](inflect: true)").characters)
    }

    var body: some View {
        let items = model.shelf.items
        let count = isPreview ? Self.sampleCount : items.count
        let showsPreviews = widget.shows(.previews) && Self.hasPreviewRoom(inner: size) && count > 0
        let showsActions = widget.shows(.shelfActions) && Self.hasActionRoom(inner: size) && (count > 0 || isEditing)
        let side = Self.previewSide(inner: size)
        VStack(spacing: showsPreviews ? Metrics.Spacing.small : 0) {
            if showsPreviews {
                // Its box the widget's width; drawn at the size Customize gives it, the files laid
                // out again in it (not stretched).
                // As tall as its files at the widget's width (four are lower than two), at the
                // top of the room the row leaves them.
                let scale = widget.scale(of: .previews)
                let height = Self.fileLayout(row: CGSize(width: size.width, height: side), count: Self.fileCount(widget)).side
                Color.clear
                    .frame(width: size.width, height: height)
                    .overlay(alignment: .topLeading) {
                        let row = CGSize(width: size.width * scale.x, height: height * scale.y)
                        let files = Self.fileLayout(row: row, count: Self.fileCount(widget))
                        previews(items, side: files.side, gap: files.gap)
                            .frame(width: row.width, height: row.height, alignment: .leading)
                    }
                    .movableElement(.previews, of: widget, drawsScale: false)
                    .frame(height: side, alignment: .top)
            }
            HStack(spacing: Metrics.Spacing.small) {
                if widget.shows(.shelfCount) {
                    tray(full: count > 0, points: Self.symbolPoints(inner: size))
                    countLabel(count)
                }
                Spacer(minLength: 0)
                if showsActions {
                    Group {
                        button(.shelfAirDrop, title: String(localized: "AirDrop"), symbol: "dot.radiowaves.up.forward") { model.shelf.airDrop() }
                        button(.shelfClear, title: String(localized: "Clear"), symbol: "xmark") { model.shelf.clear() }
                    }
                    .controlSize(WidgetMetrics.buttonSize(rowHeight: Self.rowHeight(showsPreviews: showsPreviews, inner: size)))
                }
            }
            .frame(height: Self.rowHeight(showsPreviews: showsPreviews, inner: size))
        }
        .frame(width: size.width, height: size.height)
        .animation(Motion.content, value: items.count)
    }

    /// The files, to drag out (their context menu has the Finder's verbs), `side` large `gap`
    /// apart; more than the row holds scroll. A picture's samples, as many as the row holds.
    @ViewBuilder private func previews(_ items: [ShelfItem], side: CGFloat, gap: CGFloat) -> some View {
        if isPreview {
            HStack(spacing: gap) {
                ForEach(Self.sampleSymbols.prefix(Self.fileCount(widget)), id: \.self) { symbol in
                    RoundedRectangle(cornerRadius: side * 0.18, style: .continuous)
                        .fill(.white.opacity(0.1))
                        .overlay {
                            Image(systemName: symbol)
                                .font(.system(size: side * 0.42))
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: side, height: side)
                }
            }
        } else {
            let thumbnails = sharedThumbnails ?? ownThumbnails
            ScrollView(.horizontal) {
                HStack(spacing: gap) {
                    ForEach(items) { item in
                        FileTile(item: item, thumbnails: thumbnails, scale: side / Metrics.Expanded.thumbnailSize, showsName: false)
                    }
                }
            }
            .scrollIndicators(.never)
        }
    }

    /// The tray: quiet, or as Customize styled it; a click opens the shelf.
    private func tray(full: Bool, points: CGFloat) -> some View {
        let look = widget.buttonLook(of: .shelfTray)
        let symbol = full ? "tray.full.fill" : "tray"
        return Group {
            if look == .plain {
                Button(action: openShelf) {
                    Image(systemName: symbol)
                        .font(.system(size: points, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Open Shelf")
            } else {
                // The drawn button is the button: its whole shape takes clicks.
                WidgetButtonLabel(look: look, symbol: symbol, points: points, action: openShelf,
                                  title: String(localized: "Open Shelf"))
            }
        }
        .movableElement(.shelfTray, of: widget)
    }

    /// The count: the shortest wording that fits as the widget sets it ("Drop files here", "Drop
    /// files", "Drop"), or restyled; a click opens the shelf.
    private func countLabel(_ count: Int) -> some View {
        let points = Self.countPoints(inner: size, showsPreviews: widget.shows(.previews) && count > 0)
        let text = Self.countText(count)
        return Button(action: openShelf) {
            WidgetLabel(id: .shelfCount, text: text, widget: widget, size: points, weight: .medium, isSecondary: count == 0) {
                ViewThatFits(in: .horizontal) {
                    Text(text).fixedSize()
                    Text(count == 0 ? String(localized: "Drop files") : "\(count)").fixedSize()
                    Text(count == 0 ? String(localized: "Drop") : "\(count)").fixedSize()
                }
                .font(.system(size: points, weight: .medium))
                .foregroundStyle(count == 0 ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .contentTransition(.opacity)
            }
        }
        .buttonStyle(.plain)
        .help("Open Shelf")
        .movableElement(.shelfCount, of: widget)
    }

    /// AirDrop or Clear, for everything on the shelf: on glass, or as Customize styled it.
    @ViewBuilder private func button(_ id: ElementID, title: String, symbol: String, action: @escaping () -> Void) -> some View {
        let look = widget.buttonLook(of: id)
        Group {
            if look == .plain {
                Button(action: action) { Label(title, systemImage: symbol) }
                    .islandButton(.circle)
                    .help(title)
            } else {
                NowPlayingButton(title: title, symbol: symbol, points: Self.symbolPoints(inner: size), look: look, action: action)
            }
        }
        .movableElement(id, of: widget)
    }

    private func openShelf() {
        guard !isPreview, model.availablePages.contains(.shelf) else { return }
        model.island.page = .shelf
    }
}
