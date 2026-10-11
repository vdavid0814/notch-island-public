import SwiftUI

// Small pictures for the settings that change how the island looks (General, Live Activities),
// drawn like the Surface cards: a desktop with its menu bar and the island at the notch. And the
// ⓘ that explains a setting when the pointer rests on it.

// MARK: - Info

/// A setting's title with an ⓘ after it; resting the pointer on the ⓘ opens a small window that
/// explains the setting.
struct InfoLabel: View {
    let title: String
    let info: String

    init(_ title: String, _ info: String) {
        self.title = title
        self.info = info
    }

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
            InfoHint(info)
        }
    }
}

/// The ⓘ itself. The explanation opens after a short rest (a pointer passing by does not flash
/// it) and stays while the pointer is on the ⓘ or on the explanation.
struct InfoHint: View {
    let text: String

    init(_ text: String) { self.text = text }

    @State private var overIcon = false
    @State private var overPopover = false
    @State private var isShown = false

    var body: some View {
        Image(systemName: "info.circle")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(isShown ? AnyShapeStyle(Color.islandAccent) : AnyShapeStyle(SettingsPalette.secondary))
            .contentShape(.circle)
            .onHover { overIcon = $0 }
            .onTapGesture { isShown.toggle() }
            .popover(isPresented: $isShown, arrowEdge: .top) {
                Text(text)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 260, alignment: .leading)
                    .padding(12)
                    .onHover { overPopover = $0 }
            }
            .task(id: overIcon || overPopover) {
                let hovering = overIcon || overPopover
                try? await Task.sleep(for: .milliseconds(hovering ? 250 : 200))
                guard !Task.isCancelled else { return }
                if isShown != hovering { isShown = hovering }
            }
            .accessibilityLabel(Text("About \(text)"))
    }
}

// MARK: - Pictures

/// A desktop in miniature, as this Mac shows it: the preview wallpaper the user chose (General ▸
/// Preview Wallpaper, their own desktop unless they picked another), the menu bar with its menus,
/// status items and clock, the camera housing, and whatever hangs from the notch.
///
/// Its sizes, and everything drawn in it, are given as drawn at a 150 pt wide desktop and shown
/// `settingsPictureScale` times as large: the page takes the pictures as large as its width has
/// room for. Drawn at that size, not enlarged: an enlarged picture's text is a blurred bitmap.
struct MiniDesktop<Content: View>: View {
    var width: CGFloat = 150
    var height: CGFloat = 94
    @ViewBuilder var content: Content

    @AppStorage(DesktopBackdropStyle.key) private var style: DesktopBackdropStyle = DesktopBackdropStyle.defaultStyle
    @Environment(\.settingsPictureScale) private var k
    @Environment(\.settingsPictureRadius) private var radius

    var body: some View {
        let size = MiniMetrics.size(width, height, scale: k)
        ZStack(alignment: .top) {
            // A picture this small needs no more than the miniature (960 px: up to 480 pt wide at 2×).
            DesktopBackdrop(style: style, detail: size.width <= 480 && size.height <= 480 ? .miniature : .full)
            PreviewMenuBar(height: MiniMetrics.menuBar * k, notchWidth: (MiniMetrics.notchWidth + 14) * k,
                           darkText: style.prefersDarkMenuBar,
                           backing: style.menuBarBacking)
            content
                // The island floats over the desktop like the real one, with its soft shadow.
                .shadow(color: .black.opacity(0.35), radius: 3 * k, y: 1.5 * k)
            // The camera housing: whatever the island shows, the notch itself stays black.
            UnevenRoundedRectangle(bottomLeadingRadius: 3 * k, bottomTrailingRadius: 3 * k, style: .continuous)
                .fill(.black)
                .frame(width: MiniMetrics.notchWidth * k, height: MiniMetrics.menuBar * k)
        }
        .frame(width: size.width, height: size.height)
        // Its corners stay as they are at any size: concentric with the card's.
        .clipShape(.rect(cornerRadius: radius, style: .continuous))
        .accessibilityHidden(true)
    }
}

nonisolated enum MiniMetrics {
    static let menuBar: CGFloat = 12
    static let notchWidth: CGFloat = 34
    /// Real island points to picture points.
    static let scale: CGFloat = 0.17
    /// The open island's lower corners in a picture, and how far its widgets sit in from its
    /// sides and its foot (and from one another): the widgets' corners are the island's less
    /// that inset, concentric with them, as on the island itself (28 pt, 20 pt and 8 pt there).
    static let islandRadius: CGFloat = 8
    static let widgetInset: CGFloat = 4

    /// A picture's size on the page.
    static func size(_ width: CGFloat, _ height: CGFloat, scale: CGFloat) -> CGSize {
        CGSize(width: width * scale, height: height * scale)
    }

    /// A row of five pictures as drawn (`sizePicture`, `PictureChoice`): what the pictures' size
    /// on a page is measured by.
    static let widestRow: CGFloat = 5 * sizePicture.width + 4 * choiceSpacing
    /// The open island at one of its sizes (`IslandSizePicture`), as drawn.
    static let sizePicture = CGSize(width: 118, height: 74)
    /// Between the pictures of a row of choices, as drawn.
    static let choiceSpacing: CGFloat = 12
    /// The pictures at most this much larger than drawn, however wide the page.
    static let largestPictureScale: CGFloat = 1.4

    /// How large a page `pageWidth` wide shows the pictures that stand alone or in a pair
    /// (those that share a row's whole width take their size from it, `FittedPicture`): as large
    /// as five in a row would have room for in a card, in steps of a twentieth; smaller than
    /// drawn on a page too narrow even for that.
    static func pictureScale(pageWidth: CGFloat) -> CGFloat {
        let fit = (pageWidth - 2 * SettingsForm.inset) / widestRow
        return min(max((fit * 20).rounded(.down) / 20, 0.5), largestPictureScale)
    }
}

extension EnvironmentValues {
    /// How many times as large as drawn Settings' pictures are shown (`MiniDesktop`).
    @Entry var settingsPictureScale: CGFloat = 1
    /// A picture's corners: 10 pt where it stands in a row with room round it; a picture at the
    /// card's own inset is rounded concentric with the card (`SettingsForm.pictureRadius`).
    @Entry var settingsPictureRadius: CGFloat = 10
}

/// A picture as wide as it is given, drawn that many times as large as `drawn`: pictures in one
/// row share its whole width, the first and the last the card's inset from its sides, so their
/// corners are concentric with the card's.
struct FittedPicture<Content: View>: View {
    /// The picture's size as drawn.
    let drawn: CGSize
    @ViewBuilder var content: Content

    var body: some View {
        Color.clear
            .aspectRatio(drawn.width / drawn.height, contentMode: .fit)
            .overlay {
                GeometryReader { proxy in
                    if proxy.size.width > 0 {
                        content
                            .environment(\.settingsPictureScale, proxy.size.width / drawn.width)
                            .environment(\.settingsPictureRadius, SettingsForm.pictureRadius)
                    }
                }
            }
    }
}

/// The open island, empty, photographed in a surface style at a size over a drawn desktop: the
/// island as it is — its real proportions, corners and glass — where a drawing of it only came
/// near (asked for). The photographs are taken from the running app (`Scripts/settings-pictures.sh`,
/// `demo/picture`) over each drawn desktop of General ▸ Preview Wallpaper (the user's own desktop
/// shows the dark default's) and ship in the app's resources; where there are none (the tests, a
/// bare `swift run`), the drawn pictures stand in.
struct IslandPhoto: View {
    let image: NSImage
    var size = IslandPhoto.size

    @Environment(\.settingsPictureScale) private var k
    @Environment(\.settingsPictureRadius) private var radius

    /// As drawn: the photographs' 16:9 (`DemoDirector.pictureSize`).
    static let size = CGSize(width: 160, height: 90)
    /// A live activity's: the notch and a little desktop round it (`DemoDirector.activityPictureSize`).
    static let activitySize = CGSize(width: 216, height: 72)

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .frame(width: size.width * k, height: size.height * k)
            .clipShape(.rect(cornerRadius: radius, style: .continuous))
            .accessibilityHidden(true)
    }

    /// Looked up once each (also the ones that are not there).
    private static var loaded: [String: NSImage?] = [:]

    static func image(desktop: DesktopBackdropStyle, style: IslandGlassStyle, scale: IslandScale) -> NSImage? {
        named("island-\(drawn(desktop).rawValue)-\(style.rawValue)-\(scale.rawValue)")
    }

    /// A live activity in the notch.
    static func activity(_ activity: PictureActivity, desktop: DesktopBackdropStyle, style: IslandGlassStyle) -> NSImage? {
        named("activity-\(drawn(desktop).rawValue)-\(style.rawValue)-\(activity.rawValue)")
    }

    /// The desktop with the bare notch.
    static func idle(desktop: DesktopBackdropStyle) -> NSImage? {
        named("idle-\(drawn(desktop).rawValue)")
    }

    /// The open island's outline at each size, as photographed.
    static let geometry: [String: IslandPhotoGeometry] = Bundle.main
        .url(forResource: "geometry", withExtension: "json", subdirectory: "SettingsPictures")
        .flatMap { try? Data(contentsOf: $0) }
        .flatMap { try? JSONDecoder().decode([String: IslandPhotoGeometry].self, from: $0) } ?? [:]

    /// The photographs are over the drawn desktops only.
    private static func drawn(_ desktop: DesktopBackdropStyle) -> DesktopBackdropStyle {
        desktop == .desktop ? .system : desktop
    }

    private static func named(_ name: String) -> NSImage? {
        if let known = loaded[name] { return known }
        let image = Bundle.main.url(forResource: name, withExtension: "jpg", subdirectory: "SettingsPictures")
            .flatMap { NSImage(contentsOf: $0) }
        loaded[name] = .some(image)
        return image
    }
}

/// A live activity's picture: the notch photographed with it, in the surface style in use over the
/// preview wallpaper; the drawn picture where there is no photograph.
struct ActivityPicture<Drawn: View>: View {
    let activity: PictureActivity
    @ViewBuilder var drawn: Drawn

    @Environment(AppModel.self) private var model
    @AppStorage(DesktopBackdropStyle.key) private var desktop: DesktopBackdropStyle = DesktopBackdropStyle.defaultStyle

    var body: some View {
        if let photo = IslandPhoto.activity(activity, desktop: desktop, style: model.preferences.glassStyle) {
            IslandPhoto(image: photo, size: IslandPhoto.activitySize)
        } else {
            drawn
        }
    }
}

/// The open island's outline at one size as it was photographed (points on the photographed
/// screen, of `DemoDirector.pictureSize`): what the picture of its opening grows it along.
nonisolated struct IslandPhotoGeometry: Codable, Sendable, Equatable {
    var width: CGFloat
    var height: CGFloat
    var radius: CGFloat
    var shoulder: CGFloat
    var notchWidth: CGFloat
    var notchHeight: CGFloat
}

/// A black island in miniature, hanging from the top.
struct MiniIsland<Content: View>: View {
    let width: CGFloat
    let height: CGFloat
    /// Its lower corners (a banner's or a pill's: as round as its height lets them be).
    var radius: CGFloat?
    @ViewBuilder var content: Content

    @Environment(\.settingsPictureScale) private var k

    var body: some View {
        IslandShape(bottomRadius: (radius ?? min(10, height / 2)) * k, shoulderRadius: 3 * k)
            .fill(.black)
            .frame(width: width * k, height: height * k)
            .overlay(alignment: .top) {
                content
                    .frame(width: width * k, height: height * k, alignment: .top)
            }
    }
}

/// Picture cards, like System Settings' Appearance: one per choice, the selected one ringed.
struct PictureChoice<Value: Hashable, Picture: View>: View {
    let options: [Value]
    @Binding var selection: Value
    let title: (Value) -> String
    var cardWidth: CGFloat = 150
    /// The pictures' size as drawn: given, they share the row's whole width (`FittedPicture`),
    /// as far from one another as from the card's edges.
    var filling: CGSize?
    @ViewBuilder let picture: (Value) -> Picture

    @Environment(\.settingsPictureScale) private var k

    var body: some View {
        HStack(alignment: .top, spacing: filling == nil ? MiniMetrics.choiceSpacing * k : SettingsForm.inset) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection
                Button {
                    withAnimation(.spring(duration: 0.3, bounce: 0.15)) { selection = option }
                } label: {
                    VStack(spacing: 7) {
                        Group {
                            if let filling {
                                FittedPicture(drawn: filling) { picture(option) }
                            } else {
                                picture(option)
                            }
                        }
                            .overlay {
                                RoundedRectangle(cornerRadius: filling == nil ? 10 : SettingsForm.pictureRadius, style: .continuous)
                                    .strokeBorder(isSelected ? Color.islandAccent : .white.opacity(0.12),
                                                  lineWidth: isSelected ? 3 : 1)
                            }
                        Text(title(option))
                            .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? .primary : SettingsPalette.secondary)
                            .lineLimit(1)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// Tiny widgets inside a pictured island: two in a row, as tall as their room, their corners
/// concentric with the island's (`radius`: the island's less the widgets' inset) and as far from
/// each other as from the island's sides (`gap`).
struct MiniWidgets: View {
    let width: CGFloat
    let height: CGFloat
    var radius: CGFloat = MiniMetrics.islandRadius - MiniMetrics.widgetInset
    var gap: CGFloat = MiniMetrics.widgetInset

    @Environment(\.settingsPictureScale) private var k

    var body: some View {
        // The cover in the first widget: as far in as half the widget's corner, concentric with it.
        let inset = max(1.5, radius / 2)
        let side = width * 0.4
        HStack(spacing: gap * k) {
            RoundedRectangle(cornerRadius: radius * k, style: .continuous).fill(.white.opacity(0.22))
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: (radius - inset) * k, style: .continuous).fill(.pink.opacity(0.8))
                        .padding(inset * k).aspectRatio(1, contentMode: .fit)
                }
            RoundedRectangle(cornerRadius: radius * k, style: .continuous).fill(.white.opacity(0.16))
                .overlay(alignment: .leading) {
                    VStack(alignment: .leading, spacing: 2.5 * k) {
                        Capsule().fill(.orange.opacity(0.85)).frame(width: side * 0.55 * k, height: 2 * k)
                        Capsule().fill(.white.opacity(0.3)).frame(width: side * 0.35 * k, height: 2 * k)
                    }
                    .padding(.leading, (radius + 1) * k)
                }
                .frame(width: side * k)
        }
        .frame(width: width * k, height: height * k)
    }
}

/// The open island at one of the sizes (General ▸ Size when open).
struct IslandSizePicture: View {
    let scale: IslandScale

    @Environment(\.settingsPictureScale) private var k

    var body: some View {
        let f = scale.factor
        let width = (600 * f * MiniMetrics.scale).rounded()
        let height = (MiniMetrics.menuBar + 160 * f * MiniMetrics.scale).rounded()
        // The island's corners and its widgets' inset grow with it, as they do on the island.
        let radius = MiniMetrics.islandRadius * f, inset = MiniMetrics.widgetInset * f
        MiniDesktop(width: MiniMetrics.sizePicture.width, height: MiniMetrics.sizePicture.height) {
            MiniIsland(width: width, height: height, radius: radius) {
                MiniWidgets(width: width - 2 * inset, height: height - MiniMetrics.menuBar - 2 * inset,
                            radius: radius - inset, gap: inset)
                    .padding(.top, (MiniMetrics.menuBar + inset) * k)
            }
        }
    }
}

/// The island growing out of the notch and back, over and over, at the chosen speed (General ▸
/// Animation length).
///
/// The desktop is SwiftUI; the island and its widgets are Core Animation layers (`GrowthLoopView`),
/// looped by the window server. Driven by SwiftUI, every frame of the loop ran an update over all of
/// Settings (measured: ~11 % CPU for as long as General was open), even in a graph of its own.
struct GrowthPicture: View {
    let duration: Double

    @Environment(\.settingsPictureScale) private var k
    @Environment(\.settingsPictureRadius) private var radius
    @Environment(AppModel.self) private var model
    @AppStorage(DesktopBackdropStyle.key) private var desktop: DesktopBackdropStyle = DesktopBackdropStyle.defaultStyle

    var body: some View {
        let preferences = model.preferences
        // The island as photographed, in the style and at the size in use: the photograph of it
        // open shows through its outline as that grows out of the notch over the bare desktop's.
        if let closed = IslandPhoto.idle(desktop: desktop),
           let open = IslandPhoto.image(desktop: desktop, style: preferences.glassStyle, scale: preferences.scale),
           let geometry = IslandPhoto.geometry[preferences.scale.rawValue] {
            GrowthLoop(duration: duration, scale: k, photo: GrowthPhoto(closed: closed, open: open, geometry: geometry))
                .frame(width: IslandPhoto.size.width * k, height: IslandPhoto.size.height * k)
                .clipShape(.rect(cornerRadius: radius, style: .continuous))
                .accessibilityHidden(true)
        } else {
            let shown = MiniMetrics.size(Self.size.width, Self.size.height, scale: k)
            MiniDesktop(width: Self.size.width, height: Self.size.height) {
                GrowthLoop(duration: duration, scale: k)
                    .frame(width: shown.width, height: shown.height)
            }
        }
    }

    // As drawn (`settingsPictureScale` times as large on the page).
    static let size = CGSize(width: 150, height: 70)
    static let open = CGSize(width: 102, height: 40)
    static let closed = CGSize(width: MiniMetrics.notchWidth, height: MiniMetrics.menuBar)
    /// Where the widgets sit in the open island.
    static let widgets = CGSize(width: open.width - 2 * MiniMetrics.widgetInset,
                                height: open.height - MiniMetrics.menuBar - 2 * MiniMetrics.widgetInset)

    /// The island's outline at a size (as drawn), top-centred in a picture `width` wide and
    /// `scale` times as large (`MiniIsland`'s shape).
    static func islandPath(_ size: CGSize, in width: CGFloat, scale: CGFloat,
                           radius: CGFloat = MiniMetrics.islandRadius, shoulder: CGFloat = 3) -> CGPath {
        let rect = CGRect(x: (width - size.width * scale) / 2, y: 0, width: size.width * scale, height: size.height * scale)
        return IslandShape(bottomRadius: min(radius, size.height / 2) * scale, shoulderRadius: shoulder * scale)
            .path(in: rect).cgPath
    }
}

/// The photographs the island's opening is shown with: the bare desktop, the island open over it,
/// and the open island's outline in them.
struct GrowthPhoto: Equatable {
    let closed: NSImage
    let open: NSImage
    let geometry: IslandPhotoGeometry

    static func == (a: GrowthPhoto, b: GrowthPhoto) -> Bool {
        a.closed === b.closed && a.open === b.open && a.geometry == b.geometry
    }
}

private struct GrowthLoop: NSViewRepresentable {
    let duration: Double
    let scale: CGFloat
    var photo: GrowthPhoto?

    func makeNSView(context: Context) -> GrowthLoopView {
        let view = GrowthLoopView(frame: CGRect(origin: .zero, size: MiniMetrics.size(GrowthPicture.size.width, GrowthPicture.size.height,
                                                                                    scale: scale)))
        view.scale = scale
        view.photo = photo
        return view
    }

    func updateNSView(_ view: GrowthLoopView, context: Context) {
        view.scale = scale
        view.photo = photo
        view.duration = duration
    }
}

/// The looping island of `GrowthPicture`: a black island shape whose outline springs between the
/// notch and the open size, and the widgets fading in and out with it — the same springs and pauses
/// the SwiftUI picture used (open: `duration`, bounce 0.2, then 0.9 s; close: 0.8 × `duration`,
/// no bounce, then 0.6 s).
///
/// Each spring is its own animation, added just before it starts: between them nothing is attached
/// and the window server draws no frames. A repeating group of the same springs was active through
/// the pauses as well (58 % of the cycle), and every one of its 60 frames a second re-composited
/// Settings around the picture: 0.25–0.75 W in the window server for as long as General was open
/// (measured), against ~0.02 W without the picture.
final class GrowthLoopView: NSView {
    private let island = CAShapeLayer()
    private let widgets = CALayer()
    static let animationKey = "growth"
    /// How far ahead of its start a spring is handed to the render server.
    static let lead: CFTimeInterval = 0.05

    var duration: Double = 0 {
        didSet { if duration != oldValue { restart() } }
    }

    /// How many times as large as drawn the picture is shown: the island and its widgets with it.
    var scale: CGFloat = 1 {
        didSet {
            guard scale != oldValue else { return }
            widgets.contents = nil
            needsLayout = true
            restart()
        }
    }

    private var laidWidth: CGFloat = 0

    /// Photographs instead of the drawn island (`GrowthPicture`): the bare desktop, and over it
    /// the photograph of the open island, seen through the island's outline (its mask) as that
    /// springs open and shut — the same springs, and still nothing drawn per frame by the app.
    var photo: GrowthPhoto? {
        didSet {
            guard photo != oldValue else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            base.contents = photo?.closed
            reveal.contents = photo?.open
            if photo != nil {
                island.removeFromSuperlayer()
                reveal.mask = island
                widgets.isHidden = true
            } else {
                reveal.mask = nil
                layer?.insertSublayer(island, below: widgets)
                widgets.isHidden = false
            }
            CATransaction.commit()
            needsLayout = true
            restart()
        }
    }
    private let base = CALayer()
    private let reveal = CALayer()

    private var closedSize: CGSize {
        photo.map { CGSize(width: $0.geometry.notchWidth + 2 * $0.geometry.shoulder, height: $0.geometry.notchHeight) } ?? GrowthPicture.closed
    }

    /// A point more than the island's own outline at each side and its foot: its edge light too.
    private var openSize: CGSize {
        photo.map { CGSize(width: $0.geometry.width + 2, height: $0.geometry.height + 1) } ?? GrowthPicture.open
    }

    private func path(_ size: CGSize) -> CGPath {
        guard let photo else { return GrowthPicture.islandPath(size, in: bounds.width, scale: scale) }
        // Photographed points to the picture's.
        return GrowthPicture.islandPath(size, in: bounds.width, scale: bounds.width / 800,
                                        radius: photo.geometry.radius, shoulder: photo.geometry.shoulder)
    }

    /// When the running loop's first cycle started (media time), and the next spring to add.
    private var cycleStart: CFTimeInterval = 0
    private var nextStep = 0
    private var timer: (any DispatchSourceTimer)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        wantsLayer = true
        island.fillColor = NSColor.black.cgColor
        island.path = path(closedSize)
        widgets.opacity = 0
        widgets.contentsGravity = .resize
        base.contentsGravity = .resize
        reveal.contentsGravity = .resize
        layer?.addSublayer(base)
        layer?.addSublayer(reveal)
        layer?.addSublayer(island)
        layer?.addSublayer(widgets)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit { timer?.cancel() }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        restart()
    }

    /// Its page hidden (Settings keeps its pages): no timer, no spring until it shows again.
    override func viewDidHide() {
        super.viewDidHide()
        restart()
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        restart()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        island.frame = bounds
        base.frame = bounds
        reveal.frame = bounds
        let size = GrowthPicture.widgets
        widgets.frame = CGRect(x: (bounds.width - size.width * scale) / 2, y: (MiniMetrics.menuBar + MiniMetrics.widgetInset) * scale,
                               width: size.width * scale, height: size.height * scale)
        CATransaction.commit()
        // At another width (the pictures' scale changed): the outline is centred in it, from the
        // loop's start.
        if bounds.width != laidWidth {
            laidWidth = bounds.width
            restart()
        }
    }

    /// Open, pause, close, pause: when the close starts and how long one cycle is.
    private var closeAt: Double { duration + 0.9 }
    private var cycle: Double { closeAt + duration + 0.6 }

    private func restart() {
        timer?.cancel()
        timer = nil
        island.removeAnimation(forKey: Self.animationKey)
        widgets.removeAnimation(forKey: Self.animationKey)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        island.path = path(closedSize)
        widgets.opacity = 0
        CATransaction.commit()
        guard let window, duration > 0, !isHiddenOrHasHiddenAncestor else { return }
        if photo == nil, widgets.contents == nil { renderWidgets(scale: window.backingScaleFactor) }
        cycleStart = CACurrentMediaTime() + Self.lead
        nextStep = 0
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: .main)
        timer.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.addNextSpring() }
        }
        self.timer = timer
        timer.schedule(deadline: .now())
        timer.resume()
    }

    /// Adds the next spring at its exact place in the loop, then waits until just before the one
    /// after it.
    private func addNextSpring() {
        guard window != nil, duration > 0, !isHiddenOrHasHiddenAncestor else { return }
        let opens = nextStep % 2 == 0
        var begin = cycleStart + Double(nextStep / 2) * cycle + (opens ? 0 : closeAt)
        // Woken late (a busy main thread, say a page being built), the loop waits for it rather
        // than starting the spring part-way through.
        let earliest = CACurrentMediaTime() + 0.01
        if begin < earliest {
            cycleStart += earliest - begin
            begin = earliest
        }
        let closed = path(closedSize)
        let open = path(openSize)

        func spring(_ key: String, from: Any, to: Any, duration: Double, bounce: Double, available: Double) -> CASpringAnimation {
            let animation = CASpringAnimation(perceptualDuration: duration, bounce: bounce)
            animation.keyPath = key
            animation.fromValue = from
            animation.toValue = to
            animation.beginTime = begin
            animation.duration = min(animation.settlingDuration, available)
            // Until it starts, the spring holds where it starts (the model already holds where
            // it ends).
            animation.fillMode = .backwards
            return animation
        }
        let available = opens ? cycle : cycle - closeAt
        let length = opens ? duration : duration * 0.8
        let bounce = opens ? 0.2 : 0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        island.path = opens ? open : closed
        widgets.opacity = opens ? 1 : 0
        // Scrolled out of sight (the picture sits at the foot of General), the loop keeps its place
        // in time without a single frame: the springs are only skipped, and it carries on as soon
        // as it scrolls back into view.
        if !visibleRect.isEmpty {
            island.add(spring("path", from: opens ? closed : open, to: opens ? open : closed,
                              duration: length, bounce: bounce, available: available), forKey: Self.animationKey)
            widgets.add(spring("opacity", from: opens ? 0 : 1, to: opens ? 1 : 0,
                               duration: length, bounce: bounce, available: available), forKey: Self.animationKey)
        }
        CATransaction.commit()

        nextStep += 1
        let following = cycleStart + Double(nextStep / 2) * cycle + (nextStep % 2 == 0 ? 0 : closeAt)
        let wait = max(0, following - Self.lead - CACurrentMediaTime())
        timer?.schedule(deadline: .now() + wait, leeway: .milliseconds(5))
    }

    /// The widgets never change: drawn once into the layer.
    private func renderWidgets(scale backing: CGFloat) {
        let size = GrowthPicture.widgets
        let renderer = ImageRenderer(content: MiniWidgets(width: size.width, height: size.height)
            .environment(\.settingsPictureScale, scale))
        renderer.scale = backing
        widgets.contents = renderer.cgImage
        widgets.contentsScale = backing
    }
}

/// Volume in the notch, as a banner under it or as the minimal pill beside it.
struct LevelStylePicture: View {
    let style: LevelHUDStyle

    @Environment(\.settingsPictureScale) private var k

    var body: some View {
        MiniDesktop(width: 150, height: 70) {
            switch style {
            case .banner:
                MiniIsland(width: 96, height: MiniMetrics.menuBar + 16) {
                    HStack(spacing: 5 * k) {
                        Image(systemName: "speaker.wave.2.fill").font(.system(size: 7 * k))
                        MiniSlider(value: 0.6).frame(width: 46 * k)
                        Text("60%").font(.system(size: 6 * k, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.top, (MiniMetrics.menuBar + 3) * k)
                }
            case .pill:
                MiniIsland(width: MiniMetrics.notchWidth + 2 * 30, height: MiniMetrics.menuBar) {
                    HStack {
                        Image(systemName: "speaker.wave.2.fill").font(.system(size: 6 * k))
                        Spacer(minLength: MiniMetrics.notchWidth * k)
                        MiniSlider(value: 0.6).frame(width: 20 * k)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6 * k)
                    .frame(height: MiniMetrics.menuBar * k)
                }
            }
        }
    }
}

private struct MiniSlider: View {
    let value: Double

    @Environment(\.settingsPictureScale) private var k

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.25))
                Capsule().fill(Color.islandAccent).frame(width: proxy.size.width * value)
            }
        }
        .frame(height: 3 * k)
    }
}

/// Now Playing's pill: the cover beside the notch, the level bars moving on the other side.
struct NowPlayingPicture: View {
    @Environment(\.settingsPictureScale) private var k

    var body: some View {
        MiniDesktop(width: 150, height: 56) {
            MiniIsland(width: MiniMetrics.notchWidth + 2 * 16, height: MiniMetrics.menuBar) {
                HStack {
                    RoundedRectangle(cornerRadius: 2 * k)
                        .fill(LinearGradient(colors: [.pink, .orange], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 8 * k, height: 8 * k)
                    Spacer(minLength: MiniMetrics.notchWidth * k)
                    MiniEqualizer().frame(width: 8 * k, height: 7 * k)
                }
                .padding(.horizontal, 4 * k)
                .frame(height: MiniMetrics.menuBar * k)
            }
        }
    }
}

/// The pill's own bars in miniature: Core Animation, so an open Settings page costs no frames.
/// (A SwiftUI `TimelineView` here re-rendered the page 8 times a second for as long as it was open.)
private struct MiniEqualizer: View {
    @Environment(\.settingsPictureScale) private var k

    var body: some View {
        EqualizerView(isAnimating: true, onBattery: true, size: CGSize(width: 9.5 * k, height: 7 * k), barWidth: 1.2 * k)
    }
}

/// The AirPods banner: the set, its name, and three battery rings.
struct AirPodsPicture: View {
    @Environment(\.settingsPictureScale) private var k

    var body: some View {
        MiniDesktop(width: 150, height: 56) {
            MiniIsland(width: 104, height: MiniMetrics.menuBar + 18) {
                HStack(spacing: 4 * k) {
                    Image(systemName: "airpods.pro").font(.system(size: 9 * k))
                    Text("AirPods").font(.system(size: 6 * k, weight: .semibold))
                    Spacer(minLength: 2 * k)
                    ForEach([0.8, 0.82, 0.86], id: \.self) { level in
                        Circle().trim(from: 0, to: level)
                            .stroke(.green, style: StrokeStyle(lineWidth: 1.2 * k, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .background(Circle().stroke(.white.opacity(0.2), lineWidth: 1.2 * k))
                            .frame(width: 8 * k, height: 8 * k)
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8 * k)
                .padding(.top, (MiniMetrics.menuBar + 4) * k)
            }
        }
    }
}

/// A power notice: the battery charging, under the notch.
struct PowerPicture: View {
    @Environment(\.settingsPictureScale) private var k

    var body: some View {
        MiniDesktop(width: 150, height: 56) {
            MiniIsland(width: 96, height: MiniMetrics.menuBar + 16) {
                HStack(spacing: 5 * k) {
                    Image(systemName: "bolt.fill").font(.system(size: 7 * k)).foregroundStyle(.green)
                    Text("Charging").font(.system(size: 6 * k, weight: .semibold))
                    Spacer(minLength: 2 * k)
                    BatteryGlyph(level: 76, isCharging: true, tint: .charging, height: 6 * k)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8 * k)
                .padding(.top, (MiniMetrics.menuBar + 3) * k)
            }
        }
    }
}

/// One picture above a section's settings, centred.
struct SettingPictureRow<Picture: View>: View {
    @ViewBuilder var picture: Picture

    var body: some View {
        picture
            .frame(maxWidth: .infinity)
            // The picture's corners (10 pt) concentric with the card's (it opens a section).
            .padding(.vertical, SettingsForm.cardRadius - SettingsForm.inset - 10)
    }
}
