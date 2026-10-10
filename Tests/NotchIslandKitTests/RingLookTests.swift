import SwiftUI
import Testing
@testable import NotchIslandKit

/// A line bent round — a ring, a dial — is set as a line is, and a graph as a chart is.
@MainActor struct RingLookTests {
    @Test(arguments: ProgressLook.Ends.allCases) func anArcStaysInsideItsRing(_ ends: ProgressLook.Ends) {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        for (start, sweep) in [(-90.0, 360.0), (135.0, 270.0)] {
            let bounds = RingArc(to: 0.4, start: start, sweep: sweep, thickness: 10, ends: ends).path(in: rect).boundingRect
            #expect(!bounds.isEmpty && rect.insetBy(dx: -0.01, dy: -0.01).contains(bounds))
            #expect(RingArc(to: 0, start: start, sweep: sweep, thickness: 10, ends: ends).path(in: rect).isEmpty)
        }
        // All the way round: the whole ring, whatever its ends.
        let whole = RingArc(to: 1, start: -90, sweep: 360, thickness: 10, ends: ends).path(in: rect).boundingRect
        #expect(abs(whole.width - 100) < 0.01 && abs(whole.height - 100) < 0.01)
    }

    @Test func sharpEndsStopWhereRoundOnesGoOn() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        // A quarter from the top, 10 thick: just before its start (48, 5) a round end has ink, a
        // sharp and a rounded one none; just inside it all have, but a rounded one not in its corner.
        func arc(_ ends: ProgressLook.Ends) -> Path { RingArc(to: 0.25, start: -90, sweep: 360, thickness: 10, ends: ends).path(in: rect) }
        let before = CGPoint(x: 48, y: 5), inside = CGPoint(x: 52, y: 5), corner = CGPoint(x: 50.3, y: 0.3)
        #expect(arc(.round).contains(before), "\(arc(.round).boundingRect)")
        #expect(!arc(.sharp).contains(before), "\(arc(.sharp).boundingRect)")
        #expect(!arc(.rounded).contains(before))
        for ends in ProgressLook.Ends.allCases { #expect(arc(ends).contains(inside)) }
        #expect(arc(.sharp).contains(corner) && !arc(.rounded).contains(corner))
    }

    @Test func aRingsSizeAndThicknessFollowItsLook() {
        var look = ProgressLook()
        #expect(ProgressRing.metrics(diameter: 80, line: 8, look: look) == (80, 8))
        look.barLength = 0.5
        look.barThickness = 4
        // No thicker than leaves a hole in the middle.
        #expect(ProgressRing.metrics(diameter: 80, line: 8, look: look) == (40, 18))
    }

    @Test func theDialsTextsAreTheirLinesParts() {
        #expect(ProgressLook.Part.elapsed.textID(in: .fanDial) == .fanName)
        #expect(ProgressLook.Part.remaining.textID(in: .fanDial) == .value)
        #expect(ProgressLook.Part.elapsed.textID(in: .tempDial) == .tempName)
        #expect(ProgressLook.Part.remaining.textID(in: .tempDial) == .tempValue)
        #expect(ProgressLook.Part.remaining.textID(in: .levelSlider) == nil)
        #expect(ProgressLook.Part.remaining.textID(in: .progress) == .remainingTime)
        #expect(ProgressLook.Part.bar.title(in: .fanDial, isRing: true) == "Ring")
        #expect(ProgressLook.Part.remaining.title(in: .fanDial) == "Value")
        #expect(ProgressLook.Part.elapsed.title(in: .progress) == "Elapsed")
    }

    @Test func whichLinesAreRings() {
        let wide = CGSize(width: 240, height: 40), square = CGSize(width: 90, height: 90)
        #expect(ProgressPartsPanel.isRing(.fanDial, inner: wide) && ProgressPartsPanel.isRing(.tempDial, inner: wide))
        #expect(!ProgressPartsPanel.isRing(.cpuLoad, inner: wide) && ProgressPartsPanel.isRing(.cpuLoad, inner: square))
        #expect(!ProgressPartsPanel.isRing(.levelSlider, inner: wide) && ProgressPartsPanel.isRing(.levelSlider, inner: square))
        #expect(!ProgressPartsPanel.isRing(.progress, inner: square))
    }

    @Test func fanControlKeepsItsDialsAndGraphsLooks() {
        var widget = IslandWidget(kind: .fanControl, frame: GridRect(column: 0, row: 0, width: 7, height: 2),
                                  options: IslandWidgetKind.fanControl.defaultOptions)
        var line = ProgressLook()
        line.ends = .sharp
        line.knob = .capsule
        var chart = ChartLook()
        chart.percentStep = 25
        var text = TextStyle()
        text.isBold = true
        widget.progressLooks = [.fanDial: line, .tempDial: line, .value: line]
        widget.chartLooks = [.tempGraph: chart, .rpmGraph: chart, .fanDial: chart]
        widget.offsets = [.value: ElementOffset(x: 4, y: 4), .fanDial: ElementOffset(x: 2, y: 0)]
        widget.textStyles = [.fanName: text, .value: text, .tempName: text, .tempValue: text, .tempGraphText: text,
                             .rpmGraphText: text, .fanDial: text]
        widget.sanitize()
        #expect(Set(widget.progressLooks.keys) == [.fanDial, .tempDial])
        #expect(Set(widget.chartLooks.keys) == [.tempGraph, .rpmGraph])
        #expect(Set(widget.textStyles.keys) == [.fanName, .value, .tempName, .tempValue, .tempGraphText, .rpmGraphText])
        // The speed is the dial's own text now: no longer moved by itself.
        #expect(Set(widget.offsets.keys) == [.fanDial])
    }

    @Test func theBatterysRingKeepsALineLook() {
        var widget = IslandWidget(kind: .battery, frame: GridRect(column: 0, row: 0, width: 2, height: 2),
                                  options: IslandWidgetKind.battery.defaultOptions)
        var line = ProgressLook()
        line.ends = .rounded
        widget.progressLooks = [.batteryRing: line, .percentage: line]
        widget.sanitize()
        #expect(widget.progressLooks == [.batteryRing: line])
    }

    @Test func aGraphWritesAValueEverySoMany() {
        // The temperature's own: 25, 50, 75 and 100.
        #expect(SensorGraph.marks(SensorGraph.temperatureRange, step: SensorGraph.temperatureStep) == [25, 50, 75, 100])
        // From the lowest up, the highest always: 25, 40, 55, 70, 85 and 100; 30, 50, 70 and 80.
        #expect(SensorGraph.marks(25...100, step: 15) == [25, 40, 55, 70, 85, 100])
        #expect(SensorGraph.marks(30...80, step: 20) == [30, 50, 70, 80])
        // No step: the ends alone (their guides stay; nothing is written).
        #expect(SensorGraph.marks(25...100, step: 0) == [25, 100])
        #expect(SensorGraph.speedStep(1200...5800) == 2300)
        let marks = SensorGraph.marks(25...100, step: 5)
        #expect(SensorGraph.written(marks, range: 25...100, height: 400, caption: 10) == marks)
        // Low: the ends always, those between only clear of their neighbours.
        let low = SensorGraph.written(marks, range: 25...100, height: 44, caption: 10)
        #expect(low.first == 25 && low.last == 100 && low.count < marks.count)
        for (lower, upper) in zip(low, low.dropFirst()) {
            #expect(SensorGraph.captionTop((lower - 25) / 75, height: 44, caption: 10)
                    - SensorGraph.captionTop((upper - 25) / 75, height: 44, caption: 10) >= 10)
        }
        var look = ChartLook()
        look.valueStep = -3
        look.sanitize()
        #expect(look.valueStep == nil)
    }

    @Test func aGraphsRangeIsItsOwnUntilAnEndIsSet() throws {
        var look = ChartLook()
        #expect(look.range(own: 30...110, gap: 5) == 30...110)
        look.rangeMinimum = 40
        #expect(look.range(own: 30...110, gap: 5) == 40...110)
        look.rangeMaximum = 42
        // The highest stays above the lowest.
        #expect(look.range(own: 30...110, gap: 5) == 40...45)
        let stored = try JSONDecoder().decode(ChartLook.self, from: JSONEncoder().encode(look))
        #expect(stored == look && stored != .plain)
        look.rangeMinimum = .infinity
        look.sanitize()
        #expect(look.rangeMinimum == nil && look.rangeMaximum == 42)
    }

    @Test func theFansDialNamesItsMode() {
        #expect(FanControlWidget.nameText(manual: false, access: .ready, showsMode: true) == "Fan")
        #expect(FanControlWidget.nameText(manual: true, access: .ready, showsMode: true) == "Manual")
        #expect(FanControlWidget.nameText(manual: true, access: .ready, showsMode: false) == "Fan")
        #expect(FanControlWidget.nameText(manual: false, access: .needsApproval, showsMode: true) == "Allow in Login Items")
        #expect(FanControlWidget.isAlert(manual: false, access: .failed("no")) && !FanControlWidget.isAlert(manual: false, access: .unknown))
    }

    @Test func aGraphsColoursAreItsOwnUntilOneIsPicked() {
        let model = AppModel()
        let own: [Color] = [.blue, .green, .yellow, .red]
        var look = ChartLook()
        #expect(SensorGraph.colors(look, automatic: own, model: model) == own)
        look.highColor = .custom(.rgb(1, 0, 1))
        let picked = SensorGraph.colors(look, automatic: own, model: model)
        #expect(picked.count == 3 && picked[0] == .blue && picked[1] == .yellow && picked[2] == IslandTheme.RGB.rgb(1, 0, 1).color)
    }
}

/// The top bar's sides, each put back by itself.
struct HeaderSideResetTests {
    @Test func aSideGoesBackToItsOwnItemsAndTheOtherKeepsItsOwn() {
        var bar = HeaderLayout(leading: [.clock, .settings, .pages], trailing: [.siri, .nowPlaying])
        bar.reset(.leading)
        // The pages alone on the left; Settings must stay in the bar, so it went to the right; the
        // clock is out.
        #expect(bar.leading == [.pages])
        #expect(bar.trailing == [.siri, .nowPlaying, .settings])
        bar.reset(.trailing)
        #expect(bar.leading == [.pages] && bar.trailing == HeaderLayout.standard.trailing)
        var moved = HeaderLayout(leading: [.battery], trailing: [.pages, .settings])
        moved.reset(.trailing)
        // The battery comes back from the left; the pages, which must stay, go there.
        #expect(moved.trailing == HeaderLayout.standard.trailing && moved.leading == [.pages])
    }
}

struct HeaderBarsResetTests {
    @Test func bothBarsGoBackAndThePagesStay() {
        var bar = HeaderLayout(leading: [.clock, .settings], trailing: [.pages, .siri], hiddenPages: [.battery],
                               pageOrder: [.shelf, .home, .timer, .battery])
        bar.resetBars()
        #expect(bar.leading == HeaderLayout.standard.leading && bar.trailing == HeaderLayout.standard.trailing)
        #expect(bar.hiddenPages == [.battery] && bar.pageOrder.first == .shelf)
    }
}

struct HeaderTintTests {
    @Test func eachButtonAndPageKeepsItsOwnColourWithTheBar() throws {
        var bar = HeaderLayout.standard
        let fresh = try JSONDecoder().decode(HeaderLayout.self, from: JSONEncoder().encode(bar))
        #expect(fresh.itemTints.isEmpty && fresh.pageTints.isEmpty && fresh.hasStandardBars)
        bar.setTint(.rgb(1, 0.5, 0), of: [.item(.settings), .page(.shelf)])
        bar.setTint(.rgb(0, 0.5, 1), of: [.item(.siri)])
        bar.place(.toggle(.airDrop), on: .trailing, at: 0)
        let stored = try JSONDecoder().decode(HeaderLayout.self, from: JSONEncoder().encode(bar))
        #expect(stored == bar && stored.trailing.first == .toggle(.airDrop))
        #expect(stored.tint(of: .item(.settings)) == .rgb(1, 0.5, 0) && stored.tint(of: .page(.shelf)) == .rgb(1, 0.5, 0))
        #expect(stored.tint(of: .item(.siri)) == .rgb(0, 0.5, 1) && stored.tint(of: .item(.pin)) == nil && stored.tint(of: .page(.home)) == nil)
        // Fifteen: three to a row, five rows, none left over.
        #expect(HeaderItem.allCases.count == 15 && HeaderItem(rawValue: "toggle.airDrop") == .toggle(.airDrop))
        // One alone back in its own colour; Reset Bars takes them all.
        bar.setTint(nil, of: [.item(.siri)])
        #expect(bar.itemTints.count == 1 && !bar.hasStandardBars)
        bar.resetBars()
        #expect(bar.itemTints.isEmpty && bar.pageTints.isEmpty && bar.hasStandardBars)
    }

    @Test func aPageGoneTakesItsColourAndThePickerHasNone() {
        var bar = HeaderLayout.standard
        let page = bar.addCustomPage(title: "Page 2")!
        bar.setTint(.rgb(1, 0, 0), of: [.page(page), .item(.pages)])
        bar.sanitize()
        #expect(bar.pageTints[page] == .rgb(1, 0, 0) && bar.itemTints[.pages] == nil)
        bar.removeCustomPage(page)
        #expect(bar.pageTints.isEmpty)
    }
}

@MainActor struct HeaderPickTests {
    @Test func aClickPicksOneAndCommandClickMore() {
        let studio = WidgetStudio()
        studio.pick(.item(.settings), adding: false)
        #expect(studio.headerPicks == [.item(.settings)] && studio.headerSelection == .settings)
        studio.pick(.page(.shelf), adding: true)
        #expect(studio.headerPicks == [.item(.settings), .page(.shelf)] && studio.headerSelection == nil)
        // A plain click on another is that one alone; on the only pick, none.
        studio.pick(.item(.siri), adding: false)
        #expect(studio.headerPicks == [.item(.siri)])
        studio.pick(.item(.siri), adding: false)
        #expect(studio.headerPicks.isEmpty)
        studio.pick(.item(.pin), adding: true)
        studio.pick(.item(.pin), adding: true)
        #expect(studio.headerPicks.isEmpty)
    }
}

@MainActor struct EditHistoryTests {
    @Test func stepsBackAndForwardAndADragIsOneStep() {
        var history = EditHistory<Int>()
        #expect(!history.canUndo && history.undo(from: 0) == nil)
        history.note(from: 0, to: 1, at: 10)
        // Within the same drag: no step of its own.
        history.note(from: 1, to: 2, at: 10.2)
        history.note(from: 2, to: 3, at: 12)
        #expect(history.undoStack == [0, 2])
        #expect(history.undo(from: 3) == 2)
        // The change the step back itself makes is no step.
        history.note(from: 3, to: 2, at: 12.1)
        #expect(history.undoStack == [0] && history.redoStack == [3])
        #expect(history.undo(from: 2) == 0 && history.redo(from: 0) == 2 && history.redo(from: 2) == 3)
        history.note(from: 2, to: 3, at: 12.2)
        #expect(history.undoStack == [0, 2] && !history.canRedo)
        // Something new after a step back: nothing to make again.
        _ = history.undo(from: 3)
        history.note(from: 3, to: 2, at: 12.3)
        history.note(from: 2, to: 7, at: 20)
        #expect(history.undoStack == [0, 2] && !history.canRedo)
    }
}
