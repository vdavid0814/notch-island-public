import Foundation
import Observation

/// Clear Liquid Glass in Light Mode: a bright wallpaper shows straight through the island, and
/// widgets on no background (or the faint white plate) read poorly over it. So, as the Mac goes
/// into Light Mode with Liquid Glass chosen — or Liquid Glass is chosen in Light Mode — every widget
/// on None or Plate gets the Colour background in black at 40 %, set as the user would set it in
/// Settings ▸ Widgets (`IslandWidget.background`): shown there, changed or turned off per widget.
///
/// What a widget had before is kept and given back once the Mac goes dark or another style is
/// chosen — unless the user changed the widget's background meanwhile: then theirs stays, and it is
/// not touched again (`optedOut`).
@MainActor final class LightGlassBackdrop {
    /// The black every widget is given, and its strength.
    static let color = IslandTheme.RGB(red: 0, green: 0, blue: 0)
    static let opacity = 0.4

    nonisolated static let key = "ni2.lightGlassBackdrop"

    /// A widget's background before it was set here.
    private struct Original: Codable, Equatable {
        var background: WidgetBackground
        var color: IslandTheme.RGB?
        var opacity: Double?
    }

    private struct State: Codable {
        /// The widgets given the black now, with what they had before.
        var applied: [UUID: Original] = [:]
        /// Widgets whose background the user changed after it was set here: left alone.
        var optedOut: Set<UUID> = []
    }

    private weak var model: AppModel?
    private let defaults: UserDefaults
    private var state: State
    private var isPending = false

    init(model: AppModel, defaults: UserDefaults = .standard) {
        self.model = model
        self.defaults = defaults
        state = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(State.self, from: $0) } ?? State()
    }

    /// Follows the Mac's appearance, the glass chosen and every board from now on.
    func start() {
        evaluate()
        track()
    }

    /// Whether widgets get the black now: Light Mode, Liquid Glass chosen.
    private var isActive: Bool {
        guard let model else { return false }
        return !SystemAppearance.shared.isDark && model.preferences.glassStyle == .liquidGlass
    }

    private func track() {
        guard let model else { return }
        withObservationTracking {
            _ = SystemAppearance.shared.isDark
            _ = model.preferences.glassStyle
            _ = model.preferences.header.orderedPages
            for store in boards(model) { _ = store.board }
        } onChange: { [weak self] in
            // Once the change is made, and once for a burst of them.
            DispatchQueue.main.async {
                guard let self, !self.isPending else { return }
                self.isPending = true
                DispatchQueue.main.async {
                    self.isPending = false
                    self.evaluate()
                    self.track()
                }
            }
        }
    }

    /// Every page's board.
    private func boards(_ model: AppModel) -> [WidgetStore] {
        model.preferences.header.orderedPages.filter(\.isBoard).map { model.boards.store(for: $0) }
    }

    private static func isBlack(_ widget: IslandWidget) -> Bool {
        widget.background == .tinted && widget.backgroundColor == color && widget.backgroundOpacity == opacity
    }

    private func evaluate() {
        // Settings' pictures switch the style for a moment: nothing of the user's is changed then.
        guard let model, !model.isPictureScene else { return }
        let stores = boards(model)
        var changed = false
        // A widget given the black and changed since by the user: theirs from now on.
        for store in stores {
            for widget in store.board.widgets + store.board.parked {
                let id = widget.id.rawValue
                if state.applied[id] != nil, !Self.isBlack(widget) {
                    state.applied[id] = nil
                    state.optedOut.insert(id)
                    changed = true
                }
            }
        }
        if isActive {
            for store in stores {
                for widget in store.board.widgets where widget.background != .tinted {
                    let id = widget.id.rawValue
                    guard state.applied[id] == nil, !state.optedOut.contains(id) else { continue }
                    state.applied[id] = Original(background: widget.background, color: widget.backgroundColor,
                                                 opacity: widget.backgroundOpacity)
                    store.updateOutsideHistory(widget.id) {
                        $0.background = .tinted
                        $0.backgroundColor = Self.color
                        $0.backgroundOpacity = Self.opacity
                    }
                    changed = true
                }
            }
        } else if !state.applied.isEmpty {
            for (id, original) in state.applied {
                let widgetID = WidgetID(rawValue: id)
                guard let store = model.boards.store(containing: widgetID) else { continue }
                store.updateOutsideHistory(widgetID) {
                    $0.background = original.background
                    $0.backgroundColor = original.color
                    $0.backgroundOpacity = original.opacity
                }
            }
            state.applied = [:]
            changed = true
        }
        // Widgets gone (deleted, their page removed) are forgotten.
        let present = Set(stores.flatMap { ($0.board.widgets + $0.board.parked).map(\.id.rawValue) })
        let before = (state.applied.count, state.optedOut.count)
        state.applied = state.applied.filter { present.contains($0.key) }
        state.optedOut = state.optedOut.intersection(present)
        if before != (state.applied.count, state.optedOut.count) { changed = true }
        if changed, let data = try? JSONEncoder().encode(state) { defaults.set(data, forKey: Self.key) }
    }
}
