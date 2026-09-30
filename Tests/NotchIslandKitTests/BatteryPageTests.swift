import AppKit
import Foundation
import SwiftUI
import Testing
@testable import NotchIslandKit

// MARK: - Fixtures

/// A model on a throwaway defaults domain, never started.
@MainActor private func withModel(_ body: (AppModel) throws -> Void) rethrows {
    let name = "ni2.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    let preferences = Preferences(defaults: defaults)
    preferences.hapticsEnabled = false
    preferences.timerSound = false
    try body(AppModel(preferences: preferences))
}

@MainActor private func withModelAsync(_ body: @MainActor (AppModel) async throws -> Void) async throws {
    let name = "ni2.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    try await body(AppModel(preferences: Preferences(defaults: defaults)))
}

private func laptop(level: Int = 76, charging: Bool = false, plugged: Bool? = nil, charged: Bool = false,
                    minutes: Int? = nil) -> PowerState {
    PowerState(hasBattery: true, level: level, isCharging: charging, isPluggedIn: plugged ?? charging,
               isCharged: charged, minutesRemaining: minutes, isLowPowerMode: false)
}

/// RGBA, 8 bits a channel, rows from the top.
private func pixels(_ image: CGImage) -> [UInt8] {
    var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
    let context = CGContext(data: &pixels, width: image.width, height: image.height, bitsPerComponent: 8,
                            bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return pixels
}

/// 20:00 on a Wednesday in Budapest, past both of the demo day's charges.
private let demoCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Budapest")!
    return calendar
}()
private let demoNow = demoCalendar.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 20))!

private func today(_ hour: Int, _ minute: Int = 0) -> Date {
    demoCalendar.date(bySettingHour: hour, minute: minute, second: 0, of: demoNow)!
}

// MARK: - Pages

@MainActor @Suite struct BatteryPageAvailabilityTests {
    @Test func aDesktopHasNoBatteryPage() {
        withModel { model in
            #expect(!model.power.hasBattery)
            #expect(model.availablePages == [.home, .shelf, .timer])
        }
    }

    @Test func aLaptopHasItAfterTheTimer() {
        withModel { model in
            model.power.injectDemo(laptop(), event: nil)
            #expect(model.availablePages == [.home, .shelf, .timer, .battery])
        }
    }

    @Test func theShelfOffHidesItsPageAndTheBoardTakesItsPlace() {
        withModel { model in
            model.island.page = .shelf
            model.preferences.shelfEnabled = false
            #expect(model.availablePages == [.home, .timer])
            #expect(model.panelPage == .home)
            model.preferences.shelfEnabled = true
            #expect(model.panelPage == .shelf)
        }
    }

    @Test func aDesktopAskedForTheBatteryPageOpensTheOneItHas() {
        withModel { model in
            model.controller.expand(page: .battery, userInitiated: true)
            #expect(model.island.page == .home)
            #expect(model.island.presentation == .expanded(.home))
            model.controller.collapse()
        }
    }

    @Test func theURLAndTheDemoParse() {
        #expect(AppCommand.parse(URL(string: "notchisland://open?page=battery")!) == .open(.battery))
        #expect(AppCommand.parse(URL(string: "notchisland://demo/batteryhistory")!) == .demo(.batteryHistory))
    }

    @Test func spotlightOffersOnlyThePagesThisMacHas() {
        withModel { model in
            let pages = { model.assistant.commands(matching: "").compactMap { command -> ExpandedPage? in
                if case .page(let page) = command { page } else { nil }
            } }
            #expect(!pages().contains(.battery))
            model.power.injectDemo(laptop(), event: nil)
            #expect(pages().contains(.battery))
        }
    }
}

// MARK: - Text

@Suite struct BatteryPageTextTests {
    @Test func theStateLineSaysWhatTheBatteryIsDoing() {
        #expect(BatteryPageText.state(laptop(charging: true, minutes: 72), details: nil) == "Charging — 1 h 12 min to full")
        #expect(BatteryPageText.state(laptop(minutes: 340), details: nil) == "5 h 40 min left")
        #expect(BatteryPageText.state(laptop(level: 100, plugged: true, charged: true), details: nil) == "Fully charged")
        #expect(BatteryPageText.state(laptop(level: 80, plugged: true), details: nil) == "On power adapter")
        #expect(BatteryPageText.state(laptop(charging: true), details: nil) == "Charging")
        #expect(BatteryPageText.state(laptop(), details: nil) == "On battery")
    }

    @Test func theGaugesEstimateStandsInForTheSystems() {
        let details = BatteryDetails.demo(power: laptop(charging: true))
        var charging = details, onBattery = details
        charging.minutesToFull = 45
        onBattery.minutesToEmpty = 300
        #expect(BatteryPageText.state(laptop(charging: true), details: charging) == "Charging — 45 min to full")
        #expect(BatteryPageText.state(laptop(), details: onBattery) == "5 h left")
    }

    @Test func theLastChargeNamesItsDay() {
        let now = Date()
        #expect(BatteryPageText.lastCharged(BatteryLastCharge(level: 80, date: now)).hasPrefix("Last charged to 80% at "))
        #expect(BatteryPageText.lastCharged(BatteryLastCharge(level: 100, date: now.addingTimeInterval(-86_400)))
            .hasPrefix("Last charged to 100% yesterday at "))
        #expect(BatteryPageText.lastCharged(BatteryLastCharge(level: 100, date: now.addingTimeInterval(-3 * 86_400)))
            .hasPrefix("Last charged to 100% on "))
    }

    @Test func theFactsAreHealthCyclesAndTheAdapter() {
        #expect(BatteryPageText.facts(nil).map(\.value) == ["—", "—"])
        let plugged = BatteryPageText.facts(BatteryDetails.demo(power: laptop(charging: true)))
        #expect(plugged.map(\.value) == ["94%", "212", "96 W"])
        #expect(BatteryPageText.facts(BatteryDetails.demo(power: laptop())).count == 2)
    }
}

// MARK: - Demo day

@Suite struct BatteryDemoDayTests {
    @Test func theDemoDayIsARealisticHistoryUpToNow() {
        let records = BatteryHistory.demoRecords(now: demoNow, calendar: demoCalendar)
        #expect(records.first?.kind == .appStart)
        #expect(records.allSatisfy { $0.date <= demoNow })
        #expect(zip(records, records.dropFirst()).allSatisfy { $0.time <= $1.time })
        #expect(BatteryHistory.lastCharge(in: records) == BatteryLastCharge(level: 100, date: today(18, 30)))

        let model = BatteryChartModel(records: records, range: .today, now: demoNow, calendar: demoCalendar)
        func spans(_ kind: BatteryChartSegment.Kind) -> [ClosedRange<Date>] {
            model.segments.filter { $0.kind == kind }.map { $0.start...$0.end }
        }
        #expect(spans(.gap) == [today(0, 40)...today(7, 10)])
        #expect(spans(.charging) == [today(9, 30)...today(10, 40), today(17)...today(18, 30)])
        #expect(spans(.displayOff) == [today(0, 30)...today(0, 40), today(12, 40)...today(13, 20)])
        #expect(model.buckets.count == 96)
        #expect(model.buckets.filter { $0.start >= demoNow }.allSatisfy { $0.level == nil })
        #expect(model.buckets.contains { $0.isGap } && model.buckets.contains { $0.isDisplayOff })
        #expect(model.buckets.contains { ($0.level ?? 100) < 20 && !$0.isCharging })
        #expect(model.ticks.count == 5)
    }

    @Test func itsShapesHaveEveryPartInEachStyle() {
        let records = BatteryHistory.demoRecords(now: demoNow, calendar: demoCalendar)
        let model = BatteryChartModel(records: records, range: .today, now: demoNow, calendar: demoCalendar)
        let size = CGSize(width: 320, height: 100)
        for style in BatteryChartStyle.allCases {
            let geometry = BatteryChartGeometry(model: model, style: style, size: size)
            #expect(!geometry.level.isEmpty && !geometry.charging.isEmpty && !geometry.low.isEmpty, "\(style)")
            #expect(!geometry.gaps.isEmpty && !geometry.displayOff.isEmpty)
            // Everything below 20 % lies in the chart's bottom fifth, and before 17:00 (the charge).
            let low = geometry.low.boundingRect
            #expect(low.minY >= size.height * 0.8 - 1, "\(style) \(low)")
            #expect(low.maxX <= size.width * CGFloat(today(17).timeIntervalSince(model.interval.start) / model.interval.duration) + 1)
            #expect(geometry.ticks.map(\.x) == [0, 80, 160, 240, 320])
        }
    }
}

// MARK: - Settings

@Suite struct BatteryDisplaySettingsTests {
    @Test func defaultsAreBarsOfTodayWithEverythingShown() {
        let settings = BatteryDisplaySettings()
        #expect(settings.style == .bars && settings.range == .today)
        #expect(settings.showsGaps && settings.shadesDisplayOff && settings.showsCaptions)
        #expect(settings.normalColor == .automatic && settings.chargingColor == .automatic && settings.lowColor == .automatic)
    }

    @Test func decodingKeepsWhatItCanRead() throws {
        let json = #"{"style":"line","range":"sideways","showsGaps":false,"lowColor":{"rgb":{"_0":{"red":2,"green":0,"blue":0},"alpha":1}},"chargingColor":7}"#
        let settings = try JSONDecoder().decode(BatteryDisplaySettings.self, from: Data(json.utf8))
        #expect(settings.style == .line)
        #expect(settings.range == .today)
        #expect(!settings.showsGaps)
        #expect(settings.shadesDisplayOff)
        #expect(settings.chargingColor == .automatic)
        #expect(settings.lowColor == .rgb(IslandTheme.RGB(red: 1, green: 0, blue: 0), alpha: 1))
        #expect(try JSONDecoder().decode(BatteryDisplaySettings.self, from: Data("{}".utf8)) == BatteryDisplaySettings())
    }

    @Test func itRoundTripsAndPersistsUnderItsKey() throws {
        var settings = BatteryDisplaySettings()
        settings.style = .area
        settings.range = .last48Hours
        settings.normalColor = .theme
        settings.showsCaptions = false
        #expect(try JSONDecoder().decode(BatteryDisplaySettings.self, from: JSONEncoder().encode(settings)) == settings)

        let name = "ni2.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        Preferences(defaults: defaults).battery = settings
        #expect(defaults.data(forKey: "ni2.battery") != nil)
        #expect(Preferences(defaults: defaults).battery == settings)
    }
}

// MARK: - Header

/// The header as the panel lays it out (the Settings stage draws the same one), in a window of its
/// own that is never on screen.
@MainActor private func hostHeader(_ model: AppModel, _ layout: IslandLayout) async throws
    -> (window: NSWindow, host: NSView, split: NotchSplit) {
    let split = NotchSplit(layout: layout, presentation: .expanded(.home),
                           outerInset: Metrics.Expanded.horizontalInset, clearance: Metrics.notchClearance)
    let host = IslandHostingView(rootView: ExpandedHeader(split: split, height: layout.notch.height).environment(model))
    let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: split.islandWidth, height: layout.notch.height),
                          styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = host
    host.islandRect = host.bounds
    // The segmented bar measures itself again a turn after it is in a window.
    for _ in 0..<5 {
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(20))
    }
    return (window, host, split)
}

private func segmentedControl(in view: NSView) -> NSSegmentedControl? {
    view as? NSSegmentedControl ?? view.subviews.lazy.compactMap(segmentedControl).first
}

@MainActor @Suite struct BatteryHeaderTests {
    /// Every island size at the narrowest and the default panel: the battery's segment only where
    /// all four fit beside the notch, and then the bar lies inside the ear.
    @Test(arguments: [CGSize(width: 156, height: 28), CGSize(width: 156, height: 32), CGSize(width: 185, height: 32)])
    func thePagePickerFitsBesideTheNotch(notch: CGSize) async throws {
        try await withModelAsync { model in
            model.island.page = .battery
            @MainActor func picker(_ layout: IslandLayout) async throws -> (control: NSSegmentedControl, frame: CGRect, split: NotchSplit) {
                let (window, host, split) = try await hostHeader(model, layout)
                defer { window.contentView = nil }
                let control = try #require(segmentedControl(in: host))
                return (control, control.convert(control.bounds, to: host), split)
            }
            // Each bar's own width, measured where there is room for it.
            let roomy = IslandLayout(notch: notch, scale: .large, panel: PanelLayout(widthFactor: PanelSettings.widthRange.upperBound))
            let three = try await picker(roomy)
            #expect(three.control.segmentCount == 3)
            model.power.injectDemo(laptop(), event: nil)
            let four = try await picker(roomy)
            #expect(four.control.segmentCount == 4 && four.frame.width > three.frame.width)

            for factor in [PanelSettings.widthRange.lowerBound, 1] {
                for scale in IslandScale.allCases {
                    let (control, frame, split) = try await picker(IslandLayout(notch: notch, scale: scale,
                                                                              panel: PanelLayout(widthFactor: factor)))
                    let context = Comment(rawValue: "\(scale) at \(factor): \(frame.width) pt in \(split.earWidth)")
                    #expect(control.segmentCount == (four.frame.width <= split.earWidth ? 4 : 3), context)
                    // The battery page shown without its segment: none is selected.
                    #expect(control.selectedSegment == (control.segmentCount == 4 ? 3 : -1), context)
                    let fits = frame.minX >= split.leadingEar.lowerBound - 0.5 && frame.maxX <= split.leadingEar.upperBound + 0.5
                    if three.frame.width <= split.earWidth {
                        #expect(fits, context)
                    } else {
                        // Not even home, shelf and timer fit (Extra Small, and Small beside the wide
                        // notch, at the narrowest panel): the bar is the one from before the battery page.
                        withKnownIssue { #expect(fits, context) }
                    }
                }
            }
        }
    }

    @Test func theBatteryInTheHeaderOpensItsPage() async throws {
        try await withModelAsync { model in
            model.power.injectDemo(laptop(), event: nil)
            let layout = IslandLayout(notch: CGSize(width: 185, height: 32), scale: .compact)
            let (window, _, split) = try await hostHeader(model, layout)
            defer {
                window.orderOut(nil)
                window.contentView = nil
            }
            // The battery: the first thing drawn right of the notch.
            let renderer = ImageRenderer(content: ExpandedHeader(split: split, height: layout.notch.height).environment(model))
            renderer.scale = 1
            let image = try #require(renderer.cgImage)
            let picture = pixels(image)
            func drawn(_ x: Int) -> [Int] { (0..<image.height).filter { picture[($0 * image.width + x) * 4 + 3] > 25 } }
            let left = try #require((Int(split.trailingEar.lowerBound)..<image.width).first { !drawn($0).isEmpty })
            let right = (left..<image.width).first { drawn($0).isEmpty } ?? image.width
            let rows = (left..<right).flatMap(drawn)
            let pill = CGPoint(x: CGFloat(left + right) / 2, y: CGFloat(rows.min()! + rows.max()! + 1) / 2)

            // A click reaches SwiftUI only in a window that is ordered in: this one is transparent and
            // far off every screen.
            window.alphaValue = 0
            window.setFrameOrigin(CGPoint(x: -20_000, y: -20_000))
            window.orderFrontRegardless()
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = try #require(NSEvent.mouseEvent(
                    with: type, location: CGPoint(x: pill.x, y: layout.notch.height - pill.y), modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                    eventNumber: 0, clickCount: 1, pressure: 1))
                window.sendEvent(event)
                try await Task.sleep(for: .milliseconds(30))
            }
            #expect(model.island.presentation == .expanded(.battery))
            model.controller.collapse()
        }
    }
}

// MARK: - Snapshot

/// The page drawn offscreen as the panel lays it out: on the demo day in each style at two island
/// sizes, where the chart's colours must be there (the charges green, the low stretch red), and
/// charging with the adapter at every size, where nothing may be cut. `$NI_RENDER_BATTERY` names a
/// folder to write the pictures to, for looking at.
@MainActor @Suite struct BatteryPageSnapshotTests {
    @Test(arguments: [IslandScale.compact, .extraSmall], BatteryChartStyle.allCases)
    func theDemoDayDraws(scale: IslandScale, style: BatteryChartStyle) async throws {
        try await withModelAsync { model in
            let state = laptop(level: 64, minutes: 340)
            model.power.injectDemo(state, event: nil)
            // Rolling, so the picture has both charges whatever the hour the test runs at.
            model.preferences.battery.range = .last24Hours
            model.preferences.battery.style = style
            model.battery.injectDemo((BatteryHistory.demoRecords(now: Date(), calendar: .autoupdatingCurrent),
                                      BatteryDetails.demo(power: state)))
            let page = Self.pageSize(scale)
            let picture = try await Self.render(model, scale: scale)
            #expect(picture.width == Int(page.width * 2) && picture.height == Int(page.height * 2))
            #expect(Self.count(in: picture, where: Self.isGreen) > 200, "charging bars")
            #expect(Self.count(in: picture, where: Self.isRed) > 20, "low bars")
            try Self.write(picture, "battery-\(scale.rawValue)-\(style.rawValue)")
        }
    }

    /// The tallest summary (three facts) and the longest state: one line each, measured in the page's
    /// type, and nothing drawn below the page.
    @Test(arguments: IslandScale.allCases)
    func chargingWithTheAdapterNothingIsCut(scale: IslandScale) async throws {
        try await withModelAsync { model in
            let state = laptop(level: 64, charging: true, minutes: 72)
            let details = BatteryDetails.demo(power: state)
            model.power.injectDemo(state, event: nil)
            model.preferences.battery.range = .last24Hours
            model.battery.injectDemo((BatteryHistory.demoRecords(now: Date(), calendar: .autoupdatingCurrent), details))
            let page = Self.pageSize(scale)
            let column = BatteryPage.summaryWidth(page: page.width)
            let chart = page.width - column - Metrics.Expanded.columnSpacing

            // The state line picks the first of its forms that fits: the short one always does.
            #expect(BatteryPageText.state(state, details: details, short: true) == "1 h 12 min to full")
            #expect(Self.width(BatteryPageText.state(state, details: details, short: true), .subheadline.weight(.medium)) <= column)
            let facts = BatteryPageText.facts(details)
            #expect(facts.map(\.label) == ["Maximum Capacity", "Cycle Count", "Power Adapter"])
            let labels = facts.map { Self.width($0.label, .caption) }.max() ?? 0
            let values = facts.map { Self.width($0.value, .caption.monospacedDigit()) }.max() ?? 0
            #expect(labels + Metrics.Spacing.medium + values <= column)
            // The last charge with its time, today, yesterday or on a weekday (the range's name gives way).
            let evening = Calendar.current.date(bySettingHour: 18, minute: 30, second: 0, of: Date())!
            for days in [0, 1, 3] {
                let charge = BatteryLastCharge(level: 100, date: evening.addingTimeInterval(-86_400 * Double(days)))
                #expect(Self.width(BatteryPageText.lastCharged(charge), .caption2.weight(.medium)) <= chart, "\(days) days ago")
            }

            let picture = try await Self.render(model, scale: scale, under: 40)
            #expect(Self.count(in: picture, rows: Int(page.height * 2)..<picture.height) { max($0, $1, $2) > 24 } == 0,
                    "drawn below the page")
            try Self.write(picture, "battery-\(scale.rawValue)-charging")
        }
    }

    private static func pageSize(_ scale: IslandScale) -> CGSize {
        let layout = IslandLayout(notch: CGSize(width: 185, height: 32), scale: scale)
        let panel = layout.size(for: .expanded(.battery))
        let split = NotchSplit(layout: layout, presentation: .expanded(.battery),
                               outerInset: Metrics.Expanded.horizontalInset, clearance: Metrics.notchClearance)
        return CGSize(width: panel.width - 2 * split.contentInset,
                      height: panel.height - layout.notch.height - Metrics.Expanded.pageTopInset - Metrics.Expanded.pageBottomInset)
    }

    /// The page as the panel lays it out at `scale`, with `under` points of black below it, at 2×.
    private static func render(_ model: AppModel, scale: IslandScale, under: CGFloat = 0) async throws -> CGImage {
        let page = pageSize(scale)
        let view = BatteryPage()
            .frame(width: page.width, height: page.height)
            .padding(.bottom, under)
            .background(.black)
            .environment(model)
            .environment(\.colorScheme, .dark)
            .controlSize(Metrics.controlSize(forScale: scale.factor))
        @MainActor func render() -> CGImage? {
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            return renderer.cgImage
        }
        // The chart's shapes are built off the main thread after the first pass asks for them.
        var image = render()
        for _ in 0..<50 {
            try await Task.sleep(for: .milliseconds(20))
            image = render()
            if let image, count(in: image, where: isGreen) > 0 { break }
        }
        return try #require(image)
    }

    private static func write(_ picture: CGImage, _ name: String) throws {
        guard let folder = ProcessInfo.processInfo.environment["NI_RENDER_BATTERY"] else { return }
        let data = NSBitmapImageRep(cgImage: picture).representation(using: .png, properties: [:])
        try data?.write(to: URL(fileURLWithPath: folder).appendingPathComponent("\(name).png"))
    }

    /// A line of text's own width in `font`.
    private static func width(_ text: String, _ font: Font) -> CGFloat {
        NSHostingView(rootView: Text(text).font(font).fixedSize()).fittingSize.width
    }

    /// By hue, so the area's lighter fills count too.
    private static func isGreen(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> Bool { g > 80 && Int(g) > 2 * Int(r) && Int(g) > 3 * Int(b) / 2 }
    private static func isRed(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> Bool { r > 80 && Int(r) > 2 * Int(g) && Int(r) > 2 * Int(b) }

    private static func count(in image: CGImage, rows: Range<Int>? = nil, where test: (UInt8, UInt8, UInt8) -> Bool) -> Int {
        let bytes = pixels(image)
        let rows = rows ?? 0..<image.height
        return stride(from: rows.lowerBound * image.width * 4, to: rows.upperBound * image.width * 4, by: 4)
            .reduce(0) { $0 + (test(bytes[$1], bytes[$1 + 1], bytes[$1 + 2]) ? 1 : 0) }
    }
}
