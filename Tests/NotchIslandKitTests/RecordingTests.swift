import Foundation
import Testing
@testable import NotchIslandKit

@Suite struct ScreenRecordingTests {
    @Test func commands() {
        #expect(AppCommand.parse(URL(string: "notchisland://record")!) == .toggleRecording)
        #expect(AppCommand.parse(URL(string: "notchisland://demo/recording")!) == .demo(.recording(true)))
        #expect(AppCommand.parse(URL(string: "notchisland://demo/recording?on=0")!) == .demo(.recording(false)))
    }

    /// Named as macOS names a recording, where the Screenshot app saves.
    @Test func movieIsNamedAsMacOSNamesOne() {
        var parts = DateComponents()
        (parts.year, parts.month, parts.day, parts.hour, parts.minute, parts.second) = (2026, 10, 8, 21, 58, 3)
        let date = Calendar.current.date(from: parts)!
        let url = ScreenRecorder.newMovieURL(now: date)
        #expect(url.lastPathComponent == "Screen Recording 2026-10-08 at 21.58.03.mov")
        #expect(url.deletingLastPathComponent() == ScreenRecorder.saveDirectory())
    }

    /// The widget is a control as Wi-Fi is: on while it records, red, never an action.
    @Test @MainActor func widgetIsAControlOnWhileRecording() {
        #expect(IslandWidgetKind.screenRecording.control == .screenRecording)
        #expect(!WidgetControl.screenRecording.isAction)
        #expect(WidgetControl.screenRecording.status(on: true) == "Recording")
        let model = AppModel()
        #expect(!ControlWidget.isOn(.screenRecording, model: model, picture: false))
        model.recorder.demo(true)
        #expect(model.recorder.isRecording && ControlWidget.isOn(.screenRecording, model: model, picture: false))
        #expect(!ControlWidget.isOn(.screenRecording, model: model, picture: true))
        model.recorder.demo(false)
        #expect(!model.recorder.isRecording)
    }
}

@Suite struct MemoryReadoutTests {
    @Test @MainActor func megabytesUnderAGigabyteGigabytesAbove() {
        let locale = Locale(identifier: "en_US")
        let total: UInt64 = 16 << 30
        #expect(SystemReadings.memory(512 << 20, of: total, locale: locale).value == "512 MB")
        #expect(SystemReadings.memory(UInt64(9.6 * Double(1 << 30)), of: total, locale: locale).value.hasSuffix("GB"))
        #expect(SystemReadings.memory(nil, of: total, locale: locale).value == "—")
        #expect(SystemReadings.memory(1 << 30, of: total, locale: locale).caption == "Used of 16 GB")
    }
}

@Suite struct RecordingThumbnailTests {
    /// Save to … moves the movie, under its own name or "… 2" beside one of that name; where it is,
    /// it stays.
    @Test @MainActor func savingMovesItUnderAFreeName() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("thumbnail-\(UUID().uuidString)")
        let from = root.appendingPathComponent("from"), to = root.appendingPathComponent("to")
        try FileManager.default.createDirectory(at: from, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: to, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let movie = from.appendingPathComponent("Screen Recording.mov")
        try Data([1]).write(to: movie)
        try Data([2]).write(to: to.appendingPathComponent("Screen Recording.mov"))
        let moved = try #require(RecordingThumbnail.move(movie, to: to))
        #expect(moved.lastPathComponent == "Screen Recording 2.mov")
        #expect(!FileManager.default.fileExists(atPath: movie.path) && FileManager.default.fileExists(atPath: moved.path))
        #expect(RecordingThumbnail.move(moved, to: to) == moved)
    }
}

@Suite struct PageSwipeTests {
    /// A swipe turns one page in the picker's order, and stops at either end.
    @Test @MainActor func turnsOnePageAndStopsAtTheEnds() throws {
        let model = AppModel()
        let pages = model.pickerPages
        try #require(pages.count >= 2)
        model.island.page = pages[0]
        model.controller.turnPage(by: -1)
        #expect(model.panelPage == pages[0])
        model.controller.turnPage(by: 1)
        #expect(model.panelPage == pages[1])
        model.island.page = pages[pages.count - 1]
        model.controller.turnPage(by: 1)
        #expect(model.panelPage == pages[pages.count - 1])
        model.controller.turnPage(by: -1)
        #expect(model.panelPage == pages[pages.count - 2])
    }
}
