import SwiftUI

/// A new version is out, in the pill: the recording's pill in green — "update available" in the
/// leading ear, a green dot in the trailing one, a faint green line round the notch. Static: it
/// redraws nothing until it goes.
struct UpdateCompact: View {
    let split: NotchSplit
    let height: CGFloat
    let glyphSide: CGFloat

    @Environment(AppModel.self) private var model

    var body: some View {
        let layout = model.layout
        NotchSplitBand(split: split, height: height) {
            Text(verbatim: "update available")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        } trailing: {
            Circle()
                .fill(UpdateStyle.green)
                .frame(width: glyphSide * 0.42, height: glyphSide * 0.42)
                .frame(width: glyphSide, height: glyphSide)
        }
        .overlay {
            RecordingOutline(bottomRadius: layout.bottomRadius(for: .compact(.update)),
                             shoulderRadius: layout.shoulderRadius(for: .compact(.update)),
                             opacity: RecordingStyle.compactOutlineOpacity, color: UpdateStyle.green)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("An update is available"))
    }
}

/// The pointer over the update pill: the new version, Update on green-tinted Liquid Glass and ✕,
/// on one row as the recording card has its time and Stop. Update installs in place (About shows
/// the same); ✕ closes the notice for this version. While it installs, how far it got instead of
/// the buttons. A click anywhere else on it opens the panel.
struct UpdateCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let layout = model.layout
        let presentation = IslandPresentation.expanded(.update)
        let split = NotchSplit(layout: layout, presentation: presentation, outerInset: Metrics.Compact.inset,
                               clearance: Metrics.Compact.notchClearance)
        let updater = model.updater
        VStack(spacing: 0) {
            Color.clear.frame(height: layout.notch.height)
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Update available")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                    if let version = updater.notice?.version {
                        Text("NotchIsland \(version)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 8)
                if let progress = Self.progress(updater.state) {
                    Text(progress)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Button {
                        model.haptics.play(.tick)
                        if case .available = updater.state {
                            updater.installFromNotice()
                        } else {
                            // Signed differently, or to be installed by hand: About explains it.
                            model.controller.openSettings(pane: .about)
                        }
                    } label: {
                        Text("Update")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .frame(height: RecordingCard.rowHeight)
                            .contentShape(.capsule)
                            .glassEffect(Glass.regular.tint(UpdateStyle.green.opacity(0.75)).interactive(), in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .help("Install the new version")
                }
                Button {
                    model.haptics.play(.tick)
                    updater.dismissNotice()
                    model.controller.updateNoticeEnded()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: RecordingCard.rowHeight, height: RecordingCard.rowHeight)
                        .contentShape(.circle)
                        .glassEffect(Glass.regular.interactive(), in: .circle)
                }
                .buttonStyle(.plain)
                .help("Not this version")
                .accessibilityLabel(Text("Close"))
            }
            .padding(.horizontal, split.contentInset + 6)
            .frame(maxHeight: .infinity)
        }
        .contentShape(.rect)
        .onTapGesture { model.controller.openPanelWhileRecording() }
        .overlay {
            RecordingOutline(bottomRadius: layout.bottomRadius(for: presentation),
                             shoulderRadius: layout.shoulderRadius(for: presentation), color: UpdateStyle.green)
        }
    }

    /// While it installs: how far it got; nil when the buttons show.
    static func progress(_ state: AppUpdater.State) -> String? {
        switch state {
        case .downloading(_, let progress?): String(localized: "Downloading \(Int((progress * 100).rounded())) %")
        case .downloading: String(localized: "Downloading…")
        case .installing: String(localized: "Installing…")
        case .relaunching: String(localized: "Restarting…")
        default: nil
        }
    }
}

enum UpdateStyle {
    /// The system's green.
    static let green = Color(red: 0.2, green: 0.78, blue: 0.35)
}
