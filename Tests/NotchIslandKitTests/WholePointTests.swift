import CoreGraphics
import Testing
@testable import NotchIslandKit

/// Dragged and resized parts land on whole points: their edges and their sizes, whatever the
/// fractions they started from or the lines they hold to.
@Suite struct WholePointTests {
    private static func isWhole(_ value: CGFloat) -> Bool { value == value.rounded() }

    @Test func aDraggedPartLandsOnWholePoints() {
        var drag = ElementDrag(id: .playbackButtons, base: CGRect(x: 10.3, y: 20.6, width: 27.4, height: 18.2), start: .zero,
                               others: [CGRect(x: 80.7, y: 5.25, width: 30, height: 30)], bounds: CGSize(width: 300, height: 140))
        for step in stride(from: 0.0, through: 120.0, by: 3.7) {
            drag.move(by: CGSize(width: step, height: step / 3))
            #expect(Self.isWhole(drag.frame.minX))
            #expect(Self.isWhole(drag.frame.minY))
        }
    }

    @Test func aResizedPartIsAWholeSize() {
        var resize = ElementResize(id: .playbackButtons, horizontal: 1, vertical: 1, start: CGRect(x: 10.3, y: 20.6, width: 27.4, height: 18.2),
                                   others: [CGRect(x: 80.7, y: 5.25, width: 30, height: 30)], bounds: CGSize(width: 300, height: 140))
        for step in stride(from: 0.0, through: 60.0, by: 2.3) {
            resize.move(by: CGSize(width: step, height: step / 2))
            #expect(Self.isWhole(resize.frame.minX) && Self.isWhole(resize.frame.minY))
            #expect(Self.isWhole(resize.frame.width) && Self.isWhole(resize.frame.height))
        }
    }

    /// Another part's centre line is shown only when the dragged part's centre is on it, not near.
    @Test func aCentreLineShowsOnlyWhenOnIt() {
        let other = CGRect(x: 100, y: 10, width: 30, height: 30)
        let on = ElementDrag(id: .nextButton, base: CGRect(x: 40, y: 15, width: 20, height: 20), start: .zero,
                             others: [other], bounds: CGSize(width: 300, height: 140))
        #expect(on.nearCentres().y == [other.midY])
        let near = ElementDrag(id: .nextButton, base: CGRect(x: 40, y: 17, width: 20, height: 20), start: .zero,
                               others: [other], bounds: CGSize(width: 300, height: 140))
        #expect(near.nearCentres().y.isEmpty)
    }

    /// An arrow key takes a part to the next line that way: its top (or bottom, or centre) on
    /// another part's edge or centre, a whole point or more on; a point where none is near.
    @MainActor @Test func anArrowGoesToTheNextLine() {
        // A part 20 long at 50: lines at 53 (its top 3 on) and 55 (its top 5 on).
        #expect(WidgetElementEditor.nextLine(from: 50, length: 20, direction: 1, lines: [53, 55]) == 3)
        // Down from 53: the next is 55.
        #expect(WidgetElementEditor.nextLine(from: 53, length: 20, direction: 1, lines: [53, 55]) == 2)
        // Its bottom (70) to 72.
        #expect(WidgetElementEditor.nextLine(from: 50, length: 20, direction: 1, lines: [72]) == 2)
        // Up from 55 to 53.
        #expect(WidgetElementEditor.nextLine(from: 55, length: 20, direction: -1, lines: [53, 55]) == 2)
        // Nothing within reach: a point.
        #expect(WidgetElementEditor.nextLine(from: 50, length: 20, direction: 1, lines: [200]) == 1)
    }
}
