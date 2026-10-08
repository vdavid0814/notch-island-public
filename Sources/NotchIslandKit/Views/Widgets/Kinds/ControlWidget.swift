import SwiftUI

/// One of Control Center's controls (Wi-Fi first) or Siri as a widget:
///
/// - **Button** (one cell, or no label on): the widget itself is the round button (its background
///   is the circle), the glyph coloured while on.
/// - **Tile** (room for a label): the button with the name and the state beside it (wide) or under
///   it (two rows tall), like Control Center's larger modules.
///
/// A switch shows its state; an action (AirDrop, Calculator, Lock Screen, Siri…) opens or does
/// something and has none: its glyph is always in colour, its button always the quiet circle.
struct ControlWidget: View {
    let control: WidgetControl
    let widget: IslandWidget
    let size: CGSize

    @Environment(AppModel.self) private var model
    @Environment(\.isWidgetPreview) private var isPreview

    /// From this height (two rows, even at the smallest island size) the name goes under the button.
    static let tallTileHeight: CGFloat = 50

    private var isTall: Bool { size.height >= Self.tallTileHeight }

    private var showsTile: Bool {
        let hasLabel = widget.shows(.controlName) || widget.shows(.controlStatus)
        return hasLabel && Self.hasTileRoom(widget, inner: size)
    }

    /// On: a switch that is on (in a picture, every switch). An action never is.
    static func isOn(_ control: WidgetControl, model: AppModel, picture: Bool) -> Bool {
        // A picture shows the recording as it starts: off.
        if control == .screenRecording { return !picture && model.recorder.isRecording }
        guard !control.isAction, let system = control.systemControl else { return false }
        return picture || model.controls.isOn(system)
    }

    /// Room for the name and the state beside (or under) the button.
    static func hasTileRoom(_ widget: IslandWidget, inner: CGSize) -> Bool {
        !WidgetMetrics.isRound(widget) && (inner.height >= tallTileHeight || inner.width >= inner.height * 1.6)
    }

    /// The name and the state only where there is room for the tile.
    static func hasRoom(for element: ElementID, in widget: IslandWidget, inner: CGSize) -> Bool {
        element == .controlName || element == .controlStatus ? hasTileRoom(widget, inner: inner) : true
    }

    /// The round button's diameter in the tile.
    static func diameter(inner: CGSize) -> CGFloat {
        if inner.height >= tallTileHeight, inner.width < inner.height * 1.6 {
            return min(inner.width * 0.58, inner.height * 0.58, 56).rounded()
        }
        // Wide and two rows tall: larger, so the even gap round it stays close to the corner.
        if inner.height >= tallTileHeight { return min(inner.height * 0.8, inner.width * 0.36, 68).rounded() }
        // One row: as tall as the tile's inside (concentric with its round end).
        return min(inner.height, max(24, inner.width * 0.42), 48).rounded()
    }

    /// Beside its label (wide), the button as far in from the widget's side as from its top and
    /// bottom: it sits in the corner's curve, not against the side.
    static func tileInset(inner: CGSize) -> CGFloat {
        max(0, (inner.height - diameter(inner: inner)) / 2).rounded()
    }

    /// The symbol's size: in the tile's button, or alone (the widget is the button).
    static func buttonPoints(_ widget: IslandWidget, inner: CGSize) -> CGFloat {
        let tile = (widget.shows(.controlName) || widget.shows(.controlStatus)) && hasTileRoom(widget, inner: inner)
        return tile ? diameter(inner: inner) * 0.42 : min(inner.width, inner.height, 56) * 0.46
    }

    /// How the tile's label is set: the name over the state, the name alone, or the name over two
    /// lines (broken between words, the state left out) — the first that keeps the name within a
    /// step of the largest any of them allows, measured against the room: a name is never cut
    /// ("Lock Scr…"), as Control Center never cuts one.
    struct LabelLayout: Equatable {
        enum Arrangement: Equatable { case nameAndStatus, line, twoLines(String, String) }

        var arrangement: Arrangement
        var name: CGFloat
        var status: CGFloat
    }

    /// The smallest a name is set before a shorter arrangement is taken.
    static let minimumNamePoints: CGFloat = 8
    /// A line's height, as a share of its type size.
    static let lineHeight: CGFloat = 1.2

    /// A picture's state where the live one is this Mac's own (where the sound plays): a sample,
    /// so a picture is the same on every Mac and with any output.
    static func status(_ control: WidgetControl, on: Bool, picture: Bool) -> String {
        picture && control == .system(.soundOutput) ? String(localized: "Speakers") : control.status(on: on)
    }

    static func labelLayout(_ control: WidgetControl, widget: IslandWidget, inner: CGSize, picture: Bool = false) -> LabelLayout {
        let longestStatus = picture && control == .system(.soundOutput) ? status(control, on: true, picture: true) : control.longestStatus
        let tall = inner.height >= tallTileHeight && inner.width < inner.height * 1.6
        let diameter = diameter(inner: inner)
        let width = max(1, tall ? inner.width : inner.width - tileInset(inner: inner) - diameter - max(4, diameter * 0.2)) - 2
        let height = max(1, tall ? inner.height - diameter - Metrics.Spacing.xSmall : inner.height)
        let showsName = widget.shows(.controlName)
        let showsStatus = widget.shows(.controlStatus) && widget.kind.spec.element(.controlStatus) != nil
        let room = tall ? inner.height - diameter : inner.height
        let design = WidgetMetrics.points(room, ratio: showsName && showsStatus ? 0.34 : 0.4, min: 10, max: 15)
        // The largest size at which `text` is as wide as the room, at most `upper`.
        func fitting(_ text: String, weight: NSFont.Weight, upper: CGFloat) -> CGFloat {
            let one = (text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 100, weight: weight)]).width / 100
            return one > 0 ? min(upper, (width / one * 4).rounded(.down) / 4) : upper
        }
        let status = min((design * 0.85).rounded(), fitting(longestStatus, weight: .regular, upper: height / lineHeight))
        guard showsName else { return LabelLayout(arrangement: .line, name: 0, status: status) }
        var candidates: [LabelLayout] = []
        if showsStatus {
            let share = design / (design + (design * 0.85).rounded())
            let name = fitting(control.title, weight: .semibold, upper: min(design, height * share / lineHeight))
            let state = min((design * 0.85).rounded(), fitting(longestStatus, weight: .regular,
                                                               upper: height * (1 - share) / lineHeight))
            candidates.append(LabelLayout(arrangement: .nameAndStatus, name: name, status: state))
        }
        candidates.append(LabelLayout(arrangement: .line, name: fitting(control.title, weight: .semibold, upper: min(design, height / lineHeight)),
                                      status: status))
        if let (first, second) = twoLines(control.title) {
            let longer = [first, second].max { $0.count < $1.count } ?? first
            let name = min(fitting(first, weight: .semibold, upper: design), fitting(second, weight: .semibold, upper: design),
                           fitting(longer, weight: .semibold, upper: height / (2 * lineHeight)))
            candidates.append(LabelLayout(arrangement: .twoLines(first, second), name: name, status: status))
        }
        let best = candidates.map(\.name).max() ?? 0
        let pick = candidates.first { $0.name >= best * 0.88 && $0.name >= minimumNamePoints } ?? candidates.max { $0.name < $1.name }!
        return pick
    }

    /// A name of more than one word over two lines, broken where the two are most alike in length.
    static func twoLines(_ title: String) -> (String, String)? {
        let words = title.split(separator: " ").map(String.init)
        guard words.count >= 2 else { return nil }
        let splits = (1..<words.count).map { (words[..<$0].joined(separator: " "), words[$0...].joined(separator: " ")) }
        return splits.min { max($0.0.count, $0.1.count) < max($1.0.count, $1.1.count) }
    }

    var body: some View {
        let on = Self.isOn(control, model: model, picture: isPreview)
        let system = control.systemControl
        let failed = system != nil && model.controls.failed == system
        Button {
            guard !isPreview else { return }
            perform()
            model.haptics.play(.tick)
        } label: {
            Group {
                if showsTile {
                    tile(on: on)
                } else if widget.buttonLook(of: .controlButton) != .plain {
                    // Restyled in Customize: as Now Playing's buttons are.
                    WidgetButtonLabel(look: widget.buttonLook(of: .controlButton), symbol: control.symbol(on: on),
                                      points: Self.buttonPoints(widget, inner: size))
                        .movableElement(.controlButton, of: widget)
                        .frame(width: size.width, height: size.height)
                } else {
                    // One circle: the widget's own background is the button, so no second circle
                    // is drawn inside it. On (or an action) is the glyph in colour, off a quiet glyph.
                    coloured(glyph(on: on, points: min(size.width, size.height, 56) * 0.46), loneGlyphStyle(on: on))
                        .movableElement(.controlButton, of: widget)
                        .frame(width: size.width, height: size.height)
                }
            }
            // A failed switch shakes.
            .offset(x: failed ? 3 : 0)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        // Recording is red, as the notch shows it.
        .tint(control == .screenRecording ? RecordingStyle.red : nil)
        .animation(Motion.content, value: on)
        .animation(.spring(duration: 0.12, bounce: 0.6).repeatCount(3, autoreverses: true), value: failed)
        .help(control.title)
        .accessibilityLabel(control.title)
        .accessibilityValue(control.isAction ? "" : control.status(on: on))
        .accessibilityAddTraits(control.isAction ? .isButton : [.isButton, .isToggle])
        .whileShown {
            if !isPreview, let system { withoutAnimation { model.controls.startObserving(system) } }
        } stop: {
            if !isPreview, let system { model.controls.stopObserving(system) }
        }
    }

    /// The switch, or the action: Siri opens in the notch.
    private func perform() {
        switch control {
        case .system(let system): model.controls.toggle(system)
        case .assistant: model.perform(.assistant)
        case .screenRecording: model.perform(.toggleRecording)
        }
    }

    /// The glyph in `style` — Siri's in its own gradient (as the gallery shows it), as the gradient
    /// masked by the glyph: set as
    /// the glyph's own colour, the gradient was drawn at the screen's pixels and came out blocky
    /// where the editor zooms it.
    @ViewBuilder private func coloured(_ glyph: some View, _ style: AnyShapeStyle) -> some View {
        if control == .assistant {
            glyph.hidden().overlay {
                LinearGradient(colors: WidgetSpecs.siri.map(\.color), startPoint: .topLeading, endPoint: .bottomTrailing)
                    .mask { glyph }
            }
        } else {
            glyph.foregroundStyle(style)
        }
    }

    /// The lone glyph's colour: on (or an action) on a coloured background white (the colour
    /// already says "on"), elsewhere the tint; off, secondary.
    private func loneGlyphStyle(on: Bool) -> AnyShapeStyle {
        guard on || control.isAction else { return AnyShapeStyle(.secondary) }
        return widget.background == .tinted ? AnyShapeStyle(.white) : AnyShapeStyle(.tint)
    }

    /// The system's symbol, or a logo it has none for (`DrawnSymbol`).
    @ViewBuilder private func glyph(on: Bool, points: CGFloat) -> some View {
        let symbol = control.symbol(on: on)
        if DrawnSymbol.isOwn(symbol), let drawn = DrawnSymbol(symbol: symbol) {
            drawn.view(points: points, edges: .rounded, style: AnyShapeStyle(.foreground), outlined: false)
        } else {
            Image(systemName: symbol)
                .font(.system(size: points, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
        }
    }

    /// Control Center's round button: the glyph on a filled circle while on, on a faint one while
    /// off or for an action — or as Customize styled it.
    @ViewBuilder private func button(on: Bool, diameter: CGFloat) -> some View {
        let look = widget.buttonLook(of: .controlButton)
        Group {
            if look == .plain {
                coloured(glyph(on: on, points: diameter * 0.42), on ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                    .frame(width: diameter, height: diameter)
                    .background(on ? AnyShapeStyle(.tint) : AnyShapeStyle(.white.opacity(0.14)), in: .circle)
            } else {
                WidgetButtonLabel(look: look, symbol: control.symbol(on: on), points: diameter * 0.42)
                    .frame(width: diameter, height: diameter)
            }
        }
        .movableElement(.controlButton, of: widget)
    }

    /// Wide: the button beside the label. Tall: the button at the top, the label at the bottom.
    @ViewBuilder private func tile(on: Bool) -> some View {
        if isTall, size.width < size.height * 1.6 {
            let diameter = Self.diameter(inner: size)
            VStack(alignment: .leading, spacing: Metrics.Spacing.xSmall) {
                button(on: on, diameter: diameter)
                Spacer(minLength: 0)
                label(on: on)
            }
            .frame(width: size.width, height: size.height, alignment: .leading)
        } else {
            let diameter = Self.diameter(inner: size)
            HStack(spacing: max(4, diameter * 0.2)) {
                button(on: on, diameter: diameter)
                label(on: on)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, Self.tileInset(inner: size))
            .frame(width: size.width, height: size.height, alignment: .leading)
        }
    }

    /// The name and the state as `labelLayout` sets them, each on its lines; each can be moved and
    /// restyled in Customize (`WidgetLabel`).
    private func label(on: Bool) -> some View {
        let layout = Self.labelLayout(control, widget: widget, inner: size, picture: isPreview)
        let status = Self.status(control, on: on, picture: isPreview)
        let showsStatus = widget.shows(.controlStatus) && widget.kind.spec.element(.controlStatus) != nil
            && (layout.arrangement == .nameAndStatus || !widget.shows(.controlName))
        return VStack(alignment: .leading, spacing: 0) {
            if widget.shows(.controlName) {
                WidgetLabel(id: .controlName, text: control.title, widget: widget, size: layout.name, weight: .semibold,
                            isSecondary: false) {
                    if case .twoLines(let first, let second) = layout.arrangement {
                        Text(verbatim: first + "\n" + second).font(.system(size: layout.name, weight: .semibold))
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                    } else {
                        Text(control.title).font(.system(size: layout.name, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .movableElement(.controlName, of: widget)
            }
            if showsStatus {
                WidgetLabel(id: .controlStatus, text: status, widget: widget, size: layout.status, weight: .regular,
                            isSecondary: true) {
                    Text(status)
                        .font(.system(size: layout.status))
                        .foregroundStyle(.secondary)
                        .contentTransition(.opacity)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .movableElement(.controlStatus, of: widget)
            }
        }
    }
}
