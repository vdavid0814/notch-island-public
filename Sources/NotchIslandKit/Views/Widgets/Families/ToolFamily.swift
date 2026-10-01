import SwiftUI

/// The shelf, Siri and the tools (`ToolSpecs`): each kind to its view, a kind not built yet to its placeholder.
struct ToolFamily: View, WidgetFamilyElements {
    let widget: IslandWidget
    let size: CGSize
    let thumbnails: ThumbnailCache

    var body: some View {
        switch widget.kind {
        case .shelf: ShelfWidget(widget: widget, size: size, thumbnails: thumbnails)
        case .assistant: AssistantWidget(widget: widget, size: size)
        case .shortcut: ShortcutWidget(widget: widget, size: size)
        case .appLauncher: AppLauncherWidget(widget: widget, size: size)
        case .clipboard: ClipboardWidget(widget: widget, size: size)
        case .photoFrame: PhotoWidget(widget: widget, size: size)
        default: WidgetPlaceholder(kind: widget.kind, size: size)
        }
    }

    func demands(_ input: PlanInput) -> [ElementDemand] {
        input.demands(types: [.shelfCount: ShelfWidget.labelType.at(13), .label: ShortcutWidget.nameType.at(13)])
    }

    func element(_ id: ElementID) -> ToolElement { ToolElement(widget: widget, id: id, thumbnails: thumbnails) }

    /// Siri is one button.
    func allowsCustomLayout(_ size: CGSize) -> Bool { widget.kind.spec.supportsCustomLayout }
}

/// One element of a tool widget on its own (a custom layout), at the size the layout plans.
struct ToolElement: View {
    let widget: IslandWidget
    let id: ElementID
    let thumbnails: ThumbnailCache

    @Environment(\.widgetPlan) private var plan
    @Environment(\.widgetStyle) private var style
    @Environment(AppModel.self) private var model

    var body: some View {
        let planned = plan?.elements[id]
        let room = planned?.size ?? CGSize(width: 60, height: 22)
        switch (widget.kind, id) {
        case (.shelf, .previews):
            ShelfPreviews(thumbnails: thumbnails, side: room.height)
        case (.shelf, .shelfCount):
            ShelfLabel(widget: widget, showsChevron: room.width >= 110, labelSize: planned?.points ?? 13, style: style)
        case (.shelf, .shelfActions.part("airDrop")), (.shelf, .shelfActions.part("clear")):
            if !model.shelf.items.isEmpty {
                ShelfAction(id: id, style: style).controlSize(style.controlSize(id, height: room.height))
            }
        case (.shortcut, .symbol), (.shortcut, .label):
            ShortcutElement(widget: widget, id: id)
        default:
            EmptyView()
        }
    }
}

/// The shelf's files, a row of previews to drag out.
private struct ShelfPreviews: View {
    let thumbnails: ThumbnailCache
    let side: CGFloat

    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Metrics.Spacing.medium) {
                ForEach(model.shelf.items) { item in
                    FileTile(item: item, thumbnails: thumbnails, scale: side / Metrics.Expanded.thumbnailSize, showsName: false)
                }
            }
        }
        .scrollIndicators(.never)
        .frame(height: side)
    }
}

/// The tray, the count (or "Drop files here") and the chevron: a click opens the shelf.
private struct ShelfLabel: View {
    let widget: IslandWidget
    let showsChevron: Bool
    let labelSize: CGFloat
    let style: ResolvedWidgetStyle
    var fit: CGFloat?

    @Environment(\.widgetFrameProbe) private var probe
    @Environment(AppModel.self) private var model

    var body: some View {
        let items = model.shelf.items
        let type = ShelfWidget.labelType.at(labelSize)
        Button {
            model.island.page = .shelf
        } label: {
            HStack(spacing: Metrics.Spacing.xSmall) {
                Image(systemName: items.isEmpty ? "tray" : "tray.full.fill")
                    .foregroundStyle(.secondary)
                if widget.shows(.shelfCount) {
                    // Shorter wording before smaller type, and nothing rather than "Dro…": the
                    // tray already says what the widget is.
                    ViewThatFits(in: .horizontal) {
                        Text(items.isEmpty ? "Drop files here" : "^[\(items.count) item](inflect: true)")
                            .fixedSize()
                        Text(items.isEmpty ? "Drop files" : "\(items.count)")
                            .fixedSize()
                        Text(items.isEmpty ? "Drop" : "\(items.count)")
                            .fixedSize()
                        Color.clear.frame(width: 0, height: 0)
                    }
                    .widgetText(.shelfCount, type, in: style)
                    .foregroundStyle(items.isEmpty ? .secondary : .primary)
                    .contentTransition(.opacity)
                }
                Spacer(minLength: 0)
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                        .imageScale(.small)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .font(.system(size: labelSize, weight: .medium))
        .help("Open Shelf")
        // The whole label (the tray, the count, the chevron): what a custom layout places.
        .editorElement(.shelfCount, in: probe, drawn: .text(style.drawnType(.shelfCount, type), lines: 1, fit: fit))
    }
}

/// AirDrop or Clear, for everything on the shelf.
private struct ShelfAction: View {
    let id: ElementID
    let style: ResolvedWidgetStyle

    @Environment(\.widgetFrameProbe) private var probe
    @Environment(AppModel.self) private var model

    var body: some View {
        if id == .shelfActions.part("airDrop") {
            Button {
                model.shelf.airDrop()
            } label: {
                Label("AirDrop", systemImage: "dot.radiowaves.up.forward")
            }
            .widgetButton(id, in: style)
            .widgetButton(.shelfActions, in: style)
            .islandButton(.circle)
            .help("Send with AirDrop")
            .buttonElement(id, in: probe)
        } else {
            Button(role: .destructive) {
                model.shelf.clear()
            } label: {
                Label("Clear", systemImage: "xmark")
            }
            .widgetButton(id, in: style)
            .widgetButton(.shelfActions, in: style)
            .islandButton(.circle)
            .help("Remove everything from the shelf")
            .buttonElement(id, in: probe)
        }
    }
}

struct ShelfWidget: View {
    let widget: IslandWidget
    let size: CGSize
    let thumbnails: ThumbnailCache

    @Environment(\.widgetFrameProbe) private var probe
    @Environment(\.widgetStyle) private var style
    @Environment(AppModel.self) private var model

    /// The count's type (medium): the tray and the chevron beside it take the same size.
    static let labelType = TypeSpec(points: 13, weight: .medium)

    var body: some View {
        let items = model.shelf.items
        let side = (min(size.height - 34, 64) * widget.size(of: .previews).factor).rounded()
        let showsPreviews = widget.shows(.previews) && side >= 22 && !items.isEmpty
        // The row under the previews (or the whole widget): its height and, beside the tray and
        // the chevron, the shortest wording ("Drop", or the count) cap the type.
        let rowHeight = showsPreviews ? max(20, size.height - side - Metrics.Spacing.small) : size.height
        let labelFit = min(WidgetType.size(fittingLines: 1, in: rowHeight),
                           WidgetType.size(fitting: items.isEmpty ? "Drop files" : "\(items.count) items", in: size.width * 0.62, weight: .medium))
        let labelSize = style.textPoints(.shelfCount, auto: WidgetType.fitted(WidgetType.points(size.height, ratio: 0.3, min: 11, max: 15),
                                                                              fit: labelFit, widget.size(of: .shelfCount), floor: 9),
                                         fit: labelFit)
        VStack(spacing: Metrics.Spacing.small) {
            if showsPreviews {
                ShelfPreviews(thumbnails: thumbnails, side: side)
                    .editorElement(.previews, in: probe)
            }
            HStack(spacing: Metrics.Spacing.small) {
                ShelfLabel(widget: widget, showsChevron: size.width >= 110, labelSize: labelSize, style: style, fit: labelFit)
                if widget.shows(.shelfActions), !items.isEmpty, size.width >= 200 {
                    ShelfAction(id: .shelfActions.part("airDrop"), style: style)
                    ShelfAction(id: .shelfActions.part("clear"), style: style)
                }
            }
            .frame(maxHeight: showsPreviews ? nil : .infinity)
        }
        .frame(width: size.width, height: size.height)
        .animation(Motion.content, value: items.count)
    }
}

/// One button: Siri in the notch (the assistant).
struct AssistantWidget: View {
    /// The user's wording, else Siri's name.
    private var name: String { style.element(.assistantLabel)?.text.labelOverride ?? "Siri" }

    let widget: IslandWidget
    let size: CGSize

    @Environment(\.widgetFrameProbe) private var probe
    @Environment(\.widgetStyle) private var style
    @Environment(AppModel.self) private var model

    static let labelType = TypeSpec(points: 13, weight: .semibold)

    var body: some View {
        let tall = size.height >= 70
        let showsLabel = widget.shows(.assistantLabel)
        let iconSide = tall ? min(size.height * 0.4, 40) : min(size.height * 0.6, 22)
        let labelFit = min(WidgetType.size(fittingLines: 1, in: tall ? size.height - iconSide * 1.2 - Metrics.Spacing.small : size.height),
                           WidgetType.size(fitting: name, in: tall ? size.width - 8 : size.width - iconSide * 1.3 - Metrics.Spacing.small - 8,
                                           weight: .semibold))
        let labelSize = style.textPoints(.assistantLabel, auto: WidgetType.fitted(WidgetType.points(size.height, ratio: tall ? 0.16 : 0.4,
                                                                                                    min: 11, max: 17),
                                                                                  fit: labelFit, widget.size(of: .assistantLabel), floor: 9),
                                         fit: labelFit)
        let label = Self.labelType.at(labelSize)
        Button {
            model.perform(.assistant)
        } label: {
            Group {
                if tall {
                    VStack(spacing: Metrics.Spacing.small) {
                        Image(systemName: "siri").font(.system(size: min(size.height * 0.4, 40)))
                        if showsLabel {
                            Text(name).widgetTextElement(.assistantLabel, label, fit: labelFit, in: style, probe: probe)
                        }
                    }
                } else {
                    HStack(spacing: Metrics.Spacing.small) {
                        Image(systemName: "siri").font(.system(size: min(size.height * 0.6, 22)))
                        if showsLabel, size.width >= 70 {
                            Text(name).widgetTextElement(.assistantLabel, label, fit: labelFit, in: style, probe: probe)
                        }
                    }
                }
            }
            .frame(width: size.width, height: size.height)
            .contentShape(.rect(cornerRadius: WidgetMetrics.cornerRadius))
        }
        .buttonStyle(.plain)
        .foregroundStyle(
            LinearGradient(colors: IslandWidgetKind.assistant.iconColors, startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .help("Siri")
    }
}
