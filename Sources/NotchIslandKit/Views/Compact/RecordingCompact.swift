import SwiftUI

/// The screen being recorded, in the pill: a faint red line round the notch, how long it has been
/// recording in the leading ear (small), a red dot in the trailing one. Static but for the time,
/// which the text counts itself (no timeline redraws the pill).
struct RecordingCompact: View {
    let split: NotchSplit
    let height: CGFloat
    let glyphSide: CGFloat

    @Environment(AppModel.self) private var model

    var body: some View {
        let layout = model.layout
        NotchSplitBand(split: split, height: height) {
            RecordingTime(since: model.recorder.startedAt)
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        } trailing: {
            Circle()
                .fill(RecordingStyle.red)
                .frame(width: glyphSide * 0.42, height: glyphSide * 0.42)
                .frame(width: glyphSide, height: glyphSide)
        }
        .overlay {
            RecordingOutline(bottomRadius: layout.bottomRadius(for: .compact(.recording)),
                             shoulderRadius: layout.shoulderRadius(for: .compact(.recording)),
                             opacity: RecordingStyle.compactOutlineOpacity)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Recording the screen"))
    }
}

/// The pointer over the notch while recording: how long it has been recording and Stop on
/// red-tinted Liquid Glass — the two as tall as each other, on one line (the red dot is the pill's;
/// here Stop is the red). A click anywhere else on it opens the panel.
struct RecordingCard: View {
    @Environment(AppModel.self) private var model

    /// The row's height: the time's and Stop's.
    static let rowHeight: CGFloat = 38

    var body: some View {
        let layout = model.layout
        let presentation = IslandPresentation.expanded(.recording)
        let split = NotchSplit(layout: layout, presentation: presentation, outerInset: Metrics.Compact.inset,
                               clearance: Metrics.Compact.notchClearance)
        VStack(spacing: 0) {
            Color.clear.frame(height: layout.notch.height)
            HStack(spacing: 10) {
                RecordingTime(since: model.recorder.startedAt)
                    .font(.system(size: 28, weight: .semibold, design: .rounded).monospacedDigit())
                    .lineLimit(1)
                    .frame(height: Self.rowHeight)
                Spacer(minLength: 8)
                Button {
                    model.recorder.stop()
                    model.haptics.play(.tick)
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .frame(height: Self.rowHeight)
                        .contentShape(.capsule)
                        .glassEffect(Glass.regular.tint(RecordingStyle.red.opacity(0.75)).interactive(), in: .capsule)
                }
                .buttonStyle(.plain)
                .help("Stop recording")
            }
            .padding(.horizontal, split.contentInset + 6)
            .frame(maxHeight: .infinity)
        }
        .contentShape(.rect)
        .onTapGesture { model.controller.openPanelWhileRecording() }
        .overlay {
            RecordingOutline(bottomRadius: layout.bottomRadius(for: presentation),
                             shoulderRadius: layout.shoulderRadius(for: presentation))
        }
    }
}

/// How long it has been recording ("1:23"), counted by the text itself; "0:00" before it starts.
struct RecordingTime: View {
    let since: Date?

    var body: some View {
        if let since {
            Text(timerInterval: since...Date.distantFuture, countsDown: false)
        } else {
            Text(verbatim: "0:00")
        }
    }
}

/// The faint red line round the island while recording: the island's own outline, its inner half
/// showing (the island clips the outer), the top edge along the screen left out.
struct RecordingOutline: View {
    let bottomRadius: CGFloat
    let shoulderRadius: CGFloat
    var opacity = RecordingStyle.outlineOpacity
    var color = RecordingStyle.red

    static let lineWidth: CGFloat = 4

    var body: some View {
        IslandShape(bottomRadius: bottomRadius, shoulderRadius: shoulderRadius)
            .stroke(color.opacity(opacity), lineWidth: Self.lineWidth)
            .mask {
                VStack(spacing: 0) {
                    Color.clear.frame(height: Self.lineWidth / 2)
                    Color.black
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

enum RecordingStyle {
    /// The system's recording red.
    static let red = Color(red: 1, green: 0.23, blue: 0.19)
    /// The line round the card: 40 % see-through.
    static let outlineOpacity = 0.6
    /// Round the pill, where it stays for the whole recording: 20 % more see-through (60 %).
    static let compactOutlineOpacity = 0.4
}
