import ImageIO
import SwiftUI

/// What the widget sits on: nothing, a faint plate, a plate in its colour, its blurred cover, a
/// gradient or a picture (`IslandWidget.background`, at its strength), in the widget's corners
/// (the style's radius among them), with the style's border (`SurfaceStyle`). Given the widget's
/// style, corners and cover colour as `IslandWidgetView` resolved them (no environment to read).
struct WidgetSurface: View {
    let widget: IslandWidget
    let size: CGSize
    let accent: Color?
    let style: ResolvedWidgetStyle
    let corners: WidgetCorners
    let artworkColor: Color?

    @Environment(AppModel.self) private var model

    var body: some View {
        // A one-cell widget is always a circle, whatever the cell's proportions at this island
        // size (a cell a little wider than tall would otherwise make a capsule).
        if WidgetMetrics.isRound(widget) {
            let side = min(size.width, size.height)
            surface(RoundedRectangle(cornerRadius: side / 2, style: .continuous), size: CGSize(width: side, height: side))
                .frame(width: size.width, height: size.height)
        } else if let radius = corners.outer.uniformRadius {
            surface(RoundedRectangle(cornerRadius: radius, style: .continuous), size: size)
        } else {
            surface(UnevenRoundedRectangle(cornerRadii: corners.outer, style: .continuous), size: size)
        }
    }

    @ViewBuilder private func surface<S: InsettableShape>(_ shape: S, size: CGSize) -> some View {
        if let width = style.surface.borderWidth, width > 0 {
            fill(shape, size: size)
                .overlay {
                    shape.strokeBorder(style.surface.border?.shapeStyle(artwork: artworkColor) ?? AnyShapeStyle(.white.opacity(0.3)),
                                       lineWidth: width)
                }
        } else {
            fill(shape, size: size)
        }
    }

    @ViewBuilder private func fill<S: Shape>(_ shape: S, size: CGSize) -> some View {
        // 0…1 from the widget's setting (plate default 0.4; colour 0.5 → 0.22 at its default 0.5;
        // artwork, gradient and picture fully drawn at 1).
        let strength = widget.effectiveBackgroundOpacity
        switch widget.background {
        case .none:
            Color.clear
        case .plate:
            shape.fill(.white.opacity(0.28 * strength))
        case .tinted:
            shape.fill(LinearGradient(
                colors: [(accent ?? .islandAccent).opacity(strength), (accent ?? .islandAccent).opacity(0.44 * strength)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ))
        case .gradient:
            let start = style.surface.fill?.color(artwork: artworkColor) ?? accent ?? .islandAccent
            let end = style.surface.fillEnd?.color(artwork: artworkColor) ?? start.opacity(0.44)
            shape.fill(LinearGradient(colors: [start, end], startPoint: .topLeading, endPoint: .bottomTrailing))
                .opacity(strength)
        case .artwork:
            if let artwork = model.media.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
                    .blur(radius: 22, opaque: true)
                    .overlay(.black.opacity(style.surface.artworkDim ?? 0.38))
                    .clipShape(shape)
                    .opacity(strength)
            } else {
                // No cover yet: the plate's default look, scaled the same way.
                shape.fill(.white.opacity(0.07 * strength))
            }
        case .image:
            SurfacePicture(path: style.surface.imagePath, size: size)
                .clipShape(shape)
                .opacity(strength)
                .background(shape.fill(.white.opacity(0.07 * strength)))
        }
    }
}

/// The user's picture filling the widget: decoded once, off the main thread, at the pixels drawn,
/// in Core Animation's own 8-bit BGRA (`ArtworkDecoder.displayReady`).
private struct SurfacePicture: View {
    let path: String?
    let size: CGSize

    @Environment(\.displayScale) private var scale
    @State private var image: CGImage?

    var body: some View {
        let pixels = Int((max(size.width, size.height) * scale).rounded(.up))
        Group {
            if let image {
                Image(decorative: image, scale: scale)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.clear
            }
        }
        .frame(width: size.width, height: size.height)
        .task(id: Key(path: path, pixels: pixels)) {
            guard let path else { return image = nil }
            let decoded = await Thrifty.run { Self.decode(path, pixels: pixels) }
            image = if let decoded { await ArtworkDecoder.displayReady(decoded) } else { nil }
        }
    }

    private struct Key: Equatable {
        var path: String?
        var pixels: Int
    }

    nonisolated static func decode(_ path: String, pixels: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL,
                                                      [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(pixels, 1),
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
