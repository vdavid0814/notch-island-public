import AppKit
import CoreText
import Synchronization
import SwiftUI

/// A type setting a widget's text is drawn in: the style's choices, resolved.
nonisolated struct TypeSpec: Hashable, Sendable {
    var points: CGFloat
    var design: FontDesignChoice = .standard
    var weight: FontWeightChoice = .regular
    var width: FontWidthChoice = .standard
    var italic = false
    var monospacedDigits = false
    /// Points between letters.
    var tracking: CGFloat = 0
    var textCase: TextCaseChoice = .asIs

    /// The same type at another size.
    func at(_ points: CGFloat) -> TypeSpec {
        var copy = self
        copy.points = points
        return copy
    }

    /// The kind's own type with the user's choices on top (nil keeps the kind's).
    func applying(_ style: TextStyle) -> TypeSpec {
        var copy = self
        if let design = style.design { copy.design = design }
        if let weight = style.weight { copy.weight = weight }
        if let width = style.width { copy.width = width }
        if let italic = style.italic { copy.italic = italic }
        if let monospacedDigits = style.monospacedDigits { copy.monospacedDigits = monospacedDigits }
        if let tracking = style.tracking { copy.tracking = tracking }
        if let textCase = style.textCase { copy.textCase = textCase }
        return copy
    }

    /// The string as it is drawn (and measured): in its case.
    func cased(_ text: String) -> String {
        switch textCase {
        case .asIs: text
        case .uppercase: text.uppercased()
        case .lowercase: text.lowercased()
        }
    }
}

/// Real fonts for widget text, and what a line of it measures.
///
/// The `NSFont` built here is the one the text is drawn in (`Font(CTFont)`), so what is measured is
/// what is drawn. For the kinds' default type (no width, italic or tracking) `Font(CTFont)` and
/// `Font.system(size:weight:design:)` lay out to the same size (`WidgetFitTests`), so the default
/// look may draw through either.
nonisolated enum WidgetTypography {
    static func nsFont(_ spec: TypeSpec) -> NSFont {
        let base = NSFont.systemFont(ofSize: spec.points, weight: spec.weight.nsWeight, width: spec.width.nsWidth)
        var descriptor = base.fontDescriptor
        if let design = spec.design.systemDesign, let designed = descriptor.withDesign(design) { descriptor = designed }
        if spec.italic { descriptor = descriptor.withSymbolicTraits(descriptor.symbolicTraits.union(.italic)) }
        if spec.monospacedDigits {
            descriptor = descriptor.addingAttributes([.featureSettings: [[
                NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
                NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector,
            ]]])
        }
        return NSFont(descriptor: descriptor, size: spec.points) ?? base
    }

    static func font(_ spec: TypeSpec) -> Font { Font(nsFont(spec) as CTFont) }

    /// How wide `text` is drawn on one line: rounded up to the pixel, plus a pixel (SwiftUI rounds
    /// a text's width up to the pixel too; the pixel more keeps a line that just fits from being cut).
    static func width(_ text: String, _ spec: TypeSpec, scale: CGFloat) -> CGFloat {
        let key = MeasureKey(text: spec.cased(text), spec: spec, scale: scale)
        if let width = widthCache.withLock({ $0[key] }) { return width }
        let width = (typographicWidth(key.text, spec) * scale).rounded(.up) / scale + 1 / scale
        widthCache.withLock { $0[key] = width }
        return width
    }

    /// One line's height as SwiftUI lays it out. SwiftUI places lines on whole points whatever the
    /// display's scale, so each metric is rounded up to the point: over 6–60 pt in every design this
    /// is never less than SwiftUI's line and at most 2 pt more.
    static func lineHeight(_ spec: TypeSpec) -> CGFloat {
        let metrics = lineMetrics(spec)
        return (metrics.ascent * spec.points).rounded(.up) + (metrics.descent * spec.points).rounded(.up)
            + (metrics.leading * spec.points).rounded(.up)
    }

    /// A line's height per point of type, unrounded (the metrics grow in proportion with the size).
    static func lineHeightPerPoint(_ spec: TypeSpec) -> CGFloat {
        let metrics = lineMetrics(spec)
        return metrics.ascent + metrics.descent + metrics.leading
    }

    /// How many lines `text` wraps to in `width`.
    static func lineCount(_ text: String, _ spec: TypeSpec, width: CGFloat) -> Int {
        CFArrayGetCount(CTFrameGetLines(frame(text, spec, width: width)))
    }

    /// `text` wrapped in `width`: how many lines, and how wide the widest is drawn (its trailing
    /// space left out, rounded as `width(_:_:scale:)`).
    static func wrapped(_ text: String, _ spec: TypeSpec, width: CGFloat, scale: CGFloat) -> (lines: Int, width: CGFloat) {
        let lines = CTFrameGetLines(frame(text, spec, width: width)) as! [CTLine]
        let widest = lines.map { CGFloat(CTLineGetTypographicBounds($0, nil, nil, nil) - CTLineGetTrailingWhitespaceWidth($0)) }.max() ?? 0
        return (lines.count, (widest * scale).rounded(.up) / scale + 1 / scale)
    }

    private static func frame(_ text: String, _ spec: TypeSpec, width: CGFloat) -> CTFrame {
        let setter = CTFramesetterCreateWithAttributedString(attributed(spec.cased(text), spec))
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: min(max(width, 1), 100_000), height: 100_000), transform: nil)
        return CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), path, nil)
    }

    /// Unrounded, for estimates (kept with the rounded widths, as scale 0).
    static func referenceWidth(_ text: String, _ spec: TypeSpec) -> CGFloat {
        let key = MeasureKey(text: spec.cased(text), spec: spec, scale: 0)
        if let width = widthCache.withLock({ $0[key] }) { return width }
        let width = typographicWidth(key.text, spec)
        widthCache.withLock { $0[key] = width }
        return width
    }

    /// Unrounded, in the size `spec` gives.
    static func typographicWidth(_ text: String, _ spec: TypeSpec) -> CGFloat {
        CGFloat(CTLineGetTypographicBounds(CTLineCreateWithAttributedString(attributed(text, spec)), nil, nil, nil))
    }

    static let reference: CGFloat = 100

    private static func attributed(_ text: String, _ spec: TypeSpec) -> NSAttributedString {
        var attributes: [NSAttributedString.Key: Any] = [.font: nsFont(spec)]
        if spec.tracking != 0 { attributes[.kern] = spec.tracking }
        return NSAttributedString(string: text, attributes: attributes)
    }

    /// Ascent, descent and leading per point: the same at every size, and whatever the digits,
    /// tracking and case.
    private static func lineMetrics(_ spec: TypeSpec) -> LineMetrics {
        var key = TypeSpec(points: reference)
        (key.design, key.weight, key.width, key.italic) = (spec.design, spec.weight, spec.width, spec.italic)
        if let metrics = metricCache.withLock({ $0[key] }) { return metrics }
        let font = nsFont(key) as CTFont
        let metrics = LineMetrics(ascent: CTFontGetAscent(font) / reference, descent: CTFontGetDescent(font) / reference,
                                  leading: CTFontGetLeading(font) / reference)
        metricCache.withLock { $0[key] = metrics }
        return metrics
    }

    private struct MeasureKey: Hashable {
        var text: String
        var spec: TypeSpec
        var scale: CGFloat
    }

    private struct LineMetrics {
        var ascent: CGFloat
        var descent: CGFloat
        var leading: CGFloat
    }

    private static let widthCache = Mutex(MeasureCache<MeasureKey, CGFloat>())
    private static let metricCache = Mutex(MeasureCache<TypeSpec, LineMetrics>())
}

/// The last 256 measurements, oldest out first.
nonisolated struct MeasureCache<Key: Hashable, Value> {
    static var capacity: Int { 256 }

    private var values: [Key: Value] = [:]
    private var order: [Key] = []
    private var next = 0

    subscript(key: Key) -> Value? {
        get { values[key] }
        set {
            guard let newValue else { return }
            if values.updateValue(newValue, forKey: key) != nil { return }
            if order.count < Self.capacity {
                order.append(key)
            } else {
                values[order[next]] = nil
                order[next] = key
                next = (next + 1) % Self.capacity
            }
        }
    }

    var count: Int { values.count }
}

nonisolated extension FontWeightChoice {
    var nsWeight: NSFont.Weight {
        switch self {
        case .ultraLight: .ultraLight
        case .thin: .thin
        case .light: .light
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        case .black: .black
        }
    }
}

nonisolated extension FontWidthChoice {
    var nsWidth: NSFont.Width {
        switch self {
        case .compressed: .compressed
        case .condensed: .condensed
        case .standard: .standard
        case .expanded: .expanded
        }
    }
}

nonisolated extension FontDesignChoice {
    /// nil: the system font as it is.
    var systemDesign: NSFontDescriptor.SystemDesign? {
        switch self {
        case .standard: nil
        case .rounded: .rounded
        case .serif: .serif
        case .monospaced: .monospaced
        }
    }
}
