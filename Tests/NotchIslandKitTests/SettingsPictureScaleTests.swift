import CoreGraphics
import Testing
@testable import NotchIslandKit

/// How large a Settings page shows its pictures (`MiniMetrics.pictureScale`).
@Suite struct SettingsPictureScaleTests {
    @Test func thePicturesGrowWithThePageUpToTheirLargest() {
        // The reference Mac's room (Settings 1180 pt wide), and a wider one.
        #expect(MiniMetrics.pictureScale(pageWidth: 920) == MiniMetrics.largestPictureScale)
        #expect(MiniMetrics.pictureScale(pageWidth: 1316) == MiniMetrics.largestPictureScale)
        // With larger text (a 1024 pt screen): as drawn.
        #expect(MiniMetrics.pictureScale(pageWidth: 664) == 1)
        // The smallest Settings (820 pt wide): smaller than drawn, so the row of five fits.
        #expect(MiniMetrics.pictureScale(pageWidth: 560) == 0.8)
    }

    @Test func theWidestRowFitsItsCardAtEveryWidth() {
        for width in stride(from: CGFloat(400), through: 1600, by: 7) {
            let scale = MiniMetrics.pictureScale(pageWidth: width)
            #expect(scale * MiniMetrics.widestRow <= width - 2 * SettingsForm.inset, "\(width) pt")
        }
    }
}
