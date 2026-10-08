import SwiftUI

/// The last things copied, one row each, as many as the widget is set to (`WidgetConfig.count`); a
/// click copies one again. It reads what Spotlight's Clipboard keeps (Settings ▸ Spotlight) and
/// watches nothing of its own.
///
/// Each row is two parts of its own in Customize: the copy's text, set as Now Playing's title is
/// (`WidgetLabel`, its own `TextStyle`, the same code), and its symbol, a button set as Now Playing's
/// are (`ButtonLook`; the symbol placed and sized in the band under the editor). A click on the row
/// copies it again.
struct ClipboardWidget: View {
    let widget: IslandWidget
    let size: CGSize

    @Environment(\.isWidgetPreview) private var isPreview
    @Environment(\.isElementEditing) private var isEditing
    @Environment(AppModel.self) private var model
    @State private var copied: UUID?

    static let samples = ["notchisland://open?page=timer", "Meeting moved to 3 pm", "rgb(91, 140, 255)", "Budapest, Váci út 1.", "42",
                          "Thank you!", "https://apple.com", "#5B8CFF"]
    static let symbol = "doc.on.doc"

    /// Rows until the user sets how many: one in a widget a row tall, three in a taller one
    /// (`IslandWidget.clipRowCount`).
    static func count(_ widget: IslandWidget) -> Int { widget.clipRowCount }

    /// A row's height: the widget's, shared by its rows, at most 30 points (the rows in its middle).
    static func rowHeight(_ widget: IslandWidget, inner: CGSize) -> CGFloat {
        min(max(inner.height, 1) / CGFloat(count(widget)), 30)
    }

    /// A row's text's own size, before Customize sets one.
    static func textPoints(_ widget: IslandWidget, inner: CGSize) -> CGFloat {
        max(min(rowHeight(widget, inner: inner) * 0.46, 12.5), CGFloat(TextStyle.sizes.lowerBound))
    }

    /// A row's symbol's size.
    static func symbolPoints(_ widget: IslandWidget, inner: CGSize) -> CGFloat {
        textPoints(widget, inner: inner) * 0.85
    }

    /// The `row`th copy's text (from 1): the copy, or a sample where there is none (a picture, the
    /// editor).
    static func text(row: Int, items: [ClipboardItem]) -> String {
        items.indices.contains(row - 1) ? items[row - 1].preview : samples[(row - 1) % samples.count]
    }

    var body: some View {
        let items = isPreview ? [] : model.clipboard.items
        let rows = Array(1...Self.count(widget))
        // In a picture and in the editor every row is there (to be set), a copy's or a sample.
        let shown = isPreview || isEditing ? rows.count : min(rows.count, items.count)
        Group {
            if shown == 0 {
                Label(model.preferences.siri.showsClipboard ? "Nothing copied yet" : "Clipboard is off in Settings ▸ Spotlight",
                      systemImage: "doc.on.clipboard")
                    .font(.system(size: min(12, max(size.height / 1.2, 8)), weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: size.width, height: size.height, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(rows.prefix(shown), id: \.self) { row in
                        self.row(row, text: Self.text(row: row, items: items), item: items.indices.contains(row - 1) ? items[row - 1] : nil)
                    }
                }
                .frame(width: size.width, height: size.height, alignment: .leading)
            }
        }
    }

    /// One copy: its text (as Now Playing's title: `WidgetLabel`, moved by itself) and, on the rows
    /// that have one, its symbol (a button) — each a part of its own; a click on the row copies it
    /// again. A symbol takes no room: it is set over the row's start, so adding one (or switching
    /// them off) moves nothing, and may lie over the text until it is moved.
    private func row(_ row: Int, text: String, item: ClipboardItem?) -> some View {
        let points = Self.textPoints(widget, inner: size)
        let symbolPoints = Self.symbolPoints(widget, inner: size)
        return WidgetLabel(id: .clipText(row), text: text, widget: widget, size: points, weight: .medium, isSecondary: false) {
            Text(text).font(.system(size: points, weight: .medium)).lineLimit(1).minimumScaleFactor(0.75)
        }
        .movableElement(.clipText(row), of: widget)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
            if widget.clipSymbolRows.contains(row) {
                Button { copy(item) } label: { symbol(row, item: item, points: symbolPoints) }
                    .buttonStyle(.plain)
                    .movableElement(.clipSymbol(row), of: widget)
            }
        }
        .padding(.horizontal, 4)
        .frame(width: size.width, height: Self.rowHeight(widget, inner: size), alignment: .leading)
        .contentShape(.rect)
        .onTapGesture { copy(item) }
        .help("Copy it again")
    }

    /// The symbol as the widget draws it (a tick while just copied), or as Customize styled it.
    @ViewBuilder private func symbol(_ row: Int, item: ClipboardItem?, points: CGFloat) -> some View {
        let isCopied = item != nil && copied == item?.id
        let look = widget.buttonLook(of: .clipSymbol(row))
        if look == .plain {
            Image(systemName: isCopied ? "checkmark" : Self.symbol)
                .font(.system(size: points, weight: .semibold))
                .foregroundStyle(isCopied ? AnyShapeStyle(.green) : AnyShapeStyle(.tertiary))
                .frame(width: points * 1.5)
                .contentShape(.rect)
        } else {
            WidgetButtonLabel(look: look, symbol: isCopied ? "checkmark" : Self.symbol, points: points)
        }
    }

    private func copy(_ item: ClipboardItem?) {
        guard !isPreview, let item else { return }
        model.clipboard.place(item)
        model.haptics.play(.tick)
        copied = item.id
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            if copied == item.id { copied = nil }
        }
    }
}
