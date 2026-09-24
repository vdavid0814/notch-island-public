import SwiftUI

/// Headphones connected: "Connected" beside the notch, then the set's picture bouncing in, its name
/// and each battery the system reports — left, right and the case, as rings
/// that fill up one after another, like the iPhone's connection card.
struct AirPodsBanner: View {
    let info: AirPodsInfo

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    var body: some View {
        BannerLayout(kind: .airPods(info)) {
            EmptyView()
        } headerTrailing: {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.subheadline.weight(.semibold))
                .accessibilityHidden(true)
        } row: {
            // The picture, large, bouncing in as the banner grows.
            VStack(spacing: 3) {
                Image(systemName: info.symbol)
                    .font(.system(size: 46, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
                    .symbolEffect(.bounce.up.byLayer, options: .nonRepeating, value: hasAppeared)
            }
            .frame(width: 72)
            VStack(alignment: .leading, spacing: 2) {
                Text(info.name)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text("Connected")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .layoutPriority(1)
            Spacer(minLength: 8)
            HStack(spacing: 12) {
                ForEach(Array(batteries.enumerated()), id: \.offset) { index, battery in
                    AirPodsBatteryItem(symbol: battery.symbol, level: battery.level, side: battery.side,
                                       isShown: hasAppeared, delay: reduceMotion ? 0 : 0.12 * Double(index + 1))
                }
            }
        }
        .accessibilityElement(children: .combine)
        .task {
            // One frame in, so the rings fill and the picture bounces as the banner grows.
            try? await Task.sleep(for: .milliseconds(60))
            hasAppeared = true
        }
    }

    /// Each battery, the earbuds marked L and R beside their rings.
    private var batteries: [(symbol: String, level: Int, side: String?)] {
        var items: [(String, Int, String?)] = []
        if let left = info.left { items.append((info.leftSymbol, left, "L")) }
        if let right = info.right { items.append((info.rightSymbol, right, "R")) }
        if let single = info.single, info.left == nil, info.right == nil { items.append((info.symbol, single, nil)) }
        if let chargingCase = info.chargingCase { items.append((info.caseSymbol, chargingCase, nil)) }
        return items
    }
}

/// One battery: the part's symbol in a ring filled to its charge, the percentage beside it.
private struct AirPodsBatteryItem: View {
    let symbol: String
    let level: Int
    /// "L" or "R", small before the percentage; nil for the case.
    let side: String?
    let isShown: Bool
    let delay: Double

    var body: some View {
        let level = min(max(level, 0), 100)
        let tint: Color = level <= 20 ? .red : .green
        VStack(spacing: 4) {
            ZStack {
                Circle().stroke(.white.opacity(0.16), lineWidth: 3.5)
                Circle()
                    .trim(from: 0, to: isShown ? CGFloat(level) / 100 : 0)
                    .stroke(tint, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(duration: 0.7, bounce: 0.1).delay(delay), value: isShown)
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 40, height: 40)

            // The side, small, to the left of the percentage: "L 80%".
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                if let side {
                    Text(side).font(.system(size: 8, weight: .bold))
                }
                Text("\(level)%").font(.caption.weight(.semibold).monospacedDigit())
            }
            .foregroundStyle(.secondary)
                .opacity(isShown ? 1 : 0)
                .animation(.easeOut(duration: 0.3).delay(delay), value: isShown)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(level) percent"))
    }
}
