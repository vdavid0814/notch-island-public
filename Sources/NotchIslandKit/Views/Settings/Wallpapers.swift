import AppKit
import AVFoundation
import ImageIO
import SwiftUI

/// What every picture of a desktop in Settings shows behind the island: the widget studio's stage,
/// the surface cards and the small pictures of each setting (General ▸ Preview Wallpaper).
nonisolated enum DesktopBackdropStyle: String, CaseIterable, Identifiable, Sendable {
    // In the order the picker shows them.

    /// The picture on this Mac's desktop, whatever it is (an image, or one of the system's moving
    /// wallpapers, pictured by its resting frame).
    case desktop
    /// The macOS default wallpaper, dark: violet folds of light. (Stored as "system", the name the
    /// only default had before there were two.)
    case system
    /// The macOS default wallpaper, light: the same folds in sand and warm grey.
    case systemLight
    /// Black and white squares: a test pattern that shows exactly what the glass lets through.
    case checkerboard

    nonisolated static let key = "ni2.studio.backdrop"
    /// Previews show the user's own desktop until they pick another.
    nonisolated static let defaultStyle = DesktopBackdropStyle.desktop

    var id: String { rawValue }

    var title: String {
        switch self {
        case .desktop: "Your Desktop"
        case .system: "macOS Dark"
        case .systemLight: "macOS Light"
        case .checkerboard: "Test"
        }
    }

    /// The menu bar's text over this wallpaper (macOS draws it dark over a light picture).
    var prefersDarkMenuBar: Bool { self == .systemLight }

    /// A shade behind the menu bar: only the checkerboard needs one to keep its text legible.
    var menuBarBacking: Double { self == .checkerboard ? 0.6 : 0 }
}

// MARK: - Backdrop

/// A desktop for previews: the chosen wallpaper, filling the proposed frame without changing it
/// (a filled image laid out as content grew the view to the picture's aspect ratio, which pushed
/// the island off the top of the widget studio's stage).
struct DesktopBackdrop: View {
    var style: DesktopBackdropStyle

    @State private var picture: NSImage?

    init(style: DesktopBackdropStyle) {
        self.style = style
        // Already loaded: drawn in the first frame, no fade.
        _picture = State(initialValue: WallpaperLibrary.shared.cached(style))
    }

    var body: some View {
        Color.clear
            .overlay {
                // Drawn at once while the picture loads, and in its place if there is none.
                switch style {
                case .checkerboard: Checkerboard()
                case .systemLight: DefaultWallpaper(light: true)
                case .system, .desktop: DefaultWallpaper(light: false)
                }
            }
            // Top-aligned: a preview is the top of a screen, under its menu bar.
            .overlay(alignment: .top) {
                if style != .checkerboard, let picture {
                    Image(nsImage: picture)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                        .transition(.opacity)
                }
            }
            .clipped()
            .animation(.easeOut(duration: 0.25), value: picture == nil)
            .task(id: style) {
                guard style != .checkerboard else { return }
                let image = await WallpaperLibrary.shared.image(for: style)
                guard !Task.isCancelled else { return }
                if image !== picture { picture = image }
            }
            .accessibilityHidden(true)
    }
}

/// The preview wallpaper the user chose (General ▸ Preview Wallpaper), as a backdrop.
struct ChosenDesktopBackdrop: View {
    @AppStorage(DesktopBackdropStyle.key) private var style: DesktopBackdropStyle = DesktopBackdropStyle.defaultStyle

    var body: some View {
        DesktopBackdrop(style: style)
    }
}

// MARK: - Library

/// The wallpapers' pictures, each decoded once (downsampled, off the main thread) and kept while
/// the app runs: Settings shows the same picture in a dozen places.
@MainActor final class WallpaperLibrary {
    static let shared = WallpaperLibrary()

    private var images: [String: NSImage] = [:]
    private var loading: [String: Task<NSImage?, Never>] = [:]
    /// What `.desktop` last resolved to: the picture is looked up again when the desktop changes.
    private var desktopKey: String?
    /// The default wallpaper's videos, light and dark (the catalogue is read once).
    private var defaultSources: [Bool: WallpaperSource] = [:]

    private func systemDefault(light: Bool) -> WallpaperSource {
        if let source = defaultSources[light] { return source }
        let source = WallpaperSource.systemDefault(light: light)
        defaultSources[light] = source
        return source
    }

    /// Long side of the decoded pictures: sharp on the widget studio's stage at 2× (about 880 pt
    /// wide). 2400 kept ~16 MB per picture.
    nonisolated static let maximumPixels = 1800

    /// Settings closed: nothing shows a wallpaper any more, so the decoded pictures go (they are
    /// the only large images the app keeps). The frames cached on disk make the next open quick.
    func purge() {
        for task in loading.values { task.cancel() }
        loading.removeAll()
        images.removeAll()
        desktopKey = nil
        WallpaperSwatch.purge()
    }

    func cached(_ style: DesktopBackdropStyle) -> NSImage? {
        switch style {
        case .checkerboard: nil
        case .desktop: desktopKey.flatMap { images[$0] }
        case .system, .systemLight: images[systemDefault(light: style == .systemLight).key]
        }
    }

    func image(for style: DesktopBackdropStyle) async -> NSImage? {
        let source: WallpaperSource
        switch style {
        case .checkerboard: return nil
        case .desktop:
            source = await WallpaperSource.currentDesktop()
            desktopKey = source.key
        case .system, .systemLight:
            source = systemDefault(light: style == .systemLight)
        }
        if let image = images[source.key] { return image }
        if let task = loading[source.key] { return await task.value }
        let task = Task { () -> NSImage? in
            guard let cgImage = await Self.decode(source) else { return nil }
            return NSImage(cgImage: cgImage, size: .zero)
        }
        loading[source.key] = task
        let image = await task.value
        loading[source.key] = nil
        if let image { images[source.key] = image }
        return image
    }

    @concurrent private static func decode(_ source: WallpaperSource) async -> CGImage? {
        switch source {
        case .image(let url):
            return downsample(url)
        case .aerial(let id):
            // A frame taken once is kept on disk: the next launch reads a small JPEG instead of
            // opening a 4K video.
            let cached = WallpaperSource.cacheDirectory.appendingPathComponent("\(id).jpg")
            if let image = downsample(cached) { return image }
            if let frame = await firstFrame(of: WallpaperSource.aerialVideo(id)) {
                save(frame, to: cached)
                return frame
            }
            // Not downloaded on this Mac: the system's small preview, better than nothing.
            return downsample(WallpaperSource.aerialThumbnail(id))
        case .none:
            return nil
        }
    }

    nonisolated private static func downsample(_ url: URL?) -> CGImage? {
        guard let url, let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixels,
        ] as CFDictionary)
    }

    /// The resting frame of a moving wallpaper: the first, which is what the desktop shows while
    /// nothing moves it.
    nonisolated private static func firstFrame(of url: URL?) async -> CGImage? {
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return nil }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maximumPixels, height: maximumPixels)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return try? await generator.image(at: .zero).image
    }

    nonisolated private static func save(_ image: CGImage, to url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        CGImageDestinationFinalize(destination)
    }
}

// MARK: - Sources

/// Where a wallpaper's picture comes from.
///
/// The system's own wallpapers are "aerials": videos (the default macOS one included) that the
/// wallpaper agent downloads to `~/Library/Application Support/com.apple.wallpaper/aerials`. For
/// them `NSWorkspace.desktopImageURL(for:)` reports the default picture's file, not what is on the
/// desktop, so the wallpaper store's index is read to find the video instead.
nonisolated enum WallpaperSource: Sendable, Equatable {
    case image(URL)
    /// An aerial by its asset id (its video is `<id>.mov`).
    case aerial(String)
    case none

    var key: String {
        switch self {
        case .image(let url): "image:\(url.path)"
        case .aerial(let id): "aerial:\(id)"
        case .none: "none"
        }
    }

    static let aerialsDirectory = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/Application Support/com.apple.wallpaper/aerials")
    static let storeIndex = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist")
    static let cacheDirectory = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/Caches/com.davidvarga.notchisland/Wallpapers")
    static let aerialsProvider = "com.apple.wallpaper.choice.aerials"

    static func aerialVideo(_ id: String) -> URL { aerialsDirectory.appendingPathComponent("videos/\(id).mov") }
    static func aerialThumbnail(_ id: String) -> URL { aerialsDirectory.appendingPathComponent("thumbnails/\(id).png") }

    /// The macOS default wallpaper: the landscape video of the system's own dynamic wallpaper in
    /// the asked appearance.
    static func systemDefault(light: Bool) -> WallpaperSource {
        let entries = AerialEntries.load()
        guard let asset = entries.defaultAsset(light: light) else { return .none }
        return .aerial(asset)
    }

    /// What is on the main screen's desktop now.
    @MainActor static func currentDesktop() async -> WallpaperSource {
        let fallback = NSScreen.main.flatMap { NSWorkspace.shared.desktopImageURL(for: $0) }
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return await resolveDesktop(fallback: fallback, dark: dark)
    }

    @concurrent static func resolveDesktop(fallback: URL?, dark: Bool) async -> WallpaperSource {
        if let choice = StoreChoice.load(from: storeIndex), choice.provider == aerialsProvider {
            let entries = AerialEntries.load()
            if let id = entries.asset(for: choice, dark: dark) { return .aerial(id) }
        }
        return fallback.map(WallpaperSource.image) ?? .none
    }
}

/// The wallpaper chosen for every space and display, from the wallpaper store's index.
nonisolated struct StoreChoice: Sendable, Equatable {
    var provider: String
    /// The aerial (or its group) the user picked.
    var assetID: String?
    /// The exact video, when the picker chose one (the appearance variant of the default).
    var variantID: String?

    static func load(from url: URL) -> StoreChoice? {
        guard let data = try? Data(contentsOf: url),
              let index = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return parse(index)
    }

    static func parse(_ index: [String: Any]) -> StoreChoice? {
        // "AllSpacesAndDisplays" holds the choice unless each display has its own; either way the
        // first content found is the main desktop's.
        var scopes: [Any] = []
        if let all = index["AllSpacesAndDisplays"] { scopes.append(all) }
        if let displays = index["Displays"] as? [String: Any] { scopes.append(contentsOf: displays.values) }
        for scope in scopes {
            guard let scope = scope as? [String: Any] else { continue }
            let holders = ["Linked", "Desktop"].compactMap { scope[$0] as? [String: Any] }
            for holder in holders {
                guard let content = holder["Content"] as? [String: Any],
                      let choice = (content["Choices"] as? [[String: Any]])?.first,
                      let provider = choice["Provider"] as? String else { continue }
                let configuration = (choice["Configuration"] as? Data).flatMap(plist) as? [String: Any]
                let options = (content["EncodedOptionValues"] as? Data).flatMap(plist) as? [String: Any]
                let values = options?["values"] as? [String: Any]
                let variant = ((values?["aerialVariant"] as? [String: Any])?["picker"] as? [String: Any])?["_0"] as? [String: Any]
                return StoreChoice(provider: provider, assetID: configuration?["assetID"] as? String,
                                   variantID: variant?["id"] as? String)
            }
        }
        return nil
    }

    private static func plist(_ data: Data) -> Any? {
        try? PropertyListSerialization.propertyList(from: data, format: nil)
    }
}

/// The aerials' catalogue (`manifest/entries.json`): which videos exist and what they are.
nonisolated struct AerialEntries: Sendable {
    struct Asset: Sendable, Equatable {
        var id: String
        var categories: [String]
        var subcategories: [String]
        var appearance: String?
        var orientation: String?
    }

    var assets: [Asset]

    /// The category of the system's dynamic wallpapers (the default macOS one among them).
    static let dynamicCategory = "dynamic-aerials"

    static func load() -> AerialEntries {
        let url = WallpaperSource.aerialsDirectory.appendingPathComponent("manifest/entries.json")
        guard let data = try? Data(contentsOf: url) else { return AerialEntries(assets: []) }
        return parse(data)
    }

    static func parse(_ data: Data) -> AerialEntries {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = root["assets"] as? [[String: Any]] else { return AerialEntries(assets: []) }
        return AerialEntries(assets: raw.compactMap { entry in
            guard let id = entry["id"] as? String else { return nil }
            let variant = entry["variant"] as? [String: Any]
            return Asset(id: id,
                         categories: entry["categories"] as? [String] ?? [],
                         subcategories: entry["subcategories"] as? [String] ?? [],
                         appearance: variant?["appearance"] as? String,
                         orientation: variant?["orientation"] as? String)
        })
    }

    /// The default wallpaper's landscape video in one appearance.
    func defaultAsset(light: Bool) -> String? {
        let appearance = light ? "light" : "dark"
        return assets.first {
            $0.categories.contains(Self.dynamicCategory) && $0.appearance == appearance && $0.orientation != "portrait"
        }?.id
    }

    /// The video a store choice shows: its chosen variant, the asset itself, or — when it names a
    /// group (the dynamic default) — the group's landscape video in the current appearance.
    func asset(for choice: StoreChoice, dark: Bool) -> String? {
        if let variant = choice.variantID, assets.contains(where: { $0.id == variant }) { return variant }
        guard let id = choice.assetID else { return nil }
        if assets.contains(where: { $0.id == id }) { return id }
        let members = assets.filter { $0.subcategories.contains(id) && $0.orientation != "portrait" }
        return (members.first { $0.appearance == (dark ? "dark" : "light") } ?? members.first)?.id
    }
}

// MARK: - Drawn wallpapers

/// The macOS default wallpaper's look — folds of light over a deep violet (or, light, over sand
/// and warm grey) with bright rims — drawn: what shows while the real picture loads, and on a Mac
/// that has not downloaded it.
struct DefaultWallpaper: View {
    var light = false

    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            let base = light
                ? [Color(red: 0.74, green: 0.66, blue: 0.56), Color(red: 0.55, green: 0.48, blue: 0.42), Color(red: 0.62, green: 0.63, blue: 0.70)]
                : [Color(red: 0.13, green: 0.12, blue: 0.22), Color(red: 0.07, green: 0.07, blue: 0.14), Color(red: 0.22, green: 0.24, blue: 0.40)]
            context.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .linearGradient(Gradient(colors: base), startPoint: .zero, endPoint: CGPoint(x: w, y: h)))
            // Four folds sweeping from the lower left to the top, each lit along its edge.
            let folds: [(start: CGFloat, top: CGFloat, bend: CGFloat)] = [(0.0, 0.34, 0.28), (0.02, 0.72, 0.45), (0.3, 0.98, 0.5), (0.68, 1.05, 0.4)]
            for (index, fold) in folds.enumerated() {
                var path = Path()
                path.move(to: CGPoint(x: fold.start * w, y: h))
                path.addCurve(to: CGPoint(x: fold.top * w, y: 0),
                              control1: CGPoint(x: (fold.start + fold.bend) * w, y: h * 0.45),
                              control2: CGPoint(x: (fold.top - fold.bend * 0.3) * w, y: h * 0.5))
                path.addLine(to: CGPoint(x: w * 1.2, y: 0))
                path.addLine(to: CGPoint(x: w * 1.2, y: h))
                path.closeSubpath()
                let shade = light
                    ? Color(red: 0.86 - 0.05 * Double(index), green: 0.82 - 0.06 * Double(index), blue: 0.78 - 0.02 * Double(index))
                    : Color(red: 0.16 + 0.03 * Double(index), green: 0.16 + 0.03 * Double(index), blue: 0.30 + 0.05 * Double(index))
                context.fill(path, with: .linearGradient(Gradient(colors: [shade.opacity(0.9), shade.opacity(0.35)]),
                                                         startPoint: CGPoint(x: fold.start * w, y: h), endPoint: CGPoint(x: fold.top * w, y: 0)))
                context.stroke(path, with: .color(light ? .white.opacity(0.7) : Color(red: 0.62, green: 0.62, blue: 0.95).opacity(0.7)),
                               lineWidth: max(1, w / 500))
            }
        }
    }
}

/// Black and white squares, like an image editor's transparency grid at full contrast.
struct Checkerboard: View {
    var square: CGFloat = 16

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            var squares = Path()
            let columns = Int((size.width / square).rounded(.up)), rows = Int((size.height / square).rounded(.up))
            for row in 0..<rows {
                for column in 0..<columns where (row + column) % 2 == 0 {
                    squares.addRect(CGRect(x: CGFloat(column) * square, y: CGFloat(row) * square, width: square, height: square))
                }
            }
            context.fill(squares, with: .color(.black))
        }
    }
}

// MARK: - Picker

/// The preview wallpapers as a choice bar, the same system tab bar as every other row of choices
/// in Settings (`choiceBar()`: its thumb slides, drags and animates as theirs do), each segment a
/// picture of the wallpaper beside its name.
struct WallpaperBar: View {
    @Binding var selection: DesktopBackdropStyle
    @State private var swatches: [DesktopBackdropStyle: NSImage] = [:]

    var body: some View {
        let styles = DesktopBackdropStyle.allCases
        SegmentBar(
            titles: styles.map(\.title),
            images: styles.map { swatches[$0] ?? WallpaperSwatch.drawn($0) },
            selection: Binding(get: { styles.firstIndex(of: selection) ?? 0 },
                               set: { selection = styles[$0] })
        )
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Preview Wallpaper")
        .task {
            for style in styles where style != .checkerboard {
                guard let picture = await WallpaperLibrary.shared.image(for: style) else { continue }
                swatches[style] = WallpaperSwatch.make(style, picture: picture)
            }
        }
    }
}

/// The system's segmented control — what `choiceBar()` draws — filling its width, each segment an
/// image beside its title (SwiftUI's tab bar drops the images and keeps to its titles' width).
struct SegmentBar: NSViewRepresentable {
    let titles: [String]
    let images: [NSImage]
    @Binding var selection: Int

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(labels: titles, trackingMode: .selectOne,
                                         target: context.coordinator, action: #selector(Coordinator.changed(_:)))
        // The tabs role and the capsule corners: exactly the bar `choiceBar()` draws.
        control.role = .tabs
        control.borderShape = .capsule
        control.segmentDistribution = .fillEqually
        control.controlSize = .extraLarge
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.selection = $selection
        if control.segmentCount != titles.count { control.segmentCount = titles.count }
        for index in titles.indices {
            control.setLabel(titles[index], forSegment: index)
            if index < images.count, control.image(forSegment: index) !== images[index] {
                control.setImage(images[index], forSegment: index)
            }
            control.setImageScaling(.scaleProportionallyDown, forSegment: index)
        }
        if control.selectedSegment != selection { control.selectedSegment = selection }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSSegmentedControl, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? nsView.intrinsicContentSize.width, height: nsView.intrinsicContentSize.height)
    }

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    final class Coordinator: NSObject {
        var selection: Binding<Int>

        init(selection: Binding<Int>) { self.selection = selection }

        @objc func changed(_ control: NSSegmentedControl) {
            selection.wrappedValue = control.selectedSegment
        }
    }
}

/// A wallpaper's small picture for a segment: filled, rounded, with a hairline edge. A bitmap,
/// since a segment's image is an image, not a view.
@MainActor enum WallpaperSwatch {
    static let size = CGSize(width: 36, height: 21)
    static let radius: CGFloat = 4
    /// Transparent room around the picture, so it does not touch the segment's top and bottom
    /// (the segment's height is the system's), and after it before the title.
    static let margin: CGFloat = 2
    static let verticalMargin: CGFloat = 4
    static let gap: CGFloat = 7

    /// The picture, or (while it loads, and for the checkerboard) the drawn wallpaper.
    static func make(_ style: DesktopBackdropStyle, picture: NSImage?) -> NSImage {
        let canvas = CGSize(width: margin + size.width + gap, height: size.height + 2 * verticalMargin)
        // Drawn now, into a small bitmap of its own. An NSImage with a drawing handler draws lazily
        // and keeps what the handler captured — the full-size wallpaper, ~9 MB each — for as long as
        // the swatch lives (measured: three of them outlived Settings).
        let scale: CGFloat = 2
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(canvas.width * scale),
                                            pixelsHigh: Int(canvas.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                                            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                            bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return NSImage(size: canvas) }
        bitmap.size = canvas
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        // The bitmap is in pixels, the drawing below in points.
        context.cgContext.scaleBy(x: scale, y: scale)
        defer { NSGraphicsContext.restoreGraphicsState() }
        let draw = { () -> Bool in
            let rect = CGRect(origin: CGPoint(x: margin, y: verticalMargin), size: size)
            let clip = NSBezierPath(roundedRect: rect.insetBy(dx: 0.25, dy: 0.25), xRadius: radius, yRadius: radius)
            NSGraphicsContext.saveGraphicsState()
            clip.addClip()
            if let picture, picture.size.width > 0, picture.size.height > 0 {
                // Aspect fill, from the top (a preview is the top of a screen).
                let scale = max(rect.width / picture.size.width, rect.height / picture.size.height)
                let drawn = CGSize(width: picture.size.width * scale, height: picture.size.height * scale)
                picture.draw(in: CGRect(x: rect.midX - drawn.width / 2, y: rect.maxY - drawn.height,
                                        width: drawn.width, height: drawn.height))
            } else if style == .checkerboard {
                NSColor.white.setFill()
                rect.fill()
                NSColor.black.setFill()
                let square = rect.height / 3
                for row in 0..<3 {
                    for column in 0..<Int((rect.width / square).rounded(.up)) where (row + column) % 2 == 0 {
                        CGRect(x: CGFloat(column) * square, y: CGFloat(row) * square, width: square, height: square).fill()
                    }
                }
            } else {
                NSColor(style == .systemLight ? Color(red: 0.72, green: 0.64, blue: 0.55) : Color(red: 0.16, green: 0.15, blue: 0.28)).setFill()
                rect.fill()
            }
            NSGraphicsContext.restoreGraphicsState()
            NSColor.white.withAlphaComponent(0.28).setStroke()
            clip.lineWidth = 0.5
            clip.stroke()
            return true
        }
        _ = draw()
        context.flushGraphics()
        let image = NSImage(size: canvas)
        image.addRepresentation(bitmap)
        image.isTemplate = false
        return image
    }

    /// Drawn once per style for the first frame, before the picture is in.
    static func drawn(_ style: DesktopBackdropStyle) -> NSImage {
        if let image = placeholders[style] { return image }
        let image = make(style, picture: WallpaperLibrary.shared.cached(style))
        placeholders[style] = image
        return image
    }

    private static var placeholders: [DesktopBackdropStyle: NSImage] = [:]

    static func purge() { placeholders.removeAll() }
}

/// The bar on a card of its own, only as tall as the bar and rounded concentric with it (a
/// form's row is a squarer, taller box around a capsule).
struct WallpaperCard: View {
    @Binding var selection: DesktopBackdropStyle
    @State private var barHeight: CGFloat = 32

    static let inset: CGFloat = 8

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: barHeight / 2 + Self.inset, style: .continuous)
        WallpaperBar(selection: $selection)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { barHeight = $0 }
            .padding(Self.inset)
            .frame(maxWidth: .infinity)
            .background(SettingsPalette.card, in: shape)
            .overlay { shape.strokeBorder(SettingsPalette.cardStroke) }
    }
}
