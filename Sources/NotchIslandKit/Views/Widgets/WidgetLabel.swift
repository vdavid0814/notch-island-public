import AppKit
import SwiftUI

/// A text part of a widget (Now Playing's title, its artist) as its `TextStyle` sets it.
///
/// The text as the widget sets it (`plain`) still lays the widget out, so restyling one part moves
/// no other; the styled text is set over it from its top-leading corner, in its own box: as wide as
/// the widget gives the part (or the box it was resized to) and as tall as its lines. Letters are
/// never stretched: a larger box holds more text, and what does not fit ends in "…". In
/// Customize's editor the box's free room is filled with dots, so it shows how much it holds.
///
/// With the plain style, outside the editor, it is `plain` alone.
struct WidgetLabel<Plain: View>: View {
    let id: ElementID
    let text: String
    let widget: IslandWidget
    /// The widget's own size and weight for it.
    let size: CGFloat
    let weight: NSFont.Weight
    /// Drawn dimmer than the main text (the artist).
    let isSecondary: Bool
    /// The text in parts, some faded (the timer's units not being set); nil: one text. Joined, they
    /// are `text`.
    var segments: [LabelSegment]?
    /// A box of its own hangs from the text's top-trailing corner, not its top-leading one: a text
    /// at the end of its row (the timer's time) keeps to the widget's corner whatever its box.
    var hangsFromTrailing = false
    /// The widget's own colour for it, where its style leaves the colour at Automatic (the timer's
    /// orange); nil: white, or grey where it is secondary.
    var automaticColor: Color?
    @ViewBuilder let plain: () -> Plain

    @Environment(\.isElementEditing) private var isEditing
    @Environment(\.inkText) private var inkText
    @Environment(\.linePreview) private var linePreview
    @Environment(\.widgetShape) private var widgetShape
    @Environment(AppModel.self) private var model

    var body: some View {
        content.opacity(inkText == nil || inkText == id ? 1 : 0)
    }

    @ViewBuilder private var content: some View {
        let style = widget.textStyle(of: id)
        if style == .plain, !isEditing {
            plain()
        } else {
            // "+ Line": the box grows down by as many lines as the text takes (not in the editor,
            // where it shows its room at its lines).
            // In a box of its own, as tall in the layout as one line at the widget's own size,
            // whatever the text: a long title shrinks its plain line, and moved the parts below.
            LabelLayout(box: style.box, growsDown: style.overflow == .addLines,
                        height: style.box == nil ? nil : NSFont.systemFont(ofSize: size, weight: weight).lineHeight,
                        hangsFromTrailing: hangsFromTrailing) {
                plain().hidden()
                // The part's edges are its background's where it has one (the room around the text
                // included), the text's box where not.
                let insets = style.background?.insets ?? .zero
                styled(style)
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(key: LabelBoxKey.self, value: proxy.frame(in: .named(LabelBoxKey.space))
                                .insetBy(dx: -insets.width, dy: -insets.height))
                        }
                    }
                    .background { background(style.background) }
            }
            .coordinateSpace(.named(LabelBoxKey.space))
        }
    }

    // MARK: The text

    private func styled(_ style: TextStyle) -> some View {
        // As on the island, in the editor too: shrunk, or on more lines.
        let grows = style.overflow == .addLines
        let shrinks = style.overflow == .shrink
        // Shrunk in a box: to the size its lines hold it at, so the dots show the room left there.
        // Tried on more lines in the editor: the size a text that long gets, its room strongly dotted.
        let preview = isEditing && linePreview == id ? LabelFit.preview(text, style: style, size: size, weight: weight) : nil
        let (font, lines) = preview.map { ($0.font, $0.lines) } ?? (shrinks
            ? LabelFit.fitted(text, style: style, size: size, weight: weight)
            : (style.font(size: size, weight: weight), style.lineCount(lineHeight: style.font(size: size, weight: weight).lineHeight)))
        let strongDots = preview != nil
        return Group {
            if style.alignment == .justified {
                JustifiedLayout(spacing: font.spaceWidth, maxLines: grows ? .max : lines, words: Self.words(in: text).count) {
                    ForEach(Array(words(style).enumerated()), id: \.offset) { _, word in
                        decorate(Text(word.text), style, font: font, isFiller: word.isFiller, strong: strongDots)
                    }
                    decorate(Text("…"), style, font: font, isFiller: false)
                }
                .clipped()
            } else {
                let text = decorate(segmented(style), style, font: font, isFiller: false)
                    .lineLimit(grows ? nil : lines)
                    .minimumScaleFactor(shrinks ? style.effectiveMinimumScale : 1)
                    .truncationMode(.tail)
                    .multilineTextAlignment(style.alignment.textAlignment)
                if isEditing, !grows {
                    // The room left, as dots: under the text, after an unseen copy of it at its own
                    // size (where the text fills its lines, or is shrunk, there is none). Centred or
                    // on the right, on the lines below it: dots after it would move it.
                    let after = style.alignment == .leading ? Text("") : Text("\n")
                    ZStack(alignment: style.alignment.frameAlignment) {
                        // Clear in itself: a colour set on the text wins over one set around it.
                        // A break before the dots: glued to the last word, they would take it to the
                        // next line.
                        (decorate(Text(self.text), style, font: font, isFiller: false, isUnseen: true)
                            + after.font(Font(font))
                            + decorate(Text(Self.filler), style, font: font, isFiller: true, strong: strongDots))
                            .lineLimit(lines)
                            .truncationMode(.tail)
                            .multilineTextAlignment(style.alignment.textAlignment)
                        text
                    }
                } else {
                    text
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: style.box == nil || grows ? nil : .infinity, alignment: style.alignment.frameAlignment)
    }

    /// The words, set one by one when justified, and in the editor the dots as short words after them.
    private func words(_ style: TextStyle) -> [(text: String, isFiller: Bool)] {
        let words = Self.words(in: text).map { ($0, false) }
        // On as many lines as it takes: no room to show.
        guard isEditing, style.overflow != .addLines else { return words }
        return words + Array(repeating: ("…", true), count: 180)
    }

    private static func words(in text: String) -> [String] {
        text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
    }

    /// The text, its faded parts in its colour at `LabelSegment.fadedOpacity` (their own colour wins
    /// over the one the whole is set in).
    private func segmented(_ style: TextStyle) -> Text {
        guard let segments, !segments.isEmpty else { return Text(text) }
        let faded = color(style.color).opacity(LabelSegment.fadedOpacity)
        return segments.reduce(Text(verbatim: "")) { joined, segment in
            let part = segment.isFaded ? Text(verbatim: segment.text).foregroundStyle(faded) : Text(verbatim: segment.text)
            return Text("\(joined)\(part)")
        }
    }

    private func decorate(_ text: Text, _ style: TextStyle, font: NSFont, isFiller: Bool, isUnseen: Bool = false,
                          strong: Bool = false) -> Text {
        text
            .font(Font(font))
            .underline(style.isUnderlined && !isFiller, color: isUnseen ? .clear : nil)
            .strikethrough(style.isStruckThrough && !isFiller, color: isUnseen ? .clear : nil)
            .foregroundStyle(isUnseen ? AnyShapeStyle(.clear) : isFiller ? (strong ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
                : color(style.color))
    }

    private func color(_ color: TextStyle.TextColor) -> AnyShapeStyle {
        switch color {
        case .automatic: automaticColor.map { AnyShapeStyle($0) } ?? (isSecondary ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
        case .custom(let rgb): AnyShapeStyle(rgb.color)
        case .artwork: AnyShapeStyle(model.media.artworkColor.map { Color($0) } ?? .islandAccent)
        }
    }

    /// Enough dots for any box: the text's lines cut them off. Each may end a line (a zero-width
    /// space after it), so they fill a line to its end and the text's last word stays where it is.
    private static var filler: String { "\u{200B}" + String(repeating: "…\u{200B}", count: 400) }

    // MARK: The background

    @ViewBuilder private func background(_ background: ElementBackground?) -> some View {
        if let background {
            let fill: AnyShapeStyle = switch background.kind {
            case .plate: AnyShapeStyle(.white.opacity(0.28 * background.effectiveOpacity))
            case .colour: AnyShapeStyle((background.color?.color ?? .islandAccent).opacity(background.effectiveOpacity))
            case .artwork: AnyShapeStyle((model.media.artworkColor.map { Color($0) } ?? .islandAccent)
                .opacity(background.effectiveOpacity))
            }
            // Around the text, not under its edge: a little room on every side, outside its box. Where
            // it reaches two of the widget's edges at a corner, it takes the widget's corner there.
            let insets = background.insets
            GeometryReader { proxy in
                let rect = proxy.frame(in: .named(WidgetShape.space))
                UnevenRoundedRectangle(cornerRadii: Self.radii(of: rect, own: background.radius(height: rect.height), in: widgetShape),
                                       style: .continuous)
                    .fill(fill)
            }
            .padding(.horizontal, -insets.width)
            .padding(.vertical, -insets.height)
        }
    }

    /// Its own radius at every corner, but the widget's at a corner of the widget it fills.
    static func radii(of rect: CGRect, own: CGFloat, in widget: WidgetShape?) -> RectangleCornerRadii {
        guard let widget else { return .uniform(own) }
        let tolerance: CGFloat = 0.5
        let left = rect.minX <= tolerance, top = rect.minY <= tolerance
        let right = rect.maxX >= widget.size.width - tolerance, bottom = rect.maxY >= widget.size.height - tolerance
        return RectangleCornerRadii(topLeading: left && top ? widget.corners.topLeading : own,
                                    bottomLeading: left && bottom ? widget.corners.bottomLeading : own,
                                    bottomTrailing: right && bottom ? widget.corners.bottomTrailing : own,
                                    topTrailing: right && top ? widget.corners.topTrailing : own)
    }
}

/// The size shrunk text is set at in its box: the largest, down to its smallest, at which it takes
/// no more lines than the box holds at that size. Measured, rather than left to `Text`'s
/// `minimumScaleFactor`, so the editor's dots can be set at the same size (`Text` still shrinks it
/// further should its lines break differently).
@MainActor enum LabelFit {
    private struct Key: Hashable {
        let text: String
        let style: TextStyle
        let size: CGFloat
        let weight: CGFloat
        let grows: Bool
    }

    private static var cache: [Key: (font: NSFont, lines: Int)] = [:]

    /// With a box of its own (and `grows`), the letters as large as the box holds the text in, up to
    /// its largest: a title on one line fills the box, one on two lines fills them (the dots after
    /// it). Otherwise as large as its size, shrunk as far as its lines need. Never under its smallest.
    static func fitted(_ text: String, style: TextStyle, size: CGFloat, weight: NSFont.Weight,
                       grows: Bool = true) -> (font: NSFont, lines: Int) {
        let full = style.font(size: size, weight: weight)
        guard let box = style.box else { return (full, style.lineCount(lineHeight: full.lineHeight)) }
        let key = Key(text: text, style: style, size: size, weight: weight.rawValue, grows: grows)
        if let known = cache[key] { return known }
        // Grown no larger than its largest, shrunk no smaller than its smallest (nor than its largest).
        let largest = min(CGFloat(style.maximumSize ?? TextStyle.sizes.upperBound), boxLimit(style, size: size, weight: weight) ?? .infinity)
        var points = grows ? largest : full.pointSize
        let smallest = grows ? style.minimumSize.map { CGFloat($0) } : nil
        // (fitted to a box, never under the smallest a style offers: as its slider shows it)
        let lowest = min(smallest ?? (grows ? max(full.pointSize * style.effectiveMinimumScale, CGFloat(TextStyle.automaticLowest))
                                            : full.pointSize * style.effectiveMinimumScale), points)
        var result: (font: NSFont, lines: Int)
        while true {
            let font = points == full.pointSize ? full : NSFont(descriptor: full.fontDescriptor, size: points) ?? full
            let lines = grows ? boxLines(style, box: box, lineHeight: font.lineHeight) : style.lineCount(lineHeight: font.lineHeight)
            result = (font, max(lines, 1))
            // The largest at which the text fits the lines the box holds then: a one-line title fills
            // the box, a two-line one its two lines.
            if points <= lowest || (lines >= 1 && lineCount(of: text, font: font, width: CGFloat(box.width)) <= lines) { break }
            points = max(points - 0.5, lowest)
        }
        // A handful of labels, each restyled now and then: what is not shown any more goes.
        if cache.count > 64 { cache.removeAll() }
        cache[key] = result
        return result
    }

    /// The largest its letters can be in its box: one line of them as tall as the box (nil without a
    /// box).
    static func boxLimit(_ style: TextStyle, size: CGFloat, weight: NSFont.Weight) -> CGFloat? {
        guard let box = style.box else { return nil }
        let base = style.font(size: size, weight: weight)
        var points = CGFloat(TextStyle.sizes.upperBound)
        while points > CGFloat(TextStyle.sizes.lowerBound) {
            let font = NSFont(descriptor: base.fontDescriptor, size: points) ?? base
            if font.lineHeight <= CGFloat(box.height) + 0.5 { break }
            points -= 0.5
        }
        return points
    }

    /// A text on fewer lines than it may take, tried on more: as many as are set, or (lines following
    /// the box) one more than it takes — those lines, and the size its letters get there: as large as
    /// that many lines fit the box, up to its largest, never under its smallest (where they fit
    /// only smaller, at its smallest). nil where it would look the same: letters that do not fit
    /// themselves to a box, or it takes its lines already.
    static func preview(_ text: String, style: TextStyle, size: CGFloat, weight: NSFont.Weight) -> (font: NSFont, lines: Int)? {
        guard style.overflow == .shrink, let box = style.box else { return nil }
        let fitted = fitted(text, style: style, size: size, weight: weight)
        let used = lineCount(of: text, font: fitted.font, width: CGFloat(box.width))
        let lines = style.linesFillBox ? used + 1 : style.maxLines ?? 1
        guard used < lines else { return nil }
        let full = style.font(size: size, weight: weight)
        let lowest = style.minimumSize.map { CGFloat($0) } ?? full.pointSize * style.effectiveMinimumScale
        var points = min(fitted.font.pointSize, CGFloat(style.maximumSize ?? TextStyle.sizes.upperBound))
        // Offered whenever it takes fewer lines than set: a smallest above the size the lines fit
        // at no longer hides it (it only came once the smallest was lowered).
        while points > lowest {
            let font = NSFont(descriptor: full.fontDescriptor, size: points) ?? full
            if CGFloat(lines) * font.lineHeight <= CGFloat(box.height) + 0.5 { break }
            points = max(points - 0.5, lowest)
        }
        return (NSFont(descriptor: full.fontDescriptor, size: points) ?? full, lines)
    }

    /// The lines a box holds at `lineHeight`: all of them where lines follow it, those set where
    /// they fit.
    private static func boxLines(_ style: TextStyle, box: TextStyle.BoxSize, lineHeight: CGFloat) -> Int {
        let holds = Int((CGFloat(box.height) + 0.5) / max(lineHeight, 1))
        return style.linesFillBox ? holds : min(style.maxLines ?? 1, holds)
    }

    /// The lines `text` takes in `font` at `width`.
    static func lineCount(of text: String, font: NSFont, width: CGFloat) -> Int {
        let height = (text as NSString).boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                                     options: [.usesLineFragmentOrigin], attributes: [.font: font]).height
        return Int((height / font.lineHeight).rounded())
    }
}

/// A part of a label's text, faded or not (`WidgetLabel.segments`).
nonisolated struct LabelSegment: Equatable, Sendable {
    var text: String
    var isFaded = false

    /// How strongly a faded part is drawn.
    static let fadedOpacity = 0.45
}

/// The styled text's box, in its label's own points.
struct LabelBoxKey: PreferenceKey {
    static let space = "widgetLabel"

    static var defaultValue: CGRect? { nil }

    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = nextValue() ?? value
    }
}

/// The plain text sizes the label; the styled one is set from the same corner, as wide as the label
/// is offered (or its box), as tall as its lines (or its box).
private struct LabelLayout: Layout {
    let box: TextStyle.BoxSize?
    /// The box's height is not kept: the text is as tall as its lines.
    let growsDown: Bool
    /// Its height in the layout (nil: the plain text's).
    var height: CGFloat?
    /// The styled text set from the plain one's top-trailing corner.
    var hangsFromTrailing = false

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let plain = subviews.first?.sizeThatFits(proposal) ?? .zero
        return CGSize(width: plain.width, height: height?.rounded(.up) ?? plain.height)
    }

    /// On the plain text's baselines (the title and artist on one line share one).
    func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize,
                           subviews: Subviews, cache: inout ()) -> CGFloat? {
        // Its baselines only: its middle and edges are its own (with a height of its own, a
        // shrunk plain line's middle moved it).
        guard let plain = subviews.first, guide == .firstTextBaseline || guide == .lastTextBaseline else { return nil }
        return bounds.minY + plain.dimensions(in: proposal)[guide]
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        subviews[0].place(at: bounds.origin, proposal: proposal)
        let offered = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? bounds.width
        let width = box.map { CGFloat($0.width) } ?? max(offered, bounds.width)
        let height = growsDown ? nil : box.map { CGFloat($0.height) }
        let origin = hangsFromTrailing ? CGPoint(x: bounds.maxX - width, y: bounds.minY) : bounds.origin
        subviews[1].place(at: origin, anchor: .topLeading, proposal: ProposedViewSize(width: width, height: height))
    }
}

/// Justified text: words laid out in lines, every full line spread to the box's width (the
/// paragraph's last line as it is). Where its words go past `maxLines` the last line ends in its
/// last subview, "…"; what does not fit goes below, where the label clips it. After the first
/// `words` subviews come the editor's dots: set a space apart, never spread, never a reason to cut.
private struct JustifiedLayout: Layout {
    let spacing: CGFloat
    let maxLines: Int
    let words: Int

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? subviews.dropLast().reduce(0) { $0 + $1.sizeThatFits(.unspecified).width + spacing }
        let lines = Self.lines(subviews: subviews, width: width, spacing: spacing)
        let height = lines.prefix(maxLines).reduce(0) { $0 + $1.height }
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let ellipsis = subviews.last else { return }
        let lines = Self.lines(subviews: subviews, width: bounds.width, spacing: spacing)
        // The words' own lines: the dots after them may run past the last.
        let lastWord = words - 1
        let overflows = words > 0 && !lines.prefix(maxLines).contains { $0.indices.contains(lastWord) }
        var y = bounds.minY
        var placed = Set<Int>()
        for (number, line) in lines.prefix(maxLines).enumerated() {
            let isLast = number == min(lines.count, maxLines) - 1
            var indices = line.indices
            if isLast, overflows {
                // Room for "…" after the words that still fit.
                let dots = ellipsis.sizeThatFits(.unspecified).width
                while !indices.isEmpty,
                      indices.reduce(0, { $0 + subviews[$1].sizeThatFits(.unspecified).width }) + CGFloat(indices.count) * spacing + dots > bounds.width {
                    indices.removeLast()
                }
            }
            let widths = indices.map { min(subviews[$0].sizeThatFits(.unspecified).width, bounds.width) }
            let used = widths.reduce(0, +)
            // A full line of words is spread; the paragraph's last line, a cut one and the dots are not.
            let spreads = !isLast && indices.count > 1 && (indices.last ?? 0) < lastWord
            let gap = spreads ? (bounds.width - used) / CGFloat(indices.count - 1) : spacing
            var x = bounds.minX
            for (index, width) in zip(indices, widths) {
                subviews[index].place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                                      proposal: ProposedViewSize(width: width, height: line.height))
                placed.insert(index)
                x += width + gap
            }
            if isLast, overflows {
                ellipsis.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: .unspecified)
                placed.insert(subviews.count - 1)
            }
            y += line.height
        }
        // Out of sight, under the box (clipped).
        for index in subviews.indices where !placed.contains(index) {
            subviews[index].place(at: CGPoint(x: bounds.minX, y: bounds.maxY + 1000), anchor: .topLeading, proposal: .unspecified)
        }
    }

    /// The words (every subview but the last) in lines no wider than `width`.
    private static func lines(subviews: Subviews, width: CGFloat, spacing: CGFloat) -> [(indices: [Int], height: CGFloat)] {
        var lines: [(indices: [Int], height: CGFloat)] = []
        var current: [Int] = [], used: CGFloat = 0, height: CGFloat = 0
        for index in subviews.indices.dropLast() {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.isEmpty ? size.width : used + spacing + size.width
            if !current.isEmpty, needed > width {
                lines.append((current, height))
                current = [index]
                used = size.width
                height = size.height
            } else {
                current.append(index)
                used = needed
                height = max(height, size.height)
            }
        }
        if !current.isEmpty { lines.append((current, height)) }
        return lines
    }
}

extension TextStyle {
    /// The system font at this style's size, weight, design and slant; `size` and `weight` are the
    /// widget's own where the style keeps them.
    /// How far a face without an italic of its own is slanted for one (about the system's 12°).
    static let slant: CGFloat = 0.21

    func font(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let points = CGFloat(self.size ?? Double(size))
        let base = NSFont.systemFont(ofSize: points, weight: isBold ? .bold : weight)
        var descriptor = base.fontDescriptor
        let design: NSFontDescriptor.SystemDesign? = switch self.design {
        case .standard: nil
        case .rounded: .rounded
        case .serif: .serif
        case .monospaced: .monospaced
        }
        if let design, let designed = descriptor.withDesign(design) { descriptor = designed }
        guard isItalic else { return NSFont(descriptor: descriptor, size: points) ?? base }
        let italic = NSFont(descriptor: descriptor.withSymbolicTraits(descriptor.symbolicTraits.union(.italic)), size: points)
        if let italic, italic.fontDescriptor.symbolicTraits.contains(.italic) { return italic }
        // A face with no italic of its own (SF Rounded): slanted, as the system slants one.
        // The matrix carries the size too.
        let slanted = descriptor.addingAttributes([.matrix: AffineTransform(m11: points, m12: 0, m21: points * Self.slant, m22: points,
                                                                            tX: 0, tY: 0)])
        return NSFont(descriptor: slanted, size: points) ?? base
    }
}

extension TextStyle.Alignment {
    var textAlignment: TextAlignment {
        switch self {
        case .leading, .justified: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    var frameAlignment: Alignment {
        switch self {
        case .leading, .justified: .topLeading
        case .center: .top
        case .trailing: .topTrailing
        }
    }
}

extension NSFont {
    /// The height of one of its lines as `Text` sets them (measured: the same at every size and
    /// design, where the layout manager's is a point short at some).
    var lineHeight: CGFloat { ("Ag" as NSString).size(withAttributes: [.font: self]).height }

    /// The width of a space in this font: the gap between justified words at the least.
    var spaceWidth: CGFloat { (" " as NSString).size(withAttributes: [.font: self]).width }
}
