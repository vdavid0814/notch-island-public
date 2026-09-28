import Foundation

/// A sum or a unit conversion Siri worked out from the query, shown first in the list the way
/// Spotlight shows it: "12 + 30 * 2 = 72", "10 km in mi = 6.21 mi". Return copies the result.
nonisolated struct AssistantCalculation: Sendable, Hashable {
    /// What was worked out, as typed.
    let expression: String
    /// The result as shown and copied.
    let result: String
}

/// Works out arithmetic and unit conversions typed into Siri, without asking any model.
///
/// A small parser of its own rather than `NSExpression`, which raises an Objective-C exception
/// (a crash) on input it does not like, and Siri parses every keystroke.
nonisolated enum AssistantCalculator {
    static func calculate(_ text: String) -> AssistantCalculation? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 200 else { return nil }
        if let conversion = convert(text) { return conversion }
        return evaluate(text)
    }

    // MARK: Arithmetic

    static func evaluate(_ text: String) -> AssistantCalculation? {
        var parser = Parser(text)
        guard let value = parser.parse(), parser.didOperate, value.isFinite else { return nil }
        return AssistantCalculation(expression: text, result: format(value))
    }

    nonisolated(unsafe) private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.maximumFractionDigits = 10
        formatter.minimumFractionDigits = 0
        return formatter
    }()

    /// Up to ten decimals, without trailing zeros; the user's decimal separator.
    static func format(_ value: Double) -> String {
        if value != 0, abs(value) >= 1e15 || abs(value) < 1e-9 {
            return String(format: "%.10g", value)
        }
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private struct Parser {
        private let tokens: [Token]
        private var index = 0
        /// An operator or function was used: a bare number is not a calculation.
        private(set) var didOperate = false

        enum Token: Equatable {
            case number(Double)
            case name(String)
            case symbol(Character)
        }

        init(_ text: String) {
            tokens = Self.tokenize(text) ?? []
        }

        mutating func parse() -> Double? {
            guard !tokens.isEmpty, let value = expression(), index == tokens.count else { return nil }
            return value
        }

        private static func tokenize(_ text: String) -> [Token]? {
            var tokens: [Token] = []
            let chars = Array(text)
            var i = 0
            while i < chars.count {
                let c = chars[i]
                if c.isWhitespace { i += 1; continue }
                if c.isNumber || c == "." || c == "," {
                    var literal = ""
                    while i < chars.count, chars[i].isNumber || chars[i] == "." || chars[i] == "," || chars[i] == "_" {
                        if chars[i] != "_" { literal.append(chars[i] == "," ? "." : chars[i]) }
                        i += 1
                    }
                    guard literal.filter({ $0 == "." }).count <= 1, let value = Double(literal) else { return nil }
                    tokens.append(.number(value))
                    continue
                }
                // "3 x 4", "3x4": x between numbers is a times sign, not a name.
                if c == "x" || c == "X", case .number = tokens.last,
                   let next = chars[(i + 1)...].first(where: { !$0.isWhitespace }), next.isNumber || next == "(" {
                    tokens.append(.symbol("*"))
                    i += 1
                    continue
                }
                if c.isLetter || c == "π" {
                    var name = ""
                    while i < chars.count, chars[i].isLetter || chars[i] == "π" { name.append(chars[i]); i += 1 }
                    tokens.append(.name(name.lowercased()))
                    continue
                }
                switch c {
                case "+", "-", "−", "*", "×", "·", "/", "÷", ":", "^", "%", "(", ")", "!":
                    let normal: Character = switch c {
                    case "−": "-"
                    case "×", "·": "*"
                    case "÷", ":": "/"
                    default: c
                    }
                    tokens.append(.symbol(normal))
                    i += 1
                default:
                    return nil
                }
            }
            return tokens
        }

        private var current: Token? { index < tokens.count ? tokens[index] : nil }

        private mutating func take(_ symbol: Character) -> Bool {
            guard current == .symbol(symbol) else { return false }
            index += 1
            return true
        }

        /// Sums; "200 + 10%" adds ten per cent of 200, as a calculator does.
        private mutating func expression() -> Double? {
            guard var value = term() else { return nil }
            while true {
                let adds: Bool
                if take("+") { adds = true } else if take("-") { adds = false } else { break }
                didOperate = true
                let start = index
                guard let (right, isPercent) = percentTerm(start: start) else { return nil }
                let amount = isPercent ? value * right : right
                value = adds ? value + amount : value - amount
            }
            return value
        }

        /// A term, and whether it was a bare percentage ("10%").
        private mutating func percentTerm(start: Int) -> (Double, Bool)? {
            guard let value = term() else { return nil }
            let isPercent = index - start == 2 && tokens[index - 1] == .symbol("%")
            return (value, isPercent)
        }

        private mutating func term() -> Double? {
            guard var value = power() else { return nil }
            while true {
                if take("*") {
                    didOperate = true
                    guard let right = power() else { return nil }
                    value *= right
                } else if take("/") {
                    didOperate = true
                    guard let right = power() else { return nil }
                    value /= right
                } else if case .symbol("(") = current, let right = power() {
                    // "2(3 + 4)"
                    didOperate = true
                    value *= right
                } else if case .name = current, let right = power() {
                    // "2pi", "3 sqrt 4"
                    didOperate = true
                    value *= right
                } else {
                    break
                }
            }
            return value
        }

        private mutating func power() -> Double? {
            guard let base = unary() else { return nil }
            if take("^") {
                didOperate = true
                guard let exponent = power() else { return nil }
                return pow(base, exponent)
            }
            return base
        }

        private mutating func unary() -> Double? {
            if take("-") {
                guard let value = unary() else { return nil }
                return -value
            }
            if take("+") { return unary() }
            return postfix()
        }

        private mutating func postfix() -> Double? {
            guard var value = primary() else { return nil }
            while true {
                if take("%") {
                    didOperate = true
                    value /= 100
                } else if take("!") {
                    didOperate = true
                    guard value >= 0, value <= 170, value == value.rounded() else { return nil }
                    value = (1...max(1, Int(value))).reduce(1.0) { $0 * Double($1) }
                } else {
                    break
                }
            }
            return value
        }

        private mutating func primary() -> Double? {
            switch current {
            case .number(let value):
                index += 1
                return value
            case .symbol("("):
                index += 1
                guard let value = expression(), take(")") else { return nil }
                return value
            case .name(let name):
                index += 1
                // A constant alone is not a sum ("e" is the start of Excel).
                if let constant = Self.constants[name] { return constant }
                guard let function = Self.functions[name] else { return nil }
                didOperate = true
                guard let argument = take("(") ? parenthesized() : power() else { return nil }
                return function(argument)
            default:
                return nil
            }
        }

        private mutating func parenthesized() -> Double? {
            guard let value = expression(), take(")") else { return nil }
            return value
        }

        static let constants: [String: Double] = ["pi": .pi, "π": .pi, "e": M_E, "tau": 2 * .pi]
        static let functions: [String: @Sendable (Double) -> Double] = [
            "sqrt": { $0.squareRoot() }, "gyok": { $0.squareRoot() }, "cbrt": { cbrt($0) },
            "sin": { sin($0) }, "cos": { cos($0) }, "tan": { tan($0) }, "tg": { tan($0) },
            "asin": { asin($0) }, "acos": { acos($0) }, "atan": { atan($0) },
            "ln": { log($0) }, "log": { log10($0) }, "lg": { log10($0) }, "exp": { exp($0) },
            "abs": { abs($0) }, "round": { $0.rounded() }, "floor": { floor($0) }, "ceil": { ceil($0) },
        ]
    }

    // MARK: Units

    /// "10 km in mi", "70 kg to lb", "100 f to c", "5 gb in mb" (to, in, as, =, ->, →, ban/ben).
    static func convert(_ text: String) -> AssistantCalculation? {
        let lowered = text.lowercased()
        let pattern = #"^\s*(-?[0-9]+(?:[.,][0-9]+)?)\s*([a-z°/µ²³ ]+?)\s+(?:in|to|as|into|=|->|→|ba|be|ban|ben)\s+([a-z°/µ²³ ]+?)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: lowered, range: NSRange(lowered.startIndex..., in: lowered)),
              let numberRange = Range(match.range(at: 1), in: lowered),
              let fromRange = Range(match.range(at: 2), in: lowered),
              let toRange = Range(match.range(at: 3), in: lowered),
              let value = Double(lowered[numberRange].replacingOccurrences(of: ",", with: ".")),
              let from = unit(String(lowered[fromRange])),
              let to = unit(String(lowered[toRange])),
              type(of: from) == type(of: to), from != to else { return nil }
        let converted = Measurement(value: value, unit: from).converted(to: to).value
        guard converted.isFinite else { return nil }
        return AssistantCalculation(expression: text, result: "\(format(converted)) \(to.symbol)")
    }

    private static func unit(_ name: String) -> Dimension? {
        let name = name.trimmingCharacters(in: .whitespaces)
        return units[name] ?? (name.hasSuffix("s") ? units[String(name.dropLast())] : nil)
    }

    private static let units: [String: Dimension] = {
        var table: [String: Dimension] = [:]
        func add(_ unit: Dimension, _ names: String...) { for name in names { table[name] = unit } }
        add(UnitLength.kilometers, "km", "kilometer", "kilometre", "kilométer")
        add(UnitLength.meters, "m", "meter", "metre", "méter")
        add(UnitLength.centimeters, "cm", "centimeter", "centimetre", "centiméter")
        add(UnitLength.millimeters, "mm", "millimeter", "millimetre", "milliméter")
        add(UnitLength.miles, "mi", "mile", "mérföld")
        add(UnitLength.yards, "yd", "yard")
        add(UnitLength.feet, "ft", "foot", "feet", "láb")
        add(UnitLength.inches, "in", "inch", "inches", "hüvelyk", "\"")
        add(UnitLength.nauticalMiles, "nmi", "nautical mile")
        add(UnitMass.kilograms, "kg", "kilogram", "kilo")
        add(UnitMass.grams, "g", "gram", "gramm")
        add(UnitMass.milligrams, "mg", "milligram")
        add(UnitMass.pounds, "lb", "lbs", "pound", "font")
        add(UnitMass.ounces, "oz", "ounce", "uncia")
        add(UnitMass.stones, "st", "stone")
        add(UnitMass.metricTons, "t", "ton", "tonne", "tonna")
        add(UnitTemperature.celsius, "c", "°c", "celsius")
        add(UnitTemperature.fahrenheit, "f", "°f", "fahrenheit")
        add(UnitTemperature.kelvin, "k", "kelvin")
        add(UnitVolume.liters, "l", "liter", "litre")
        add(UnitVolume.deciliters, "dl", "deciliter")
        add(UnitVolume.milliliters, "ml", "milliliter", "millilitre")
        add(UnitVolume.gallons, "gal", "gallon")
        add(UnitVolume.cups, "cup")
        add(UnitVolume.fluidOunces, "fl oz", "floz")
        add(UnitSpeed.kilometersPerHour, "km/h", "kmh", "kph")
        add(UnitSpeed.milesPerHour, "mph")
        add(UnitSpeed.metersPerSecond, "m/s")
        add(UnitSpeed.knots, "kn", "knot")
        add(UnitDuration.hours, "h", "hr", "hour", "óra")
        add(UnitDuration.minutes, "min", "minute", "perc")
        add(UnitDuration.seconds, "s", "sec", "second", "másodperc")
        add(UnitInformationStorage.bytes, "b", "byte")
        add(UnitInformationStorage.kilobytes, "kb", "kilobyte")
        add(UnitInformationStorage.megabytes, "mb", "megabyte")
        add(UnitInformationStorage.gigabytes, "gb", "gigabyte")
        add(UnitInformationStorage.terabytes, "tb", "terabyte")
        add(UnitArea.squareMeters, "m2", "m²", "sqm")
        add(UnitArea.squareKilometers, "km2", "km²")
        add(UnitArea.squareFeet, "ft2", "ft²", "sqft")
        add(UnitArea.hectares, "ha", "hectare", "hektár")
        add(UnitArea.acres, "acre")
        add(UnitEnergy.kilocalories, "kcal", "calorie", "kalória")
        add(UnitEnergy.kilojoules, "kj", "kilojoule")
        return table
    }()
}
