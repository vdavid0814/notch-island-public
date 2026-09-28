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
struct MiniDesktop<Content: View>: View {
    var width: CGFloat = 150
    var height: CGFloat = 94
    @ViewBuilder var content: Content

    @AppStorage(DesktopBackdropStyle.key) private var style: DesktopBackdropStyle = DesktopBackdropStyle.defaultStyle

    var body: some View {
        ZStack(alignment: .top) {
            // A picture this small needs no more than the miniature (up to 240 pt wide at 2×).
            DesktopBackdrop(style: style, detail: width <= 240 && height <= 240 ? .miniature : .full)
            PreviewMenuBar(height: MiniMetrics.menuBar, notchWidth: MiniMetrics.notchWidth + 14,
                           darkText: style.prefersDarkMenuBar,
                           backing: style.menuBarBacking)
            content
                // The island floats over the desktop like the real one, with its soft shadow.
                .shadow(color: .black.opacity(0.35), radius: 3, y: 1.5)
            // The camera housing: whatever the island shows, the notch itself stays black.
            UnevenRoundedRectangle(bottomLeadingRadius: 3, bottomTrailingRadius: 3, style: .continuous)
                .fill(.black)
                .frame(width: MiniMetrics.notchWidth, height: MiniMetrics.menuBar)
        }
        .frame(width: width, height: height)
        .clipShape(.rect(cornerRadius: 10, style: .continuous))
        .accessibilityHidden(true)
    }
}

nonisolated enum MiniMetrics {
    static let menuBar: CGFloat = 12
    static let notchWidth: CGFloat = 34
    /// Real island points to picture points.
    static let scale: CGFloat = 0.17
}

/// A black island in miniature, hanging from the top.
struct MiniIsland<Content: View>: View {
    let width: CGFloat
    let height: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        IslandShape(bottomRadius: min(10, height / 2), shoulderRadius: 3)
            .fill(.black)
            .frame(width: width, height: height)
            .overlay(alignment: .top) {
                content
                    .frame(width: width, height: height, alignment: .top)
            }
    }
}

/// Picture cards, like System Settings' Appearance: one per choice, the selected one ringed.
struct PictureChoice<Value: Hashable, Picture: View>: View {
    let options: [Value]
    @Binding var selection: Value
    let title: (Value) -> String
    var cardWidth: CGFloat = 150
    @ViewBuilder let picture: (Value) -> Picture

    var body: some View {
        HStack(spacing: 12) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection
                Button {
                    withAnimation(.spring(duration: 0.3, bounce: 0.15)) { selection = option }
                } label: {
                    VStack(spacing: 7) {
                        picture(option)
                            .overlay {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
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

/// Tiny widgets inside a pictured island.
struct MiniWidgets: View {
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        let gap: CGFloat = 3
        HStack(spacing: gap) {
            RoundedRectangle(cornerRadius: 3, style: .continuous).fill(.white.opacity(0.22))
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(.pink.opacity(0.8)).padding(2).aspectRatio(1, contentMode: .fit)
                }
            VStack(spacing: gap) {
                RoundedRectangle(cornerRadius: 3, style: .continuous).fill(.white.opacity(0.22))
                    .overlay { Capsule().fill(.orange.opacity(0.85)).frame(height: 2).padding(.horizontal, 4) }
                RoundedRectangle(cornerRadius: 3, style: .continuous).fill(.white.opacity(0.14))
            }
            .frame(width: width * 0.38)
        }
        .frame(width: width, height: height)
    }
}

/// The open island at one of the sizes (General ▸ Size when open).
struct IslandSizePicture: View {
    let scale: IslandScale

    var body: some View {
        let f = scale.factor
        let width = (600 * f * MiniMetrics.scale).rounded()
        let height = (MiniMetrics.menuBar + 160 * f * MiniMetrics.scale).rounded()
        MiniDesktop(width: 118, height: 74) {
            MiniIsland(width: width, height: height) {
                MiniWidgets(width: width - 10, height: height - MiniMetrics.menuBar - 5)
                    .padding(.top, MiniMetrics.menuBar + 1)
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

    var body: some View {
        MiniDesktop(width: Self.size.width, height: Self.size.height) {
            GrowthLoop(duration: duration)
                .frame(width: Self.size.width, height: Self.size.height)
        }
    }

    static let size = CGSize(width: 150, height: 70)
    static let open = CGSize(width: 102, height: 40)
    static let closed = CGSize(width: MiniMetrics.notchWidth, height: MiniMetrics.menuBar)
    /// Where the widgets sit in the open island.
    static let widgets = CGSize(width: open.width - 10, height: open.height - MiniMetrics.menuBar - 5)

    /// The island's outline at a size, top-centred in the picture (`MiniIsland`'s shape).
    static func islandPath(_ size: CGSize) -> CGPath {
        let rect = CGRect(x: (Self.size.width - size.width) / 2, y: 0, width: size.width, height: size.height)
        return IslandShape(bottomRadius: min(10, size.height / 2), shoulderRadius: 3).path(in: rect).cgPath
    }
}

private struct GrowthLoop: NSViewRepresentable {
    let duration: Double

    func makeNSView(context: Context) -> GrowthLoopView {
        GrowthLoopView(frame: CGRect(origin: .zero, size: GrowthPicture.size))
    }

    func updateNSView(_ view: GrowthLoopView, context: Context) {
        view.duration = duration
    }
}

/// The looping island of `GrowthPicture`: a black island shape whose outline springs between the
/// notch and the open size, and the widgets fading in and out with it — the same springs and pauses
/// the SwiftUI picture used (open: `duration`, bounce 0.2, then 0.9 s; close: 0.8 × `duration`,
/// no bounce, then 0.6 s).
final class GrowthLoopView: NSView {
    private let island = CAShapeLayer()
    private let widgets = CALayer()
    static let animationKey = "growth"

    var duration: Double = 0 {
        didSet { if duration != oldValue { restart() } }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        wantsLayer = true
        island.fillColor = NSColor.black.cgColor
        island.path = GrowthPicture.islandPath(GrowthPicture.closed)
        widgets.opacity = 0
        widgets.contentsGravity = .resize
        layer?.addSublayer(island)
        layer?.addSublayer(widgets)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        restart()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        island.frame = bounds
        let size = GrowthPicture.widgets
        widgets.frame = CGRect(x: (bounds.width - size.width) / 2, y: MiniMetrics.menuBar + 1,
                               width: size.width, height: size.height)
        CATransaction.commit()
    }

    private func restart() {
        island.removeAnimation(forKey: Self.animationKey)
        widgets.removeAnimation(forKey: Self.animationKey)
        guard let window, duration > 0 else { return }
        if widgets.contents == nil { renderWidgets(scale: window.backingScaleFactor) }

        let closed = GrowthPicture.islandPath(GrowthPicture.closed)
        let open = GrowthPicture.islandPath(GrowthPicture.open)
        let closeAt = duration + 0.9
        let cycle = closeAt + duration + 0.6

        func spring(_ key: String, from: Any, to: Any, begin: Double, duration: Double, bounce: Double) -> CASpringAnimation {
            let animation = CASpringAnimation(perceptualDuration: duration, bounce: bounce)
            animation.keyPath = key
            animation.fromValue = from
            animation.toValue = to
            animation.beginTime = begin
            animation.duration = min(animation.settlingDuration, cycle - begin)
            animation.fillMode = .forwards
            return animation
        }
        func loop(_ animations: [CAAnimation]) -> CAAnimationGroup {
            let group = CAAnimationGroup()
            group.animations = animations
            group.duration = cycle
            group.repeatCount = .infinity
            group.beginTime = CACurrentMediaTime()
            return group
        }
        island.add(loop([
            spring("path", from: closed, to: open, begin: 0, duration: duration, bounce: 0.2),
            spring("path", from: open, to: closed, begin: closeAt, duration: duration * 0.8, bounce: 0),
        ]), forKey: Self.animationKey)
        widgets.add(loop([
            spring("opacity", from: 0, to: 1, begin: 0, duration: duration, bounce: 0.2),
            spring("opacity", from: 1, to: 0, begin: closeAt, duration: duration * 0.8, bounce: 0),
        ]), forKey: Self.animationKey)
    }

    /// The widgets never change: drawn once into the layer.
    private func renderWidgets(scale: CGFloat) {
        let size = GrowthPicture.widgets
        let renderer = ImageRenderer(content: MiniWidgets(width: size.width, height: size.height)
            .frame(width: size.width, height: size.height))
        renderer.scale = scale
        widgets.contents = renderer.cgImage
        widgets.contentsScale = scale
    }
}

/// Volume in the notch, as a banner under it or as the minimal pill beside it.
struct LevelStylePicture: View {
    let style: LevelHUDStyle

    var body: some View {
        MiniDesktop(width: 150, height: 70) {
            switch style {
            case .banner:
                MiniIsland(width: 96, height: MiniMetrics.menuBar + 16) {
                    HStack(spacing: 5) {
                        Image(systemName: "speaker.wave.2.fill").font(.system(size: 7))
                        MiniSlider(value: 0.6).frame(width: 46)
                        Text("60%").font(.system(size: 6, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.top, MiniMetrics.menuBar + 3)
                }
            case .pill:
                MiniIsland(width: MiniMetrics.notchWidth + 2 * 30, height: MiniMetrics.menuBar) {
                    HStack {
                        Image(systemName: "speaker.wave.2.fill").font(.system(size: 6))
                        Spacer(minLength: MiniMetrics.notchWidth)
                        MiniSlider(value: 0.6).frame(width: 20)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .frame(height: MiniMetrics.menuBar)
                }
            }
        }
    }
}

private struct MiniSlider: View {
    let value: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.25))
                Capsule().fill(Color.islandAccent).frame(width: proxy.size.width * value)
            }
        }
        .frame(height: 3)
    }
}

/// Now Playing's pill: the cover beside the notch, the level bars moving on the other side.
struct NowPlayingPicture: View {
    var body: some View {
        MiniDesktop(width: 150, height: 56) {
            MiniIsland(width: MiniMetrics.notchWidth + 2 * 16, height: MiniMetrics.menuBar) {
                HStack {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(LinearGradient(colors: [.pink, .orange], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 8, height: 8)
                    Spacer(minLength: MiniMetrics.notchWidth)
                    MiniEqualizer().frame(width: 8, height: 7)
                }
                .padding(.horizontal, 4)
                .frame(height: MiniMetrics.menuBar)
            }
        }
    }
}

/// The pill's own bars in miniature: Core Animation, so an open Settings page costs no frames.
/// (A SwiftUI `TimelineView` here re-rendered the page 8 times a second for as long as it was open.)
private struct MiniEqualizer: View {
    var body: some View {
        EqualizerView(isAnimating: true, onBattery: true, size: CGSize(width: 9.5, height: 7), barWidth: 1.2)
    }
}

/// The AirPods banner: the set, its name, and three battery rings.
struct AirPodsPicture: View {
    var body: some View {
        MiniDesktop(width: 150, height: 56) {
            MiniIsland(width: 104, height: MiniMetrics.menuBar + 18) {
                HStack(spacing: 4) {
                    Image(systemName: "airpods.pro").font(.system(size: 9))
                    Text("AirPods").font(.system(size: 6, weight: .semibold))
                    Spacer(minLength: 2)
                    ForEach([0.8, 0.82, 0.86], id: \.self) { level in
                        Circle().trim(from: 0, to: level)
                            .stroke(.green, style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .background(Circle().stroke(.white.opacity(0.2), lineWidth: 1.2))
                            .frame(width: 8, height: 8)
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.top, MiniMetrics.menuBar + 4)
            }
        }
    }
}

/// A power notice: the battery charging, under the notch.
struct PowerPicture: View {
    var body: some View {
        MiniDesktop(width: 150, height: 56) {
            MiniIsland(width: 96, height: MiniMetrics.menuBar + 16) {
                HStack(spacing: 5) {
                    Image(systemName: "bolt.fill").font(.system(size: 7)).foregroundStyle(.green)
                    Text("Charging").font(.system(size: 6, weight: .semibold))
                    Spacer(minLength: 2)
                    BatteryGlyph(level: 76, isCharging: true, tint: .charging, height: 6)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.top, MiniMetrics.menuBar + 3)
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
            .padding(.vertical, 4)
    }
}
