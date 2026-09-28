import Foundation
import Testing
@testable import NotchIslandKit

@Suite struct AssistantCalculatorTests {
    private func result(_ text: String) -> String? {
        AssistantCalculator.calculate(text)?.result
    }

    private func number(_ text: String) -> Double? {
        result(text).flatMap { Double($0.replacingOccurrences(of: ",", with: ".")) }
    }

    @Test func arithmetic() {
        #expect(number("2+2") == 4)
        #expect(number("12 + 30 * 2") == 72)
        #expect(number("(1 + 2) * 3") == 9)
        #expect(number("2^10") == 1024)
        #expect(number("7 / 2") == 3.5)
        #expect(number("3 x 4") == 12)
        #expect(number("3×4") == 12)
        #expect(number("10 ÷ 4") == 2.5)
        #expect(number("-5 + 2") == -3)
        #expect(number("2(3 + 4)") == 14)
        #expect(number("5!") == 120)
        #expect(number("1,5 * 2") == 3)
    }

    @Test func percentages() {
        #expect(number("200 + 10%") == 220)
        #expect(number("200 - 25%") == 150)
        #expect(number("50% * 80") == 40)
    }

    @Test func functions() {
        #expect(number("sqrt(16)") == 4)
        #expect(number("sqrt 9 + 1") == 4)
        #expect(number("2pi")! > 6.28)
    }

    /// Plain searches are not sums: a word, a bare number, a constant, an app's name.
    @Test func searchesAreLeftAlone() {
        for text in ["e", "excel", "pi", "42", "log", "tan", "Xcode", "iPhone 17", "2 apples", "1+", "(3", "hello world"] {
            #expect(AssistantCalculator.calculate(text) == nil, "\(text)")
        }
    }

    @Test func unitConversions() {
        #expect(result("10 km in mi")?.hasSuffix("mi") == true)
        let meters = AssistantCalculator.calculate("1 km to m")?.result
        #expect(meters?.hasPrefix("1000") == true)
        let fahrenheit = AssistantCalculator.calculate("100 c to f")?.result
        #expect(fahrenheit?.hasPrefix("212") == true)
        #expect(AssistantCalculator.calculate("5 kg in km") == nil)
    }

    @Test func mergedAppsKeepSpotlightsAndAddTheMissing() {
        let a = AssistantHit(kind: .app, url: URL(fileURLWithPath: "/Applications/A.app"), name: "A", contentType: nil, lastUsed: .now)
        let aDisk = AssistantHit(kind: .app, url: URL(fileURLWithPath: "/Applications/A.app"), name: "A", contentType: nil, lastUsed: nil)
        let b = AssistantHit(kind: .app, url: URL(fileURLWithPath: "/Applications/B.app"), name: "B", contentType: nil, lastUsed: nil)
        let merged = AssistantSearch.merged([a], [aDisk, b])
        #expect(merged.map(\.name) == ["A", "B"])
        #expect(merged[0].lastUsed != nil)
    }

    @Test func appsOnDiskAreFoundWithoutSpotlight() {
        let apps = AssistantSearch.diskApps()
        #expect(apps.contains { $0.url.path == "/System/Applications/Calculator.app" })
        // One folder down too: /System/Applications/Utilities.
        #expect(apps.contains { $0.url.path.hasPrefix("/System/Applications/Utilities/") })
        #expect(!apps.contains { $0.name.hasSuffix(".app") })
    }
}
