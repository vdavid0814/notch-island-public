import AppKit
import SwiftUI

/// Over the widget on the Customize canvas: its elements picked (a click, ⇧/⌘-click, a marquee),
/// dragged to move and resized by eight handles on the grid inside the widget. Drawn outside the
/// magnification, so its handles and one-point lines stay crisp at every zoom.
///
/// The first drag of a widget still laid out by its kind unlocks it where its elements are drawn
/// (one undo step, with the drag). A move only moves; a resize lays the content out again at each
/// new place it lands on, at once, so the element is always the size its outline shows. Everything lands on the
/// grid's lines, the widget's edges, centre and padding line, and the other elements' edges and
/// centres (`InnerSnapper`); ⌘ turns that off. What is drawn while dragging is where the element
/// lands — snapped, kept inside the widget and above its least size — never a frame it cannot take.
struct ElementLayoutEditor: View {
    let session: EditorSession
    let geometry: CanvasGeometry

    @State private var drag: Drag?
    @State private var marquee: CGRect?
    /// One per gesture: the handles come with the first drag's pick, and a state they shared with
    /// the drag was reset under it (the drag "ended" as it began).
    @GestureState private var isMoving = false
    @GestureState private var isResizing = false

    /// A move or a resize in progress, in the widget's points.
    /// A drag's state and steps are the session's (`LayoutDrag`), so tests drive the same code.
    private typealias Drag = LayoutDrag

    static let space = "layoutCanvas"

    var body: some View {
        let frames = session.elementFrames
        let state = session.layoutState
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(.rect)
                .gesture(SpatialTapGesture(coordinateSpace: .named(Self.space)).onEnded { pick(at: $0.location, frames: frames) })
                .gesture(dragGesture(frames: frames))
                .onContinuousHover(coordinateSpace: .named(Self.space)) { phase in
                    switch phase {
                    case .active(let location): session.hover = element(at: location, frames: frames, includingLocked: false)
                    case .ended: session.hover = nil
                    }
                }
            // Always there (unseen while the kind lays the widget out): the first drag unlocks the
            // widget, and a view that came with it restarted the drag under the pointer.
            InnerGridLines(grid: session.drawnLayout?.grid ?? InnerGrid(columns: 2, rows: 1))
                .stroke(.white.opacity(drag != nil ? 0.2 : 0.09), lineWidth: 0.5)
                .opacity(state.isCustom && session.drawnLayout != nil ? 1 : 0)
                .frame(width: geometry.scaledWidget.width, height: geometry.scaledWidget.height)
                .offset(x: geometry.scaledWidget.minX, y: geometry.scaledWidget.minY)
                .allowsHitTesting(false)
            // The widget itself when it is the one picked.
            if session.selection.isEmpty {
                RoundedRectangle(cornerRadius: WidgetMetrics.cornerRadius * geometry.zoom + 3, style: .continuous)
                    .strokeBorder(Color.islandAccent.opacity(0.9), lineWidth: 2)
                    .frame(width: geometry.scaledWidget.width + 6, height: geometry.scaledWidget.height + 6)
                    .offset(x: geometry.scaledWidget.minX - 3, y: geometry.scaledWidget.minY - 3)
                    .allowsHitTesting(false)
            }
            if let hover = session.hover, !session.selection.contains(hover), drag == nil,
               let frame = frames.first(where: { $0.id == hover })?.frame {
                outline(geometry.canvasRect(frame), width: 1, color: .white.opacity(0.85))
            }
            ForEach(frames.filter { session.selection.contains($0.id) }, id: \.id) { item in
                let isLocked = session.layoutItem(item.id)?.locked == true
                outline(geometry.canvasRect(item.frame), width: 1.5,
                        color: session.isLayoutRefused && drag?.starts[item.id] != nil ? .red : Color.islandAccent)
                    .overlay(alignment: .topLeading) {
                        if isLocked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(Color.onIslandAccent)
                                .padding(3)
                                .background(Color.islandAccent, in: Circle())
                                .offset(x: geometry.canvasRect(item.frame).minX - 8, y: geometry.canvasRect(item.frame).minY - 8)
                        }
                    }
            }
            // The landing place's guides, across the widget.
            ForEach(session.layoutGuides, id: \.self) { guide in
                let isVertical = guide.axis == .vertical
                GuideLine(axis: isVertical ? .vertical : .horizontal,
                          position: isVertical ? geometry.scaledWidget.minX + guide.position * geometry.zoom
                                               : geometry.scaledWidget.minY + guide.position * geometry.zoom,
                          length: isVertical ? geometry.scaledWidget.height : geometry.scaledWidget.width)
                    .offset(x: isVertical ? 0 : geometry.scaledWidget.minX, y: isVertical ? geometry.scaledWidget.minY : 0)
                    .allowsHitTesting(false)
            }
            if let drag {
                if drag.handle != nil {
                    // Where it lands: the element is drawn there too.
                    ResizeOutline(frame: geometry.canvasRect(drag.landed), cornerRadius: 3,
                                  badge: "\(Self.points(drag.landed.width)) × \(Self.points(drag.landed.height))",
                                  badgeAtBottom: geometry.canvasRect(drag.landed).minY < 30, isValid: !session.isLayoutRefused)
                } else if drag.starts.count == 1 {
                    SpacingMarks(rect: drag.landed, others: frames.filter { drag.starts[$0.id] == nil }.map(\.frame),
                                 size: geometry.widgetSize, geometry: geometry)
                }
            }
            if let marquee {
                Rectangle()
                    .fill(Color.islandAccent.opacity(0.12))
                    .overlay { Rectangle().strokeBorder(Color.islandAccent.opacity(0.8), lineWidth: 1) }
                    .frame(width: marquee.width, height: marquee.height)
                    .offset(x: marquee.minX, y: marquee.minY)
                    .allowsHitTesting(false)
            }
            // One element picked: its eight handles.
            if let id = session.selectedElement, state != .unsupported, let frame = frames.first(where: { $0.id == id })?.frame,
               session.layoutItem(id)?.locked != true, drag?.handle == nil || drag?.starts[id] != nil {
                let rect = geometry.canvasRect(drag?.handle != nil ? (drag?.landed ?? frame) : frame)
                let handles = rect.width < 28 || rect.height < 28 ? ResizeHandle.corners : ResizeHandle.allCases
                ForEach(handles, id: \.self) { handle in
                    LayoutHandle(pointer: handle.pointer)
                        .position(handle.position(on: rect.insetBy(dx: -2, dy: -2)))
                        .gesture(resizeGesture(id, handle: handle, frames: frames))
                }
            }
        }
        .coordinateSpace(.named(Self.space))
        .finishingCancelledDrag(isMoving) { if drag?.handle == nil { finish() } }
        .finishingCancelledDrag(isResizing) { if drag?.handle != nil { finish() } }
    }

    private static func points(_ value: CGFloat) -> String { String(format: "%g", Double((value * 2).rounded() / 2)) }

    private func outline(_ rect: CGRect, width: CGFloat, color: Color) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .strokeBorder(color, lineWidth: width)
            .frame(width: rect.width + 4, height: rect.height + 4)
            .offset(x: rect.minX - 2, y: rect.minY - 2)
            .allowsHitTesting(false)
    }

    // MARK: Picking

    /// The element under a point of the canvas: the one drawn in front; a locked one only when asked.
    private func element(at location: CGPoint, frames: [(id: ElementID, frame: CGRect)], includingLocked: Bool) -> ElementID? {
        let point = geometry.widgetPoint(location)
        let slack = 2 / geometry.zoom
        return frames.last { item in
            item.frame.insetBy(dx: -slack, dy: -slack).contains(point) && (includingLocked || session.layoutItem(item.id)?.locked != true)
        }?.id
    }

    private func pick(at location: CGPoint, frames: [(id: ElementID, frame: CGRect)]) {
        let modifiers = NSEvent.modifierFlags
        // ⌥: also what is locked.
        guard let id = element(at: location, frames: frames, includingLocked: modifiers.contains(.option)) else {
            session.selection = []
            return
        }
        if modifiers.contains(.shift) || modifiers.contains(.command) {
            if session.selection.contains(id) { session.selection.remove(id) } else { session.selection.insert(id) }
        } else {
            session.selection = [id]
        }
    }

    // MARK: Moving

    private func dragGesture(frames: [(id: ElementID, frame: CGRect)]) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(Self.space))
            .tracking($isMoving)
            .onChanged { value in
                if drag == nil, marquee == nil {
                    // On an element: it moves (with the others picked, if it is one of them). Beside them: a marquee.
                    if session.layoutState != .unsupported,
                       let id = element(at: value.startLocation, frames: frames, includingLocked: false) {
                        beginMove(id)
                    } else {
                        marquee = .zero
                    }
                }
                if marquee != nil {
                    marquee = CGRect(x: min(value.startLocation.x, value.location.x), y: min(value.startLocation.y, value.location.y),
                                     width: abs(value.location.x - value.startLocation.x), height: abs(value.location.y - value.startLocation.y))
                } else {
                    move(by: CGSize(width: value.translation.width / geometry.zoom, height: value.translation.height / geometry.zoom))
                }
            }
            .onEnded { _ in finish() }
    }

    /// The drag starts: the layout it changes (the widget unlocked where its stacks draw it, if it
    /// still is laid out by its kind), and the elements it moves where they are in it.
    private func beginMove(_ id: ElementID) {
        drag = session.beginMoveDrag(id)
    }

    private func move(by translation: CGSize) {
        guard var current = drag else { return }
        session.moveDrag(&current, by: translation, zoom: geometry.zoom, snapping: !NSEvent.modifierFlags.contains(.command))
        drag = current
    }

    // MARK: Resizing

    private func resizeGesture(_ id: ElementID, handle: ResizeHandle, frames: [(id: ElementID, frame: CGRect)]) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.space))
            .tracking($isResizing)
            .onChanged { value in
                if drag == nil {
                    drag = session.beginResizeDrag(id, handle: handle)
                }
                guard var current = drag else { return }
                let translation = CGSize(width: value.translation.width / geometry.zoom, height: value.translation.height / geometry.zoom)
                session.resizeDrag(&current, id, by: translation, zoom: geometry.zoom,
                                   keepsAspect: NSEvent.modifierFlags.contains(.shift), snapping: !NSEvent.modifierFlags.contains(.command))
                drag = current
            }
            .onEnded { _ in finish() }
    }

    // MARK: Ending

    private func finish() {
        if let marquee {
            // Everything the marquee touches (⌥: also what is locked); ⇧ and ⌘ add to what is picked.
            let modifiers = NSEvent.modifierFlags
            let area = CGRect(origin: geometry.widgetPoint(marquee.origin),
                              size: CGSize(width: marquee.width / geometry.zoom, height: marquee.height / geometry.zoom))
            let touched = session.elementFrames.filter { item in
                item.frame.intersects(area) && (modifiers.contains(.option) || session.layoutItem(item.id)?.locked != true)
            }.map(\.id)
            if marquee.width > 2 || marquee.height > 2 {
                session.selection = modifiers.contains(.shift) || modifiers.contains(.command) ? session.selection.union(touched) : Set(touched)
            }
            self.marquee = nil
        }
        guard drag != nil else { return }
        drag = nil
        withAnimation(.spring(duration: 0.2, bounce: 0.1)) { session.commitDraft() }
    }
}

/// A resize handle on the canvas: a small white square, the resize arrows over it.
private struct LayoutHandle: View {
    let pointer: PointerStyle

    var body: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(.white)
            .overlay { RoundedRectangle(cornerRadius: 2, style: .continuous).strokeBorder(Color.islandAccent == .white ? Color.black.opacity(0.55) : Color.islandAccent, lineWidth: 1) }
            .frame(width: 8, height: 8)
            .shadow(color: .black.opacity(0.5), radius: 1.5)
            .frame(width: 18, height: 18)
            .contentShape(.rect)
            .pointerStyle(pointer)
    }
}

/// The editing grid's lines over the widget.
private nonisolated struct InnerGridLines: Shape {
    let grid: InnerGrid

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for line in grid.columnLines.dropFirst().dropLast() {
            let x = rect.minX + CGFloat(line) * rect.width
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
        }
        for line in grid.rowLines.dropFirst().dropLast() {
            let y = rect.minY + CGFloat(line) * rect.height
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        return path
    }
}

/// While one element is moved: how far it is from what lies beside it on each side (the nearest
/// element in its way, else the widget's edge), in points of the widget.
private struct SpacingMarks: View {
    let rect: CGRect
    let others: [CGRect]
    let size: CGSize
    let geometry: CanvasGeometry

    var body: some View {
        let gaps = SpacingGaps(rect: rect, others: others, size: size)
        ZStack(alignment: .topLeading) {
            ForEach(gaps.marks, id: \.self) { mark in
                let from = canvas(mark.from), to = canvas(mark.to)
                Path { path in
                    path.move(to: from)
                    path.addLine(to: to)
                }
                .stroke(Color.pink.opacity(0.9), lineWidth: 1)
                Text(String(format: "%g", Double((mark.length * 2).rounded() / 2)))
                    .font(.system(size: 9, weight: .semibold).monospacedDigit())
                    .padding(.horizontal, 3)
                    .background(Color.pink, in: Capsule())
                    .foregroundStyle(.white)
                    .fixedSize()
                    .position(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
            }
        }
        .allowsHitTesting(false)
    }

    private func canvas(_ point: CGPoint) -> CGPoint {
        CGPoint(x: geometry.scaledWidget.minX + point.x * geometry.zoom, y: geometry.scaledWidget.minY + point.y * geometry.zoom)
    }
}

/// The spaces around a rectangle among others in a widget: on each side, to the nearest rectangle
/// that lies in its way (overlapping it on the other axis), else to the widget's edge.
nonisolated struct SpacingGaps: Sendable {
    nonisolated struct Mark: Hashable, Sendable {
        var from: CGPoint
        var to: CGPoint
        var length: CGFloat
    }

    var marks: [Mark]

    init(rect: CGRect, others: [CGRect], size: CGSize, minimum: CGFloat = 0.5) {
        let beside = others.filter { $0.maxY > rect.minY && $0.minY < rect.maxY }
        let above = others.filter { $0.maxX > rect.minX && $0.minX < rect.maxX }
        let left = beside.filter { $0.maxX <= rect.minX }.map(\.maxX).max() ?? 0
        let right = beside.filter { $0.minX >= rect.maxX }.map(\.minX).min() ?? size.width
        let top = above.filter { $0.maxY <= rect.minY }.map(\.maxY).max() ?? 0
        let bottom = above.filter { $0.minY >= rect.maxY }.map(\.minY).min() ?? size.height
        var marks: [Mark] = []
        func add(_ from: CGPoint, _ to: CGPoint) {
            let length = abs(to.x - from.x) + abs(to.y - from.y)
            if length >= minimum { marks.append(Mark(from: from, to: to, length: length)) }
        }
        add(CGPoint(x: left, y: rect.midY), CGPoint(x: rect.minX, y: rect.midY))
        add(CGPoint(x: rect.maxX, y: rect.midY), CGPoint(x: right, y: rect.midY))
        add(CGPoint(x: rect.midX, y: top), CGPoint(x: rect.midX, y: rect.minY))
        add(CGPoint(x: rect.midX, y: rect.maxY), CGPoint(x: rect.midX, y: bottom))
        self.marks = marks
    }
}
