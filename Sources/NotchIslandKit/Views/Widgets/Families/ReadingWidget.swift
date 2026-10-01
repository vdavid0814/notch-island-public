import SwiftUI

/// What a widget that shows one value reads now: the value, its caption and its symbol.
struct WidgetReading: Equatable {
    var value: String
    var caption: String
    var symbol: String
    /// The value's colour when it says something (low, charging); nil is the text's own.
    var tint: Color?
    /// The widest value it may come to show: sized for it, so the type does not jump as the
    /// reading changes.
    var widest: String?
    /// For VoiceOver; nil reads the value and the caption.
    var spoken: String?

    init(_ value: String, caption: String, symbol: String, tint: Color? = nil, widest: String? = nil, spoken: String? = nil) {
        self.value = value
        self.caption = caption
        self.symbol = symbol
        self.tint = tint
        self.widest = widest
        self.spoken = spoken
    }
}

/// One value with its caption and symbol (`ElementSpec.reading`): on one row the symbol, the value
/// and the caption side by side; in a taller widget the caption over the value. Every battery
/// figure, system reading and countdown is one of these — each only says what it reads.
struct ReadingWidget: View {
    let widget: IslandWidget
    let size: CGSize
    let reading: WidgetReading

    @Environment(\.widgetFrameProbe) private var probe
    @Environment(\.widgetStyle) private var style

    /// The value's type (rounded, digits of one width) and the caption's.
    static let valueType = TypeSpec(points: 20, design: .rounded, weight: .semibold, monospacedDigits: true)
    static let captionType = TypeSpec(points: 11, weight: .medium)

    /// The symbol is measured as the kind's own (a thermometer is half as wide as the spec's star).
    static func demands(_ input: PlanInput) -> [ElementDemand] {
        input.demands(types: [.value: valueType.at(20), .label: captionType.at(11)]).map { demand in
            guard demand.id == .symbol else { return demand }
            var demand = demand
            demand.content = .symbol(name: input.spec.symbol, weight: input.style.elements[.symbol]?.symbol.weight ?? .semibold)
            return demand
        }
    }

    var body: some View {
        let showsValue = widget.shows(.value), showsCaption = widget.shows(.label), showsSymbol = widget.shows(.symbol)
        let caption = style.element(.label)?.text.labelOverride ?? reading.caption
        // Over two rows when tall, unless the style's Direction says (Layout ▸ Direction).
        let tall = style.layout.axis.map { $0 == .vertical } ?? (size.height >= 56)
        let spacing = style.layout.spacing.map { CGFloat($0) }
        let inner = size.width - 8
        let lineFit = WidgetType.size(fittingLines: 1, in: tall ? size.height * 0.3 : size.height)
        let symbolFit = tall ? lineFit : WidgetType.size(fittingLines: 1, in: size.height) * 0.9
        let symbolSize = style.symbolPoints(.symbol, auto: WidgetType.fitted(
            WidgetType.points(size.height, ratio: tall ? 0.18 : 0.4, min: 9, max: 18), fit: symbolFit, widget.size(of: .symbol), floor: 8),
                                            fit: symbolFit)
        // The value takes what the symbol (and, on one row, nothing else: the caption gives way) leaves.
        let valueRoom = tall ? inner : inner - (showsSymbol ? symbolSize * 1.3 + 6 : 0)
        let valueFit = min(WidgetType.size(fitting: reading.widest ?? reading.value, in: valueRoom, weight: .semibold, rounded: true,
                                           monospacedDigits: true),
                           WidgetType.size(fittingLines: 1, in: tall ? size.height - (showsCaption || showsSymbol ? size.height * 0.3 + 2 : 0)
                                                                     : size.height) * 1.05)
        let valueSize = style.textPoints(.value, auto: WidgetType.fitted(
            WidgetType.points(tall ? size.height * 0.6 : size.height, ratio: 0.62, min: 12, max: 40), fit: valueFit,
            widget.size(of: .value), floor: 10), fit: valueFit)
        let valueType = Self.valueType.at(valueSize)
        // The caption: in a tall widget on its own line (beside the symbol); on one row in what the
        // value leaves, and left out where not even its smallest type fits there.
        let beside = inner - (showsSymbol ? symbolSize * 1.3 + 6 : 0)
            - (showsValue ? WidgetTypography.width(reading.widest ?? reading.value, style.drawnType(.value, valueType), scale: 2) + 6 : 0)
        let captionFit = min(lineFit, WidgetType.size(fitting: caption, in: tall ? inner - (showsSymbol ? symbolSize * 1.3 + 4 : 0) : beside,
                                                      weight: .medium))
        let captionFits = captionFit >= Self.smallestCaption
        let captionSize = style.textPoints(.label, auto: min(WidgetType.fitted(
            WidgetType.points(size.height, ratio: tall ? 0.16 : 0.34, min: 9, max: 13), fit: captionFit, widget.size(of: .label), floor: 8), captionFit),
                                           fit: captionFit)
        let captionType = Self.captionType.at(captionSize)
        // On one row, a caption the style draws wider than its plain letters (more space between
        // them, Expanded, capitals) is measured as drawn: drawn whole beside the value, it pushed
        // the value and the symbol out of the widget. One no wider than plainly fits as measured.
        let hasCaptionRoom = captionFits && (tall || style.element(.label) == nil
            || WidgetTypography.width(caption, style.drawnType(.label, captionType), scale: 2)
                <= max(beside, WidgetTypography.width(caption, captionType, scale: 2)) + 0.5)

        let value = Text(reading.value)
            .widgetTextElement(.value, valueType, fit: valueFit, in: style, probe: probe)
            .foregroundStyle(reading.tint.map(AnyShapeStyle.init) ?? AnyShapeStyle(.primary))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .contentTransition(.numericText())
        let captionText = Text(caption)
            .widgetTextElement(.label, captionType, fit: captionFit, in: style, probe: probe)
            .foregroundStyle(.secondary)
            .lineLimit(style.element(.label)?.text.lineLimit ?? 1)
        let symbol = Image(systemName: reading.symbol)
            .widgetSymbolElement(.symbol, reading.symbol, points: symbolSize, weight: .semibold, fit: symbolFit, in: style, probe: probe)
            .foregroundStyle(.secondary)
        Group {
            if tall {
                VStack(alignment: stackAlignment.horizontal, spacing: spacing ?? 2) {
                    if showsSymbol || (showsCaption && hasCaptionRoom) {
                        HStack(spacing: 4) {
                            if showsSymbol { symbol }
                            if showsCaption, hasCaptionRoom { captionText }
                        }
                    }
                    if showsValue { value }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: style.layout.alignment?.alignment ?? .bottomLeading)
            } else {
                HStack(alignment: stackAlignment.vertical, spacing: spacing ?? 6) {
                    // The row's slack on the side the alignment leaves free (the value never takes it).
                    if stackAlignment.horizontal != .leading { Spacer(minLength: 0) }
                    if showsSymbol { symbol }
                    if showsValue { value.layoutPriority(1) }
                    if showsCaption, hasCaptionRoom { captionText.fixedSize() }
                    if stackAlignment.horizontal != .trailing { Spacer(minLength: 0) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: style.layout.alignment?.alignment ?? .leading)
            }
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(reading.spoken ?? "\(caption): \(reading.value)"))
    }

    /// The style's alignment of the lines (Layout ▸ Alignment), the kind's leading otherwise.
    private var stackAlignment: Alignment { style.layout.alignment?.alignment ?? .leading }

    /// Below this the caption is left out rather than drawn.
    static let smallestCaption: CGFloat = 8.5
}

/// One element of a reading on its own (a custom layout), at the size the layout plans.
struct ReadingElement: View {
    let id: ElementID
    let reading: WidgetReading

    @Environment(\.widgetPlan) private var plan
    @Environment(\.widgetStyle) private var style

    var body: some View {
        let planned = plan?.elements[id]
        let alignment = style.element(id)?.text.alignment?.frameAlignment ?? .leading
        switch id {
        case .value:
            Text(reading.value)
                .widgetText(.value, ReadingWidget.valueType.at(planned?.points ?? 16), in: style)
                .foregroundStyle(reading.tint.map(AnyShapeStyle.init) ?? AnyShapeStyle(.primary))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
        case .label:
            Text(style.element(.label)?.text.labelOverride ?? reading.caption)
                .widgetText(.label, ReadingWidget.captionType.at(planned?.points ?? 11), in: style)
                .foregroundStyle(.secondary)
                .lineLimit(style.element(.label)?.text.lineLimit ?? 1)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
        case .symbol:
            Image(systemName: reading.symbol)
                .widgetSymbol(.symbol, points: planned?.points ?? 12, weight: .semibold, in: style)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        default:
            EmptyView()
        }
    }
}
