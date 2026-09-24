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

    @State private var appIcon: NSImage?

    var body: some View {
        // A clear square that takes exactly the proposed frame; the image fills it from an overlay
        // and is clipped, so a non-square cover never spills over its neighbours.
        Color.clear
            .overlay {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
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
