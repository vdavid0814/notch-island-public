import SwiftUI

/// The shelf, Siri and the tools (`ToolSpecs`): each kind to its view, a kind not built yet to its placeholder.
struct ToolFamily: View {
    let widget: IslandWidget
    let size: CGSize
    let thumbnails: ThumbnailCache

    var body: some View {
        switch widget.kind {
        case .shelf: ShelfWidget(widget: widget, size: size, thumbnails: thumbnails)
        case .assistant: AssistantWidget(widget: widget, size: size)
        default: WidgetPlaceholder(kind: widget.kind, size: size)
        }
    }
}

struct ShelfWidget: View {
    let widget: IslandWidget
    let size: CGSize
    let thumbnails: ThumbnailCache

    @Environment(\.widgetFrameProbe) private var probe
    @Environment(AppModel.self) private var model

    var body: some View {
        let items = model.shelf.items
        let side = (min(size.height - 34, 64) * widget.size(of: .previews).factor).rounded()
        let showsPreviews = widget.shows(.previews) && side >= 22 && !items.isEmpty
        // The row under the previews (or the whole widget): its height and, beside the tray and
        // the chevron, the shortest wording ("Drop", or the count) cap the type.
        let rowHeight = showsPreviews ? max(20, size.height - side - Metrics.Spacing.small) : size.height
        let labelFit = min(WidgetType.size(fittingLines: 1, in: rowHeight),
                           WidgetType.size(fitting: items.isEmpty ? "Drop files" : "\(items.count) items", in: size.width * 0.62, weight: .medium))
        let labelSize = WidgetType.fitted(WidgetType.points(size.height, ratio: 0.3, min: 11, max: 15), fit: labelFit,
                                          widget.size(of: .shelfCount), floor: 9)
        VStack(spacing: Metrics.Spacing.small) {
            if showsPreviews {
                ScrollView(.horizontal) {
                    HStack(spacing: Metrics.Spacing.medium) {
                        ForEach(items) { item in
                            FileTile(item: item, thumbnails: thumbnails,
                                     scale: side / Metrics.Expanded.thumbnailSize, showsName: false)
                        }
                    }
                }
                .scrollIndicators(.never)
                .frame(height: side)
                .editorElement(.previews, in: probe)
            }
            HStack(spacing: Metrics.Spacing.small) {
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
                            .foregroundStyle(items.isEmpty ? .secondary : .primary)
                            .contentTransition(.opacity)
                            .editorElement(.shelfCount, in: probe)
                        }
                        Spacer(minLength: 0)
                        if size.width >= 110 {
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
                if widget.shows(.shelfActions), !items.isEmpty, size.width >= 200 {
                    Button {
                        model.shelf.airDrop()
                    } label: {
                        Label("AirDrop", systemImage: "dot.radiowaves.up.forward")
                    }
                    .islandButton(.circle)
                    .help("Send with AirDrop")
                    .editorElement(.shelfActions.part("airDrop"), in: probe)
                    Button(role: .destructive) {
                        model.shelf.clear()
                    } label: {
                        Label("Clear", systemImage: "xmark")
                    }
                    .islandButton(.circle)
                    .help("Remove everything from the shelf")
                    .editorElement(.shelfActions.part("clear"), in: probe)
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
    let widget: IslandWidget
    let size: CGSize

    @Environment(\.widgetFrameProbe) private var probe
    @Environment(AppModel.self) private var model

    var body: some View {
        let tall = size.height >= 70
        let showsLabel = widget.shows(.assistantLabel)
        let iconSide = tall ? min(size.height * 0.4, 40) : min(size.height * 0.6, 22)
        let labelFit = min(WidgetType.size(fittingLines: 1, in: tall ? size.height - iconSide * 1.2 - Metrics.Spacing.small : size.height),
                           WidgetType.size(fitting: "Siri", in: tall ? size.width - 8 : size.width - iconSide * 1.3 - Metrics.Spacing.small - 8,
                                           weight: .semibold))
        let labelSize = WidgetType.fitted(WidgetType.points(size.height, ratio: tall ? 0.16 : 0.4, min: 11, max: 17), fit: labelFit,
                                          widget.size(of: .assistantLabel), floor: 9)
        Button {
            model.perform(.assistant)
        } label: {
            Group {
                if tall {
                    VStack(spacing: Metrics.Spacing.small) {
                        Image(systemName: "siri").font(.system(size: min(size.height * 0.4, 40)))
                        if showsLabel { Text("Siri").font(.system(size: labelSize, weight: .semibold)).editorElement(.assistantLabel, in: probe) }
                    }
                } else {
                    HStack(spacing: Metrics.Spacing.small) {
                        Image(systemName: "siri").font(.system(size: min(size.height * 0.6, 22)))
                        if showsLabel, size.width >= 70 {
                            Text("Siri").font(.system(size: labelSize, weight: .semibold))
                                .editorElement(.assistantLabel, in: probe)
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
