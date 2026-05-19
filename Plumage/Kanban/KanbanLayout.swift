import CoreGraphics

// Single source of truth for the column/card layout constants the drag
// pipeline depends on — `resolveDropTarget` needs to know the card height
// and the LazyVStack spacing to compute where a dropped card actually lands,
// and `KanbanColumnView` uses the same height for its placeholder slot.
//
// LOAD-BEARING COUPLING: `cardHeight` is consumed by
// `resolveDropTarget` in KanbanDragState.swift to compute the placeholder
// insertion Y-offset. Replacing this constant with measured per-card heights
// (e.g. via KanbanFrameRegistry frames) requires updating resolveDropTarget
// at the same time — otherwise the drop animation lands on the wrong pixel
// when card heights diverge from the constant (Dynamic Type, long goal lines).
// `IssueCardView` constrains itself to `cardContentHeight`, so the constant
// stays accurate while every card still respects that height; this is the
// invariant a future per-card-height refactor must protect.
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
