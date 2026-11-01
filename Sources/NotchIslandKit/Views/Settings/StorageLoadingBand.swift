import SwiftUI

/// About's Storage measuring, on the notch (asked for): "Loading" beside it on the right, its dots
/// coming one by one and going one by one, and a green line round the notch and the word that fills
/// from left to right as the places are measured. Drawn only while Storage measures: nothing at rest.
struct StorageLoadingBand: View {
    @Environment(AppModel.self) private var model

    /// The word and its three dots, at the band's size.
    nonisolated static let labelWidth: CGFloat = 66
    /// From the notch's side to the word.
    nonisolated static let labelGap: CGFloat = 10

    var body: some View {
        let notch = model.layout.notch
        ZStack {
            if let progress = model.storageLoading {
                GeometryReader { proxy in
                    let trace = NotchTrace(notch: notch, cornerRadius: model.layout.bottomRadius(for: .idle))
                    ZStack(alignment: .topLeading) {
                        trace
                            .trim(from: 0, to: progress)
                            .stroke(.green, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                            .shadow(color: .green.opacity(0.6), radius: 3)
                            .animation(.easeOut(duration: 0.45), value: progress)
                        LoadingLabel()
                            .frame(width: Self.labelWidth, alignment: .leading)
                            .position(x: proxy.size.width / 2 + notch.width / 2 + Self.labelGap + Self.labelWidth / 2,
                                      y: notch.height / 2)
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: model.storageLoading == nil)
        .allowsHitTesting(false)
    }
}

/// Round the notch and the word beside it, a few points out: down the notch's left side, along under
/// both, up past the word's end. Its corners concentric with the notch's.
nonisolated private struct NotchTrace: Shape {
    let notch: CGSize
    let cornerRadius: CGFloat
    /// From the notch to the line.
    var gap: CGFloat = 3

    func path(in rect: CGRect) -> Path {
        let left = rect.midX - notch.width / 2 - gap
        let right = rect.midX + notch.width / 2 + StorageLoadingBand.labelGap + StorageLoadingBand.labelWidth + 4 + gap
        let bottom = notch.height + gap
        let radius = cornerRadius + gap
        var path = Path()
        path.move(to: CGPoint(x: left, y: 0))
        path.addArc(tangent1End: CGPoint(x: left, y: bottom), tangent2End: CGPoint(x: right, y: bottom), radius: radius)
        path.addArc(tangent1End: CGPoint(x: right, y: bottom), tangent2End: CGPoint(x: right, y: 0), radius: radius)
        path.addLine(to: CGPoint(x: right, y: 0))
        return path
    }
}

/// "Loading" and its dots: one, two, three, then two, one, none, and again. Each dot comes and
/// goes in a step, as asked: three changes a second for the window server to draw, where a fade
/// between them redrew the band at every frame for the whole measuring.
private struct LoadingLabel: View {
    private static let step = 0.35
    private static let dots = [0, 1, 2, 3, 2, 1]

    var body: some View {
        TimelineView(.periodic(from: .now, by: Self.step)) { context in
            let shown = Self.dots[Int(context.date.timeIntervalSinceReferenceDate / Self.step) % Self.dots.count]
            HStack(spacing: 0) {
                Text("Loading")
                ForEach(0..<3, id: \.self) { dot in
                    Text(verbatim: ".").opacity(dot < shown ? 1 : 0)
                }
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.green)
        }
    }
}
