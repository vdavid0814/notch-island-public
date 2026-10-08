import Foundation
import Testing
@testable import NotchIslandKit

@Suite struct ButtonLookTests {
    private func widget() -> IslandWidget {
        IslandWidget(kind: .nowPlaying, frame: GridRect(column: 0, row: 0, width: 7, height: 3),
                     options: IslandWidgetKind.nowPlaying.defaultOptions)
    }

    /// A button's look is kept with the widget, and comes back as it was.
    @Test func aLookIsStoredWithTheWidget() throws {
        var look = ButtonLook()
        look.material = .glass
        look.shape = .capsule
        look.corners = .rounded
        look.fill = .colour
        look.fillColor = IslandTheme.RGB(red: 0.2, green: 0.4, blue: 1)
        look.size = 1.25
        look.iconScale = 1.3
        look.iconOffset = ElementOffset(x: 0.1, y: -0.05)
        look.iconEdges = .sharp
        look.iconFill = .none
        var widget = widget()
        widget.setButtonLook(look, of: .playbackButtons)
        let decoded = try JSONDecoder().decode(IslandWidget.self, from: JSONEncoder().encode(widget))
        #expect(decoded.buttonLook(of: .playbackButtons) == look)
        #expect(decoded == widget)
    }

    /// The plain look is no look; a look on a part that is not a button, or a kind without
    /// buttons, is dropped.
    @Test func onlyButtonsKeepALook() {
        var widget = widget()
        var look = ButtonLook()
        look.material = .solid
        widget.setButtonLook(.plain, of: .playbackButtons)
        #expect(widget.buttonLooks.isEmpty)
        widget.buttonLooks[.trackInfo] = look
        widget.buttonLooks[.nextButton] = look
        widget.sanitize()
        #expect(widget.buttonLooks.keys.sorted { $0.rawValue < $1.rawValue } == [.nextButton])
    }

    /// The symbol's size and place stay within what the panel offers.
    @Test func theSymbolStaysInside() {
        var look = ButtonLook()
        look.iconScale = 9
        look.iconOffset = ElementOffset(x: 3, y: -.infinity)
        look.sanitize()
        #expect(look.iconScale == ButtonLook.iconScales.upperBound)
        #expect(look.iconOffset == .zero)
        look.iconOffset = ElementOffset(x: 3, y: -2)
        look.size = 0.1
        look.sanitize()
        #expect(look.iconOffset == ElementOffset(x: 0.5, y: -0.5))
        #expect(look.size == ButtonLook.sizes.lowerBound)
    }

    /// A look stored by a later version (a material this one does not know) reads as far as it can.
    @Test func unknownValuesFallBack() throws {
        let json = #"{"material":"metal","shape":"capsule","iconScale":1.5}"#
        let look = try JSONDecoder().decode(ButtonLook.self, from: Data(json.utf8))
        #expect(look.material == .regular)
        #expect(look.shape == .capsule)
        #expect(look.iconScale == 1.5)
    }

    /// A circle with sharp corners is a square, with rounded ones a rounded square; round, a circle.
    @Test func cornersMakeTheShape() {
        #expect(ButtonLook.Corners.sharp.radius(height: 40) == 0)
        #expect(ButtonLook.Corners.rounded.radius(height: 40) > 0)
        #expect(ButtonLook.Corners.rounded.radius(height: 40) < 20)
        #expect(ButtonLook.Corners.round.radius(height: 40) == 20)
    }

    /// A button drawn past its widget's edge is moved in; one that fits stays over its symbol.
    @MainActor @Test func aButtonStaysInsideItsWidget() {
        let widget = CGSize(width: 300, height: 140)
        var look = ButtonLook()
        look.material = .solid
        let middle = CGRect(x: 140, y: 60, width: 20, height: 20)
        #expect(WidgetButtonLabel.shift(room: middle, drawn: CGSize(width: 34, height: 34), widget: widget) == .zero)
        // At the bottom edge: 7 points past it, moved up to 3 points inside.
        let bottom = CGRect(x: 140, y: 120, width: 20, height: 20)
        let frame = WidgetButtonLabel.drawnFrame(of: look, points: 20, room: bottom, widget: widget)
        #expect(frame.maxY == widget.height - WidgetButtonLabel.edgeInset)
        #expect(frame.midX == bottom.midX)
        // Regular: the symbol at its size, over its room.
        look.material = .regular
        look.iconScale = 2
        #expect(WidgetButtonLabel.drawnFrame(of: look, points: 20, room: middle, widget: widget).size == CGSize(width: 40, height: 40))
    }

    /// A shape is about as large as the symbol alone was, and its symbol smaller inside it; the
    /// shape's own size makes it larger without the symbol.
    @MainActor @Test func aShapeKeepsTheButtonsSize() {
        var look = ButtonLook()
        look.material = .solid
        let size = WidgetButtonLabel.size(of: look, points: 20)
        #expect(size.width <= 28)
        #expect(WidgetButtonLabel.iconScale(of: look, symbol: "play.fill") < 1)
        look.size = 1.5
        #expect(WidgetButtonLabel.size(of: look, points: 20).width > size.width)
        #expect(WidgetButtonLabel.iconScale(of: look, symbol: "play.fill") == WidgetButtonLabel.shapedIcon)
        // Back and forward, a circle with its seconds, fill their shape more.
        #expect(WidgetButtonLabel.iconScale(of: look, symbol: "gobackward.15") == WidgetButtonLabel.shapedSeekIcon)
        look.material = .regular
        #expect(WidgetButtonLabel.iconScale(of: look, symbol: "play.fill") == 1)
    }
}
