import CoreGraphics

/// The user's size preference. Only the expanded panel scales: compact and
/// banner shapes must hug the physical notch whatever the preference says.
nonisolated enum IslandScale: String, Sendable, CaseIterable, Identifiable, Codable {
    case extraSmall
    case small
    case compact
    case standard
    case large

    var id: String { rawValue }

    var factor: CGFloat {
        switch self {
        case .extraSmall: 0.72
        case .small: 0.8
        case .compact: 0.9
        case .standard: 1.0
        case .large: 1.15
        }
    }

    var title: String {
        switch self {
        // Named from the middle out (the user's wish): the stored names stay, so saved choices keep
        // their size — `compact` is shown as Standard, `standard` as Large, `large` as Extra Large.
        case .extraSmall: "Extra Small"
        case .small: "Small"
        case .compact: "Standard"
        case .standard: "Large"
        case .large: "Extra Large"
        }
    }
}

/// Island geometry as a pure function of the notch size and the scale.
///
/// This is the single source of truth for sizes: the views draw with it, the
/// window controller stages frames with it and the pointer monitor hit-tests
/// with it, so the three can never drift apart (legacy recomputed the same
/// geometry in four places).
nonisolated struct IslandLayout: Sendable, Equatable {
    let notch: CGSize
    let scale: IslandScale
    /// The screen the island is on (zero when unknown): Settings takes most of it.
    var screen: CGSize = .zero
    /// Siri's window proportions (Settings ▸ Siri ▸ Window).
    var siri = SiriLayout()
    /// The open panel's width and board height (Settings ▸ Widgets ▸ Size).
    var panel = PanelLayout()

    /// The same island with other panel proportions: a draft the Size editor shows while dragging.
    func replacing(panel: PanelLayout) -> IslandLayout {
        var layout = self
        layout.panel = panel
        return layout
    }

    /// The widest the panel may be on this screen, and the tallest.
    var maximumExpandedSize: CGSize {
        let screen = screen == .zero ? Self.fallbackScreen : screen
        return CGSize(width: screen.width - 2 * Self.settingsSideMargin,
                      height: (Self.expandedMaximumScreenShare * screen.height).rounded(.down))
    }

    /// The panel's proportions that make it `size` (its edges dragged in Settings ▸ Widgets ▸
    /// Size), each in steps of `step` and within its range — and no further than the screen lets
    /// the panel grow, so a factor never runs on past the size it still changes.
    func panel(forExpandedSize size: CGSize, step: Double = PanelSettings.step) -> PanelSettings {
        let f = scale.factor
        let base = max(notch.width + Self.expandedExtraWidth, Self.expandedMinimumWidth) * f
        let limit = maximumExpandedSize
        // The nearest step; at the screen's limit the first step that reaches it.
        func snapped(_ value: CGFloat, atLimit: Bool, in range: ClosedRange<Double>) -> Double {
            let steps = Double(value) / step
            return range.clamp((atLimit ? (steps - 1e-9).rounded(.up) : steps.rounded()) * step)
        }
        let width = snapped(min(size.width, limit.width) / base, atLimit: size.width >= limit.width, in: PanelSettings.widthRange)
        let height = snapped((min(size.height, limit.height) - notch.height) / (Self.expandedPageHeight * f),
                             atLimit: size.height >= limit.height, in: PanelSettings.boardHeightRange)
        return PanelSettings(widthFactor: width, boardHeightFactor: height)
    }

    /// Glass extends this far above the window top, where it is clipped, so its
    /// top edge never shows a rim against the bezel.
    static let overdraw: CGFloat = 24
    /// Transparent slack around the island while animating: room for spring
    /// overshoot and the glass shadow.
    static let stageMargin: CGFloat = 28
    /// Slack kept after settling, so the glass shadow is not clipped.
    static let restingMargin: CGFloat = 10

    /// Banners need room for a symbol, a native slider and a value on one row.
    static let bannerMinimumWidth: CGFloat = 380
    /// The AirPods card (see `size(for: .banner(.airPods))`).
    static let airPodsBannerWidth: CGFloat = 400
    static let airPodsDetailHeight: CGFloat = 112
    /// Over macOS's volume card: its outline exactly (below the menu bar's height, a point, the
    /// card's top offset and its height), so where the fade clears the island's edge is the card's.
    static let coveringDetailHeight: CGFloat = 1 + SystemVolumeCard.Kind.volume.top + SystemVolumeCard.Kind.volume.size.height
    static let coveringBodyWidth: CGFloat = SystemVolumeCard.Kind.volume.size.width
    static let coveringBottomRadius: CGFloat = SystemVolumeCard.Kind.volume.radius
    static let coveringShoulder: CGFloat = 10
    /// The same over macOS's AirPods card, when the island covers it.
    static let airPodsCoveringDetailHeight: CGFloat = 1 + SystemVolumeCard.Kind.airPods.top + SystemVolumeCard.Kind.airPods.size.height

    /// The AirPods card lies on macOS's own (Settings ▸ Live Activities ▸ With macOS's own card).
    static var coversAirPodsCard: Bool { AirPodsSystemCard.current == .cover }
    /// Each ear of the minimal level pill: the symbol on one side, a small slider on the other.
    static let levelPillEar: CGFloat = 92
    /// The detail row a banner adds below the header band.
    static let bannerDetailHeight: CGFloat = 48
    /// Expanded panel before scaling: extra width beside the notch, its floor, and the page height.
    /// The panel's own factors (`panel`) scale them further, within the screen: no wider than
    /// Settings may be, and a page no taller than `expandedMaximumScreenShare` of the screen.
    static let expandedExtraWidth: CGFloat = 380
    static let expandedMinimumWidth: CGFloat = 600
    static let expandedPageHeight: CGFloat = 160
    static let expandedMaximumScreenShare: CGFloat = 0.62
    /// The assistant below its header band: the search field, a list of hits and actions, or an
    /// answer. As wide as the expanded panel, so from the header's Siri button it grows downward.
    static let assistantPageHeight: CGFloat = 280
    /// Settings in the island: most of the screen, grown out of the notch (a full-screen feel
    /// without leaving it). Kept this far from the screen's sides and bottom, and no larger than
    /// the maximum on big displays.
    static let settingsSideMargin: CGFloat = 50
    static let settingsBottomMargin: CGFloat = 64
    static let settingsMaximum = CGSize(width: 1180, height: 740)
    static let settingsMinimum = CGSize(width: 820, height: 520)
    /// Standing in for the screen before one is known (a 14-inch MacBook's default resolution).
    static let fallbackScreen = CGSize(width: 1512, height: 982)
    /// The app gallery (Applications ⌘1): wider than the list, for nine columns of apps.
    static let assistantGalleryWidth: CGFloat = 820
    /// One app in the gallery (`GalleryCell`: 6 + 48-pt icon + 4 + caption line + 6) and the space
    /// between rows: the gallery is exactly the user's number of rows tall, never a cut-off row.
    static let galleryCellHeight: CGFloat = 77
    static let galleryRowSpacing: CGFloat = 4

    /// The gallery page for `rows` rows: the field above them, the insets around.
    static func galleryPageHeight(rows: Int) -> CGFloat {
        let rows = CGFloat(max(1, rows))
        return assistantTopInset * 2 + assistantFieldHeight + Metrics.Expanded.pageBottomInset
            + rows * galleryCellHeight + (rows - 1) * galleryRowSpacing
    }
    /// The assistant's field and rows (`AssistantView`), which are not scaled.
    static let assistantFieldHeight: CGFloat = 40
    static let assistantRowHeight: CGFloat = 32
    static let assistantRowSpacing: CGFloat = 2
    /// Above the field (`Metrics.Spacing.medium`), between it and the rows (the same), and below
    /// the last thing showing: a little less than the panel's bottom inset, so the field alone
    /// reads as one bar.
    static let assistantTopInset: CGFloat = 8
    static let assistantBottomInset: CGFloat = 12
    /// Only the field.
    static var assistantFieldPageHeight: CGFloat { assistantTopInset + assistantFieldHeight + assistantBottomInset }
    /// The field and the three suggestions under it.
    static var assistantSuggestionsPageHeight: CGFloat { assistantRowsPageHeight(3) }

    /// The field and `count` rows under it.
    static func assistantRowsPageHeight(_ count: Int) -> CGFloat {
        let rows = CGFloat(max(count, 1))
        return assistantFieldPageHeight + assistantTopInset + rows * assistantRowHeight + (rows - 1) * assistantRowSpacing
    }

    /// How far a list row's selection capsule sits in from the panel's side and bottom: this far in,
    /// its ends are concentric with the panel's lower corners (a 32-pt row rounds 16 pt at most, the
    /// panel 30 pt at the standard size, so 14 pt); never nearer than the page's own inset.
    var assistantRowInset: CGFloat {
        max(Metrics.Expanded.horizontalInset, bottomRadius(for: .assistant(.list)) - Self.assistantRowHeight / 2)
    }

    /// A gallery cell's selection plate: concentric with the panel's lower corners from the page's
    /// inset, where the last row's cells sit.
    var assistantGalleryPlateRadius: CGFloat {
        bottomRadius(for: .assistant(.gallery)) - Metrics.Expanded.pageBottomInset
    }

    /// Width of each ear beside the notch in compact and banner: as narrow as the
    /// glyph allows — the compact shoulder (6), the glyph's outer inset (4), the
    /// glyph itself (notch height − 2 × 4) and the clearance from the notch (4).
    var ear: CGFloat { notch.height + 6 }

    /// Visible island size, without the overdraw.
    func size(for p: IslandPresentation) -> CGSize {
        switch p {
        case .idle:
            return notch
        case .compact:
            // Never taller than the notch: a taller pill reads as a window stuck to the screen.
            return CGSize(width: notch.width + 2 * ear, height: notch.height)
        case .banner(.levelCovering):
            // macOS's volume card (293 × 64 pt, 11 pt below the menu bar's height, measured from its
            // image): its body is exactly the card, with the shoulders beside it (asked for: the
            // card's shape, lying over it, edge on edge).
            return CGSize(width: Self.coveringBodyWidth + 2 * Self.coveringShoulder,
                          height: notch.height + Self.coveringDetailHeight)
        case .banner(.airPods) where Self.coversAirPodsCard:
            return CGSize(width: SystemVolumeCard.Kind.airPods.size.width + 2 * Self.coveringShoulder,
                          height: notch.height + Self.airPodsCoveringDetailHeight)
        case .banner(.airPods):
            // Large enough to lie over macOS's own AirPods card (about 300 × 60 pt under the
            // notch, in a 352 × 148 window with its shadow), which the island covers.
            return CGSize(width: max(notch.width + 2 * ear, Self.airPodsBannerWidth),
                          height: notch.height + Self.airPodsDetailHeight)
        case .banner(.levelPill):
            // Pill height; the trailing ear holds a small slider, so both ears are that wide.
            return CGSize(width: notch.width + 2 * Self.levelPillEar, height: notch.height)
        case .banner:
            return CGSize(
                width: max(notch.width + 2 * ear, Self.bannerMinimumWidth),
                height: notch.height + Self.bannerDetailHeight
            )
        case .expanded:
            let f = scale.factor
            let screen = screen == .zero ? Self.fallbackScreen : screen
            // Scaled lengths are rounded so glass edges stay on the pixel grid at every scale.
            let width = (max(notch.width + Self.expandedExtraWidth, Self.expandedMinimumWidth) * f * panel.widthFactor).rounded()
            let page = (Self.expandedPageHeight * f * panel.boardHeightFactor).rounded()
            return CGSize(
                width: min(width, screen.width - 2 * Self.settingsSideMargin),
                // The header band stays exactly the notch height; only the page scales.
                height: notch.height + min(page, (Self.expandedMaximumScreenShare * screen.height - notch.height).rounded(.down))
            )
        case .settings:
            let screen = screen == .zero ? Self.fallbackScreen : screen
            let width = min(max(screen.width - 2 * Self.settingsSideMargin, Self.settingsMinimum.width), Self.settingsMaximum.width)
            let page = min(max(screen.height - notch.height - Self.settingsBottomMargin, Self.settingsMinimum.height),
                           Self.settingsMaximum.height)
            return CGSize(width: width.rounded(), height: notch.height + page.rounded())
        case .assistant(let room):
            let f = scale.factor
            let screen = screen == .zero ? Self.fallbackScreen : screen
            // The user's rows and columns scale the defaults (7 list rows, a 9 × 4 gallery).
            let list = (Self.assistantPageHeight * f * CGFloat(siri.listRows) / 7).rounded()
            let page: CGFloat = switch room {
            case .field: Self.assistantFieldPageHeight
            // The last row as far above the bottom as the rows are in from the side
            // (`assistantRowInset`), instead of the field's bottom inset.
            case .rows(let count): min(Self.assistantRowsPageHeight(count) - Self.assistantBottomInset + assistantRowInset,
                                       max(list, Self.assistantSuggestionsPageHeight))
            case .list: max(list, Self.assistantSuggestionsPageHeight)
            case .gallery: Self.galleryPageHeight(rows: siri.galleryRows)
            case .galleryRows(let count): Self.galleryPageHeight(rows: min(count, siri.galleryRows))
            }
            // The panel's width times Siri's own factor, so Siri grows out of the header as wide.
            let panel = (max(notch.width + Self.expandedExtraWidth, Self.expandedMinimumWidth) * f * self.panel.widthFactor
                         * siri.widthFactor).rounded()
            let gallery = (Self.assistantGalleryWidth * f * CGFloat(siri.galleryColumns) / 9).rounded()
            return CGSize(
                width: min(room.isGallery ? max(panel, gallery) : panel, screen.width - 2 * Self.settingsSideMargin),
                height: notch.height + page
            )
        }
    }

    /// The island's outline in a presentation: its size and radii.
    func outline(for p: IslandPresentation) -> IslandOutline {
        IslandOutline(size: size(for: p), bottomRadius: bottomRadius(for: p), shoulderRadius: shoulderRadius(for: p),
                      shoulderDrop: Self.liesOnSystemCard(p) ? notch.height : 0)
    }

    /// Lies on macOS's own card, in its outline.
    static func liesOnSystemCard(_ p: IslandPresentation) -> Bool {
        switch p {
        case .banner(.levelCovering(.volume)): true
        case .banner(.airPods): coversAirPodsCard
        default: false
        }
    }

    func bottomRadius(for p: IslandPresentation) -> CGFloat {
        switch p {
        case .idle: min(8, notch.height / 2)
        case .compact, .banner(.levelPill): notch.height / 2
        // A little rounder than macOS's volume card under it.
        case .banner(.levelCovering): Self.coveringBottomRadius
        case .banner(.airPods) where Self.coversAirPodsCard: SystemVolumeCard.Kind.airPods.radius
        case .banner: 24
        case .expanded, .assistant, .settings: 30 * scale.factor
        }
    }

    /// Radius of the concave fillet where the island meets the top bezel.
    func shoulderRadius(for p: IslandPresentation) -> CGFloat {
        switch p {
        case .idle: 0
        case .compact, .banner(.levelPill): 6
        case .banner(.levelCovering): Self.coveringShoulder
        case .banner(.airPods) where Self.coversAirPodsCard: Self.coveringShoulder
        case .banner: 8
        case .expanded, .assistant, .settings: 10
        }
    }

    /// Island rect in window-local AppKit coordinates (bottom-left origin) for a
    /// window of `stageSize`: centred horizontally, flush with the top.
    func islandRect(for p: IslandPresentation, inStage stageSize: CGSize) -> CGRect {
        let size = size(for: p)
        return CGRect(
            x: (stageSize.width - size.width) / 2,
            y: stageSize.height - size.height,
            width: size.width,
            height: size.height
        )
    }
}
