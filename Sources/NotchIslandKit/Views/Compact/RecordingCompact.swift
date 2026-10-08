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
                             shoulderRadius: layout.shoulderRadius(for: .compact(.recording)))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Recording the screen"))
    }
}

/// The pointer over the notch while recording: how long it has been recording, beside a red dot,
/// and a red glass Stop. A click anywhere else on it opens the panel.
struct RecordingCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let layout = model.layout
        let presentation = IslandPresentation.expanded(.recording)
        let split = NotchSplit(layout: layout, presentation: presentation, outerInset: Metrics.Compact.inset,
                               clearance: Metrics.Compact.notchClearance)
        VStack(spacing: 0) {
            Color.clear.frame(height: layout.notch.height)
            HStack(spacing: 10) {
                Circle()
                    .fill(RecordingStyle.red)
                    .frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 0) {
                    RecordingTime(since: model.recorder.startedAt)
                        .font(.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit())
                    Text("Recording")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button {
                    model.recorder.stop()
                    model.haptics.play(.tick)
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .islandButton(.capsule, prominent: true)
                .tint(RecordingStyle.red)
                .controlSize(.large)
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

    static let lineWidth: CGFloat = 4

    var body: some View {
        IslandShape(bottomRadius: bottomRadius, shoulderRadius: shoulderRadius)
            .stroke(RecordingStyle.red.opacity(RecordingStyle.outlineOpacity), lineWidth: Self.lineWidth)
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
    /// The line round the notch: 40 % see-through.
    static let outlineOpacity = 0.6
}
