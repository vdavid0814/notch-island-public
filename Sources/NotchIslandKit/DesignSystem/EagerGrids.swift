import SwiftUI

// Grids for Settings' pages, built whole: see `GalleryGrid`.

/// Cards in rows: as many columns of at least `minimum` (at most `maximum`) as fit, sharing the
/// width, the cards centred in them — `LazyVGrid` with one adaptive column, but not lazy.
///
/// Settings' pages are built ahead and kept, so building every item once costs nothing later; a
/// lazy grid placed its items again at every frame of a scroll, each item coming into or going out
/// of it rebuilt the page's keyboard loop (~a quarter of a scroll's main-thread time, measured), and
/// a page moved on the render server while it scrolls (`ScrollCoalescer`) must already be drawn.
struct GalleryGrid: Layout {
    var minimum: CGFloat
    var maximum: CGFloat
    var spacing: CGFloat

    private func columns(_ width: CGFloat) -> (count: Int, width: CGFloat) {
        let count = max(1, Int(((width + spacing) / (minimum + spacing)).rounded(.down)))
        return (count, (width - CGFloat(count - 1) * spacing) / CGFloat(count))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout [CGFloat]) -> CGSize {
        // Unspecified or unbounded (a stack measuring how far it stretches): three columns' worth.
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? (minimum * 3 + spacing * 2)
        let (count, column) = columns(width)
        let item = min(column, maximum)
        var rows: [CGFloat] = []
        for start in stride(from: 0, to: subviews.count, by: count) {
            rows.append(subviews[start..<min(start + count, subviews.count)]
                .map { $0.sizeThatFits(ProposedViewSize(width: item, height: nil)).height }.max() ?? 0)
        }
        cache = rows
        return CGSize(width: width, height: rows.reduce(0, +) + CGFloat(max(0, rows.count - 1)) * spacing)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout [CGFloat]) {
        let (count, column) = columns(bounds.width)
        let item = min(column, maximum)
        var y = bounds.minY
        for (row, start) in stride(from: 0, to: subviews.count, by: count).enumerated() {
            let height = row < cache.count ? cache[row] : 0
            for index in start..<min(start + count, subviews.count) {
                let x = bounds.minX + CGFloat(index - start) * (column + spacing) + column / 2
                subviews[index].place(at: CGPoint(x: x, y: y + height / 2), anchor: .center,
                                      proposal: ProposedViewSize(width: item, height: height))
            }
            y += height + spacing
        }
    }

    func makeCache(subviews: Subviews) -> [CGFloat] { [] }
}

/// `count` columns `width` wide, `spacing` apart, from the leading edge, the items centred in their
/// cells — `LazyVGrid` with fixed columns and leading alignment, but not lazy (`GalleryGrid`).
struct SwatchGrid: Layout {
    var count: Int
    var width: CGFloat
    var spacing: CGFloat
    var rowSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout [CGFloat]) -> CGSize {
        var rows: [CGFloat] = []
        for start in stride(from: 0, to: subviews.count, by: count) {
            rows.append(subviews[start..<min(start + count, subviews.count)]
                .map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }.max() ?? 0)
        }
        cache = rows
        return CGSize(width: CGFloat(count) * width + CGFloat(count - 1) * spacing,
                      height: rows.reduce(0, +) + CGFloat(max(0, rows.count - 1)) * rowSpacing)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout [CGFloat]) {
        var y = bounds.minY
        for (row, start) in stride(from: 0, to: subviews.count, by: count).enumerated() {
            let height = row < cache.count ? cache[row] : 0
            for index in start..<min(start + count, subviews.count) {
                let x = bounds.minX + CGFloat(index - start) * (width + spacing) + width / 2
                subviews[index].place(at: CGPoint(x: x, y: y + height / 2), anchor: .center,
                                      proposal: ProposedViewSize(width: width, height: nil))
            }
            y += height + rowSpacing
        }
    }

    func makeCache(subviews: Subviews) -> [CGFloat] { [] }
}
