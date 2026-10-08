import Foundation

// What Spotlight's calculator answers beyond sums and units: the time somewhere else, a time moved
// from one city to another, days from now and days until a date, and — once the user turns them
// on — currencies. All worked out here from the query alone; only the currencies' rates come from
// outside (`CurrencyRates`), and never the query.

nonisolated extension AssistantCalculator {
    // MARK: Time zones

    /// "time in tokyo", "tokyo time", "15:00 london in budapest", "3pm in new york".
    static func worldTime(_ text: String, context: Context) -> AssistantCalculation? {
        let lowered = text.lowercased()
        // The time now, somewhere.
        for pattern in [#"^(?:what(?:'s| is) the )?(?:current )?time (?:in|at) (.+?)\??$"#, #"^(.+?) time$"#, #"^idő (.+?)$"#] {
            if let place = firstGroup(pattern, in: lowered), let zone = zone(named: place) {
                return AssistantCalculation(expression: text, result: clock(context.now, in: zone, context: context, comparedTo: context.timeZone))
            }
        }
        // A time of day moved from one place to another ("15:00 london in budapest"), or from here
        // ("15:00 in tokyo").
        let pattern = #"^(\d{1,2})(?::(\d{2}))?\s*(am|pm)?(?:\s+(.+?))?\s+(?:in|to)\s+(.+?)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: lowered, range: NSRange(lowered.startIndex..., in: lowered)) else { return nil }
        func group(_ index: Int) -> String? { Range(match.range(at: index), in: lowered).map { String(lowered[$0]) } }
        guard var hour = group(1).flatMap(Int.init), let target = group(5).flatMap(zone(named:)) else { return nil }
        let minute = group(2).flatMap(Int.init) ?? 0
        // A bare number is a time only with a colon or am/pm ("5 in tokyo" is nothing).
        guard group(2) != nil || group(3) != nil else { return nil }
        if let half = group(3) {
            guard (1...12).contains(hour) else { return nil }
            hour = hour % 12 + (half == "pm" ? 12 : 0)
        }
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        let source = group(4).map { zone(named: $0) } ?? context.timeZone
        guard let source, source != target else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = source
        var parts = calendar.dateComponents([.year, .month, .day], from: context.now)
        parts.hour = hour
        parts.minute = minute
        guard let moment = calendar.date(from: parts) else { return nil }
        return AssistantCalculation(expression: text, result: clock(moment, in: target, context: context, comparedTo: source))
    }

    /// "16:41", with the day when it is another one there.
    private static func clock(_ date: Date, in zone: TimeZone, context: Context, comparedTo home: TimeZone) -> String {
        let time = date.formatted(Date.FormatStyle(locale: context.locale, timeZone: zone).hour().minute())
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = home
        let here = calendar.dateComponents([.year, .month, .day], from: date)
        calendar.timeZone = zone
        let there = calendar.dateComponents([.year, .month, .day], from: date)
        let days = Calendar(identifier: .gregorian).dateComponents([.day], from: here, to: there).day ?? 0
        // Universal time by its own name (the system files it under GMT).
        let city = zone.identifier == "GMT" ? "UTC" : Self.city(zone)
        switch days {
        case 0: return "\(time) \(city)"
        case 1...: return String(localized: "\(time) \(city), the next day")
        default: return String(localized: "\(time) \(city), the day before")
        }
    }

    /// The city a time zone is named after ("Europe/Budapest" → "Budapest").
    private static func city(_ zone: TimeZone) -> String {
        zone.identifier.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? zone.identifier
    }

    /// A time zone by its city ("tokyo", "new york"), a common short name ("nyc", "la") or an
    /// abbreviation ("utc", "cet", "pst").
    static func zone(named name: String) -> TimeZone? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !name.isEmpty, name.count <= 40 else { return nil }
        if let identifier = zoneAliases[name] ?? zonesByCity[name] { return TimeZone(identifier: identifier) }
        if name.count <= 5, let zone = TimeZone(abbreviation: name.uppercased()) { return zone }
        return nil
    }

    private static let zonesByCity: [String: String] = {
        var table: [String: String] = [:]
        for identifier in TimeZone.knownTimeZoneIdentifiers {
            guard let city = identifier.split(separator: "/").last else { continue }
            let name = city.replacingOccurrences(of: "_", with: " ").lowercased()
            // The first one wins ("America/Indiana/Knox" does not take a city's name from another).
            if table[name] == nil { table[name] = identifier }
        }
        return table
    }()

    private static let zoneAliases: [String: String] = [
        "nyc": "America/New_York", "ny": "America/New_York", "la": "America/Los_Angeles", "sf": "America/Los_Angeles",
        "san francisco": "America/Los_Angeles", "cupertino": "America/Los_Angeles", "seattle": "America/Los_Angeles",
        "washington": "America/New_York", "boston": "America/New_York", "miami": "America/New_York",
        "beijing": "Asia/Shanghai", "delhi": "Asia/Kolkata", "new delhi": "Asia/Kolkata", "mumbai": "Asia/Kolkata",
        "bangalore": "Asia/Kolkata", "munich": "Europe/Berlin", "frankfurt": "Europe/Berlin", "milan": "Europe/Rome",
        "barcelona": "Europe/Madrid", "geneva": "Europe/Zurich", "tokió": "Asia/Tokyo", "bécs": "Europe/Vienna",
        "párizs": "Europe/Paris", "róma": "Europe/Rome", "prága": "Europe/Prague", "varsó": "Europe/Warsaw",
        "moszkva": "Europe/Moscow", "london": "Europe/London", "uk": "Europe/London", "japan": "Asia/Tokyo",
        "india": "Asia/Kolkata", "china": "Asia/Shanghai", "germany": "Europe/Berlin", "france": "Europe/Paris",
        "hungary": "Europe/Budapest", "utc": "UTC", "gmt": "GMT",
    ]

    // MARK: Dates

    /// "30 days from now", "2 weeks ago", "days until 24 dec", "weeks until 2027-01-01".
    static func dateMath(_ text: String, context: Context) -> AssistantCalculation? {
        let lowered = text.lowercased()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = context.timeZone
        calendar.locale = context.locale

        let shift = #"^(\d{1,5})\s*(day|week|month|year|nap|hét|hónap|év)s?\s+(from now|from today|later|ago|before today|múlva|ezelőtt)$"#
        if let regex = try? NSRegularExpression(pattern: shift),
           let match = regex.firstMatch(in: lowered, range: NSRange(lowered.startIndex..., in: lowered)),
           let count = Range(match.range(at: 1), in: lowered).flatMap({ Int(lowered[$0]) }),
           let unitName = Range(match.range(at: 2), in: lowered).map({ String(lowered[$0]) }),
           let direction = Range(match.range(at: 3), in: lowered).map({ String(lowered[$0]) }) {
            let unit: Calendar.Component = switch unitName {
            case "day", "nap": .day
            case "week", "hét": .weekOfYear
            case "month", "hónap": .month
            default: .year
            }
            let sign = ["ago", "before today", "ezelőtt"].contains(direction) ? -1 : 1
            guard let date = calendar.date(byAdding: unit, value: sign * count, to: context.now) else { return nil }
            let style = Date.FormatStyle(locale: context.locale, calendar: calendar, timeZone: context.timeZone)
                .weekday(.wide).day().month(.wide).year()
            return AssistantCalculation(expression: text, result: date.formatted(style))
        }

        let until = #"^(day|week|month|nap|hét)s? (?:until|till|to|before|since) (.+?)$"#
        if let regex = try? NSRegularExpression(pattern: until),
           let match = regex.firstMatch(in: lowered, range: NSRange(lowered.startIndex..., in: lowered)),
           let unitName = Range(match.range(at: 1), in: lowered).map({ String(lowered[$0]) }),
           let phrase = Range(match.range(at: 2), in: text).map({ String(text[$0]) }),
           let target = date(phrase, context: context, calendar: calendar) {
            let from = calendar.startOfDay(for: context.now), to = calendar.startOfDay(for: target)
            let days = calendar.dateComponents([.day], from: from, to: to).day ?? 0
            let value: Int
            let unit: String
            switch unitName {
            case "week", "hét":
                value = abs(days) / 7
                unit = value == 1 ? String(localized: "week") : String(localized: "weeks")
            case "month":
                value = abs(calendar.dateComponents([.month], from: from, to: to).month ?? 0)
                unit = value == 1 ? String(localized: "month") : String(localized: "months")
            default:
                value = abs(days)
                unit = value == 1 ? String(localized: "day") : String(localized: "days")
            }
            let result = days == 0 ? String(localized: "Today") : days > 0 ? "\(value) \(unit)" : String(localized: "\(value) \(unit) ago")
            return AssistantCalculation(expression: text, result: result)
        }
        return nil
    }

    /// A date as typed ("24 dec", "2026-12-24", "christmas", "next friday"): one without a year is
    /// the next such day.
    static func date(_ phrase: String, context: Context, calendar: Calendar) -> Date? {
        let lowered = phrase.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let named: [String: (month: Int, day: Int)] = ["christmas": (12, 25), "xmas": (12, 25), "karácsony": (12, 25),
                                                     "new year": (1, 1), "new years": (1, 1), "new year's": (1, 1), "újév": (1, 1),
                                                     "halloween": (10, 31), "valentine's day": (2, 14), "valentines": (2, 14)]
        if let day = named[lowered] {
            return calendar.nextDate(after: calendar.startOfDay(for: context.now).addingTimeInterval(-1),
                                     matching: DateComponents(month: day.month, day: day.day), matchingPolicy: .nextTime)
        }
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        let range = NSRange(phrase.startIndex..., in: phrase)
        guard let match = detector.firstMatch(in: phrase, range: range), match.range.length >= range.length - 1, let found = match.date else {
            return nil
        }
        // Without a year the detector takes this one: a day already past means the next one.
        let hasYear = phrase.range(of: #"\d{4}"#, options: .regularExpression) != nil
        if !hasYear, calendar.startOfDay(for: found) < calendar.startOfDay(for: context.now),
           let next = calendar.date(byAdding: .year, value: 1, to: found) {
            return next
        }
        return found
    }

    // MARK: Currencies

    /// "100 usd in eur", "€50 to huf", "20 dollars in forint": nil until the rates are there.
    static func convertCurrency(_ text: String, rates: [String: Double]?) -> AssistantCalculation? {
        guard let query = currencyQuery(text), let rates else { return nil }
        func perEuro(_ code: String) -> Double? { code == "EUR" ? 1 : rates[code] }
        guard let from = perEuro(query.from), let to = perEuro(query.to), from > 0 else { return nil }
        let value = query.amount / from * to
        // Whole amounts as they are, the others to the cent.
        let isWhole = abs(value - value.rounded()) < 0.005
        let formatted = value.formatted(.number.precision(.fractionLength(isWhole || abs(value) >= 1000 ? 0 : 2)).grouping(.automatic))
        return AssistantCalculation(expression: text, result: "\(formatted) \(query.to)")
    }

    /// The query as a currency conversion, whatever the rates: the model fetches them only for one.
    static func currencyQuery(_ text: String) -> (amount: Double, from: String, to: String)? {
        let lowered = text.lowercased()
        let pattern = #"^\s*([€$£¥]|ft)?\s*(-?[0-9]+(?:[.,][0-9]+)?)\s*([a-zó€$£¥ ]*?)\s+(?:in|to|as|into|=|->|→|ba|be|ban|ben)\s+([a-zó€$£¥ ]+?)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: lowered, range: NSRange(lowered.startIndex..., in: lowered)) else { return nil }
        func group(_ index: Int) -> String? {
            Range(match.range(at: index), in: lowered).map { String(lowered[$0]).trimmingCharacters(in: .whitespaces) }.flatMap { $0.isEmpty ? nil : $0 }
        }
        guard let amount = group(2).flatMap({ Double($0.replacingOccurrences(of: ",", with: ".")) }),
              let from = (group(1) ?? group(3)).flatMap(currency(named:)), let to = group(4).flatMap(currency(named:)), from != to else { return nil }
        return (amount, from, to)
    }

    static func currency(named name: String) -> String? {
        let name = name.trimmingCharacters(in: .whitespaces)
        if let code = currencyNames[name] { return code }
        let singular = name.hasSuffix("s") ? String(name.dropLast()) : name
        if let code = currencyNames[singular] { return code }
        return name.count == 3 && CurrencyRates.codes.contains(name.uppercased()) ? name.uppercased() : nil
    }

    private static let currencyNames: [String: String] = [
        "€": "EUR", "euro": "EUR", "$": "USD", "dollar": "USD", "usd": "USD", "buck": "USD", "£": "GBP", "pound": "GBP",
        "font": "GBP", "¥": "JPY", "yen": "JPY", "jen": "JPY", "ft": "HUF", "forint": "HUF", "huf": "HUF", "franc": "CHF",
        "frank": "CHF", "zloty": "PLN", "złoty": "PLN", "koruna": "CZK", "korona": "CZK", "krona": "SEK", "krone": "NOK",
        "yuan": "CNY", "rupee": "INR", "won": "KRW", "lira": "TRY", "real": "BRL", "peso": "MXN", "rand": "ZAR",
        "lej": "RON", "leu": "RON", "dollár": "USD",
    ]
}

/// The ECB's daily euro reference rates, for Spotlight's currency conversions.
///
/// Off by default (Settings ▸ Spotlight). On, the rates are fetched only when a currency
/// conversion is typed, at most once a day, and kept on disk: nothing of the query is ever sent —
/// the request is the same public file for everyone.
actor CurrencyRates {
    static let shared = CurrencyRates()

    /// The currencies the ECB publishes (and the euro they are quoted in).
    nonisolated static let codes: Set<String> = ["EUR", "USD", "JPY", "BGN", "CZK", "DKK", "GBP", "HUF", "PLN", "RON", "SEK", "CHF",
                                                 "ISK", "NOK", "TRY", "AUD", "BRL", "CAD", "CNY", "HKD", "IDR", "ILS", "INR", "KRW",
                                                 "MXN", "MYR", "NZD", "PHP", "SGD", "THB", "ZAR"]
    nonisolated static let source = URL(string: "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml")!
    nonisolated static let lifetime: TimeInterval = 24 * 3600

    private struct Stored: Codable {
        var rates: [String: Double]
        var fetched: Date
    }

    private let fileURL: URL?
    private let fetch: @Sendable () async -> Data?
    private var stored: Stored?
    private var didLoad = false
    private var lastAttempt: Date?

    init(fileURL: URL? = CurrencyRates.defaultFileURL, fetch: @escaping @Sendable () async -> Data? = CurrencyRates.download) {
        self.fileURL = fileURL
        self.fetch = fetch
    }

    nonisolated static var defaultFileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("NotchIsland", isDirectory: true).appendingPathComponent("CurrencyRates.json")
    }

    nonisolated static func download() async -> Data? {
        var request = URLRequest(url: source, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        request.httpShouldHandleCookies = false
        guard let (data, response) = try? await URLSession(configuration: .ephemeral).data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }

    /// The rates: the kept ones while they are under a day old, else fetched (at most one try a
    /// minute); the kept ones again when the fetch fails.
    func rates(now: Date = Date()) async -> [String: Double]? {
        if !didLoad {
            didLoad = true
            if let fileURL, let data = try? Data(contentsOf: fileURL) { stored = try? JSONDecoder().decode(Stored.self, from: data) }
        }
        if let stored, now.timeIntervalSince(stored.fetched) < Self.lifetime { return stored.rates }
        if let lastAttempt, now.timeIntervalSince(lastAttempt) < 60 { return stored?.rates }
        lastAttempt = now
        guard let data = await fetch(), let rates = Self.parse(data), !rates.isEmpty else { return stored?.rates }
        let fresh = Stored(rates: rates, fetched: now)
        stored = fresh
        if let fileURL, let data = try? JSONEncoder().encode(fresh) {
            try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: fileURL, options: .atomic)
        }
        return rates
    }

    /// `<Cube currency='USD' rate='1.0742'/>` lines of the ECB's file.
    nonisolated static func parse(_ data: Data) -> [String: Double]? {
        guard let text = String(data: data, encoding: .utf8),
              let regex = try? NSRegularExpression(pattern: #"currency=['"]([A-Z]{3})['"]\s+rate=['"]([0-9.]+)['"]"#) else { return nil }
        var rates: [String: Double] = [:]
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let code = Range(match.range(at: 1), in: text), let rate = Range(match.range(at: 2), in: text),
                  let value = Double(text[rate]), value > 0 else { continue }
            rates[String(text[code])] = value
        }
        return rates.isEmpty ? nil : rates
    }
}

nonisolated private func firstGroup(_ pattern: String, in text: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), match.numberOfRanges > 1,
          let range = Range(match.range(at: 1), in: text) else { return nil }
    return String(text[range])
}
