import Foundation

/// How a widget reads its numbers, times and dates: its style's formats (`FormatStyle`), in the
/// view's locale and time zone. Every field nil reads as the kind always did.
nonisolated struct WidgetFormat: Equatable, Sendable {
    var style: FormatStyle
    var locale: Locale
    var timeZone: TimeZone

    init(_ style: FormatStyle, locale: Locale = .autoupdatingCurrent, timeZone: TimeZone = .autoupdatingCurrent) {
        self.style = style
        self.locale = locale
        self.timeZone = timeZone
    }

    /// The locale with the style's clock (12 or 24 hours) on it.
    var clockLocale: Locale {
        guard let clock24Hour = style.clock24Hour else { return locale }
        var components = Locale.Components(locale: locale)
        components.hourCycle = clock24Hour ? .zeroToTwentyThree : .oneToTwelve
        return Locale(components: components)
    }

    /// Hours and minutes (and seconds when the style shows them).
    var time: Date.FormatStyle {
        let base = Date.FormatStyle(locale: clockLocale, timeZone: timeZone).hour().minute()
        return style.showsSeconds == true ? base.second() : base
    }

    func time(_ date: Date) -> String { date.formatted(time) }

    /// The date in the style's template ("EEEE d MMMM"), or nil to let the kind choose.
    func date(_ date: Date) -> String? {
        guard let template = style.dateTemplate else { return nil }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }

    /// "62%", with the style's decimals.
    func percent(_ fraction: Double) -> String {
        let decimals = style.percentDecimals ?? 0
        return fraction.formatted(.percent.precision(.fractionLength(decimals)).locale(locale))
    }

    /// A span of time in the style's duration style (narrow by default: "5h 40m").
    func duration(minutes: Int) -> String {
        let seconds = Duration.seconds(minutes * 60)
        switch style.durationStyle ?? .narrow {
        case .positional: return seconds.formatted(.time(pattern: .hourMinute))
        case .abbreviated: return seconds.formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
        case .narrow: return seconds.formatted(.units(allowed: [.hours, .minutes], width: .narrow))
        }
    }

    /// Degrees Celsius in the style's unit.
    func temperature(celsius: Double) -> String {
        let measurement = Measurement(value: celsius, unit: UnitTemperature.celsius)
        let unit: UnitTemperature = style.temperature == .fahrenheit ? .fahrenheit
            : style.temperature == .celsius ? .celsius : (locale.measurementSystem == .us ? .fahrenheit : .celsius)
        return measurement.converted(to: unit).formatted(.measurement(width: .narrow, usage: .asProvided,
                                                                      numberFormatStyle: .number.precision(.fractionLength(0)))
            .locale(locale))
    }
}
