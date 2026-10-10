import AppKit
import SwiftUI

/// A new version is out, in the pill: the recording's pill in green — "update / available" on two
/// left-aligned lines in the leading ear (as tall as the notch), a green dot fading slowly in and
/// out in the trailing one, a faint green line round the notch. The fade is the render server's
/// (`PulsingDot`): SwiftUI redraws nothing until the notice goes.
struct UpdateCompact: View {
    let split: NotchSplit
    let height: CGFloat
    let glyphSide: CGFloat

    @Environment(AppModel.self) private var model

    var body: some View {
        let layout = model.layout
        NotchSplitBand(split: split, height: height) {
            VStack(alignment: .leading, spacing: -1) {
                Text(verbatim: "update")
                Text(verbatim: "available")
            }
            .font(.system(size: UpdateStyle.compactTextSize(notchHeight: height), weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            // A little way in from the pill's end (asked for).
            .padding(.leading, UpdateStyle.compactTextInset)
        } trailing: {
            PulsingDot(color: NSColor(UpdateStyle.green), diameter: glyphSide * 0.42)
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

/// The pointer over the update pill: the new version, ✕, and Update on green-tinted Liquid Glass at
/// the right end (where the recording card has Stop), on one row. Update installs in place (About shows
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
                if let progress = Self.progress(updater.state) {
                    Text(progress)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Button {
                        model.haptics.play(.tick)
                        switch updater.state {
                        case .differentSigner, .manual:
                            // Signed differently, or to be installed by hand: About explains it.
                            model.controller.openSettings(pane: .about)
                        default:
                            updater.installFromNotice()
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

    /// Two lines filling the notch's height: about 10 pt on a 32 pt notch, at most 11.
    static func compactTextSize(notchHeight: CGFloat) -> CGFloat {
        min(11, max(8, (notchHeight - 6) / 2.6))
    }

    /// The pill's two lines start this far in from where the ear's content does.
    static let compactTextInset: CGFloat = 4
}

/// A dot fading slowly out and back in, for as long as it is on screen: a layer animation the
/// render server plays at a low frame rate, so the app does no work for it (a SwiftUI animation
/// would redraw the pill every frame, for hours).
struct PulsingDot: NSViewRepresentable {
    let color: NSColor
    let diameter: CGFloat

    /// One fade out and back in.
    static let period: CFTimeInterval = 2.4
    static let dimmest: Float = 0.2
    static let key = "pulse"

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        let dot = CALayer()
        view.layer?.addSublayer(dot)
        context.coordinator.dot = dot
        update(dot)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard let dot = context.coordinator.dot else { return }
        update(dot)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator { var dot: CALayer? }

    private func update(_ dot: CALayer) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dot.frame = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        dot.cornerRadius = diameter / 2
        dot.backgroundColor = color.cgColor
        CATransaction.commit()
        guard dot.animation(forKey: Self.key) == nil else { return }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = Self.dimmest
        fade.duration = Self.period / 2
        fade.autoreverses = true
        fade.repeatCount = .infinity
        fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        // A slow fade reads as smooth at 20 frames a second.
        fade.preferredFrameRateRange = CAFrameRateRange(minimum: 10, maximum: 30, preferred: 20)
        fade.isRemovedOnCompletion = false
        dot.add(fade, forKey: Self.key)
    }
}
