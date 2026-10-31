import SwiftUI

/// What a readout shows now: its value, the value's caption and its symbol.
struct WidgetReading: Equatable {
    var value: String
    var caption: String
    var symbol: String
    /// The widest value it may come to show: sized for it, so the type does not jump as the
    /// reading changes.
    var widest: String?

    init(_ value: String, caption: String, symbol: String, widest: String? = nil) {
        self.value = value
        self.caption = caption
        self.symbol = symbol
        self.widest = widest
    }
}

/// A readout, the base of every widget that shows one value (World Clock first): on one row its
/// symbol, the value and the caption side by side, the caption only while it fits; two rows tall,
/// the symbol and the caption over a large value. The value and the caption are texts and the
/// symbol a button in Customize, each moved and styled on its own.
struct ReadingWidget: View {
    let widget: IslandWidget
    let size: CGSize
    let reading: WidgetReading

    static func isTall(_ inner: CGSize) -> Bool { inner.height >= 56 }

    /// The value's size: never wider than its widest reading allows.
    static func valuePoints(_ widget: IslandWidget, reading: WidgetReading, inner: CGSize) -> CGFloat {
        let tall = isTall(inner)
        let symbolRoom = !tall && widget.shows(.symbol) ? symbolPoints(inner: inner) * 1.3 + 6 : 0
        let wide = ((reading.widest ?? reading.value) as NSString).size(withAttributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 100, weight: .semibold),
        ]).width / 100
        let fit = wide > 0 ? (inner.width - 8 - symbolRoom) / wide : 40
        return max(min(WidgetMetrics.points(tall ? inner.height * 0.6 : inner.height, ratio: 0.62, min: 12, max: 40), fit.rounded(.down)), 9)
    }

    static func captionPoints(inner: CGSize) -> CGFloat {
        WidgetMetrics.points(inner.height, ratio: isTall(inner) ? 0.16 : 0.34, min: 9, max: 13)
    }

    static func symbolPoints(inner: CGSize) -> CGFloat {
        WidgetMetrics.points(inner.height, ratio: isTall(inner) ? 0.18 : 0.4, min: 9, max: 18)
    }

    var body: some View {
        let tall = Self.isTall(size)
        let valuePoints = Self.valuePoints(widget, reading: reading, inner: size)
        let captionPoints = Self.captionPoints(inner: size), symbolPoints = Self.symbolPoints(inner: size)
        // The value in rounded figures unless Customize sets another typeface.
        let shown = widget.withOwnDesign(.rounded, for: .value)
        let value = WidgetLabel(id: .value, text: reading.value, widget: shown, size: valuePoints, weight: .semibold,
                                isSecondary: false) {
            Text(reading.value)
                .font(.system(size: valuePoints, weight: .semibold, design: .rounded).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .movableElement(.value, of: widget)
        let caption = WidgetLabel(id: .label, text: reading.caption, widget: widget, size: captionPoints, weight: .medium,
                                  isSecondary: true) {
            Text(reading.caption)
                .font(.system(size: captionPoints, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .movableElement(.label, of: widget)
        let showsCaption = widget.shows(.label), showsSymbol = widget.shows(.symbol)
        Group {
            if tall {
                VStack(alignment: .leading, spacing: 2) {
                    if showsSymbol || showsCaption {
                        HStack(spacing: 4) {
                            if showsSymbol { symbol(points: symbolPoints) }
                            if showsCaption { caption }
                        }
                    }
                    value
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            } else {
                // The caption beside the value only while it fits there.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) {
                        if showsSymbol { symbol(points: symbolPoints) }
                        value.fixedSize()
                        if showsCaption { caption.fixedSize() }
                        Spacer(minLength: 0)
                    }
                    HStack(spacing: 6) {
                        if showsSymbol { symbol(points: symbolPoints) }
                        value
                        Spacer(minLength: 0)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(reading.caption): \(reading.value)"))
    }

    /// The symbol: quiet, or as Customize styled it (as Now Playing's buttons are).
    @ViewBuilder private func symbol(points: CGFloat) -> some View {
        let look = widget.buttonLook(of: .symbol)
        Group {
            if look == .plain {
                Image(systemName: reading.symbol)
                    .font(.system(size: points, weight: .semibold))
                    .foregroundStyle(.secondary)
            } else {
                WidgetButtonLabel(look: look, symbol: reading.symbol, points: points)
            }
        }
        .movableElement(.symbol, of: widget)
    }
}

/// The time in another city: the city's time, its name (or the user's caption, and a day before or
/// after where it is one) and a globe. Ticks once a minute, on the minute, only while shown.
struct WorldClockWidget: View {
    let widget: IslandWidget
    let size: CGSize

    @Environment(\.widgetDate) private var fixedDate
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var home

    var body: some View {
        if let fixedDate {
            ReadingWidget(widget: widget, size: size, reading: Self.reading(widget.config, at: fixedDate, locale: locale, home: home))
        } else {
            PanelTimelineView(.everyMinute) { context in
                ReadingWidget(widget: widget, size: size, reading: Self.reading(widget.config, at: context.date, locale: locale, home: home))
            }
        }
    }

    /// Cupertino's, until a city is set.
    static let defaultZone = "America/Los_Angeles"

    /// The city a time zone is named after ("Europe/Budapest" → "Budapest").
    static func city(_ zone: TimeZone) -> String {
        zone.identifier.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? zone.identifier
    }

    static func zone(_ config: WidgetConfig) -> TimeZone {
        config.timeZone.flatMap(TimeZone.init(identifier:)) ?? TimeZone(identifier: defaultZone) ?? .current
    }

    /// The caption: the user's, else the city's name (Cupertino's own), and "Tomorrow" or
    /// "Yesterday" where its day is not this one.
    static func caption(_ config: WidgetConfig, at date: Date, home: TimeZone) -> String {
        let zone = zone(config)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = home
        let here = calendar.dateComponents([.year, .month, .day], from: date)
        calendar.timeZone = zone
        let away = calendar.dateComponents([.year, .month, .day], from: date)
        let days = calendar.dateComponents([.day], from: here, to: away).day ?? 0
        let name = config.label ?? (config.timeZone == nil ? "Cupertino" : city(zone))
        return days == 0 ? name : days > 0 ? String(localized: "\(name) · Tomorrow") : String(localized: "\(name) · Yesterday")
    }

    static func reading(_ config: WidgetConfig, at date: Date, locale: Locale, home: TimeZone) -> WidgetReading {
        var style = Date.FormatStyle.dateTime.hour().minute()
        style.timeZone = zone(config)
        style.locale = locale
        // As wide as the widest time ("22:58" there), so the value does not jump as the minutes go by.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone(config)
        let widest = calendar.date(bySettingHour: 22, minute: 58, second: 0, of: date)?.formatted(style)
        return WidgetReading(date.formatted(style), caption: caption(config, at: date, home: home), symbol: "globe", widest: widest)
    }
}
