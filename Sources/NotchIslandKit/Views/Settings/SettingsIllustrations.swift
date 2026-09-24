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
            .foregroundStyle(isShown ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(SettingsPalette.secondary))
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

/// A desktop in miniature: the default wallpaper, the menu bar, and whatever hangs from the notch.
struct MiniDesktop<Content: View>: View {
    var width: CGFloat = 150
    var height: CGFloat = 94
    @ViewBuilder var content: Content

    var body: some View {
        ZStack(alignment: .top) {
            DefaultWallpaper()
            Rectangle().fill(.black.opacity(0.14)).frame(height: MiniMetrics.menuBar)
            content
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
                                    .strokeBorder(isSelected ? Color.accentColor : .white.opacity(0.12),
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
private struct MiniWidgets: View {
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
/// Animation length). Runs only while on screen.
struct GrowthPicture: View {
    let duration: Double

    @State private var isOpen = false

    var body: some View {
        let open = CGSize(width: 102, height: 40)
        let closed = CGSize(width: MiniMetrics.notchWidth, height: MiniMetrics.menuBar)
        MiniDesktop(width: 150, height: 70) {
            MiniIsland(width: isOpen ? open.width : closed.width, height: isOpen ? open.height : closed.height) {
                MiniWidgets(width: open.width - 10, height: open.height - MiniMetrics.menuBar - 5)
                    .padding(.top, MiniMetrics.menuBar + 1)
                    .opacity(isOpen ? 1 : 0)
            }
        }
        .task(id: duration) {
            while !Task.isCancelled {
                withAnimation(.spring(duration: duration, bounce: 0.2)) { isOpen = true }
                try? await Task.sleep(for: .seconds(duration + 0.9))
                guard !Task.isCancelled else { return }
                withAnimation(.spring(duration: duration * 0.8, bounce: 0)) { isOpen = false }
                try? await Task.sleep(for: .seconds(duration + 0.6))
            }
        }
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
                Capsule().fill(Color.accentColor).frame(width: proxy.size.width * value)
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

private struct MiniEqualizer: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 8)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 1) {
                ForEach(0..<3, id: \.self) { bar in
                    Capsule()
                        .fill(.white)
                        .frame(height: 2 + 5 * abs(sin(t * 3 + Double(bar) * 1.3)))
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
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
