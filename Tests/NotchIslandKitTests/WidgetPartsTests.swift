import AppKit
import Foundation
import Testing
@testable import NotchIslandKit

@Suite struct WidgetPartsTests {
    /// The symbols drawn by hand, read from the system's names; others are left to the system.
    @Test func drawnSymbolsAreReadFromTheirNames() {
        #expect(DrawnSymbol(symbol: "gobackward.15") == .seek(back: true, seconds: 15))
        #expect(DrawnSymbol(symbol: "arrow.counterclockwise") == .turn(back: true))
        #expect(DrawnSymbol(symbol: "wifi.slash") == .wifi(on: false))
        #expect(DrawnSymbol(symbol: "speaker.wave.2.fill") == .speaker(waves: 2, muted: false))
        #expect(DrawnSymbol(symbol: "speaker.slash.fill") == .speaker(waves: 0, muted: true))
        #expect(DrawnSymbol(symbol: "play.fill") == nil)
        #expect(DrawnSymbol(symbol: "gobackward") == nil)
        // The logos the system has no symbol for, by names of their own.
        #expect(DrawnSymbol(symbol: DrawnSymbol.bluetoothName) == .bluetooth)
        #expect(DrawnSymbol(symbol: DrawnSymbol.airDropName) == .airDrop)
        #expect(DrawnSymbol.isOwn(DrawnSymbol.bluetoothName) && !DrawnSymbol.isOwn("wifi"))
    }

    /// Every control is built as Wi-Fi is and every level as Volume is: the same parts, each named
    /// and drawn as its own control or level in Customize.
    @MainActor @Test func controlsAndLevelsHaveTheirBasesParts() {
        let model = AppModel()
        for kind in IslandWidgetKind.allCases {
            let widget = IslandWidget(kind: kind, frame: GridRect(column: 0, row: 0, width: 2, height: 1), options: kind.defaultOptions)
            if let control = kind.control {
                #expect(kind.spec.buttons == [.controlButton], "\(kind)")
                #expect(kind.spec.texts.first == .controlName, "\(kind)")
                #expect(WidgetParts.buttonTitle(of: .controlButton, in: widget) == control.title)
                #expect(WidgetParts.text(of: .controlName, in: widget, model: model) == control.title)
                // As the editor draws it: a picture, every switch on.
                #expect(WidgetParts.buttonSymbol(of: .controlButton, in: widget, model: model)
                        == control.symbol(on: ControlWidget.isOn(control, model: model, picture: true)))
            } else if kind.level != nil {
                #expect(kind.spec.progressBars == [.levelSlider] && kind.spec.buttons == [.levelIcon], "\(kind)")
                #expect(kind.spec.texts == [.levelValue], "\(kind)")
            }
        }
        // Siri opens: no state to show, so no On or Off.
        #expect(IslandWidgetKind.assistant.spec.element(.controlStatus) == nil)
        #expect(WidgetControl.assistant.isAction && WidgetControl.system(.calculator).isAction && !WidgetControl.system(.wifi).isAction)
        #expect(WidgetControl.system(.bluetooth).symbol(on: true) == DrawnSymbol.bluetoothName)
        #expect(WidgetLevel.keyboard.symbol(LevelReading(value: 0, isMuted: false, isAvailable: true)) == "light.min")
    }

    /// One cell that is its one part (a control's button, the battery's ring) keeps it where the
    /// widget puts it: what was moved or sized at a larger size is not drawn there.
    @MainActor @Test func aOneCellWidgetIsItsOnePart() {
        var battery = IslandWidget(kind: .battery, frame: GridRect(column: 0, row: 0, width: 1, height: 1),
                                   options: IslandWidgetKind.battery.defaultOptions)
        battery.offsets[.batteryRing] = ElementOffset(x: 40, y: 0)
        #expect(battery.isOneElement)
        #expect(IslandWidgetView.resolved(battery, size: CGSize(width: 44, height: 44)).offsets.isEmpty)
        battery.frame.width = 2
        #expect(!battery.isOneElement)
        #expect(IslandWidget(kind: .wifi, frame: GridRect(column: 0, row: 0, width: 1, height: 1), options: []).isOneElement)
        #expect(!IslandWidget(kind: .worldClock, frame: GridRect(column: 0, row: 0, width: 1, height: 1), options: []).isOneElement)
    }

    /// Parts moved at a size laid out one way are not taken to a size laid out another (the
    /// battery's ring and its row); at a size laid out alike they are.
    @MainActor @Test func movesStayWithTheirLayout() {
        var battery = IslandWidget(kind: .battery, frame: GridRect(column: 0, row: 0, width: 4, height: 1),
                                   options: IslandWidgetKind.battery.defaultOptions)
        battery.designSize = GridSize(width: 2, height: 2)
        battery.offsets[.percentage] = ElementOffset(x: 10, y: 4)
        // Designed as a ring, drawn as a row: the move is the ring's.
        #expect(IslandWidgetView.adapted(battery, size: CGSize(width: 180, height: 44)).offsets.isEmpty)
        battery.frame = GridRect(column: 0, row: 0, width: 3, height: 2)
        battery.designSize = GridSize(width: 4, height: 2)
        // Both rows two tall and wide: taken along.
        #expect(!IslandWidgetView.adapted(battery, size: CGSize(width: 130, height: 92)).offsets.isEmpty)
    }

    /// Clipboard's copies: each text and each symbol a part of its own, the symbols switched as one.
    @MainActor @Test func clipboardRowsArePartsOfTheirOwn() {
        let spec = IslandWidgetKind.clipboard.spec
        #expect(spec.texts == (1...8).map { ElementID.clipText($0) })
        #expect(spec.buttons == (1...8).map { ElementID.clipSymbol($0) })
        #expect(ElementID.clipText(3).clipRow == 3 && ElementID.clipSymbol(8).clipRow == 8 && ElementID.artist.clipRow == nil)
        var widget = IslandWidget(kind: .clipboard, frame: GridRect(column: 0, row: 0, width: 4, height: 2),
                                  options: IslandWidgetKind.clipboard.defaultOptions)
        #expect(widget.shows(.clipSymbols))
        #expect(widget.switchElement(for: .clipSymbol(2)) == .clipSymbols)
        // A text is resized by its box, never stretched.
        var style = TextStyle()
        style.box = TextStyle.BoxSize(width: 120, height: 60)
        widget.setTextStyle(style, of: .clipText(2))
        widget.scales[.clipText(2)] = ElementScale(x: 2, y: 2)
        widget.sanitize()
        #expect(widget.scales.isEmpty)
        #expect(widget.textStyle(of: .clipText(2)).box == TextStyle.BoxSize(width: 120, height: 60))
    }

    /// A copy on one line with two set: the editor always offers to try them — in a box one line
    /// low at its smallest, in one as tall as two lines of its letters at the size they fit.
    @MainActor @Test func twoLinesNeedTheRoomOfTwo() {
        var style = TextStyle()
        style.overflow = .shrink
        style.maxLines = 2
        style.minimumSize = 5
        style.box = TextStyle.BoxSize(width: 150, height: 9)
        let text = "notchisland://open?page=timer"
        // One line low: two fit only under the smallest, offered still, at the smallest.
        #expect(LabelFit.preview(text, style: style, size: 12, weight: .medium)?.font.pointSize == 5)
        let font = LabelFit.fitted(text, style: style, size: 12, weight: .medium).font
        style.box?.height = Double((2 * font.lineHeight).rounded(.up))
        #expect(LabelFit.preview(text, style: style, size: 12, weight: .medium)?.lines == 2)
    }

    /// The user's case: "Meeting moved to 3 pm" on one line of a one-line box, two lines set, a
    /// smallest of 6: the try is offered at once (it came only once the smallest was lowered).
    @MainActor @Test func tryingMoreLinesIsOfferedWhateverTheSmallest() {
        var style = TextStyle()
        style.overflow = .shrink
        style.maxLines = 2
        style.box = TextStyle.BoxSize(width: 80.18, height: 12.14)
        for smallest in [4.0, 5, 6, 7, 8] {
            style.minimumSize = smallest
            let fitted = LabelFit.fitted("Meeting moved to 3 pm", style: style, size: 10.8, weight: .medium)
            let used = LabelFit.lineCount(of: "Meeting moved to 3 pm", font: fitted.font, width: 80.18)
            let preview = LabelFit.preview("Meeting moved to 3 pm", style: style, size: 10.8, weight: .medium)
            #expect(used >= 2 || preview?.lines == 2)
            #expect((preview?.font.pointSize ?? 99) + 0.01 >= CGFloat(min(smallest, Double(fitted.font.pointSize))))
        }
    }

    /// Every Clipboard copy's sliders against the letters drawn, at several sizes and row counts:
    /// the inspector measures the text the editor draws; Largest goes as high as one line fits the
    /// box (whatever the text), the letters never past it, never smaller for a higher one; never
    /// under a Smallest the box can hold.
    @MainActor @Test func clipboardSlidersMatchTheLettersDrawn() {
        let model = AppModel()
        let geometry = WidgetBoardGeometry(size: WidgetsSettingsPage.boardSize(IslandLayout(notch: CGSize(width: 185, height: 32), scale: .compact)),
                                           grid: .standard)
        for (width, height) in [(3, 1), (4, 2), (6, 3)] {
            for count in [1, 4, 8] {
                var widget = IslandWidget(kind: .clipboard, frame: GridRect(column: 0, row: 0, width: width, height: height),
                                          options: IslandWidgetKind.clipboard.defaultOptions)
                widget.config.count = count
                let natural = geometry.frame(for: widget.frame).size
                let padding = WidgetMetrics.padding(for: widget)
                let inner = CGSize(width: natural.width - 2 * padding, height: natural.height - 2 * padding)
                let size = WidgetParts.textSize(of: .clipText(1), in: widget, inner: inner)
                for row in 1...count {
                    let text = WidgetParts.text(of: .clipText(row), in: widget, model: model)
                    #expect(text == ClipboardWidget.text(row: row, items: []))
                    for (lines, boxLines) in [(1, 1), (2, 2), (2, 1)] {
                        var style = TextStyle()
                        style.overflow = .shrink
                        style.maxLines = lines == 1 ? nil : lines
                        let line = NSFont.systemFont(ofSize: size, weight: .medium).lineHeight
                        style.box = TextStyle.BoxSize(width: Double(inner.width * 0.8), height: Double((CGFloat(boxLines) * line).rounded(.up)))
                        let top = CGFloat(LabelFit.boxLimit(style, size: size, weight: .medium) ?? 48)
                        var last: CGFloat = 0
                        for largest in stride(from: CGFloat(4), through: top, by: 1) {
                            var set = style
                            set.maximumSize = largest >= top - 0.25 ? nil : Double(largest)
                            let drawn = LabelFit.fitted(text, style: set, size: size, weight: .medium).font.pointSize
                            #expect(drawn <= largest + 0.51)
                            #expect(drawn + 0.01 >= last)
                            last = drawn
                        }
                        for smallest in stride(from: CGFloat(4), through: top, by: 1) {
                            var set = style
                            set.minimumSize = Double(smallest)
                            #expect(LabelFit.fitted(text, style: set, size: size, weight: .medium).font.pointSize + 0.01 >= smallest)
                        }
                    }
                }
            }
        }
    }

    /// Every widget's every text, as the editor sets it in a box of its own: Largest goes as high
    /// as one line fits the box, the letters never past it and never smaller for a higher one, never
    /// under a smallest the box holds; on fewer lines than set, a try of more is always offered.
    @MainActor @Test func everyTextsSlidersAreItsBoxs() {
        let model = AppModel()
        let geometry = WidgetBoardGeometry(size: WidgetsSettingsPage.boardSize(IslandLayout(notch: CGSize(width: 185, height: 32), scale: .compact)),
                                           grid: .standard)
        // Control Center's controls share one layout: three of them stand for the rest (the sweep
        // runs on the main actor, and a long one delays the suites that time things).
        let controls = IslandWidgetKind.allCases.filter { $0.control != nil }
        for kind in IslandWidgetKind.allCases where !kind.spec.texts.isEmpty && (kind.control == nil || controls.prefix(3).contains(kind)) {
            let cells = BoardGrid.standard.defaultSize(for: kind)
            let widget = IslandWidget(kind: kind, frame: GridRect(column: 0, row: 0, width: cells.width, height: cells.height),
                                      options: kind.defaultOptions)
            let natural = geometry.frame(for: widget.frame).size
            let padding = WidgetMetrics.padding(for: widget)
            let inner = CGSize(width: natural.width - 2 * padding, height: natural.height - 2 * padding)
            for id in kind.spec.texts {
                let text = WidgetParts.text(of: id, in: widget, model: model)
                let size = WidgetParts.textSize(of: id, in: widget, inner: inner)
                let weight = WidgetParts.weight(of: id, in: widget)
                for (lines, boxLines) in [(1, 1), (2, 2), (2, 1)] {
                    var style = TextStyle()
                    style.overflow = .shrink
                    style.maxLines = lines == 1 ? nil : lines
                    let line = NSFont.systemFont(ofSize: size, weight: weight).lineHeight
                    style.box = TextStyle.BoxSize(width: Double(max(inner.width * 0.6, 20)), height: Double((CGFloat(boxLines) * line).rounded(.up)))
                    let top = CGFloat(LabelFit.boxLimit(style, size: size, weight: weight) ?? 48)
                    var last: CGFloat = 0
                    for largest in Array(stride(from: CGFloat(4), to: top, by: 2)) + [top] {
                        var set = style
                        set.maximumSize = largest >= top - 0.25 ? nil : Double(largest)
                        let fitted = LabelFit.fitted(text, style: set, size: size, weight: weight)
                        #expect(fitted.font.pointSize <= largest + 0.51, "\(kind) \(id.rawValue): Largest \(largest)")
                        #expect(fitted.font.pointSize + 0.01 >= last, "\(kind) \(id.rawValue): Largest \(largest)")
                        last = fitted.font.pointSize
                        let used = LabelFit.lineCount(of: text, font: fitted.font, width: CGFloat(style.box!.width))
                        if used < lines {
                            #expect(LabelFit.preview(text, style: set, size: size, weight: weight)?.lines == lines, "\(kind) \(id.rawValue)")
                        }
                    }
                    for smallest in stride(from: CGFloat(4), through: top, by: 3) {
                        var set = style
                        set.minimumSize = Double(smallest)
                        #expect(LabelFit.fitted(text, style: set, size: size, weight: weight).font.pointSize + 0.01 >= smallest,
                                "\(kind) \(id.rawValue): Smallest \(smallest)")
                    }
                }
            }
        }
    }

    /// Clipboard's symbols one by one: the first row alone until set; one deleted goes alone (the
    /// others stay where they are), the last one switches Symbols off; ⌘C ⌘V adds one on the next
    /// row without one, styled, moved and sized as the one copied; no more than there are rows;
    /// kept only where the kind offers it, and saved.
    @MainActor @Test func clipboardSymbolsOneByOne() {
        var widget = IslandWidget(kind: .clipboard, frame: GridRect(column: 0, row: 0, width: 4, height: 2),
                                  options: IslandWidgetKind.clipboard.defaultOptions)
        widget.config.count = 4
        #expect(widget.clipSymbolRows == [1])
        var look = ButtonLook(); look.material = .glass
        widget.buttonLooks[.clipSymbol(1)] = look
        widget.offsets[.clipSymbol(1)] = ElementOffset(x: 3, y: -2)
        let source = widget
        #expect(widget.paste(.clipSymbol(1), from: source, onto: [.clipSymbol(1)]) == .added(.clipSymbol(2)))
        #expect(widget.clipSymbolRows == [1, 2])
        #expect(widget.buttonLook(of: .clipSymbol(2)) == look && widget.offset(of: .clipSymbol(2)) == ElementOffset(x: 3, y: -2))
        _ = widget.paste(.clipSymbol(1), from: source, onto: [])
        _ = widget.paste(.clipSymbol(1), from: source, onto: [])
        #expect(widget.clipSymbolRows == [1, 2, 3, 4])
        #expect(widget.paste(.clipSymbol(1), from: source, onto: []) == .nothing)
        // Delete one: that one alone.
        widget.delete([.clipSymbol(2)])
        #expect(widget.clipSymbolRows == [1, 3, 4] && widget.shows(.clipSymbols))
        #expect(widget.buttonLooks[.clipSymbol(2)] == nil)
        // The next one pasted fills the gap.
        #expect(widget.paste(.clipSymbol(1), from: source, onto: []) == .added(.clipSymbol(2)))
        widget.delete([.clipSymbol(1), .clipSymbol(2), .clipSymbol(3), .clipSymbol(4)])
        #expect(!widget.shows(.clipSymbols) && widget.clipSymbolRows.isEmpty)
        // Pasted with Symbols off: on, with that one.
        #expect(widget.paste(.clipSymbol(1), from: source, onto: []) == .added(.clipSymbol(1)))
        #expect(widget.shows(.clipSymbols) && widget.clipSymbolRows == [1])
        // Fewer rows: only the rows there are.
        widget.config.symbolRows = [1, 3, 7]
        widget.config.count = 3
        #expect(widget.clipSymbolRows == [1, 3])
        widget.config.symbolRows = [9, 3, 3, 0]
        widget.sanitize()
        #expect(widget.config.symbolRows == [3])
        var clock = IslandWidget(kind: .worldClock, frame: GridRect(column: 0, row: 0, width: 3, height: 1), options: [])
        clock.config.symbolRows = [2]
        clock.sanitize()
        #expect(clock.config.symbolRows == nil)
        let data = try! JSONEncoder().encode(widget.config)
        #expect(try! JSONDecoder().decode(WidgetConfig.self, from: data).symbolRows == widget.config.symbolRows)
    }

    /// ⌘C ⌘V elsewhere: a shape as a second one beside it; a text's style on another text (its own
    /// box kept); nothing where the sorts differ.
    @MainActor @Test func copyAndPasteParts() {
        var widget = IslandWidget(kind: .nowPlaying, frame: GridRect(column: 0, row: 0, width: 7, height: 3),
                                  options: IslandWidgetKind.nowPlaying.defaultOptions)
        let figure = WidgetFigure.new(.ring)
        widget.figures = [figure]
        widget.offsets[figure.id] = ElementOffset(x: 10, y: 10)
        var source = widget
        guard case .added(let copy) = widget.paste(figure.id, from: source, onto: [figure.id]) else { Issue.record("no copy"); return }
        #expect(widget.figures.count == 2 && copy != figure.id && widget.figure(copy)?.kind == .ring)
        #expect(widget.offset(of: copy) == ElementOffset(x: 16, y: 16))
        var title = TextStyle(); title.isBold = true; title.box = TextStyle.BoxSize(width: 90, height: 20)
        widget.setTextStyle(title, of: .trackInfo)
        var artist = TextStyle(); artist.box = TextStyle.BoxSize(width: 60, height: 14)
        widget.setTextStyle(artist, of: .artist)
        source = widget
        #expect(widget.paste(.trackInfo, from: source, onto: [.artist]) == .styled)
        #expect(widget.textStyle(of: .artist).isBold && widget.textStyle(of: .artist).box == artist.box)
        #expect(widget.paste(.trackInfo, from: source, onto: [.playbackButtons]) == .nothing)
    }

    /// The percentages beside a chart: every step's, but none too close to the last one written;
    /// 0 and 100 % always.
    @Test func aChartWritesThePercentagesThatFit() {
        var look = ChartLook()
        #expect(look.percentages == [0, 50, 100])
        look.percentStep = 10
        #expect(look.percentages.count == 11)
        let tall = BatteryChartPlot.written(look.percentages, height: 200)
        #expect(tall == look.percentages)
        let low = BatteryChartPlot.written(look.percentages, height: 60)
        #expect(low.first == 0 && low.last == 100 && low.count < 11)
        look.percentStep = 7
        look.sanitize()
        #expect(look.percentStep == 50)
        look.percentStep = 0
        #expect(look.percentages.isEmpty)
    }

    /// A widget of a kind that came back since it was saved (a Bluetooth switch, kept unknown in
    /// `foreign` while the kind was gone) returns from there, with its own id and frame.
    @Test func aReturningKindComesBackFromForeign() throws {
        let id = WidgetID()
        let json = """
        {"version":3,"grid":{"columns":12,"rows":3},"widgets":[],"parked":[],
         "foreign":[{"kind":"bluetooth","id":"\(id)","frame":{"column":4,"row":1,"width":2,"height":1},"options":["controlName"]}]}
        """
        let board = try JSONDecoder().decode(WidgetBoard.self, from: Data(json.utf8))
        let widget = try #require(board.widget(id))
        #expect(widget.kind == .bluetooth)
        #expect(widget.frame == GridRect(column: 4, row: 1, width: 2, height: 1))
        #expect(widget.options == [.controlName])
        #expect(board.foreign.isEmpty)
    }

    /// Every widget's parts can be moved in Customize; its texts and buttons are among them, and
    /// each is one of its elements or one drawn inside one.
    @Test func everyKindsPartsCanBeCustomized() {
        for kind in IslandWidgetKind.allCases {
            let spec = kind.spec
            #expect(!spec.movable.isEmpty, "\(kind)")
            #expect(Set(spec.texts).isSubset(of: spec.movable), "\(kind)")
            #expect(Set(spec.buttons).isSubset(of: spec.movable), "\(kind)")
        }
        #expect(IslandWidgetKind.stopwatch.spec.buttons == [.resetButton, .stopwatchButton])
        #expect(IslandWidgetKind.dateTime.spec.texts == [.readout, .dateLine])
        #expect(IslandWidgetKind.wifi.spec.buttons == [.controlButton])
    }

    /// A clock restyled with its typeface left at Default keeps its own rounded figures.
    @Test func aRestyledClockKeepsItsRoundedFigures() {
        var widget = IslandWidget(kind: .dateTime, frame: GridRect(column: 0, row: 0, width: 3, height: 1),
                                  options: IslandWidgetKind.dateTime.defaultOptions)
        var style = TextStyle()
        style.isBold = true
        widget.setTextStyle(style, of: .readout)
        #expect(widget.withOwnDesign(.rounded, for: .readout).textStyle(of: .readout).design == .rounded)
        style.design = .serif
        widget.setTextStyle(style, of: .readout)
        #expect(widget.withOwnDesign(.rounded, for: .readout).textStyle(of: .readout).design == .serif)
        #expect(widget.withOwnDesign(.rounded, for: .dateLine).textStyles[.dateLine] == nil)
    }
}

/// The readouts built as World Clock is: what each says as the battery and the Mac change.
@Suite struct ReadoutWidgetTests {
    static let locale = Locale(identifier: "en_US@hours=h23")
    static let zone = TimeZone(identifier: "Europe/Budapest")!
    static let now = Date(timeIntervalSince1970: 1_790_235_660)

    static func reading(_ kind: IslandWidgetKind, _ state: PowerState, details: BatteryDetails? = nil,
                        lastCharge: BatteryLastCharge? = nil) -> WidgetReading {
        BatteryReadings.reading(kind, state: state, details: details, lastCharge: lastCharge, now: now, locale: locale, timeZone: zone)
    }

    @Test func batteryFiguresFollowThePower() {
        let onBattery = PowerState(hasBattery: true, level: 40, isCharging: false, isPluggedIn: false, isCharged: false,
                                   minutesRemaining: 150, isLowPowerMode: false)
        #expect(Self.reading(.batteryTime, onBattery).value == "2h 30m")
        #expect(Self.reading(.batteryTime, onBattery).caption == "Remaining")
        var held = onBattery
        held.isPluggedIn = true
        held.minutesRemaining = nil
        #expect(Self.reading(.batteryTime, held).value == "On Hold")
        #expect(Self.reading(.charger, onBattery).caption == "Not Connected")
        // Nothing read yet: a dash, never a made-up figure.
        #expect(Self.reading(.batteryHealth, onBattery).value == "—")
        #expect(Self.reading(.batteryCycles, onBattery, details: BatteryReadings.sampleDetails).caption == "of 1000 Cycles")
        var draw = BatteryReadings.sampleDetails
        draw.chargeWatts = nil
        #expect(Self.reading(.batteryPower, onBattery, details: draw).caption == "From the Battery")
        // Charged at 18:30 the day before.
        let charge = BatteryReadings.sampleLastCharge(now: Self.now, timeZone: Self.zone)
        #expect(Self.reading(.batteryLastCharge, onBattery, lastCharge: charge).caption == "Last Charged · Yesterday, 18:30")
    }

    @Test func theMacsFigures() {
        #expect(SystemReadings.uptime(90 * 60, thermal: .nominal, locale: Self.locale).value == "1h 30m")
        #expect(SystemReadings.uptime(SystemReadings.sampleUptime, thermal: .serious, locale: Self.locale).caption == "Hot")
        #expect(SystemReadings.disk(nil, locale: Self.locale).value == "—")
        #expect(SystemReadings.disk() != nil)
    }
}

/// The timer's ruler and time: the ruler's look kept with the widget, the time in its units.
@Suite struct TimerWidgetTests {
    @Test func theRulersLookIsKeptWithItsWidget() throws {
        var widget = IslandWidget(kind: .timer, frame: GridRect(column: 0, row: 0, width: 5, height: 2),
                                  options: IslandWidgetKind.timer.defaultOptions)
        var look = RulerLook()
        look.color = .custom(.rgb(0.3, 0.7, 1))
        look.ends = .sharp
        look.material = .glass
        look.corners = .round
        look.fill = .colour
        look.fillColor = .rgb(0.2, 0.3, 0.9)
        widget.setRulerLook(look, of: .ruler)
        let again = try JSONDecoder().decode(IslandWidget.self, from: JSONEncoder().encode(widget))
        #expect(again.rulerLook(of: .ruler) == look)
        #expect(again.isGlass(.ruler))
        // The plain look is no look at all; a look on a part that is no ruler is dropped.
        widget.setRulerLook(.plain, of: .ruler)
        #expect(widget.rulerLooks.isEmpty)
        widget.rulerLooks[.readout] = look
        widget.sanitize()
        #expect(widget.rulerLooks.isEmpty)
        #expect(IslandWidgetKind.timer.spec.rulers == [.ruler])
    }

    /// Italic where the typeface has no italic of its own (SF Rounded): slanted, at its size.
    @Test func roundedItalicIsSlanted() {
        var style = TextStyle()
        style.design = .rounded
        style.isItalic = true
        let font = style.font(size: 20, weight: .medium)
        #expect(abs(font.pointSize - 20) < 0.5)
        #expect(font.textTransform.m21 > 0 || font.fontDescriptor.symbolicTraits.contains(.italic))
        style.isItalic = false
        #expect(style.font(size: 20, weight: .medium).textTransform.m21 == 0)
    }

    /// The unit's name beside the marker: a switch of its own, moved with the ruler's look, set as
    /// a text of the ruler's (kept with the widget, its move kept within reach).
    @Test func theUnitsNameIsSetAndMoved() throws {
        #expect(IslandWidgetKind.timer.spec.innerTexts == [.rulerUnit])
        #expect(IslandWidgetKind.timer.defaultOptions.contains(.rulerUnit))
        var widget = IslandWidget(kind: .timer, frame: GridRect(column: 0, row: 0, width: 5, height: 2),
                                  options: IslandWidgetKind.timer.defaultOptions)
        var look = RulerLook()
        look.unitOffset = ElementOffset(x: -40, y: 3)
        widget.setRulerLook(look, of: .ruler)
        var style = TextStyle()
        style.size = 13
        style.isBold = true
        style.box = TextStyle.BoxSize(width: 30, height: 12)
        widget.setTextStyle(style, of: .rulerUnit)
        let again = try JSONDecoder().decode(IslandWidget.self, from: JSONEncoder().encode(widget))
        #expect(again.rulerLook(of: .ruler).unitOffset == ElementOffset(x: -40, y: 3))
        #expect(again.textStyle(of: .rulerUnit) == style)
        #expect(TimerWidget.unitName(again)?.style == style)
        widget.options.remove(.rulerUnit)
        #expect(TimerWidget.unitName(widget) == nil)
        look.unitOffset = ElementOffset(x: 900, y: .nan)
        look.sanitize()
        #expect(look.unitOffset == .zero)
        look.unitOffset = ElementOffset(x: 900, y: -900)
        look.sanitize()
        #expect(look.unitOffset == ElementOffset(x: RulerLook.unitReach, y: -RulerLook.unitReach))
    }

    @Test func theTimeReadsInItsUnits() {
        let minutes = TimerDraftUnits()
        #expect(TimerWidget.draftText(5 * 60, units: minutes) == "5:00")
        let all = TimerDraftUnits(hours: true, seconds: true)
        #expect(TimerWidget.draftText(3600 + 5 * 60 + 30, units: all) == "1:05:30")
        #expect(TimerWidget.draftText(5 * 60, units: TimerDraftUnits(hours: true)) == "0:05")
        // Without hours, minutes however many: three digits of them, never hours.
        #expect(TimerWidget.draftText(120 * 60, units: minutes) == "120:00")
        #expect(TimerWidget.draftText(120 * 60 + 16, units: TimerDraftUnits(seconds: true)) == "120:16")
        #expect(TimerWidget.countdownText(119 * 60 + 59, units: minutes) == "119:59")
        #expect(TimerWidget.countdownText(3600 + 59, units: TimerDraftUnits(hours: true)) == "1:00:59")
        // The time's room is its widest, whatever it reads: it never moves as its digits grow.
        #expect(TimerWidget.widest(minutes) == "000:00" && TimerWidget.widest(all) == "00:00:00")
        let timer = IslandWidget(kind: .timer, frame: GridRect(column: 0, row: 0, width: 5, height: 2),
                                 options: [.ruler, .readout, .timerSeconds])
        let inner = CGSize(width: 220, height: 80)
        #expect(TimerWidget.readoutWidth(timer, inner: inner)
                >= TimerWidget.textWidth("120:16", points: TimerWidget.readoutPoints(timer, inner: inner)))
        // The parts not being set faded: seconds picked, the minutes and the colon.
        #expect(TimerWidget.draftSegments(120 * 60 + 16, units: TimerDraftUnits(seconds: true), current: .seconds)
                == [LabelSegment(text: "120", isFaded: true), LabelSegment(text: ":", isFaded: true), LabelSegment(text: "16")])
        // Hours and seconds are switches of their own, off in a new timer.
        #expect(!IslandWidgetKind.timer.defaultOptions.contains(.timerHours))
        #expect(IslandWidgetKind.timer.options.contains(.timerSeconds))
    }
}

/// The calendar's grid of days: a background behind each day and one behind the grid, kept with
/// the widget; the days' numbers a text of their own.
@Suite struct DayGridLookTests {
    @Test func theGridsLookIsKeptWithItsWidget() throws {
        var widget = IslandWidget(kind: .monthCalendar, frame: GridRect(column: 0, row: 0, width: 4, height: 3),
                                  options: IslandWidgetKind.monthCalendar.defaultOptions)
        var look = DayGridLook()
        look.day.material = .solid
        look.day.corners = .round
        look.grid.material = .glass
        look.grid.fill = .colour
        look.grid.fillColor = .rgb(0.3, 0.5, 1)
        widget.setDayGridLook(look, of: .monthGrid)
        var style = TextStyle()
        style.isBold = true
        style.size = 9
        widget.setTextStyle(style, of: .monthDays)
        let again = try JSONDecoder().decode(IslandWidget.self, from: JSONEncoder().encode(widget))
        #expect(again.dayGridLook(of: .monthGrid) == look)
        #expect(again.textStyle(of: .monthDays) == style)
        #expect(again.isGlass(.monthGrid))
        #expect(IslandWidgetKind.monthCalendar.spec.dayGrids == [.monthGrid])
        #expect(IslandWidgetKind.monthCalendar.spec.innerTexts == [.monthDays])
        // The plain look is no look at all; a look on a part that is no grid is dropped.
        widget.setDayGridLook(.plain, of: .monthGrid)
        #expect(widget.dayGridLooks.isEmpty)
        widget.dayGridLooks[.label] = look
        widget.sanitize()
        #expect(widget.dayGridLooks.isEmpty)
    }

    /// The days and the weekdays are switches since version 4: a calendar saved before keeps them,
    /// one saved since keeps them off where they were switched off.
    @Test func theDaysAreASwitchAndOldCalendarsKeepThem() throws {
        #expect(IslandWidgetKind.monthCalendar.spec.element(.monthGrid)?.isRequired == false)
        #expect(IslandWidgetKind.monthCalendar.defaultOptions.isSuperset(of: [.label, .monthGrid, .monthWeekdays]))
        let old = #"{"version":3,"kind":"monthCalendar","frame":{"column":0,"row":0,"width":4,"height":3},"options":["label"]}"#
        let decoded = try JSONDecoder().decode(IslandWidget.self, from: Data(old.utf8))
        #expect(decoded.shows(.monthGrid) && decoded.shows(.monthWeekdays) && decoded.shows(.label))
        var off = decoded
        off.options = [.label]
        let again = try JSONDecoder().decode(IslandWidget.self, from: JSONEncoder().encode(off))
        #expect(!again.shows(.monthGrid) && !again.shows(.monthWeekdays))
    }
}
