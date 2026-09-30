/// Undo and redo of one widget's look (its style alone: `StyleHistory`), as snapshots of it.
///
/// Every edit records the snapshot from before it. Within a group (`begin` … `end`: a slider or a
/// colour dragged), consecutive edits of one property are a single step, so the whole drag undoes
/// at once. A new edit clears what could be redone; the oldest steps go past `depth`.
nonisolated struct EditHistory<Snapshot: Equatable> {
    let depth: Int
    private(set) var undoStack: [Snapshot] = []
    private(set) var redoStack: [Snapshot] = []
    private var isGrouping = false
    /// The property the group's last step changed: its next edit joins that step.
    private var coalescing: AnyKeyPath?

    init(depth: Int = 100) {
        self.depth = depth
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    mutating func begin() {
        isGrouping = true
        coalescing = nil
    }

    mutating func end() {
        isGrouping = false
        coalescing = nil
    }

    /// An edit of `property`, `before` being the snapshot it started from.
    mutating func record(_ before: Snapshot, property: AnyKeyPath) {
        if isGrouping, property == coalescing { return }
        undoStack.append(before)
        if undoStack.count > depth { undoStack.removeFirst(undoStack.count - depth) }
        redoStack.removeAll()
        coalescing = isGrouping ? property : nil
    }

    /// The snapshot to go back to from `current`; nil when there is none.
    mutating func undo(from current: Snapshot) -> Snapshot? {
        guard let previous = undoStack.popLast() else { return nil }
        redoStack.append(current)
        coalescing = nil
        return previous
    }

    mutating func redo(from current: Snapshot) -> Snapshot? {
        guard let next = redoStack.popLast() else { return nil }
        undoStack.append(current)
        coalescing = nil
        return next
    }
}

/// A widget's style alone.
typealias StyleHistory = EditHistory<WidgetStyle>
