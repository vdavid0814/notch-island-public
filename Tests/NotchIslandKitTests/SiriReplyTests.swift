import CoreGraphics
import Foundation
import Testing
@testable import NotchIslandKit

@Suite struct SiriReplyTests {
    @Test func photoLabelsGiveTheirMinute() {
        let calendar = Calendar.current
        let a = SiriPictures.date(in: "2026. Jul 8. at 20:20")
        #expect(a.map { calendar.dateComponents([.year, .month, .day, .hour, .minute], from: $0) }
            == DateComponents(year: 2026, month: 7, day: 8, hour: 20, minute: 20))
        let b = SiriPictures.date(in: "2025. Oct 21. at 16:25, Duration 0:10, is favourite")
        #expect(b.map { calendar.component(.month, from: $0) } == 10)
        let c = SiriPictures.date(in: "Jul 8, 2026 at 7:05")
        #expect(c.map { calendar.component(.hour, from: $0) } == 7)
        #expect(SiriPictures.date(in: "a dog") == nil)
    }

    @Test func photoLabelsTellVideosAndFavourites() {
        let video = SiriPhoto(id: 0, label: "2025. Oct 21. at 16:25, Duration 0:10, is favourite")
        #expect(video.isVideo && video.duration == "0:10" && video.isFavourite)
        let still = SiriPhoto(id: 1, label: "2026. Jul 8. at 20:20")
        #expect(!still.isVideo && still.duration == nil && !still.isFavourite)
    }

    @Test func aReplysTextIsItsParagraphs() {
        let reply = SiriReply(blocks: [
            .paragraph([SiriRun(text: "The Moon is "), SiriRun(text: "384 400 km", bold: true), SiriRun(text: " away.")], heading: false),
            .sources(["nasa.gov"]),
            .image("Moon"),
            .paragraph([SiriRun(text: "Second.")], heading: false),
        ])
        #expect(reply.text == "The Moon is 384 400 km away.\n\nSecond.")
        #expect(!reply.isEmpty && SiriReply().isEmpty)
    }

    @Test func linksGoAndComeBackByTheirTitle() {
        let text = SiriLink.text([SiriRun(text: "the "), SiriRun(text: "Moon & Earth", link: true)])
        let url = text.runs.compactMap(\.link).first
        #expect(url.flatMap(SiriLink.title(in:)) == "Moon & Earth")
        #expect(SiriLink.title(in: URL(string: "https://apple.com")!) == nil)
    }

    @Test func anAnswerIsAsTallAsItIsUpToItsMost() {
        let layout = IslandLayout(notch: CGSize(width: 156, height: 28), scale: .standard)
        let short = layout.size(for: .assistant(.answer(60))).height
        let tall = layout.size(for: .assistant(.answer(400))).height
        let huge = layout.size(for: .assistant(.answer(5000))).height
        #expect(short < layout.size(for: .assistant(.list)).height)
        #expect(tall - short == 340)
        #expect(huge > tall && huge == layout.size(for: .assistant(.answer(9999))).height)
    }
}
