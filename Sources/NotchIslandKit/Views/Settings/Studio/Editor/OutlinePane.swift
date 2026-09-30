import SwiftUI

/// The Customize editor's outline, where Settings' sidebar was: the widget, then its elements by
/// what they are (text, pictures, lines, buttons…), each with its eye (shown or not) and a dot when
/// its look is the user's own. Hovering a row shows the element on the canvas.
struct OutlinePane: View {
    let session: EditorSession

    var body: some View {
        VStack(spacing: 0) {
            if let widget = session.widget {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        OutlineRow(title: widget.kind.title, symbol: nil, kind: widget.kind,
                                   isSelected: session.selection.isEmpty, isModified: !widget.style.isEmpty,
                                   visibility: nil) {
                            session.selection = []
                        }
                        .padding(.bottom, 6)
                        ForEach(OutlineGroup.allCases, id: \.self) { group in
                            let elements = group.elements(of: widget)
                            if !elements.isEmpty {
                                Text(group.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(SettingsPalette.secondary)
                                    .padding(.horizontal, 10)
                                    .padding(.top, 8)
                                    .padding(.bottom, 2)
                                ForEach(elements, id: \.id) { element in
                                    row(element, widget)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 12)
                }
                .scrollIndicators(.never)
                footer
            }
        }
    }

    private func row(_ element: ElementSpec, _ widget: IslandWidget) -> some View {
        let id = element.id
        let switchable = !element.isRequired && widget.kind.options.contains(id)
        return OutlineRow(title: element.title, symbol: element.symbol, kind: nil,
                          isSelected: session.selection.contains(id),
                          isModified: widget.style.elements[id] != nil || widget.sizes[id] != nil,
                          visibility: switchable ? widget.shows(id) : nil,
                          toggleVisibility: {
                              withAnimation(Motion.content) {
                                  session.change(\IslandWidget.options) { widget in
                                      if widget.options.contains(id) { widget.options.remove(id) } else { widget.options.insert(id) }
                                  }
                              }
                          }) {
            if NSEvent.modifierFlags.contains(.command) || NSEvent.modifierFlags.contains(.shift) {
                if session.selection.contains(id) { session.selection.remove(id) } else { session.selection.insert(id) }
            } else {
                session.selection = [id]
            }
        }
        .onHover { inside in
            if inside { session.hover = id } else if session.hover == id { session.hover = nil }
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Button("Copy Style", systemImage: "doc.on.doc") { session.copyStyle() }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .help("Copy this widget's look (⌥⌘C)")
            Button("Paste Style", systemImage: "doc.on.clipboard") { withAnimation(Motion.content) { session.pasteStyle() } }
                .keyboardShortcut("v", modifiers: [.command, .option])
                .help("Give it a copied look: each element takes the look of the one like it (⌥⌘V)")
        }
        .labelStyle(.titleOnly)
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(alignment: .top) { Divider().opacity(0.6) }
    }
}

/// The outline's groups, in order.
enum OutlineGroup: CaseIterable {
    case text, symbols, pictures, lines, buttons, parts, decorations

    var title: String {
        switch self {
        case .text: "Text"
        case .symbols: "Symbols"
        case .pictures: "Artwork"
        case .lines: "Lines"
        case .buttons: "Buttons"
        case .parts: "Parts"
        case .decorations: "Added"
        }
    }

    func elements(of widget: IslandWidget) -> [ElementSpec] {
        switch self {
        case .decorations:
            let ids = widget.style.layout.arrangement?.decorationIDs ?? []
            return ids.sorted { $0.rawValue < $1.rawValue }.compactMap { id in
                widget.style.layout.arrangement?.decoration(id).map { decoration in
                    // A label by what it says.
                    ElementSpec(id, widget.style.elements[id]?.text.labelOverride ?? decoration.text ?? decoration.title,
                                symbol: decoration.systemImage, role: decoration.role)
                }
            }
        default:
            return widget.kind.spec.elements.filter { element in
                switch (self, element.role) {
                case (.text, .text), (.symbols, .symbol), (.pictures, .image), (.lines, .line), (.lines, .chart),
                     (.buttons, .button), (.parts, .feature): true
                default: false
                }
            }
        }
    }
}

private struct OutlineRow: View {
    let title: String
    let symbol: String?
    let kind: IslandWidgetKind?
    let isSelected: Bool
    let isModified: Bool
    /// Shown or not, for an element that can be switched off; nil for one that cannot.
    let visibility: Bool?
    var toggleVisibility: () -> Void = {}
    let select: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            if let kind {
                WidgetIcon(kind: kind, side: 22)
            } else if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .background(.white.opacity(0.07), in: .rect(cornerRadius: 6, style: .continuous))
                    .opacity(visibility == false ? 0.45 : 1)
            }
            Text(title)
                .font(.system(size: 13, weight: kind == nil ? .regular : .semibold))
                .foregroundStyle(visibility == false ? SettingsPalette.secondary : .primary)
                .lineLimit(1)
            if isModified {
                Circle()
                    .fill(Color.islandAccent)
                    .frame(width: 5, height: 5)
                    .help("Its look is your own")
            }
            Spacer(minLength: 0)
            if let visibility {
                Button(action: toggleVisibility) {
                    Image(systemName: visibility ? "eye" : "eye.slash")
                        .font(.system(size: 11))
                        .foregroundStyle(visibility ? SettingsPalette.secondary : .orange)
                        .frame(width: 20, height: 20)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .opacity(isHovered || !visibility ? 1 : 0)
                .help(visibility ? "Hide it" : "Show it")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isSelected ? Color.islandAccent.opacity(0.22) : (isHovered ? .white.opacity(0.06) : .clear))
        }
        .contentShape(.rect)
        .onTapGesture(perform: select)
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
