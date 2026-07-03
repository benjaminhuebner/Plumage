import CoreGraphics

// The issue is cached at lift time so FloatingDragCard never scans
// ProjectKanbanModel.issues per cursor frame and pulls no Observable
// dependency on the full issues array.
nonisolated struct KanbanDragItem {
    let payload: IssueDragPayload
    let issue: Issue
}

typealias KanbanDragController = DragReorderController<KanbanDragItem, ResolvedDropTarget>

nonisolated struct ResolvedDropTarget: Equatable, Sendable {
    let column: IssueColumn
    let target: ProjectKanbanModel.DropTarget
    let insertionFrame: CGRect
}

nonisolated func computePlaceholderIndex(
    dragTarget: ProjectKanbanModel.DropTarget?,
    column: IssueColumn,
    visibleIssues: [DiscoveredIssue]
) -> Int? {
    guard let dragTarget else { return nil }
    switch dragTarget {
    case .column(let targetColumn):
        guard targetColumn == column else { return nil }
        return visibleIssues.count
    case .aboveCard(let folderName, let targetColumn):
        guard targetColumn == column else { return nil }
        return visibleIssues.firstIndex(where: { $0.id == folderName })
    case .belowCard(let folderName, let targetColumn):
        guard targetColumn == column else { return nil }
        guard let idx = visibleIssues.firstIndex(where: { $0.id == folderName }) else { return nil }
        return idx + 1
    }
}

// Reorder against a partially hidden column would run order math the user
// can't see — while filtered, same-column row targets go inert (snap-back);
// cross-column drops keep working as status changes.
nonisolated func gateReorderWhileFiltered(
    _ resolved: ResolvedDropTarget?,
    sourceColumn: IssueColumn?,
    isFiltered: Bool
) -> ResolvedDropTarget? {
    guard isFiltered, let resolved, let sourceColumn else { return resolved }
    switch resolved.target {
    case .aboveCard(_, let column), .belowCard(_, let column):
        return column == sourceColumn ? nil : resolved
    case .column:
        return resolved
    }
}

// Multi-column layering over the generic single-column resolver: pick the
// hovered column, then resolve within it. Kanban cards are uniform, so the
// placeholder height is the layout constant rather than a measured frame.
nonisolated func resolveDropTarget(
    cursor: CGPoint,
    cardFrames: [String: CGRect],
    columnFrames: [IssueColumn: CGRect],
    sortedIssues: [IssueColumn: [DiscoveredIssue]],
    sourceFolderName: String
) -> ResolvedDropTarget? {
    guard let column = columnFrames.first(where: { $0.value.contains(cursor) })?.key
    else { return nil }

    let cards = (sortedIssues[column] ?? [])
        .filter { $0.id != sourceFolderName }

    let resolution = resolveRowDrop(
        cursorY: cursor.y,
        orderedRowIDs: cards.map(\.id),
        rowFrames: cardFrames,
        placeholderHeight: KanbanLayout.cardHeight,
        spacing: KanbanLayout.cardSpacing,
        containerFrame: columnFrames[column] ?? .zero
    )
    let target: ProjectKanbanModel.DropTarget =
        switch resolution.position {
        case .empty: .column(column)
        case .before(let id): .aboveCard(folderName: id, column: column)
        case .after(let id): .belowCard(folderName: id, column: column)
        }
    return ResolvedDropTarget(
        column: column, target: target, insertionFrame: resolution.insertionFrame)
}
