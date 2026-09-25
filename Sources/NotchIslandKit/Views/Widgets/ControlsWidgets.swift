import AppKit
import SwiftUI

// MARK: - Control

/// One Control Center control as its own widget, in one of two layouts:
///
/// - **Button**: the widget itself is the round button (its background is the circle), the glyph
///   coloured while on.
/// - **Tile**: the button with the control's name and state, like Control Center's wide and tall
///   modules. The label always fits: it takes one line with the state under it, the name alone,
///   or the name over two lines, whichever fits the room — never a truncated word.
///
/// Automatic is the tile when the widget is wider (or taller) than a button and has a label on.
struct ControlWidget: View {
    let control: SystemControl
    let widget: IslandWidget
    let size: CGSize

    @Environment(AppModel.self) private var model
    @Environment(\.isWidgetPreview) private var isPreview

    private var hasLabel: Bool { widget.shows(.controlName) || widget.shows(.controlStatus) }

    /// Wide enough for the name beside the button, or tall enough (two rows) for it under the
    /// button, like Control Center's larger modules. A one-cell widget is always the one-circle
    /// button — a tile there only put a circle inside the widget's circle.
    /// From this height (two rows, even at the smallest island size) the name goes under the button.
    static let tallTileHeight: CGFloat = 50
    /// The smallest a control's name is drawn before it is left out.
    static let minimumLabelSize: CGFloat = 7.5

    private var hasRoomForLabel: Bool {
        guard !WidgetMetrics.isRound(widget) else { return false }
        if size.height >= Self.tallTileHeight { return true }
        guard size.width >= size.height * 1.6 else { return false }
        // Beside the button: only when at least the smallest type of the name (or its longer word,
        // over two lines) fits there — otherwise the button alone, centred, beats a lone glyph at
        // the edge of an empty tile.
        let diameter = min(size.height, max(20, size.width * 0.32), 44)
        let room = size.width - diameter - max(4, diameter * 0.2)
        let font = NSFont.systemFont(ofSize: Self.minimumLabelSize, weight: .semibold)
        let longest = control.title.split(separator: " ").count == 2 && size.height >= 7.5 * 2.3
            ? control.title.split(separator: " ").map(String.init).max { $0.count < $1.count } ?? control.title
            : control.title
        return (longest as NSString).size(withAttributes: [.font: font]).width <= room
    }

    private var layout: WidgetLayout {
        switch widget.layout {
        case .automatic, .tile:
            hasLabel && hasRoomForLabel ? .tile : .button
        default: widget.layout
        }
    }

    var body: some View {
        let controls = model.controls
        let on = isPreview ? !control.isAction : !control.isAction && controls.isOn(control)
        Button {
            guard !isPreview else { return }
            controls.toggle(control)
            model.haptics.play(.tick)
        } label: {
            Group {
                if layout == .tile {
                    tile(on: on)
                } else {
                    // One circle: the widget's own background (plate, colour or none, at its
                    // strength) is the button, so no second circle is drawn inside it. On shows as
                    // the glyph in colour, off as a quiet glyph.
                    ControlGlyph(control: control, on: on || control.isAction,
                                 size: min(size.width, size.height, 56) * 0.46)
                        .foregroundStyle(buttonGlyphStyle(on: on))
                        .frame(width: size.width, height: size.height)
                }
            }
            .offset(x: controls.failed == control ? 3 : 0)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .animation(Motion.content, value: on)
        .animation(.spring(duration: 0.12, bounce: 0.6).repeatCount(3, autoreverses: true), value: controls.failed == control)
        .help(control.title)
        .accessibilityLabel(control.title)
        .accessibilityValue(control.isAction ? "" : control.status(on: on))
        .accessibilityAddTraits(control.isAction ? .isButton : [.isButton, .isToggle])
        .onAppear { if !isPreview { withoutAnimation { controls.startObserving(control) } } }
        .onDisappear { if !isPreview { controls.stopObserving(control) } }
    }

    /// The lone glyph's colour: on a coloured background white (the colour already says "on"),
    /// elsewhere the control's tint; off, secondary.
    private func buttonGlyphStyle(on: Bool) -> AnyShapeStyle {
        guard on || control.isAction else { return AnyShapeStyle(.secondary) }
        return widget.background == .tinted ? AnyShapeStyle(.white) : AnyShapeStyle(.tint)
    }

    /// Wide: the button beside the label. Tall: the button at the top, the label at the bottom.
    @ViewBuilder private func tile(on: Bool) -> some View {
        let tall = size.width < size.height * 1.6 && size.height >= Self.tallTileHeight
        if tall {
            // Button at the top, the name under it (Control Center's 2 × 2).
            let diameter = min(size.width * 0.5, size.height * 0.5, 44)
            VStack(alignment: .leading, spacing: Metrics.Spacing.xSmall) {
                ControlButtonFace(control: control, on: on, diameter: diameter)
                Spacer(minLength: 0)
                label(on: on, room: size.width, width: size.width, lineRoom: size.height - diameter - Metrics.Spacing.xSmall)
            }
            .frame(width: size.width, height: size.height, alignment: .leading)
        } else {
            let diameter = min(size.height, max(20, size.width * 0.32), 44)
            let gap = max(4, diameter * 0.2)
            HStack(spacing: gap) {
                ControlButtonFace(control: control, on: on, diameter: diameter)
                label(on: on, room: size.height * 1.4, width: size.width - diameter - gap, lineRoom: size.height)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: size.width, height: size.height, alignment: .leading)
        }
    }

    /// The name and the state, in the first arrangement that holds the name at (about) its best
    /// size: both on two lines, the name alone on one, or the name over two lines (broken only
    /// between words) — measured against the room, never a name cut to "Blueto…". The sizes are
    /// the element sizes' (`WidgetType.fitted`): when the room caps the name, Large takes it all and
    /// Medium and Small a step and two below, so the three always differ.
    @ViewBuilder private func label(on: Bool, room: CGFloat, width: CGFloat, lineRoom: CGFloat) -> some View {
        let layout = ControlLabelLayout.choose(
            title: control.title, status: control.status(on: on), longestStatus: control.longestStatus,
            showsName: widget.shows(.controlName), showsStatus: widget.shows(.controlStatus),
            nameDesign: WidgetType.points(room, ratio: 0.26, min: 10, max: 15),
            statusDesign: WidgetType.points(room, ratio: 0.22, min: 9, max: 13),
            width: width - 2, height: lineRoom,
            nameSize: widget.size(of: .controlName), statusSize: widget.size(of: .controlStatus),
            minimum: Self.minimumLabelSize)
        switch layout.arrangement {
        case .nameAndStatus:
            VStack(alignment: .leading, spacing: 0) {
                nameText(layout.name).lineLimit(1)
                Text(control.status(on: on)).font(.system(size: layout.status)).foregroundStyle(.secondary)
                    .lineLimit(1).contentTransition(.opacity)
            }
            .minimumScaleFactor(0.85)
        case .line:
            line(on: on, size: layout.name, statusSize: layout.status)
        case .twoWords:
            twoWords(layout.name)
        case .none:
            Color.clear.frame(width: 0, height: 0)
        }
    }

    private func nameText(_ size: CGFloat) -> Text {
        Text(control.title).font(.system(size: size, weight: .semibold))
    }

    /// The name on one line (or the state alone when the name is off).
    private func line(on: Bool, size: CGFloat, statusSize: CGFloat) -> some View {
        Group {
            if widget.shows(.controlName) {
                nameText(size)
            } else {
                Text(control.status(on: on)).font(.system(size: statusSize)).foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.85)
    }

    private func twoWords(_ size: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: -1) {
            ForEach(control.title.split(separator: " ").map(String.init), id: \.self) { word in
                Text(word).font(.system(size: size, weight: .semibold)).lineLimit(1)
            }
        }
        .minimumScaleFactor(0.85)
    }
}

/// How a control tile's label is laid out and how large (see `ControlWidget.label`). Pure, so the
/// sizes can be tested without drawing.
nonisolated struct ControlLabelLayout: Equatable, Sendable {
    nonisolated enum Arrangement: Sendable { case nameAndStatus, line, twoWords, none }

    var arrangement: Arrangement
    var name: CGFloat
    var status: CGFloat

    static func choose(title: String, status: String, longestStatus: String, showsName: Bool, showsStatus: Bool,
                       nameDesign: CGFloat, statusDesign: CGFloat, width: CGFloat, height: CGFloat,
                       nameSize: ElementSize, statusSize: ElementSize, minimum: CGFloat) -> ControlLabelLayout {
        guard showsName || showsStatus, width > 0, height > 0 else { return ControlLabelLayout(arrangement: .none, name: 0, status: 0) }
        func nameFit(_ text: String, lines: CGFloat, height: CGFloat) -> CGFloat {
            min(WidgetType.size(fitting: text, in: width, weight: .semibold), WidgetType.size(fittingLines: lines, in: height))
        }
        let statusOneLine = WidgetType.fitted(
            statusDesign, fit: min(WidgetType.size(fitting: longestStatus, in: width), WidgetType.size(fittingLines: 1, in: height)),
            statusSize, floor: minimum)
        guard showsName else {
            return ControlLabelLayout(arrangement: .line, name: 0, status: statusOneLine)
        }
        let nameAlone = WidgetType.fitted(nameDesign, fit: nameFit(title, lines: 1, height: height), nameSize, floor: minimum)
        var candidates: [ControlLabelLayout] = []
        if showsStatus {
            // The height shared in proportion to the two design sizes.
            let share = nameDesign / (nameDesign + statusDesign)
            let name = WidgetType.fitted(nameDesign, fit: nameFit(title, lines: 1, height: height * share), nameSize, floor: minimum)
            let state = WidgetType.fitted(
                statusDesign, fit: min(WidgetType.size(fitting: longestStatus, in: width),
                                       WidgetType.size(fittingLines: 1, in: height * (1 - share))),
                statusSize, floor: minimum)
            candidates.append(ControlLabelLayout(arrangement: .nameAndStatus, name: name, status: state))
        }
        candidates.append(ControlLabelLayout(arrangement: .line, name: nameAlone, status: statusOneLine))
        let words = title.split(separator: " ").map(String.init)
        if words.count == 2, let longest = words.max(by: { $0.count < $1.count }) {
            let name = WidgetType.fitted(nameDesign, fit: nameFit(longest, lines: 2.1, height: height), nameSize, floor: minimum)
            candidates.append(ControlLabelLayout(arrangement: .twoWords, name: name, status: statusOneLine))
        }
        // The first arrangement (most information first) that keeps the name within a step of the
        // largest any of them allows. The floor itself only when nothing larger fits.
        let best = candidates.map(\.name).max() ?? 0
        let legible = candidates.filter { $0.fitsWithoutFloor(width: width, height: height, title: title) }
        guard let pick = legible.first(where: { $0.name >= best * 0.88 }) ?? legible.first else {
            return ControlLabelLayout(arrangement: .none, name: 0, status: 0)
        }
        return pick
    }

    /// The arrangement really fits at its size (the floor's steps may push a size past the room).
    func fitsWithoutFloor(width: CGFloat, height: CGFloat, title: String) -> Bool {
        let slack: CGFloat = 1.12
        switch arrangement {
        case .nameAndStatus:
            return (name + status) * WidgetType.lineHeight <= height * slack
                && WidgetType.size(fitting: title, in: width * slack, weight: .semibold) >= name
        case .line:
            return name == 0 || (name * WidgetType.lineHeight <= height * slack
                && WidgetType.size(fitting: title, in: width * slack, weight: .semibold) >= name)
        case .twoWords:
            let longest = title.split(separator: " ").map(String.init).max { $0.count < $1.count } ?? title
            return name * WidgetType.lineHeight * 2 <= height * slack
                && WidgetType.size(fitting: longest, in: width * slack, weight: .semibold) >= name
        case .none:
            return true
        }
    }
}

/// Control Center's round button: the glyph on a filled circle while on, on a faint one while off.
struct ControlButtonFace: View {
    let control: SystemControl
    let on: Bool
    let diameter: CGFloat

    var body: some View {
        ControlGlyph(control: control, on: on || control.isAction, size: diameter * 0.42)
            .foregroundStyle(on ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .frame(width: diameter, height: diameter)
            .background(on ? AnyShapeStyle(.tint) : AnyShapeStyle(.white.opacity(0.14)), in: Circle())
    }
}

/// A control's glyph: its SF Symbol, or Bluetooth's and AirDrop's own logos (the SF Symbols have
/// none for them).
struct ControlGlyph: View {
    let control: SystemControl
    let on: Bool
    /// The symbol's point size; the logo is drawn as tall.
    let size: CGFloat

    var body: some View {
        if control == .bluetooth {
            BluetoothLogo()
                .stroke(style: StrokeStyle(lineWidth: max(1.2, size * 0.13), lineCap: .round, lineJoin: .round))
                .frame(width: size * 0.62, height: size * 1.1)
                .opacity(on ? 1 : 0.55)
        } else if control == .airDrop {
            AirDropLogo()
                .stroke(style: StrokeStyle(lineWidth: max(1.2, size * 0.11), lineCap: .round))
                .frame(width: size * 1.1, height: size * 1.1)
        } else {
            Image(systemName: control.symbol(on: on))
                .font(.system(size: size, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
        }
    }
}

/// The Bluetooth logo (the joined runes ᚼ and ᛒ): a stem with two arrowheads on its right and the
/// two crossing strokes on its left, drawn to be stroked.
nonisolated struct BluetoothLogo: Shape {
    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        var path = Path()
        path.move(to: point(0, 0.27))
        path.addLine(to: point(1, 0.73))
        path.addLine(to: point(0.5, 1))
        path.addLine(to: point(0.5, 0))
        path.addLine(to: point(1, 0.27))
        path.addLine(to: point(0, 0.73))
        return path
    }
}

/// The AirDrop logo: three concentric rings, open at the bottom, drawn to be stroked.
nonisolated struct AirDropLogo: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        var path = Path()
        // Open by 70° around the bottom (90° is straight down in SwiftUI's flipped space).
        let start = Angle.degrees(125)
        for radius in [outer, outer * 0.66, outer * 0.32] {
            // Each ring its own subpath: `addArc` would otherwise join it to the previous one.
            path.move(to: CGPoint(x: center.x + radius * cos(start.radians), y: center.y + radius * sin(start.radians)))
            path.addArc(center: center, radius: radius, startAngle: start, endAngle: .degrees(55), clockwise: false)
        }
        return path
    }
}

// MARK: - Keyboard backlight

/// The keyboard backlight as a slider or a ring, like the Volume and Brightness widgets.
struct KeyboardWidget: View {
    let widget: IslandWidget
    let size: CGSize

    @Environment(AppModel.self) private var model

    var body: some View {
        let controls = model.controls
        Group {
            if let level = controls.keyboardBrightness {
                if widget.resolvedLevelLayout(size) == .ring {
                    LevelRing(value: level, symbol: level < 0.01 ? "light.min" : "light.max",
                              showsValue: widget.shows(.levelValue), size: size,
                              set: { controls.setKeyboardBrightness($0) },
                              onInteraction: { model.island.isInteracting = $0 },
                              symbolSize: widget.size(of: .levelIcon), valueSize: widget.size(of: .levelValue))
                } else {
                    slider(level, controls)
                }
            } else {
                Label("No keyboard backlight", systemImage: "light.max")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: size.width, height: size.height)
            }
        }
        .onAppear { withoutAnimation { model.controls.refresh() } }
    }

    private func slider(_ level: Double, _ controls: SystemControls) -> some View {
        let iconSize = WidgetType.points(size.height, ratio: 0.42, min: 13, max: 22, widget.size(of: .levelIcon))
        return HStack(spacing: Metrics.Spacing.medium) {
            if widget.shows(.levelIcon), size.width >= 90 {
                Image(systemName: level < 0.01 ? "light.min" : "light.max")
                    .font(.system(size: iconSize))
                    .foregroundStyle(.secondary)
                    .frame(width: iconSize * 1.3)
            }
            Slider(value: Binding(get: { level }, set: { controls.setKeyboardBrightness($0) }), in: 0...1) {
                Text("Keyboard Brightness")
            } onEditingChanged: { editing in
                model.island.isInteracting = editing
            }
            .labelsHidden()
            .ownDirection()
            if widget.shows(.levelValue), size.width >= 150 {
                Text(IslandFormat.percent(level))
                    .font(.system(size: WidgetType.points(size.height, ratio: 0.3, min: 11, max: 15,
                                                          widget.size(of: .levelValue))).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 34, alignment: .trailing)
                    .ownDirection()
            }
        }
        .mirroredSides(widget.mirrored)
        .padding(.horizontal, Metrics.Spacing.xSmall)
        .frame(width: size.width, height: size.height)
    }
}
