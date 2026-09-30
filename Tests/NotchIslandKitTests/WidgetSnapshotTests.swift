import AppKit
import SwiftUI
import Testing
@testable import NotchIslandKit

/// Every offered kind at each of its size presets, with its default elements, drawn as a picture
/// (the gallery's preview mode) and compared pixel for pixel with `Snapshots/<kind>-<w>x<h>.png`.
/// A mismatch leaves the new picture in `$TMPDIR/WidgetSnapshots/` to compare.
///
/// Run on their own they are exact, run after run. Other suites drawing in the same process shift a
/// few values of some pictures by 1 in 255 (measured: up to 59 values, text and gradients — what
/// was drawn before is kept between pictures), so they run in a process of their own: only with
/// `NI_SNAPSHOTS` set — `verify`, or `record` to write the pictures instead. `Scripts/test.sh`
/// without a filter runs the suite without them, then them alone with `NI_SNAPSHOTS=verify`; a
/// filter that selects them sets it too.
@MainActor @Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["NI_SNAPSHOTS"] != nil,
                                        "run alone: Scripts/test.sh, or NI_SNAPSHOTS=verify"))
struct WidgetSnapshotTests {
    nonisolated struct Case: Sendable, CustomTestStringConvertible {
        let kind: IslandWidgetKind
        let size: GridSize

        var name: String { "\(kind.rawValue)-\(size.width)x\(size.height)" }
        var testDescription: String { name }
    }

    nonisolated static let cases: [Case] = IslandWidgetKind.allCases.filter(\.isOffered).flatMap { kind in
        kind.sizePresets.map { Case(kind: kind, size: $0) }
    }

    /// Thursday 24 September 2026, 9:41: the clock's widgets show it instead of the time now.
    static let date = Date(timeIntervalSince1970: 1_790_235_660)

    static let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Snapshots")

    @Test(arguments: cases) func matchesItsSnapshot(_ item: Case) throws {
        // Compared as stored: the renderer's deeper pixels, rounded to the PNG's 8 bits.
        let data = Self.png(try #require(Self.render(item)))
        let url = Self.directory.appendingPathComponent(item.name + ".png")
        if ProcessInfo.processInfo.environment["NI_SNAPSHOTS"] == "record" {
            try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
            try data.write(to: url)
            return
        }
        let recorded = try #require(try? Data(contentsOf: url), "no snapshot \(item.name).png: record with NI_SNAPSHOTS=record")
        let (new, old) = (Self.pixels(data), Self.pixels(recorded))
        let same = new == old
        if !same {
            let failures = FileManager.default.temporaryDirectory.appendingPathComponent("WidgetSnapshots")
            try FileManager.default.createDirectory(at: failures, withIntermediateDirectories: true)
            try data.write(to: failures.appendingPathComponent(item.name + ".png"))
        }
        let differences = zip(new, old).map { max($0, $1) - min($0, $1) }.filter { $0 > 0 }
        #expect(same, "\(item.name) differs from its snapshot: \(differences.count) values, by up to \(differences.max() ?? 0)")
    }

    /// On the island's black, at the standard island size, in the board's top-left corner (a widget
    /// three rows tall reaches the panel's bottom-left corner).
    static func render(_ item: Case) -> CGImage? {
        let layout = IslandLayout(notch: CGSize(width: 185, height: 32), scale: .standard)
        let geometry = WidgetBoardGeometry(size: WidgetsSettingsPage.boardSize(layout), grid: .standard)
        let rect = GridRect(column: 0, row: 0, width: item.size.width, height: item.size.height)
        let size = geometry.frame(for: rect).size
        let widget = IslandWidget(kind: item.kind, frame: rect, options: item.kind.defaultOptions)
        let view = IslandWidgetView(widget: widget, size: size, thumbnails: ThumbnailCache())
            .frame(width: size.width, height: size.height)
            .background(.black)
            .environment(AppModel())
            .environment(\.isWidgetPreview, true)
            .environment(\.widgetBoard, WidgetBoardShape(grid: .standard, cornerRadius: ConcentricGeometry.boardCornerRadius(layout)))
            .environment(\.widgetDate, date)
            // The same on every Mac: English with a 24-hour clock, in Budapest (where 9:41 is 07:41 UTC).
            .environment(\.locale, Locale(identifier: "en_US@hours=h23"))
            .environment(\.timeZone, TimeZone(identifier: "Europe/Budapest")!)
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return renderer.cgImage
    }

    static func png(_ image: CGImage) -> Data {
        NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) ?? Data()
    }

    /// A PNG's pixels as 8-bit RGBA, and its size.
    static func pixels(_ png: Data) -> [UInt8] {
        guard let image = NSBitmapImageRep(data: png)?.cgImage else { return [] }
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                                    bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return bytes + [UInt8(truncatingIfNeeded: image.width), UInt8(truncatingIfNeeded: image.height)]
    }
}
