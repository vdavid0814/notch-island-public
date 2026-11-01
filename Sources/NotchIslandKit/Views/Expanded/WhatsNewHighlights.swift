import SwiftUI

/// What's New's first page: the version's highlights as tiles of pictures round its title, and More
/// Details, which leads to every change in cards by topic (`WhatsNewContent`). As high as three rows of
/// cards (`ReleaseNotes.highlightRows`): the left and right columns two tiles each, the middle a wide
/// one over the title and two under it.
struct WhatsNewHighlights: View {
    let notes: ReleaseNotes
    let more: () -> Void
    let close: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The tiles come in one after another as the page opens.
    @State private var tilesIn = false

    var body: some View {
        VStack(spacing: Metrics.Spacing.small) {
            HStack {
                Spacer()
                Button("Done", systemImage: "checkmark", action: close)
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .labelStyle(.iconOnly)
                    .help("Close")
            }
            GeometryReader { proxy in
                bento(in: CGSize(width: proxy.size.width - 8, height: proxy.size.height - 8))
                    .padding(4)
            }
        }
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("What's new in NotchIsland \(notes.version)"))
        .onAppear {
            if reduceMotion { tilesIn = true } else { withAnimation(.spring(duration: 0.6, bounce: 0.2)) { tilesIn = true } }
        }
    }

    private func bento(in size: CGSize) -> some View {
        let gap = InfoRow<EmptyView>.spacing
        let column = (size.width - 3 * gap) / 4
        let side = (size.height - gap) / 2
        let wide = 2 * column + gap
        let top = (size.height * 0.28).rounded()
        let bottom = (size.height * 0.32).rounded()
        return HStack(alignment: .top, spacing: gap) {
            VStack(spacing: gap) {
                tile(0).frame(width: column, height: side)
                tile(1).frame(width: column, height: side)
            }
            VStack(spacing: gap) {
                tile(2).frame(width: wide, height: top)
                hero.frame(width: wide, height: size.height - top - bottom - 2 * gap)
                HStack(spacing: gap) {
                    tile(3).frame(width: column, height: bottom)
                    tile(4).frame(width: column, height: bottom)
                }
            }
            VStack(spacing: gap) {
                tile(5).frame(width: column, height: side)
                tile(6).frame(width: column, height: side)
            }
        }
    }

    @ViewBuilder private func tile(_ index: Int) -> some View {
        if notes.highlights.indices.contains(index) {
            HighlightTile(highlight: notes.highlights[index])
                .opacity(tilesIn ? 1 : 0)
                .scaleEffect(tilesIn ? 1 : 0.92)
                .animation(reduceMotion ? nil : .spring(duration: 0.6, bounce: 0.2).delay(0.05 * Double(index)), value: tilesIn)
        } else {
            Color.clear
        }
    }

    private var hero: some View {
        VStack(spacing: 10) {
            Text(verbatim: "NotchIsland \(notes.version)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(.white.opacity(0.1), in: .capsule)
                .overlay { Capsule().strokeBorder(.white.opacity(0.14)) }
            Text("What's \(Text("New").foregroundStyle(LinearGradient(colors: [.cyan, .blue, .purple], startPoint: .leading, endPoint: .trailing)))")
                .font(.system(size: 48, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if !notes.summary.isEmpty {
                Text(notes.summary)
                    .font(.system(size: 14.5))
                    .foregroundStyle(.white.opacity(0.68))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 12)
            }
            Button(action: more) {
                HStack(spacing: 6) {
                    Text("More Details")
                    Image(systemName: "chevron.right")
                }
                .font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 6)
            }
            .buttonStyle(.glassProminent)
            .tint(.blue)
            .controlSize(.large)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A highlight: its picture, its title at the bottom, on a card of the info pages' look (`InfoWidget`).
private struct HighlightTile: View {
    let highlight: ReleaseNotes.Highlight

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HighlightVisual(visual: highlight.visual)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Text(highlight.title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(16)
        .background(.white.opacity(0.07), in: .rect(cornerRadius: 20, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.08)) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(highlight.title))
    }
}

private struct HighlightVisual: View {
    let visual: ReleaseNotes.Highlight.Visual

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            Group {
                switch visual {
                case .bubbles(let bubbles): Bubbles(bubbles: bubbles, size: size)
                case let .gauge(value, unit, fraction, tint, note):
                    Gauge(value: value, unit: unit, fraction: fraction, tint: tint, note: note,
                          diameter: min(size.width, size.height) - 4)
                case .bars(let bars): Bars(bars: bars, height: size.height)
                case let .flow(from, into): Flow(from: from, into: into, size: size)
                case let .iconStyles(symbol, tint): IconStyles(symbol: symbol, tint: tint, size: size)
                case let .orbit(center, around): Orbit(center: center, around: around, size: size)
                }
            }
            .frame(width: size.width, height: size.height)
        }
    }
}

/// A round, glossy symbol: its colour lighter at the top, a shine over it, a glow of it under it.
private struct GlossyBubble: View {
    let bubble: ReleaseNotes.Highlight.Bubble
    let diameter: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [bubble.tint.mix(with: .white, by: 0.35), bubble.tint,
                                                  bubble.tint.mix(with: .black, by: 0.15)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().fill(RadialGradient(colors: [.white.opacity(0.5), .clear], center: UnitPoint(x: 0.32, y: 0.22),
                                         startRadius: 0, endRadius: diameter * 0.45))
            Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1)
            Image(systemName: bubble.symbol)
                .font(.system(size: diameter * 0.42, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
        }
        .frame(width: diameter, height: diameter)
        .shadow(color: bubble.tint.opacity(0.45), radius: diameter * 0.16, y: diameter * 0.08)
    }
}

private struct Bubbles: View {
    let bubbles: [ReleaseNotes.Highlight.Bubble]
    let size: CGSize

    var body: some View {
        let count = CGFloat(max(1, bubbles.count))
        // Overlapping by a fifth; the middle one a little larger than the rest.
        let diameter = min(size.height * 0.8, size.width / (count - 0.2 * (count - 1)) * 0.92)
        let middle = Double(bubbles.count - 1) / 2
        HStack(spacing: -diameter * 0.2) {
            ForEach(bubbles.indices, id: \.self) { index in
                let off = abs(Double(index) - middle)
                GlossyBubble(bubble: bubbles[index], diameter: diameter * (1 - 0.07 * off))
                    .zIndex(-off)
            }
        }
    }
}

/// A ring of ticks filled to `fraction` from the lower left, the number in it.
private struct Gauge: View {
    let value: String
    let unit: String
    let fraction: Double
    let tint: Color
    let note: String
    let diameter: CGFloat

    var body: some View {
        let line = max(8, diameter * 0.09)
        let filled = 0.75 * min(1, max(0, fraction))
        ZStack {
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(.white.opacity(0.12), style: StrokeStyle(lineWidth: line, dash: [2, 3]))
            Circle()
                .trim(from: 0, to: filled)
                .stroke(AngularGradient(colors: [tint.mix(with: .white, by: 0.4), tint], center: .center,
                                        startAngle: .zero, endAngle: .degrees(270)),
                        style: StrokeStyle(lineWidth: line, dash: [2, 3]))
            Circle()
                .fill(.white)
                .frame(width: line * 1.3, height: line * 1.3)
                .shadow(color: tint, radius: 4)
                .offset(x: diameter / 2 - line / 2)
                .rotationEffect(.degrees(360 * filled))
        }
        .rotationEffect(.degrees(135))
        .frame(width: diameter - line, height: diameter - line)
        .overlay {
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(verbatim: value).font(.system(size: diameter * 0.26, weight: .bold, design: .rounded))
                    Text(verbatim: unit).font(.system(size: diameter * 0.1, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .foregroundStyle(.white)
                if !note.isEmpty {
                    Text(note).font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.55))
                }
            }
        }
    }
}

/// Before and after: bars as high as their amounts, the last in its colour.
private struct Bars: View {
    let bars: [ReleaseNotes.Highlight.Bar]
    let height: CGFloat

    var body: some View {
        let most = bars.map(\.amount).max() ?? 1
        let room = max(20, height - 44)
        HStack(alignment: .bottom, spacing: 18) {
            ForEach(bars.indices, id: \.self) { index in
                let bar = bars[index]
                VStack(spacing: 5) {
                    Text(verbatim: bar.value)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                        .fixedSize()
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(LinearGradient(colors: [bar.tint.mix(with: .white, by: 0.3), bar.tint],
                                             startPoint: .top, endPoint: .bottom))
                        .opacity(index == bars.count - 1 ? 1 : 0.45)
                        .frame(width: 40, height: max(10, room * bar.amount / most))
                        .shadow(color: index == bars.count - 1 ? bar.tint.opacity(0.4) : .clear, radius: 8, y: 3)
                    Text(verbatim: bar.label)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
        }
    }
}

/// Small symbols in a column, an arrow, and the one they go into.
private struct Flow: View {
    let from: [ReleaseNotes.Highlight.Bubble]
    let into: ReleaseNotes.Highlight.Bubble
    let size: CGSize

    var body: some View {
        let small = min(30, (size.height - 12) / CGFloat(max(1, from.count)) - 4)
        HStack(spacing: 10) {
            VStack(spacing: 6) {
                ForEach(from.indices, id: \.self) { GlossyBubble(bubble: from[$0], diameter: small) }
            }
            Image(systemName: "chevron.right.2")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white.opacity(0.45))
            GlossyBubble(bubble: into, diameter: min(size.height * 0.75, size.width - small - 50))
        }
    }
}

/// One symbol as an icon in each of macOS's styles, named under it.
private struct IconStyles: View {
    let symbol: String
    let tint: Color
    let size: CGSize

    var body: some View {
        let side = min((size.width - 16) / 3, size.height * 0.55)
        HStack(spacing: 8) {
            style(String(localized: "Clear"), side: side) {
                RoundedRectangle(cornerRadius: side * 0.26, style: .continuous).fill(.white.opacity(0.14))
                    .overlay { RoundedRectangle(cornerRadius: side * 0.26, style: .continuous).strokeBorder(.white.opacity(0.4)) }
                    .overlay { glyph(side).foregroundStyle(.white) }
            }
            style(String(localized: "Dark"), side: side) {
                RoundedRectangle(cornerRadius: side * 0.26, style: .continuous).fill(.black)
                    .overlay { RoundedRectangle(cornerRadius: side * 0.26, style: .continuous).strokeBorder(.white.opacity(0.18)) }
                    .overlay { glyph(side).foregroundStyle(LinearGradient(colors: [tint.mix(with: .white, by: 0.3), tint],
                                                                          startPoint: .top, endPoint: .bottom)) }
            }
            style(String(localized: "Tinted"), side: side) {
                RoundedRectangle(cornerRadius: side * 0.26, style: .continuous)
                    .fill(LinearGradient(colors: [.orange.mix(with: .black, by: 0.45), .orange.mix(with: .black, by: 0.7)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay { glyph(side).foregroundStyle(.orange.mix(with: .white, by: 0.35)) }
            }
        }
    }

    private func glyph(_ side: CGFloat) -> some View {
        Image(systemName: symbol).font(.system(size: side * 0.44, weight: .semibold))
    }

    private func style(_ name: String, side: CGFloat, @ViewBuilder icon: () -> some View) -> some View {
        VStack(spacing: 6) {
            icon().frame(width: side, height: side)
                .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
            Text(name).font(.system(size: 11.5, weight: .medium)).foregroundStyle(.white.opacity(0.6))
        }
    }
}

/// A large symbol, smaller ones round it at even steps.
private struct Orbit: View {
    let center: ReleaseNotes.Highlight.Bubble
    let around: [ReleaseNotes.Highlight.Bubble]
    let size: CGSize

    var body: some View {
        let big = min(size.width, size.height) * 0.48
        let radius = big * 0.82
        let small = big * 0.46
        ZStack {
            Circle().strokeBorder(.white.opacity(0.1), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                .frame(width: 2 * radius, height: 2 * radius)
            GlossyBubble(bubble: center, diameter: big)
            ForEach(around.indices, id: \.self) { index in
                let angle = Angle.degrees(-90 + 360 * Double(index) / Double(max(1, around.count)) + 30)
                GlossyBubble(bubble: around[index], diameter: small)
                    .offset(x: radius * cos(angle.radians), y: radius * sin(angle.radians))
            }
        }
    }
}
