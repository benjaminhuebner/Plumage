import CoreGraphics

// Single source of truth for the column/card layout constants the drag
// pipeline depends on — `resolveDropTarget` needs to know the card height
// and the LazyVStack spacing to compute where a dropped card actually lands,
// and `KanbanColumnView` uses the same height for its placeholder slot.
nonisolated enum KanbanLayout {
    static let columnWidth: CGFloat = 260
    // Sized to fit IssueCardView's worst case: 2-line title + 3-line goal +
    // footer row + cardSurface's vertical padding. Changing this changes
    // every card uniformly; resolveDropTarget reads cardHeight to compute
    // the placeholder slot's Y so the drop animation lands on the right pixel.
    static let cardHeight: CGFloat = 156
    static let cardSpacing: CGFloat = 8
    static let cardSurfacePadding: CGFloat = 12
    // Inner VStack height for IssueCardView / InvalidIssueCardView, so
    // `cardSurface`'s padding sums up to `cardHeight` exactly.
    static var cardContentHeight: CGFloat { cardHeight - 2 * cardSurfacePadding }
}
