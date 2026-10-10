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
        #expect(ProgressLook.Part.remaining.textID(in: .fanDial) == .fanUnit)
        #expect(ProgressLook.Part.elapsed.textID(in: .tempDial) == .tempName)
        #expect(ProgressLook.Part.remaining.textID(in: .tempDial) == .tempValue)
        #expect(ProgressLook.Part.remaining.textID(in: .levelSlider) == nil)
        #expect(ProgressLook.Part.remaining.textID(in: .progress) == .remainingTime)
        #expect(ProgressLook.Part.bar.title(in: .fanDial, isRing: true) == "Ring")
        #expect(ProgressLook.Part.remaining.title(in: .fanDial) == "Unit")
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
        widget.textStyles = [.fanName: text, .fanUnit: text, .tempName: text, .tempValue: text, .tempGraphText: text,
                             .rpmGraphText: text, .fanDial: text]
        widget.sanitize()
        #expect(Set(widget.progressLooks.keys) == [.fanDial, .tempDial])
        #expect(Set(widget.chartLooks.keys) == [.tempGraph, .rpmGraph])
        #expect(Set(widget.textStyles.keys) == [.fanName, .fanUnit, .tempName, .tempValue, .tempGraphText, .rpmGraphText])
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

    @Test func aGraphWritesTheValuesThatFit() {
        var look = ChartLook()
        #expect(SensorGraph.guides(look) == [0, 50, 100])
        look.percentStep = 0
        // None written: the top and the bottom keep their guides.
        #expect(SensorGraph.guides(look) == [0, 100] && look.percentages.isEmpty)
        look.percentStep = 10
        let tall = SensorGraph.written(look.percentages, height: 200, caption: 10)
        #expect(tall == look.percentages)
        // Low: the ends always, those between only clear of their neighbours.
        let low = SensorGraph.written(look.percentages, height: 44, caption: 10)
        #expect(low.first == 0 && low.last == 100 && low.count < look.percentages.count)
        for (lower, upper) in zip(low, low.dropFirst()) {
            #expect(SensorGraph.captionTop(lower, height: 44, caption: 10) - SensorGraph.captionTop(upper, height: 44, caption: 10) >= 10)
        }
        #expect(ChartLook.title(ofGraphStep: 25) == "Every quarter")
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
