import CoreGraphics

nonisolated enum RowDropPosition: Equatable, Sendable {
    case before(String)
    case after(String)
    case empty
}

nonisolated struct RowDropResolution: Equatable, Sendable {
    let position: RowDropPosition
    let insertionFrame: CGRect
}

// Single-column resolution over measured row frames — row heights vary, so
// the placeholder slot is computed from the registry rects plus the gap the
// source actually opens (`placeholderHeight`), never from a layout constant.
nonisolated func resolveRowDrop(
    cursorY: CGFloat,
    orderedRowIDs: [String],
    rowFrames: [String: CGRect],
    placeholderHeight: CGFloat,
    spacing: CGFloat,
    containerFrame: CGRect
) -> RowDropResolution {
    guard !orderedRowIDs.isEmpty else {
        return RowDropResolution(position: .empty, insertionFrame: containerFrame)
    }

    for id in orderedRowIDs {
        guard let frame = rowFrames[id] else { continue }
        if cursorY < frame.midY {
            // insertionFrame points at where the SOURCE lands: the matched row
            // is already shifted down by the open gap, so the slot sits one
            // placeholder-height plus spacing above it.
            let insertionFrame = CGRect(
                x: frame.minX,
                y: frame.minY - spacing - placeholderHeight,
                width: frame.width,
                height: placeholderHeight
            )
            return RowDropResolution(position: .before(id), insertionFrame: insertionFrame)
        }
    }

    let last = orderedRowIDs[orderedRowIDs.count - 1]
    let lastFrame = rowFrames[last] ?? .zero
    // The source's new slot sits below the last row plus one spacing.
    let insertionFrame = CGRect(
        origin: CGPoint(x: lastFrame.minX, y: lastFrame.maxY + spacing),
        size: CGSize(width: lastFrame.width, height: placeholderHeight)
    )
    return RowDropResolution(position: .after(last), insertionFrame: insertionFrame)
}
