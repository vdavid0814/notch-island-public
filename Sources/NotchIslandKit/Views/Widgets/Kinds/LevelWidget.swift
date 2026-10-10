import SwiftUI

/// A level as a widget — the output volume, the display's brightness or the keyboard's: a slider
/// with its symbol and value beside it when the widget is wide, a ring with them inside when it is
/// about square. Each is set by dragging, and drawn as Customize sets its parts (the symbol a
/// button, the value a text, the slider a line).
struct LevelWidget: View {
    let level: WidgetLevel
    let widget: IslandWidget
    let size: CGSize

    @Environment(\.isWidgetPreview) private var isPreview
    @Environment(\.widgetRenderMode) private var renderMode
    @Environment(AppModel.self) private var model
    @Environment(\.reportsProgressParts) private var reportsParts

    private var isRing: Bool { Self.isRing(size) }

    static func isRing(_ size: CGSize) -> Bool { size.width < size.height * 1.6 }

    /// The symbol's size beside the bar.
    static func iconPoints(inner: CGSize) -> CGFloat { WidgetMetrics.points(inner.height, ratio: 0.42, min: 13, max: 22) }

    /// The value's size beside the bar.
    static func valuePoints(inner: CGSize) -> CGFloat { WidgetMetrics.points(inner.height, ratio: 0.3, min: 11, max: 15) }

    /// "62%", or "Muted".
    static func valueText(_ reading: LevelReading) -> String {
        reading.isMuted ? String(localized: "Muted") : IslandFormat.percent(reading.value)
    }

    /// As a ring both are drawn; as a bar the symbol from a widget 90 pt wide, the value from 150.
    static func hasRoom(for element: ElementID, inner: CGSize) -> Bool {
        if isRing(inner) { return true }
        switch element {
        case .levelIcon: return inner.width >= 90
        case .levelValue: return inner.width >= 150
        default: return true
        }
    }

    /// The level now; a picture's as Settings last showed it (`PictureReadings`), the keyboard's at
    /// half when nothing has read it. Nil: a Mac without a keyboard backlight.
    static func reading(_ level: WidgetLevel, model: AppModel, picture: Bool) -> LevelReading? {
        if let kind = level.levelKind {
            return picture ? PictureReadings.level(kind, model: model) : model.levels.reading(kind)
        }
        guard let value = picture ? model.controls.keyboardBrightness ?? 0.5 : model.controls.keyboardBrightness else { return nil }
        return LevelReading(value: value, isMuted: false, isAvailable: true, kind: .brightness)
    }

    private func set(_ value: Double) {
        if let kind = level.levelKind {
            model.levels.set(kind, to: value)
        } else {
            model.controls.setKeyboardBrightness(value)
        }
    }

    var body: some View {
        let picture = isPreview || renderMode == .canvas
        Group {
            if let reading = Self.reading(level, model: model, picture: picture) {
                if isRing {
                    // The ring drawn as the line is (`ProgressLook`); the symbol and the value inside
                    // it as the button and the text they are beside the line.
                    LevelRing(value: reading.value, symbol: level.symbol(reading),
                              showsSymbol: widget.shows(.levelIcon), showsValue: widget.shows(.levelValue), size: size,
                              look: widget.progressLook(of: .levelSlider), symbolLook: widget.buttonLook(of: .levelIcon),
                              valueStyle: widget.textStyles[.levelValue], reportsFrame: reportsParts,
                              set: set, onInteraction: { model.island.isInteracting = $0 })
                        .disabled(!reading.isAvailable)
                        .movableElement(.levelSlider, of: widget)
                } else {
                    slider(reading)
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
        // The keyboard's backlight is read as the widget comes on screen (nothing tells of a change).
        .whileShown { if !picture, level == .keyboard { withoutAnimation { model.controls.refresh() } } } stop: {}
    }

    private func slider(_ reading: LevelReading) -> some View {
        let points = Self.iconPoints(inner: size), valuePoints = Self.valuePoints(inner: size)
        let look = widget.buttonLook(of: .levelIcon)
        let symbol = level.symbol(reading)
        return HStack(spacing: Metrics.Spacing.medium) {
            // The symbol from a widget 90 pt wide, the value from 150.
            if widget.shows(.levelIcon), Self.hasRoom(for: .levelIcon, inner: size) {
                Group {
                    if look == .plain {
                        Image(systemName: symbol)
                            .foregroundStyle(reading.isMuted ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                            .contentTransition(.symbolEffect(.replace))
                            .animation(Motion.content, value: symbol)
                            .accessibilityHidden(true)
                            .font(.system(size: points))
                    } else {
                        // Restyled in Customize, as Now Playing's buttons are.
                        WidgetButtonLabel(look: look, symbol: symbol, points: points)
                    }
                }
                .frame(width: points * 1.3)
                .movableElement(.levelIcon, of: widget)
            }
            // Drawn as Now Playing's line is, and set by dragging it (`ProgressLook`).
            ScrubTrack(position: reading.value, duration: 1, look: widget.progressLook(of: .levelSlider),
                       reportsFrame: reportsParts, accessibilityName: LocalizedStringKey(level.title), spokenValue: { IslandFormat.percent($0) },
                       step: 0.05, drawsOnLayer: false) { value in
                set(value)
            } commit: {
            } onDrag: { dragging in
                model.island.isInteracting = dragging
                model.banners.isHeld = dragging || model.island.isHovering
            }
            .disabled(!reading.isAvailable)
            .movableElement(.levelSlider, of: widget)
            if widget.shows(.levelValue), Self.hasRoom(for: .levelValue, inner: size) {
                WidgetLabel(id: .levelValue, text: Self.valueText(reading), widget: widget, size: valuePoints, weight: .regular,
                            isSecondary: true) {
                    LevelValue(reading: reading)
                        .font(.system(size: valuePoints).monospacedDigit())
                }
                .frame(minWidth: 34, alignment: .trailing)
                .movableElement(.levelValue, of: widget)
            }
        }
        .padding(.horizontal, Metrics.Spacing.xSmall)
        .frame(width: size.width, height: size.height)
    }
}

/// A level as a ring with its symbol and value inside: drag up or down on it to change the level.
struct LevelRing: View {
    let value: Double
    let symbol: String
    var showsSymbol = true
    var showsValue = true
    let size: CGSize
    /// The ring as its line's look draws it; the symbol as its button's look, the value in its style.
    var look: ProgressLook = .plain
    var symbolLook: ButtonLook = .plain
    var valueStyle: TextStyle?
    var reportsFrame = false
    let set: (Double) -> Void
    var onInteraction: (Bool) -> Void = { _ in }

    @State private var dragStart: Double?

    var body: some View {
        let diameter = min(size.width, size.height)
        let line = max(3, diameter * 0.1)
        // The number only in a ring large enough to read it.
        let showsNumber = showsValue && diameter >= 44
        let symbolPoints = diameter * (showsNumber ? 0.24 : 0.34)
        ZStack {
            // Its line's middle on the ring's edge, as these rings have always been drawn.
            ProgressRing(fraction: value, diameter: diameter + line, line: line, look: look, reportsFrame: reportsFrame)
                .frame(width: diameter, height: diameter)
            VStack(spacing: 0) {
                if showsSymbol {
                    if symbolLook == .plain {
                        Image(systemName: symbol)
                            .font(.system(size: symbolPoints, weight: .semibold))
                            .contentTransition(.symbolEffect(.replace))
                    } else {
                        WidgetButtonLabel(look: symbolLook, symbol: symbol, points: symbolPoints)
                    }
                }
                if showsNumber {
                    RingText(text: Text(IslandFormat.percent(value)), style: valueStyle, size: diameter * 0.18, weight: .semibold,
                             design: .rounded, part: .remaining, look: look,
                             limit: RingText.valueLimit(diameter: diameter, line: line))
                        // The ring moves; the number just changes (a cross-fade per step smeared).
                        .transaction { $0.animation = nil }
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(line * 1.4)
            .besideProgressParts()
        }
        .frame(width: diameter, height: diameter)
        .frame(width: size.width, height: size.height)
        .contentShape(.rect)
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { drag in
                    if dragStart == nil {
                        dragStart = value
                        onInteraction(true)
                    }
                    set(((dragStart ?? value) - drag.translation.height / max(diameter * 2, 80)).clamped(to: 0...1))
                }
                .onEnded { _ in
                    dragStart = nil
                    onInteraction(false)
                }
        )
        .accessibilityRepresentation {
            Slider(value: Binding(get: { value }, set: set), in: 0...1)
        }
    }
}
