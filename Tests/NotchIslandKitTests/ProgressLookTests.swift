import Foundation
import Testing
@testable import NotchIslandKit

@Suite struct ProgressLookTests {
    private func widget() -> IslandWidget {
        IslandWidget(kind: .nowPlaying, frame: GridRect(column: 0, row: 0, width: 7, height: 3),
                     options: IslandWidgetKind.nowPlaying.defaultOptions)
    }

    /// The line's look and its times' styles are kept with the widget, and come back as they were.
    @Test func aLineIsStoredWithTheWidget() throws {
        var look = ProgressLook()
        look.trackColor = .custom(IslandTheme.RGB(red: 0.2, green: 0.3, blue: 0.6))
        look.fillColor = .artwork
        look.ends = .sharp
        look.knob = .capsule
        look.barLength = 0.75
        look.barThickness = 1.5
        look.remainingOffset = ElementOffset(x: -12, y: 3)
        var widget = widget()
        widget.setProgressLook(look, of: .progress)
        var style = TextStyle()
        style.isBold = true
        style.alignment = .center
        widget.setTextStyle(style, of: .remainingTime)
        let decoded = try JSONDecoder().decode(IslandWidget.self, from: JSONEncoder().encode(widget))
        #expect(decoded.progressLook(of: .progress) == look)
        #expect(decoded.textStyle(of: .remainingTime) == style)
        #expect(decoded == widget)
    }

    /// The plain look is no look; a look on a part that is not a line is dropped, and so is a
    /// style for a text the kind does not have.
    @Test func onlyLinesKeepALook() {
        var widget = widget()
        var look = ProgressLook()
        look.knob = .circle
        widget.progressLooks[.artist] = look
        widget.progressLooks[.progress] = .plain
        var style = TextStyle()
        style.isItalic = true
        widget.textStyles[.readout] = style
        widget.sanitize()
        #expect(widget.progressLooks.isEmpty)
        #expect(widget.textStyles[.readout] == nil)
    }

    /// A look stored by a later version reads as far as it can.
    @Test func unknownValuesFallBack() throws {
        let json = #"{"ends":"wavy","knob":"square","barLength":0.5,"stylesElapsed":true}"#
        let look = try JSONDecoder().decode(ProgressLook.self, from: Data(json.utf8))
        #expect(look.ends == .round)
        #expect(look.knob == .square)
        #expect(look.barLength == 0.5)
    }

    /// The line's length and thickness stay within what the panel offers.
    @Test func theLineStaysWithinItsSizes() {
        var look = ProgressLook()
        look.barLength = 3
        look.barThickness = 0
        look.elapsedOffset = ElementOffset(x: .nan, y: 2)
        look.sanitize()
        #expect(look.barLength == ProgressLook.barLengths.upperBound)
        #expect(look.barThickness == ProgressLook.barThicknesses.lowerBound)
        #expect(look.elapsedOffset == .zero)
    }

    /// The knob sits on the end of the part played, never past the line's start.
    @Test func theKnobSitsOnTheEnd() {
        #expect(PlayedLineView.knobCentre(100, height: 7, knob: 13) == 96.5)
        #expect(PlayedLineView.knobCentre(7, height: 7, knob: 13) == 6.5)
    }
}
