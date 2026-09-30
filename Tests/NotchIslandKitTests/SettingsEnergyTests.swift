import AppKit
import SwiftUI
import Testing
@testable import NotchIslandKit

/// Draws a view the way the window does (its layers, nested hosting views included) into 8-bit
/// premultiplied RGBA, at 2×.
///
/// Blind to what only the render server draws: `cacheDisplay` leaves out Liquid Glass entirely (a
/// glass capsule over red gives the bare red) and layer shadows. Fine for the gallery's previews,
/// which hold neither (`eachPreviewDrawsAsItDidInTheGallerysGraph`); anything with glass needs a
/// frozen-frame screenshot A/B instead.
@MainActor private func windowPixels(_ view: some View, size: CGSize) -> [UInt8] {
    let host = NSHostingView(rootView: view)
    let window = NSWindow(contentRect: CGRect(x: -10_000, y: -10_000, width: size.width, height: size.height),
                          styleMask: .borderless, backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: .darkAqua)
    window.contentView = host
    host.frame = CGRect(origin: .zero, size: size)
    host.layoutSubtreeIfNeeded()
    host.displayIfNeeded()
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 32)!
    rep.size = size
    host.cacheDisplay(in: host.bounds, to: rep)
    window.contentView = nil
    return Array(UnsafeBufferPointer(start: rep.bitmapData!, count: rep.bytesPerRow * rep.pixelsHigh))
}

private func largestDifference(_ a: [UInt8], _ b: [UInt8]) -> Int {
    guard a.count == b.count else { return .max }
    return zip(a, b).map { abs(Int($0) - Int($1)) }.max() ?? 0
}

/// The first hosting view nested inside `host`.
@MainActor private func nestedHost(in host: NSView) -> NSView? {
    func search(_ view: NSView) -> NSView? {
        for sub in view.subviews {
            if String(describing: type(of: sub)).contains("HostingView") { return sub }
            if let found = search(sub) { return found }
        }
        return nil
    }
    return search(host)
}

/// The render-server fade the SwiftUI `.easeOut(duration:)` opacity fade became.
@MainActor private func expectFadeIn(on view: NSView, duration: TimeInterval) throws {
    let fade = try #require(view.layer?.animation(forKey: NSView.fadeInKey) as? CABasicAnimation)
    #expect(fade.keyPath == "opacity")
    #expect(fade.fromValue as? Double == 0 && fade.toValue as? Double == 1)
    #expect(fade.duration == duration)
    #expect(fade.timingFunction == CAMediaTimingFunction(name: .easeOut))
}

@MainActor @Suite struct GalleryPreviewTests {
    /// Settings' pages as the gallery sits in them (`IslandSettingsView`, `SettingsDetail`).
    private func inSettings(_ content: some View, model: AppModel) -> some View {
        content
            .formStyle(.settings)
            .toggleStyle(.islandSwitch)
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .environment(model)
            .environment(\.colorScheme, .dark)
            .environment(\.appearsActive, true)
    }

    /// The preview as the gallery drew it in its own graph, before it had one of its own.
    private struct InlinePreview: View {
        let kind: IslandWidgetKind
        let grid: BoardGrid
        @Environment(AppModel.self) private var model

        var body: some View {
            let geometry = WidgetBoardGeometry(size: WidgetsSettingsPage.boardSize(model.layout), grid: grid)
            let cells = grid.defaultSize(for: kind)
            let rect = GridRect(column: 0, row: 0, width: cells.width, height: cells.height)
            let size = geometry.frame(for: rect).size
            let scale = min(1, 176 / size.width, 60 / size.height)
            IslandWidgetView(widget: IslandWidget(kind: kind, frame: rect, options: kind.defaultOptions),
                             size: size, thumbnails: ThumbnailCache())
                .environment(\.isWidgetPreview, true)
                .environment(\.colorScheme, .dark)
                .allowsHitTesting(false)
                .frame(width: size.width, height: size.height)
                .scaleEffect(scale)
                .frame(width: size.width * scale, height: size.height * scale)
        }
    }

    /// Every preview in its own graph draws exactly what it drew in the gallery's: the same
    /// styles reach it and it sits on the same fraction of a pixel in its well.
    ///
    /// Previews hold no glass, so `windowPixels` sees all of them: a widget's only glass is its
    /// buttons, which previews draw as the system's bordered ones (`IslandGlassButtonStyle`), and
    /// Now Playing's per-button glass, which a preview (the kind's defaults, `plainButtons`) never
    /// has; no widget background is glass or a material.
    @Test func eachPreviewDrawsAsItDidInTheGallerysGraph() {
        let model = AppModel()
        let grid = model.widgets.board.grid
        // A well 230 pt wide (a 250 pt card), as the gallery lays them out in a 1180 pt Settings.
        let well = CGSize(width: 230, height: 78)
        for kind in IslandWidgetKind.allCases where kind.isOffered {
            let inline = inSettings(ZStack { InlinePreview(kind: kind, grid: grid) }.frame(width: well.width, height: well.height), model: model)
            let nested = inSettings(ZStack { WidgetPreview(kind: kind, grid: grid, maxSize: CGSize(width: 176, height: 60)) }
                .frame(width: well.width, height: well.height), model: model)
            let before = windowPixels(inline, size: well), after = windowPixels(nested, size: well)
            let difference = largestDifference(before, after)
            // A clock turning its minute between the two drawings: drawn again.
            let settled = difference == 0 ? 0 : largestDifference(windowPixels(inline, size: well), windowPixels(nested, size: well))
            #expect(settled == 0, "\(kind.rawValue): largest channel difference \(settled)")
            #expect(before.contains { $0 != 0 }, "\(kind.rawValue) drew nothing")
        }
    }

    /// The preview fades in on the render server, as long as the SwiftUI fade it replaced and on
    /// its curve; it takes no clicks, so the card keeps its tooltip and hover.
    @Test func thePreviewFadesInOnTheRenderServerAndPassesEventsOn() throws {
        let model = AppModel()
        let host = NSHostingView(rootView: ZStack {
            WidgetPreview(kind: .battery, grid: model.widgets.board.grid, maxSize: CGSize(width: 176, height: 60))
        }
        .frame(width: 230, height: 78)
        .environment(model))
        host.frame = CGRect(x: 0, y: 0, width: 230, height: 78)
        host.layoutSubtreeIfNeeded()
        let preview = try #require(nestedHost(in: host))
        try expectFadeIn(on: preview, duration: WidgetPreview.fadeIn)
        #expect(preview.hitTest(CGPoint(x: 115, y: 39)) == nil)
    }
}

/// One at a time: closing Settings clears the shared desktop lookup (`WallpaperLibrary.purge`).
@MainActor @Suite(.serialized) struct SettingsWindowTests {
    @MainActor @Suite struct RenderServerFadeTests {
        /// Settings' pages fade in on the render server once the island has grown, as long as the
        /// SwiftUI fade they replaced and on its curve.
        @Test func thePagesFadeInOnTheRenderServer() async throws {
            let model = AppModel()
            let size = model.layout.size(for: .settings)
            let host = NSHostingView(rootView: IslandSettingsView().environment(model))
            let window = NSWindow(contentRect: CGRect(x: -10_000, y: -10_000, width: size.width, height: size.height),
                                  styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = host
            defer { window.contentView = nil }
            host.frame = CGRect(origin: .zero, size: size)
            // The pages join most of an opening after it starts: looked for as soon as they are in.
            let deadline = Date.now.addingTimeInterval(model.preferences.animationDuration + 10)
            var pages: NSView?
            while pages == nil, Date.now < deadline {
                try await Task.sleep(for: .milliseconds(5))
                host.layoutSubtreeIfNeeded()
                pages = nestedHost(in: host)
            }
            try expectFadeIn(on: try #require(pages), duration: IslandSettingsView.pagesFadeIn)
        }

        /// `demo/freeze` holds the fade at the frozen moment, or at its end past it.
        @Test func aFrozenFadeHoldsItsMoment() throws {
            defer { LeanSpring.frozenTime = nil }
            for (frozen, held) in [(0.05, 0.05), (1.0, 0.2)] {
                LeanSpring.frozenTime = frozen
                let view = NSView()
                view.fadeInOnRenderServer(duration: 0.2)
                let fade = try #require(view.layer?.animation(forKey: NSView.fadeInKey))
                #expect(fade.speed == 0 && fade.timeOffset == held)
                #expect(fade.fillMode == .both && !fade.isRemovedOnCompletion)
            }
            LeanSpring.frozenTime = nil
            let view = NSView()
            view.fadeInOnRenderServer(duration: 0.2)
            #expect(view.layer?.animation(forKey: NSView.fadeInKey)?.speed == 1)
        }
    }

    @MainActor @Suite struct DesktopLookupTests {
        /// The appearance is read from the application, as in the app.
        init() { _ = NSApplication.shared }
        /// The stamp changes with what the desktop is looked up from, and only with that.
        @Test func theStampFollowsTheStoreTheCatalogueAndTheSpace() throws {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            let index = folder.appendingPathComponent("Index.plist"), catalogue = folder.appendingPathComponent("entries.json")
            try Data("a".utf8).write(to: index)
            try Data("b".utf8).write(to: catalogue)
            func stamp(_ spaces: Int = 0) -> DesktopStamp { DesktopStamp.current(spaceSwitches: spaces, index: index, catalogue: catalogue) }

            let first = stamp()
            #expect(first.index != nil && first.catalogue != nil)
            #expect(stamp() == first)
            #expect(stamp(1) != first)

            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: 60)], ofItemAtPath: index.path)
            let chosen = stamp()
            #expect(chosen != first)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: 120)], ofItemAtPath: catalogue.path)
            #expect(stamp() != chosen)
        }

        /// The pictures of one opening share one lookup; closing Settings lets the next opening look
        /// again.
        @Test func picturesShareOneLookupUntilSettingsCloses() async {
            let library = WallpaperLibrary.shared
            library.purge()
            async let first = library.desktopSource()
            async let second = library.desktopSource()
            let sources = await [first, second]
            #expect(sources[0] == sources[1])
            let lookup = library.desktop?.lookup
            #expect(lookup != nil)
            _ = await library.desktopSource()
            #expect(library.desktop?.lookup == lookup)
            library.purge()
            #expect(library.desktop == nil)
        }
    }
}
