import CoreGraphics

// Single source of truth for the column/card layout constants the drag
// pipeline depends on — `resolveDropTarget` needs to know the card height
// and the LazyVStack spacing to compute where a dropped card actually lands,
// and `KanbanColumnView` uses the same height for its placeholder slot.
nonisolated enum KanbanLayout {
    static let columnWidth: CGFloat = 260
    static let cardHeight: CGFloat = 156
    static let cardSpacing: CGFloat = 8
    static let cardContainerPadding: CGFloat = 12
    // Inner VStack height for IssueCardView / InvalidIssueCardView, so
    // `cardContainer`'s padding sums up to `cardHeight` exactly.
    static var cardContentHeight: CGFloat { cardHeight - 2 * cardContainerPadding }
}
