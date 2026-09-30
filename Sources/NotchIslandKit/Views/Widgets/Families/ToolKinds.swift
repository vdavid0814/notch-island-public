import AppKit
import SwiftUI

// The tools added in 0.6 (`ToolSpecs`): a shortcut to run, apps to launch, the last copies, and a
// photo. None reads anything at rest: the apps' icons and the photo are loaded once and kept, the
// copies are the ones Spotlight's clipboard already keeps.

// MARK: - Shortcut

/// One of the user's shortcuts as a button: its symbol on a circle and its name. Which shortcut,
/// and the symbol, are chosen in Customize.
struct ShortcutWidget: View {
    let widget: IslandWidget
    let size: CGSize

    @Environment(\.widgetFrameProbe) private var probe
    @Environment(\.widgetStyle) private var style
    @Environment(\.isWidgetPreview) private var isPreview
    @Environment(AppModel.self) private var model

    static let nameType = TypeSpec(points: 13, weight: .semibold)

    static func name(_ widget: IslandWidget, style: ResolvedWidgetStyle) -> String {
        style.element(.label)?.text.labelOverride ?? widget.config.shortcutName ?? String(localized: "Shortcut")
    }

    static func run(_ widget: IslandWidget, model: AppModel) {
        if let name = widget.config.shortcutName {
            AssistantActions.runShortcut(named: name)
            model.haptics.play(.tick)
        } else {
            // Nothing chosen yet: where it is chosen.
            model.customizeWidget(widget.id)
        }
    }

    var body: some View {
        let name = Self.name(widget, style: style)
        let diameter = min(size.height, max(20, size.width * 0.32), 44)
        let beside = size.width - diameter - 8
        let showsName = widget.shows(.label) && !WidgetMetrics.isRound(widget) && beside >= 36
        let lineFit = WidgetType.size(fittingLines: 1, in: size.height)
        let fit = min(lineFit, WidgetType.size(fitting: name, in: beside, weight: .semibold))
        let points = style.textPoints(.label, auto: WidgetType.fitted(13, fit: max(fit, 8), widget.size(of: .label), floor: 8), fit: max(fit, 8))
        let glyph = style.symbolPoints(.symbol, auto: diameter * 0.46, fit: diameter * 0.8)
        Button {
            guard !isPreview else { return }
            Self.run(widget, model: model)
        } label: {
            HStack(spacing: 8) {
                ShortcutFace(symbol: widget.config.symbol, diameter: showsName ? diameter : min(size.width, size.height), points: glyph)
                    .editorElement(.symbol, in: probe, drawn: .symbol(SymbolSpec(name: "star", weight: .semibold), points: glyph, fit: diameter * 0.8))
                if showsName {
                    Text(name)
                        .widgetTextElement(.label, Self.nameType.at(points), fit: fit, in: style, probe: probe)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .foregroundStyle(widget.config.shortcutName == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                    Spacer(minLength: 0)
                }
            }
            .frame(width: size.width, height: size.height, alignment: showsName ? .leading : .center)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(widget.config.shortcutName.map { "Run \($0)" } ?? "Choose a shortcut in Customize")
        .accessibilityLabel(name)
    }
}

private struct ShortcutFace: View {
    let symbol: String?
    let diameter: CGFloat
    let points: CGFloat

    @Environment(\.widgetStyle) private var style

    var body: some View {
        Image(systemName: symbol ?? "square.stack.3d.up.fill")
            .widgetSymbol(.symbol, points: points, weight: .semibold, in: style)
            .foregroundStyle(.white)
            .frame(width: diameter, height: diameter)
            .background(.tint, in: Circle())
    }
}

struct ShortcutElement: View {
    let widget: IslandWidget
    let id: ElementID

    @Environment(\.widgetPlan) private var plan
    @Environment(\.widgetStyle) private var style
    @Environment(\.isWidgetPreview) private var isPreview
    @Environment(AppModel.self) private var model

    var body: some View {
        let planned = plan?.elements[id]
        if id == .symbol {
            let diameter = min(planned?.size.width ?? 28, planned?.size.height ?? 28)
            Button {
                guard !isPreview else { return }
                ShortcutWidget.run(widget, model: model)
            } label: {
                ShortcutFace(symbol: widget.config.symbol, diameter: diameter, points: min(planned?.points ?? diameter * 0.46, diameter * 0.8))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(ShortcutWidget.name(widget, style: style))
        } else {
            Text(ShortcutWidget.name(widget, style: style))
                .widgetText(.label, ShortcutWidget.nameType.at(planned?.points ?? 13), in: style)
                .lineLimit(style.element(.label)?.text.lineLimit ?? 1)
                .minimumScaleFactor(0.75)
                .foregroundStyle(widget.config.shortcutName == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: style.element(.label)?.text.alignment?.frameAlignment ?? .leading)
        }
    }
}

// MARK: - App launcher

/// The icons of the apps the user chose (up to eight), in rows that fill the widget: a click opens
/// one. The icons come from Launch Services once and are kept.
struct AppLauncherWidget: View {
    let widget: IslandWidget
    let size: CGSize

    @Environment(\.widgetFrameProbe) private var probe
    @Environment(\.isWidgetPreview) private var isPreview
    @Environment(AppModel.self) private var model

    /// A picture's apps, and a new launcher's until its own are chosen.
    static let standardApps = ["/System/Applications/Notes.app", "/System/Applications/Calendar.app",
                               "/System/Applications/Music.app", "/System/Applications/System Settings.app"]

    /// The rows and the icon's side that fill `size` best with `count` icons.
    static func grid(count: Int, in size: CGSize, spacing: CGFloat = 6) -> (rows: Int, columns: Int, side: CGFloat) {
        guard count > 0 else { return (1, 1, 0) }
        var best = (rows: 1, columns: count, side: CGFloat(0))
        for rows in 1...count {
            let columns = Int((Double(count) / Double(rows)).rounded(.up))
            let side = min((size.width - spacing * CGFloat(columns - 1)) / CGFloat(columns),
                           (size.height - spacing * CGFloat(rows - 1)) / CGFloat(rows))
            if side > best.side { best = (rows, columns, side) }
        }
        return (best.rows, best.columns, max(min(best.side, 56), 0))
    }

    var body: some View {
        let apps = (widget.config.apps ?? Self.standardApps).filter { FileManager.default.fileExists(atPath: $0) }
        let grid = Self.grid(count: apps.count, in: size)
        Group {
            if apps.isEmpty {
                Label("Choose apps in Customize", systemImage: "square.grid.2x2")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                VStack(spacing: 6) {
                    ForEach(0..<grid.rows, id: \.self) { row in
                        HStack(spacing: 6) {
                            ForEach(apps.dropFirst(row * grid.columns).prefix(grid.columns), id: \.self) { path in
                                Button {
                                    guard !isPreview else { return }
                                    NSWorkspace.shared.open(URL(fileURLWithPath: path))
                                    model.haptics.play(.tick)
                                } label: {
                                    Image(nsImage: AppIcons.icon(path))
                                        .resizable()
                                        .interpolation(.high)
                                        .frame(width: grid.side, height: grid.side)
                                }
                                .buttonStyle(.plain)
                                .help(FileManager.default.displayName(atPath: path))
                                .accessibilityLabel(FileManager.default.displayName(atPath: path))
                            }
                        }
                    }
                }
            }
        }
        .editorElement(.appIcons, in: probe)
        .frame(width: size.width, height: size.height)
    }
}

/// App icons by path, kept: asking Launch Services again at every redraw is not free.
@MainActor enum AppIcons {
    private static let cache = NSCache<NSString, NSImage>()

    static func icon(_ path: String) -> NSImage {
        if let icon = cache.object(forKey: path as NSString) { return icon }
        let icon = NSWorkspace.shared.icon(forFile: path)
        cache.setObject(icon, forKey: path as NSString)
        return icon
    }
}

// MARK: - Clipboard

/// The last things copied, a line each: a click puts one back on the clipboard. They are the copies
/// Spotlight's Clipboard keeps (Settings ▸ Spotlight): the widget watches nothing of its own.
struct ClipboardWidget: View {
    let widget: IslandWidget
    let size: CGSize

    @Environment(\.widgetFrameProbe) private var probe
    @Environment(\.isWidgetPreview) private var isPreview
    @Environment(AppModel.self) private var model
    @State private var copied: UUID?

    static let samples = ["notchisland://open?page=timer", "Meeting moved to 3 pm", "rgb(91, 140, 255)", "Budapest, Váci út 1.", "42"]

    var body: some View {
        let wanted = min(widget.config.count ?? 3, 5)
        let rowHeight: CGFloat = size.height < 56 ? size.height : max(min(size.height / CGFloat(wanted), 30), 20)
        let rows = max(min(wanted, Int(size.height / rowHeight)), 1)
        let items: [ClipboardItem] = isPreview
            ? Self.samples.prefix(rows).map { ClipboardItem(text: $0, copied: Date()) }
            : Array(model.clipboard.items.prefix(rows))
        let points = max(min(rowHeight * 0.46, 12.5), 8)
        Group {
            if items.isEmpty {
                Label(model.preferences.siri.showsClipboard ? "Nothing copied yet" : "Clipboard is off in Settings ▸ Spotlight",
                      systemImage: "doc.on.clipboard")
                    .font(.system(size: min(12, WidgetType.size(fittingLines: 1, in: size.height)), weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(items) { item in
                        Button {
                            guard !isPreview else { return }
                            model.clipboard.place(item)
                            model.haptics.play(.tick)
                            copied = item.id
                            Task {
                                try? await Task.sleep(for: .seconds(1.2))
                                if copied == item.id { copied = nil }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: copied == item.id ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: points * 0.85, weight: .semibold))
                                    .foregroundStyle(copied == item.id ? AnyShapeStyle(.green) : AnyShapeStyle(.tertiary))
                                    .frame(width: points * 1.3)
                                Text(item.preview)
                                    .font(.system(size: points, weight: .medium))
                                    .truncationMode(.tail)
                                Spacer(minLength: 0)
                            }
                            .lineLimit(1)
                            .padding(.horizontal, 4)
                            .frame(width: size.width, height: rowHeight, alignment: .leading)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .help("Copy it again")
                    }
                }
            }
        }
        .editorElement(.clipList, in: probe)
        .frame(width: size.width, height: size.height, alignment: .leading)
    }
}

// MARK: - Photo

/// A picture of the user's choosing, filling the widget to its corners. Decoded once off the main
/// thread at the size it is drawn, and kept until the widget's size or the file changes.
struct PhotoWidget: View {
    let widget: IslandWidget
    let size: CGSize

    @Environment(\.widgetFrameProbe) private var probe
    @Environment(\.widgetStyle) private var style
    @Environment(\.widgetCorners) private var corners
    @Environment(\.displayScale) private var displayScale
    @Environment(\.isWidgetPreview) private var isPreview
    @Environment(AppModel.self) private var model
    @State private var image: CGImage?

    private struct Key: Equatable {
        var path: String?
        var pixels: Int
    }

    var body: some View {
        let padding = WidgetMetrics.padding(for: widget)
        // To the widget's own edge: a photo in a frame of padding looks like a stamp.
        let full = CGSize(width: size.width + 2 * padding, height: size.height + 2 * padding)
        let key = Key(path: widget.config.imagePath, pixels: Int(max(full.width, full.height) * displayScale))
        let fills = style.element(.photo)?.image.contentMode != .fit
        Group {
            if let image {
                Image(decorative: image, scale: displayScale)
                    .resizable()
                    .aspectRatio(contentMode: fills ? .fill : .fit)
                    .frame(width: full.width, height: full.height)
                    .clipShape(ConcentricGeometry.shape(corners.outer))
                    .widgetImage(.photo, in: style)
            } else {
                Button {
                    if !isPreview { model.customizeWidget(widget.id) }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "photo").font(.system(size: min(size.height * 0.34, 22)))
                        if size.height >= 50 { Text("Choose a Photo").font(.caption.weight(.medium)).lineLimit(1).minimumScaleFactor(0.7) }
                    }
                    .foregroundStyle(.secondary)
                    .frame(width: size.width, height: size.height)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .editorElement(.photo, in: probe)
        .frame(width: size.width, height: size.height)
        .task(id: key) {
            guard let path = key.path else { return image = nil }
            let pixels = key.pixels
            image = await Task.detached(priority: .utility) { PhotoLoader.thumbnail(path: path, maxPixels: pixels) }.value
        }
        .accessibilityLabel("Photo")
    }
}

nonisolated enum PhotoLoader {
    /// The picture no larger than it is drawn (ImageIO's own downsampling: the full image is never decoded).
    static func thumbnail(path: String, maxPixels: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: max(maxPixels, 16), kCGImageSourceShouldCacheImmediately: true]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
