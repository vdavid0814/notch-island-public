import AppKit
import SwiftUI

/// Album art, clipped concentric with the island so its corners follow the island's own curves.
///
/// The image is already decoded by `MediaController` (once per track), so nothing is decoded in
/// `body`. Without artwork the player's app icon stands in — the system's own identity for the
/// source — and failing that a plain symbol. No placeholder platter: a fill would sit on the glass.
struct ArtworkView: View {
    let image: NSImage?
    let bundleIdentifier: String?
    var minimumRadius: CGFloat
    /// The cover as a SwiftUI picture, not on its own layer (`CoverLayer`): what is drawn over it
    /// cuts it (a mask), which an AppKit layer is not — a cover grown over its widget is cut to the
    /// widget's outline. A new track's cover then comes in at once.
    var drawsAsPicture = false

    @State private var appIcon: NSImage?
    @Environment(\.widgetRenderMode) private var renderMode

    var body: some View {
        // A clear square that takes exactly the proposed frame; the image fills it from an overlay
        // and is clipped, so a non-square cover never spills over its neighbours.
        Color.clear
            .overlay {
                if let image, renderMode == .canvas || drawsAsPicture {
                    // A picture of the cover as its layer fills it: drawn off screen too (the
                    // Customize transition's snapshot), which a layer is not.
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                } else if let image {
                    CoverLayer(image: image)
                } else if let appIcon {
                    Image(nsImage: appIcon)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "music.note")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            .clipShape(ConcentricRectangle(corners: .concentric(minimum: .fixed(minimumRadius)), isUniform: true))
            .task(id: image == nil ? bundleIdentifier : nil) {
                appIcon = image == nil ? Self.icon(for: bundleIdentifier) : nil
            }
            .accessibilityHidden(true)
    }

    /// The player's icon from Launch Services (already cached system-wide), resolved only when the
    /// track has no artwork.
    private static func icon(for bundleIdentifier: String?) -> NSImage? {
        guard let bundleIdentifier,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
    }
}

/// The cover on a Core Animation layer: a new track's cover cross-fades in while it springs up from
/// a little smaller — played by the render server from one commit, nothing redrawn by the app
/// frame by frame. (An `Image` swapped its cover in one frame.)
private struct CoverLayer: NSViewRepresentable {
    let image: NSImage

    func makeNSView(context: Context) -> CoverLayerView { CoverLayerView() }

    func updateNSView(_ view: CoverLayerView, context: Context) {
        view.show(image)
    }
}

final class CoverLayerView: NSView {
    private let cover = CALayer()
    private weak var shown: NSImage?

    /// The cross-fade and the spring that lifts the new cover to its size.
    static let fade: CFTimeInterval = 0.45
    static let startScale: CGFloat = 0.9

    override init(frame: CGRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        cover.contentsGravity = .resizeAspectFill
        cover.masksToBounds = true
        layer?.addSublayer(cover)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cover.frame = bounds
        cover.contentsScale = window?.backingScaleFactor ?? 2
        CATransaction.commit()
    }

    func show(_ image: NSImage) {
        guard image !== shown else { return }
        let first = shown == nil
        shown = image
        let contents = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if !first, window != nil {
            let fade = CATransition()
            fade.type = .fade
            fade.duration = Self.fade
            fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            cover.add(fade, forKey: "contents")
            let spring = CASpringAnimation(perceptualDuration: Self.fade * 1.3, bounce: 0.25)
            spring.keyPath = "transform.scale"
            spring.fromValue = Self.startScale
            spring.toValue = 1
            spring.duration = spring.settlingDuration
            cover.add(spring, forKey: "lift")
        }
        cover.contents = contents
        CATransaction.commit()
    }
}
