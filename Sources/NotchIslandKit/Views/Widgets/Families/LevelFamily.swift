import SwiftUI

/// Volume and brightness (`LevelSpecs`): each kind to its view, a kind not built yet to its placeholder.
struct LevelFamily: View {
    let widget: IslandWidget
    let size: CGSize

    var body: some View {
        switch widget.kind {
        case .volume: LevelWidget(kind: .volume, widget: widget, size: size)
        case .brightness: LevelWidget(kind: .brightness, widget: widget, size: size)
        case .keyboardBrightness: KeyboardWidget(widget: widget, size: size)
        default: WidgetPlaceholder(kind: widget.kind, size: size)
        }
    }
}

struct LevelWidget: View {
    let kind: LevelKind
    let widget: IslandWidget
    let size: CGSize

    @Environment(\.widgetFrameProbe) private var probe
    @Environment(\.widgetStyle) private var style
    @Environment(AppModel.self) private var model

    var body: some View {
        let reading = model.levels.reading(kind)
        if widget.resolvedLevelLayout(size) == .ring {
            LevelRing(value: reading.value, symbol: IslandFormat.levelSymbol(kind, reading: reading),
                      showsValue: widget.shows(.levelValue), size: size,
                      set: { model.levels.set(kind, to: $0) },
                      onInteraction: { model.island.isInteracting = $0 },
                      symbolSize: widget.size(of: .levelIcon), valueSize: widget.size(of: .levelValue))
                .disabled(!reading.isAvailable)
        } else {
            let iconSize = WidgetType.points(size.height, ratio: 0.42, min: 13, max: 22, widget.size(of: .levelIcon))
            HStack(spacing: Metrics.Spacing.medium) {
                if widget.shows(.levelIcon), size.width >= 90 {
                    LevelSymbol(kind: kind, reading: reading)
                        .widgetSymbol(.levelIcon, points: iconSize, in: style)
                        .frame(width: iconSize * 1.3)
                        .editorElement(.levelIcon, in: probe)
                }
                LevelSlider(kind: kind)
                    .ownDirection()
                if widget.shows(.levelValue), size.width >= 150 {
                    LevelValue(reading: reading)
                        .font(.system(size: WidgetType.points(size.height, ratio: 0.3, min: 11, max: 15,
                                                              widget.size(of: .levelValue))).monospacedDigit())
                        .frame(minWidth: 34, alignment: .trailing)
                        .ownDirection()
                        .editorElement(.levelValue, in: probe)
                }
            }
            .mirroredSides(widget.mirrored)
            .padding(.horizontal, Metrics.Spacing.xSmall)
            .frame(width: size.width, height: size.height)
        }
    }
}

extension IslandWidget {
    /// Automatic: a ring when the widget is about square, a slider when it is wide.
    func resolvedLevelLayout(_ size: CGSize) -> WidgetLayout {
        switch layout {
        case .automatic: size.width < size.height * 1.6 ? .ring : .slider
        default: layout
        }
    }
}

/// A level as a ring with its symbol inside: drag up or down on it to change the level.
struct LevelRing: View {
    let value: Double
    let symbol: String
    let showsValue: Bool
    let size: CGSize
    let set: (Double) -> Void
    var onInteraction: (Bool) -> Void = { _ in }
    /// The widget's Icon and Value elements.
    var symbolSize: ElementSize = .medium
    var valueSize: ElementSize = .medium

    @State private var dragStart: Double?

    @Environment(\.widgetFrameProbe) private var probe

    var body: some View {
        let diameter = min(size.width, size.height)
        let line = max(3, diameter * 0.1)
        let showsNumber = showsValue && diameter >= 44
        let valuePoints = WidgetType.ringText("100%", diameter: diameter, ratio: 0.18, valueSize)
        let inside = diameter - 2 * line * 1.4
        let symbolPoints = WidgetType.fitted(diameter * (showsNumber ? 0.24 : 0.34),
                                             fit: showsNumber ? max(6, inside * 0.75 - valuePoints * WidgetType.lineHeight) : inside * 0.8,
                                             symbolSize, floor: 7)
        ZStack {
            Circle().stroke(.white.opacity(0.16), lineWidth: line)
            Circle()
                .trim(from: 0, to: value)
                .stroke(.tint, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Image(systemName: symbol)
                    .font(.system(size: symbolPoints, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .editorElement(.levelIcon, in: probe)
                if showsNumber {
                    Text(IslandFormat.percent(value))
                        .font(.system(size: valuePoints, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.secondary)
                        // The ring moves; the number just changes (a cross-fade per step smeared).
                        .transaction { $0.animation = nil }
                        .editorElement(.levelValue, in: probe)
                }
            }
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

/// The keyboard backlight as a slider or a ring, like the Volume and Brightness widgets.
struct KeyboardWidget: View {
    let widget: IslandWidget
    let size: CGSize

    @Environment(\.widgetFrameProbe) private var probe
    @Environment(\.widgetStyle) private var style
    @Environment(AppModel.self) private var model
    @Environment(\.controlSize) private var controlSize
    /// On the editor's canvas nothing is read from the system: a backlight at half, as a picture.
    @Environment(\.widgetRenderMode) private var renderMode

    var body: some View {
        let controls = model.controls
        Group {
            if let level = renderMode == .canvas ? controls.keyboardBrightness ?? 0.5 : controls.keyboardBrightness {
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
        .whileShown { if renderMode == .live { withoutAnimation { model.controls.refresh() } } }
    }

    private func slider(_ level: Double, _ controls: SystemControls) -> some View {
        let iconSize = WidgetType.points(size.height, ratio: 0.42, min: 13, max: 22, widget.size(of: .levelIcon))
        return HStack(spacing: Metrics.Spacing.medium) {
            if widget.shows(.levelIcon), size.width >= 90 {
                Image(systemName: level < 0.01 ? "light.min" : "light.max")
                    .widgetSymbol(.levelIcon, points: iconSize, in: style)
                    .foregroundStyle(.secondary)
                    .frame(width: iconSize * 1.3)
                    .editorElement(.levelIcon, in: probe)
            }
            Group {
                if renderMode == .canvas {
                    SliderPicture(value: level, height: SliderPicture.nativeHeight(controlSize), set: { _ in }, onEditingChanged: { _ in })
                } else {
                    Slider(value: Binding(get: { level }, set: { controls.setKeyboardBrightness($0) }), in: 0...1) {
                        Text("Keyboard Brightness")
                    } onEditingChanged: { editing in
                        model.island.isInteracting = editing
                    }
                    .labelsHidden()
                    .tint(Color.islandAccent)
                }
            }
            .ownDirection()
            if widget.shows(.levelValue), size.width >= 150 {
                Text(IslandFormat.percent(level))
                    .font(.system(size: WidgetType.points(size.height, ratio: 0.3, min: 11, max: 15,
                                                          widget.size(of: .levelValue))).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 34, alignment: .trailing)
                    .ownDirection()
                    .editorElement(.levelValue, in: probe)
            }
        }
        .mirroredSides(widget.mirrored)
        .padding(.horizontal, Metrics.Spacing.xSmall)
        .frame(width: size.width, height: size.height)
    }
}
