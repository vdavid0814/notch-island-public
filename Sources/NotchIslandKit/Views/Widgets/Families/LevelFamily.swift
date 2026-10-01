import SwiftUI

/// Volume and brightness (`LevelSpecs`): each kind to its view, a kind not built yet to its placeholder.
struct LevelFamily: View, WidgetFamilyElements {
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

    func demands(_ input: PlanInput) -> [ElementDemand] {
        input.demands(types: [.levelValue: LevelWidget.valueType.at(15)])
    }

    func element(_ id: ElementID) -> LevelElement { LevelElement(widget: widget, id: id) }
}

/// A level as the widget reads and sets it: volume, display or keyboard brightness.
private struct LevelSource {
    let value: Double?
    let symbol: String
    let isMuted: Bool
    let isAvailable: Bool
    let set: (Double) -> Void

    @MainActor init(_ kind: IslandWidgetKind, model: AppModel, isPicture: Bool) {
        switch kind {
        case .volume, .brightness:
            let level: LevelKind = kind == .volume ? .volume : .brightness
            let reading = model.levels.reading(level)
            value = reading.value
            symbol = IslandFormat.levelSymbol(level, reading: reading)
            isMuted = reading.isMuted
            isAvailable = reading.isAvailable
            set = { model.levels.set(level, to: $0) }
        default:
            let controls = model.controls
            value = isPicture ? controls.keyboardBrightness ?? 0.5 : controls.keyboardBrightness
            symbol = (value ?? 0) < 0.01 ? "light.min" : "light.max"
            isMuted = false
            isAvailable = value != nil
            set = { controls.setKeyboardBrightness($0) }
        }
    }
}

/// One element of a level widget on its own (a custom layout), at the size the layout plans.
struct LevelElement: View {
    let widget: IslandWidget
    let id: ElementID

    @Environment(\.widgetPlan) private var plan
    @Environment(\.widgetStyle) private var style
    @Environment(\.widgetRenderMode) private var renderMode
    @Environment(\.isWidgetPreview) private var isPreview
    @Environment(\.widgetArtworkColor) private var artwork
    @Environment(AppModel.self) private var model

    var body: some View {
        let source = LevelSource(widget.kind, model: model, isPicture: renderMode == .canvas || isPreview)
        let planned = plan?.elements[id]
        // The slider drawn as a ring (its rectangle about square): the symbol and value sit in it.
        let isRing = plan?.elements[.levelSlider].map { $0.size.width < $0.size.height * 1.6 } ?? false
        switch id {
        case .levelIcon:
            Image(systemName: source.symbol)
                .widgetSymbol(.levelIcon, points: planned?.points ?? 16, weight: isRing ? .semibold : .regular, in: style)
                // The keyboard's slider shows its symbol quietly; a muted level too.
                .foregroundStyle(source.isMuted || (widget.kind == .keyboardBrightness && !isRing)
                                 ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .contentTransition(.symbolEffect(.replace))
        case .levelValue:
            // In a ring the number is rounded and bold, as the ring draws it.
            let type = isRing ? TypeSpec(points: 13, design: .rounded, weight: .semibold, monospacedDigits: true) : LevelWidget.valueType
            Text(source.isMuted && !isRing ? "Muted" : IslandFormat.percent(source.value ?? 0))
                .widgetText(.levelValue, type.at(planned?.points ?? 13), in: style)
                .foregroundStyle(.secondary)
                .transaction { $0.animation = nil }
                .frame(maxWidth: .infinity, alignment: style.element(.levelValue)?.text.alignment?.frameAlignment ?? .trailing)
        case .levelSlider:
            let size = planned?.size ?? CGSize(width: 120, height: 24)
            if let value = source.value {
                if size.width < size.height * 1.6 {
                    LevelRing(value: value, symbol: source.symbol, showsValue: false, size: size, set: source.set,
                              onInteraction: { model.island.isInteracting = $0 }, showsSymbol: false)
                } else {
                    LevelSliderElement(widget: widget, value: value, isAvailable: source.isAvailable, set: source.set)
                        .environment(\.sliderFill, ResolvedLine(style.element(.levelSlider)).fillColor(value: value, artwork: artwork))
                }
            }
        default:
            EmptyView()
        }
    }
}

/// The slider of a level: the volume's and brightness's own, the keyboard's plain one.
private struct LevelSliderElement: View {
    let widget: IslandWidget
    let value: Double
    let isAvailable: Bool
    let set: (Double) -> Void

    @Environment(AppModel.self) private var model

    var body: some View {
        switch widget.kind {
        case .volume: LevelSlider(kind: .volume)
        case .brightness: LevelSlider(kind: .brightness)
        default:
            RestingSlider(value: value, isEnabled: isAvailable, label: Text("Keyboard Brightness"), set: set) { editing in
                model.island.isInteracting = editing
            }
        }
    }
}

struct LevelWidget: View {
    let kind: LevelKind
    let widget: IslandWidget
    let size: CGSize

    @Environment(\.widgetFrameProbe) private var probe
    @Environment(\.widgetStyle) private var style
    @Environment(\.widgetArtworkColor) private var artwork
    @Environment(AppModel.self) private var model

    /// The value's type: digits of one width.
    static let valueType = TypeSpec(points: 13, monospacedDigits: true)

    var body: some View {
        let reading = model.levels.reading(kind)
        let symbol = IslandFormat.levelSymbol(kind, reading: reading)
        if widget.resolvedLevelLayout(size) == .ring {
            LevelRing(value: reading.value, symbol: symbol,
                      showsValue: widget.shows(.levelValue), size: size,
                      set: { model.levels.set(kind, to: $0) },
                      onInteraction: { model.island.isInteracting = $0 },
                      symbolSize: widget.size(of: .levelIcon), valueSize: widget.size(of: .levelValue))
                .disabled(!reading.isAvailable)
        } else {
            let autoIcon = WidgetType.points(size.height, ratio: 0.42, min: 13, max: 22, widget.size(of: .levelIcon))
            let iconFit = WidgetType.size(fittingLines: 1, in: size.height)
            let iconSize = style.symbolPoints(.levelIcon, auto: autoIcon, fit: iconFit)
            let valueFit = WidgetType.size(fittingLines: 1, in: size.height)
            let valuePoints = style.textPoints(.levelValue, auto: WidgetType.points(size.height, ratio: 0.3, min: 11, max: 15,
                                                                                    widget.size(of: .levelValue)), fit: valueFit)
            HStack(spacing: Metrics.Spacing.medium) {
                if widget.shows(.levelIcon), size.width >= 90 {
                    LevelSymbol(kind: kind, reading: reading)
                        .widgetSymbolElement(.levelIcon, symbol, points: iconSize, fit: iconFit, in: style, probe: probe)
                        .frame(width: iconSize * 1.3)
                }
                LevelSlider(kind: kind)
                    .environment(\.sliderFill, ResolvedLine(style.element(.levelSlider)).fillColor(value: reading.value, artwork: artwork))
                    .ownDirection()
                    .editorElement(.levelSlider, in: probe)
                if widget.shows(.levelValue), size.width >= 150 {
                    LevelValue(reading: reading)
                        .widgetTextElement(.levelValue, Self.valueType.at(valuePoints), fit: valueFit, in: style, probe: probe)
                        .frame(minWidth: 34, alignment: .trailing)
                        .ownDirection()
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
    /// A custom layout places the symbol on its own.
    var showsSymbol = true

    @State private var dragStart: Double?

    @Environment(\.widgetFrameProbe) private var probe
    @Environment(\.widgetStyle) private var style
    @Environment(\.widgetArtworkColor) private var artwork

    var body: some View {
        let diameter = min(size.width, size.height)
        let ring = ResolvedLine(style.element(.levelSlider))
        let line = ring.thickness ?? max(3, diameter * 0.1)
        let showsNumber = showsValue && diameter >= 44
        let inside = diameter - 2 * line * 1.4
        let valueFit = min(WidgetType.size(fitting: "100%", in: max(0, inside), weight: .semibold, rounded: true, monospacedDigits: true),
                           WidgetType.size(fittingLines: 2, in: max(0, inside)))
        let valuePoints = style.textPoints(.levelValue, auto: WidgetType.ringText("100%", diameter: diameter, ratio: 0.18, valueSize),
                                           fit: valueFit)
        let symbolFit = showsNumber ? max(6, inside * 0.75 - valuePoints * WidgetType.lineHeight) : inside * 0.8
        let symbolPoints = style.symbolPoints(.levelIcon, auto: WidgetType.fitted(diameter * (showsNumber ? 0.24 : 0.34),
                                                                                    fit: symbolFit, symbolSize, floor: 7),
                                              fit: symbolFit)
        let valueType = TypeSpec(points: valuePoints, design: .rounded, weight: .semibold, monospacedDigits: true)
        ZStack {
            Circle().stroke(ring.trackStyle(.white.opacity(0.16), artwork: artwork), lineWidth: line)
            Circle()
                .trim(from: 0, to: value)
                .stroke(ring.fillStyle(value: value, artwork: artwork, ring: true) ?? AnyShapeStyle(.tint),
                        style: StrokeStyle(lineWidth: line, lineCap: ring.cap?.lineCap ?? .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                if showsSymbol {
                    Image(systemName: symbol)
                        .widgetSymbolElement(.levelIcon, symbol, points: symbolPoints, weight: .semibold, fit: symbolFit,
                                             in: style, probe: probe)
                        .contentTransition(.symbolEffect(.replace))
                }
                if showsNumber {
                    Text(IslandFormat.percent(value))
                        .widgetTextElement(.levelValue, valueType, lines: 2, fit: valueFit, in: style, probe: probe)
                        .foregroundStyle(.secondary)
                        // The ring moves; the number just changes (a cross-fade per step smeared).
                        .transaction { $0.animation = nil }
                }
            }
        }
        .frame(width: diameter, height: diameter)
        .editorElement(.levelSlider, in: probe)
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
    @Environment(\.widgetArtworkColor) private var artwork
    @Environment(AppModel.self) private var model
    @Environment(\.controlSize) private var controlSize
    /// On the editor's canvas nothing is read from the system: a backlight at half, as a picture.
    @Environment(\.widgetRenderMode) private var renderMode
    /// A picture (the gallery, a snapshot): nothing is read from the system.
    @Environment(\.isWidgetPreview) private var isPreview

    var body: some View {
        let controls = model.controls
        let isPicture = renderMode == .canvas || isPreview
        Group {
            if let level = isPicture ? controls.keyboardBrightness ?? 0.5 : controls.keyboardBrightness {
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
        .whileShown { if !isPicture { withoutAnimation { model.controls.refresh() } } }
    }

    private func slider(_ level: Double, _ controls: SystemControls) -> some View {
        let symbol = level < 0.01 ? "light.min" : "light.max"
        let iconFit = WidgetType.size(fittingLines: 1, in: size.height)
        let iconSize = style.symbolPoints(.levelIcon, auto: WidgetType.points(size.height, ratio: 0.42, min: 13, max: 22,
                                                                               widget.size(of: .levelIcon)), fit: iconFit)
        let valueFit = WidgetType.size(fittingLines: 1, in: size.height)
        let valuePoints = style.textPoints(.levelValue, auto: WidgetType.points(size.height, ratio: 0.3, min: 11, max: 15,
                                                                                widget.size(of: .levelValue)), fit: valueFit)
        let fill = ResolvedLine(style.element(.levelSlider)).fillColor(value: level, artwork: artwork)
        return HStack(spacing: Metrics.Spacing.medium) {
            if widget.shows(.levelIcon), size.width >= 90 {
                Image(systemName: symbol)
                    .widgetSymbolElement(.levelIcon, symbol, points: iconSize, fit: iconFit, in: style, probe: probe)
                    .foregroundStyle(.secondary)
                    .frame(width: iconSize * 1.3)
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
                    .tint(fill ?? Color.islandAccent)
                }
            }
            .environment(\.sliderFill, fill)
            .ownDirection()
            .editorElement(.levelSlider, in: probe)
            if widget.shows(.levelValue), size.width >= 150 {
                Text(IslandFormat.percent(level))
                    .widgetTextElement(.levelValue, LevelWidget.valueType.at(valuePoints), fit: valueFit, in: style, probe: probe)
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

nonisolated extension LineCapChoice {
    var lineCap: CGLineCap {
        switch self {
        case .round: .round
        case .butt: .butt
        case .square: .square
        }
    }
}
