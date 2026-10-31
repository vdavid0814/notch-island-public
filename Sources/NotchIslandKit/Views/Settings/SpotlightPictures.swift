import AppKit
import SwiftUI

// Settings ▸ Spotlight's Window and App Gallery: each with a picture of what the setting gives. A
// slider has no steps to photograph, so the picture is laid out live, by `IslandLayout` at the very
// size Spotlight will take, with its own rows and icons, and scaled down over the preview wallpaper.

/// Window: its width (a slider, in place of three named sizes) and its list's height.
struct SpotlightWindowSection: View {
    @Binding var settings: SiriSettings
    /// While the slider is dragged: the width it shows, written when let go.
    @State private var widthDraft: Double?

    var body: some View {
        Section("Window") {
            var shown = settings
            let _ = shown.widthFactor = widthDraft ?? settings.widthFactor
            SettingPictureRow { SpotlightPicture(settings: shown, room: .list) }
            LabeledContent {
                ValueSlider(value: settings.widthFactor, range: SiriSettings.widthFactorRange, step: 0.01,
                            format: { "\(Int(($0 * 100).rounded())) %" }, draft: $widthDraft) { settings.widthFactor = $0 }
            } label: {
                InfoLabel("Width", "How wide Spotlight's window grows out of the notch, against the panel's width. The island's own size (General) scales it too.")
            }
            RowsStepper(title: "List height", detail: "How many results — and how much of an answer — show before the list scrolls.",
                        value: $settings.listRows, range: SiriSettings.listRowsRange, unit: "rows")
        }
    }
}

/// App Gallery: the order, the icons' size (a slider, in place of four named sizes) and how many.
struct SpotlightGallerySection: View {
    @Binding var settings: SiriSettings
    @State private var iconDraft: Double?

    var body: some View {
        Section("App Gallery") {
            var shown = settings
            let _ = shown.galleryIcon = iconDraft ?? settings.galleryIcon
            SettingPictureRow { SpotlightPicture(settings: shown, room: .gallery) }
            Picker(selection: $settings.gallerySort) {
                ForEach(SiriGallerySort.allCases) { Text($0.title).tag($0) }
            } label: {
                InfoLabel("Order", "The apps in the gallery (⌘1): with the ones you used last in a row on top, or only alphabetically.")
            }
            .choiceBar()
            LabeledContent {
                ValueSlider(value: settings.galleryIcon, range: SiriSettings.galleryIconRange, step: 1,
                            format: { "\(Int($0)) pt" }, draft: $iconDraft) { settings.galleryIcon = $0 }
            } label: {
                InfoLabel("Icon size", "How large the apps are in the gallery (⌘1). Its window grows with them, so the same number of apps fits in a row.")
            }
            RowsStepper(title: "Columns", detail: "Apps in a row. The gallery's window widens with them.",
                        value: $settings.galleryColumns, range: SiriSettings.galleryColumnsRange, unit: "apps")
            RowsStepper(title: "Rows", detail: "Rows of apps shown before the gallery scrolls: the gallery's height.",
                        value: $settings.galleryRows, range: SiriSettings.galleryRowsRange, unit: "rows")
        }
    }
}

/// The notch screen with Spotlight open at these settings, as large as it will really be on it.
private struct SpotlightPicture: View {
    let settings: SiriSettings
    let room: AssistantRoom

    @Environment(AppModel.self) private var model
    @AppStorage(DesktopBackdropStyle.key) private var backdrop: DesktopBackdropStyle = DesktopBackdropStyle.defaultStyle

    /// The picture's width; its height follows the screen's.
    private static let width: CGFloat = 520

    var body: some View {
        var layout = model.layout
        let _ = layout.siri = settings.layout
        let screen = layout.screen == .zero ? IslandLayout.fallbackScreen : layout.screen
        let k = Self.width / screen.width
        let presentation = IslandPresentation.assistant(room)
        let size = layout.size(for: presentation)
        let shape = IslandShape(bottomRadius: layout.bottomRadius(for: presentation), shoulderRadius: layout.shoulderRadius(for: presentation))
        ZStack(alignment: .top) {
            DesktopBackdrop(style: backdrop, detail: .miniature)
            PreviewMenuBar(height: layout.notch.height * k, notchWidth: size.width * k, darkText: backdrop.prefersDarkMenuBar,
                           backing: backdrop.menuBarBacking)
            Group {
                if model.preferences.glassStyle.hasGlassSurface {
                    // What the smoked glass lets through: the same desktop, blurred, inside the island.
                    DesktopBackdrop(style: backdrop, detail: .miniature)
                        .blur(radius: 14)
                        .frame(width: screen.width, height: screen.height)
                        .overlay { Color.black.opacity(0.55) }
                } else {
                    Color.black
                }
            }
            .frame(width: size.width, height: size.height, alignment: .top)
            .clipShape(shape)
            .scaleEffect(k, anchor: .top)
            .frame(width: size.width * k, height: size.height * k, alignment: .top)
            SpotlightPictureContent(settings: settings, room: room, layout: layout)
                .frame(width: size.width, height: size.height, alignment: .top)
                .environment(\.colorScheme, .dark)
                .scaleEffect(k, anchor: .top)
                .frame(width: size.width * k, height: size.height * k, alignment: .top)
                .clipped()
            UnevenRoundedRectangle(bottomLeadingRadius: 8 * k, bottomTrailingRadius: 8 * k, style: .continuous)
                .fill(.black)
                .frame(width: layout.notch.width * k, height: layout.notch.height * k)
        }
        .frame(width: screen.width * k, height: screen.height * k)
        // Window's picture: the screen's top, a little taller than the island at the most rows.
        .frame(height: room.isGallery ? nil : tallestList(layout) * k + 14, alignment: .top)
        .clipShape(.rect(cornerRadius: 10, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.12)) }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private extension SpotlightPicture {
    func tallestList(_ layout: IslandLayout) -> CGFloat {
        var most = settings
        most.listRows = SiriSettings.listRowsRange.upperBound
        var layout = layout
        layout.siri = most.layout
        return layout.size(for: .assistant(room)).height
    }
}

/// What Spotlight shows in the room, in its real sizes: the field, then its rows or its gallery.
private struct SpotlightPictureContent: View {
    let settings: SiriSettings
    let room: AssistantRoom
    let layout: IslandLayout

    var body: some View {
        let split = NotchSplit(layout: layout, presentation: .assistant(room), outerInset: Metrics.Expanded.horizontalInset,
                               clearance: Metrics.notchClearance)
        VStack(spacing: IslandLayout.assistantTopInset) {
            HStack(spacing: Metrics.Spacing.medium) {
                SpotlightMark()
                    .fill(.secondary)
                    .frame(width: 17, height: 17)
                Text("Search or Ask")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Image(systemName: "mic.fill").foregroundStyle(.secondary)
            }
            .padding(.horizontal, Metrics.Spacing.large)
            .frame(height: IslandLayout.assistantFieldHeight)
            .background(.white.opacity(0.08), in: Capsule())
            if room.isGallery {
                SpotlightPictureGallery(settings: settings, plateRadius: layout.assistantGalleryPlateRadius)
            } else {
                VStack(spacing: IslandLayout.assistantRowSpacing) {
                    ForEach(rows) { RowView(row: $0) }
                }
                .padding(.horizontal, layout.assistantRowInset - Metrics.Expanded.horizontalInset)
            }
        }
        .padding(.top, layout.notch.height + IslandLayout.assistantTopInset)
        .padding(.horizontal, split.contentInset)
    }

    /// The suggestions Spotlight lists, then apps, as many as the list has rows.
    private var rows: [AssistantRow] {
        let suggestions = settings.categories.map(AssistantRow.category)
        let apps = SpotlightPictureApps.all.map(AssistantRow.hit)
        return Array((suggestions + apps).prefix(settings.listRows))
    }
}

/// The gallery's cells at the icon size set, with this Mac's own apps.
private struct SpotlightPictureGallery: View {
    let settings: SiriSettings
    let plateRadius: CGFloat

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: IslandLayout.galleryRowSpacing), count: settings.galleryColumns)
        LazyVGrid(columns: columns, spacing: IslandLayout.galleryRowSpacing) {
            ForEach(SpotlightPictureApps.all.prefix(settings.galleryColumns * settings.galleryRows)) { hit in
                GalleryCell(hit: hit, plateRadius: plateRadius, iconSize: CGFloat(settings.galleryIcon),
                            iconFrom: SpotlightPictureApps.iconPoints)
            }
        }
    }
}

/// The apps in the pictures: this Mac's, by name, read once (two folders nothing asks permission for).
private enum SpotlightPictureApps {
    /// The icons are drawn once at this size and scaled: a slider's every step would draw 72 of them.
    static let iconPoints = CGFloat(SiriGalleryIconSize.medium.points)

    static let all: [AssistantHit] = ["/Applications", "/System/Applications"].flatMap { folder -> [AssistantHit] in
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
        return names.filter { $0.hasSuffix(".app") && AssistantGallery.isListed(folder + "/" + $0) }.map { name in
            AssistantHit(kind: .app, url: URL(fileURLWithPath: folder).appendingPathComponent(name),
                         name: String(name.dropLast(4)), contentType: nil, lastUsed: nil)
        }
    }
    .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
}
