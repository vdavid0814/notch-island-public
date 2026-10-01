import AppKit
import SwiftUI

// A widget's behaviour (`BehaviourStyle`): what a tap does, whether it shows or dims while it has
// nothing to do, and a haptic on its taps. Resolved once per body evaluation; nothing ticks.

extension IslandWidget {
    /// Whether the widget has something to do now: music loaded, a timer set, files on the shelf…
    /// A kind that always does (a clock, a switch) is always active.
    @MainActor func isActive(in model: AppModel) -> Bool {
        switch kind {
        case .nowPlaying: model.media.item != nil
        case .timer: model.timers.countdown != .idle
        case .stopwatch: model.timers.isStopwatchActive
        case .shelf: !model.shelf.items.isEmpty
        case .battery, .batteryTime, .batteryPower, .charger: model.power.state.isCharging || model.power.state.isOnBattery
        default:
            if let control = kind.systemControl, !control.isAction { model.controls.isOn(control) } else { true }
        }
    }
}

extension IslandWidgetKind {
    /// When it has nothing to do, in words ("no music is loaded"); nil for a kind that always has
    /// (a clock): Only Active and Dim Inactive do nothing there.
    var idleSituation: String? {
        switch self {
        case .nowPlaying: String(localized: "no music or video is loaded in a player")
        case .timer: String(localized: "no timer is set")
        case .stopwatch: String(localized: "the stopwatch is at zero")
        case .shelf: String(localized: "the shelf is empty")
        case .battery, .batteryTime, .batteryPower, .charger: String(localized: "the Mac is plugged in and fully charged")
        default:
            if let control = systemControl, !control.isAction { String(localized: "it is switched off") } else { nil }
        }
    }
}

/// The widget's behaviour on the island: its tap, its haptic, and its dimming while inactive (the
/// board leaves out one shown only while active — `WidgetBoardView`). In a picture (Settings'
/// gallery, the editor's canvas) nothing is performed.
struct WidgetBehaviourModifier: ViewModifier {
    let widget: IslandWidget

    @Environment(AppModel.self) private var model
    @Environment(\.isWidgetPreview) private var isPreview
    @Environment(\.widgetRenderMode) private var renderMode

    func body(content: Content) -> some View {
        let behaviour = widget.style.behaviour
        let tap = behaviour.tap ?? .standard
        let dims = behaviour.dimsWhenInactive == true && !widget.isActive(in: model)
        Group {
            switch tap {
            case .standard:
                if behaviour.haptic == true, !isPreview, renderMode == .live {
                    content.simultaneousGesture(TapGesture().onEnded { model.haptics.play(.tick) })
                } else {
                    content
                }
            case .none:
                content.allowsHitTesting(false)
            default:
                // Its own action: the whole widget is one button (what is inside answers nothing).
                content
                    .allowsHitTesting(false)
                    .overlay {
                        Color.clear
                            .contentShape(.rect(cornerRadius: WidgetMetrics.cornerRadius))
                            .onTapGesture {
                                guard !isPreview, renderMode == .live else { return }
                                if behaviour.haptic == true { model.haptics.play(.tick) }
                                perform(tap)
                            }
                            .accessibilityAddTraits(.isButton)
                            .accessibilityLabel(Text(widget.kind.title))
                    }
            }
        }
        .opacity(dims ? 0.45 : 1)
        .animation(Motion.content, value: dims)
    }

    private func perform(_ tap: TapAction) {
        switch tap {
        case .app(let path):
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: NSWorkspace.OpenConfiguration())
        case .url(let link):
            if let url = URL(string: link) { NSWorkspace.shared.open(url) }
        case .shortcut(let name):
            AssistantActions.runShortcut(named: name)
        case .page(let name):
            if let page = ExpandedPage(rawValue: name), model.availablePages.contains(page) { model.island.page = page }
        case .standard, .none:
            break
        }
    }
}

extension IslandWidget {
    /// Left off the island's board while it has nothing to do (`BehaviourStyle.showsOnlyWhenActive`).
    @MainActor func isHiddenOnIsland(in model: AppModel) -> Bool {
        style.behaviour.showsOnlyWhenActive == true && !isActive(in: model)
    }
}
