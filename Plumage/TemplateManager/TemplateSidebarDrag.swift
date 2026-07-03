import CoreGraphics

nonisolated enum SidebarDragPayload {
    case template(TemplateDescriptor)
    case category(TemplateCategory)
    case component(SharedComponent)
}

nonisolated enum SidebarContainer: Hashable, Sendable {
    case componentsHeader
    case divider
}

nonisolated enum SidebarDropTarget: Equatable, Sendable {
    case template(position: RowDropPosition, categoryID: String, insertionFrame: CGRect)
    case category(position: RowDropPosition, insertionFrame: CGRect)
    case component(position: RowDropPosition, insertionFrame: CGRect)

    var insertionFrame: CGRect {
        switch self {
        case .template(_, _, let frame): frame
        case .category(_, let frame): frame
        case .component(_, let frame): frame
        }
    }
}

typealias SidebarDragController = DragReorderController<SidebarDragPayload, SidebarDropTarget>
typealias SidebarFrameRegistry = DragReorderFrameRegistry<SidebarContainer>

nonisolated enum TemplateSidebarLayout {
    static let rowSpacing: CGFloat = 1
    static let coordinateSpace = "templateSidebar"
}

// Registry row keys: template and component rows use `TemplateCatalogItem.id`
// strings; category headers get their own namespace (headers are draggable
// rows for the drag pipeline but never selectable catalog items).
nonisolated enum SidebarRowKey {
    static func category(_ id: String) -> String { "category:\(id)" }

    static func templateID(fromRowKey key: String) -> String? {
        stripped(key, prefix: "template:")
    }

    static func categoryID(fromRowKey key: String) -> String? {
        stripped(key, prefix: "category:")
    }

    static func componentID(fromRowKey key: String) -> String? {
        stripped(key, prefix: "shared:")
    }

    private static func stripped(_ key: String, prefix: String) -> String? {
        guard key.hasPrefix(prefix) else { return nil }
        return String(key.dropFirst(prefix.count))
    }
}

// Category zones span from a category's header top to the next header top, so
// a cursor above the first category (Base, Shared Components, divider) or
// outside the sidebar resolves to nil — release there snaps back.
nonisolated func resolveTemplateSidebarDrop(
    cursor: CGPoint,
    sidebarFrame: CGRect,
    categories: [(id: String, rowIDs: [String])],
    headerFrames: [String: CGRect],
    rowFrames: [String: CGRect],
    placeholderHeight: CGFloat,
    spacing: CGFloat
) -> SidebarDropTarget? {
    guard sidebarFrame.contains(cursor) else { return nil }
    let positioned =
        categories
        .compactMap { category -> (id: String, rowIDs: [String], header: CGRect)? in
            guard let header = headerFrames[category.id] else { return nil }
            return (category.id, category.rowIDs, header)
        }
        .sorted { $0.header.minY < $1.header.minY }

    for (index, category) in positioned.enumerated() {
        let zoneBottom =
            index + 1 < positioned.count ? positioned[index + 1].header.minY : CGFloat.infinity
        guard cursor.y >= category.header.minY, cursor.y < zoneBottom else { continue }
        // An empty category's gap opens directly under its header.
        let emptySlot = CGRect(
            x: category.header.minX,
            y: category.header.maxY + spacing,
            width: category.header.width,
            height: placeholderHeight
        )
        let resolution = resolveRowDrop(
            cursorY: cursor.y,
            orderedRowIDs: category.rowIDs,
            rowFrames: rowFrames,
            placeholderHeight: placeholderHeight,
            spacing: spacing,
            containerFrame: emptySlot
        )
        return .template(
            position: resolution.position,
            categoryID: category.id,
            insertionFrame: resolution.insertionFrame
        )
    }
    return nil
}

// Section granularity: each remaining category is one "row" whose frame is
// its header + template rows block. Above the divider is no valid zone.
nonisolated func resolveCategorySidebarDrop(
    cursor: CGPoint,
    sidebarFrame: CGRect,
    zoneTop: CGFloat?,
    orderedCategoryRowKeys: [String],
    blockFrames: [String: CGRect],
    placeholderHeight: CGFloat,
    spacing: CGFloat
) -> SidebarDropTarget? {
    guard sidebarFrame.contains(cursor) else { return nil }
    if let zoneTop, cursor.y < zoneTop { return nil }
    guard !orderedCategoryRowKeys.isEmpty else { return nil }
    let resolution = resolveRowDrop(
        cursorY: cursor.y,
        orderedRowIDs: orderedCategoryRowKeys,
        rowFrames: blockFrames,
        placeholderHeight: placeholderHeight,
        spacing: spacing,
        containerFrame: .zero
    )
    return .category(position: resolution.position, insertionFrame: resolution.insertionFrame)
}

// Components reorder only inside their own section: from the section header
// down to the divider. Below the divider (categories) is no valid zone.
nonisolated func resolveComponentSidebarDrop(
    cursor: CGPoint,
    sidebarFrame: CGRect,
    zoneTop: CGFloat?,
    zoneBottom: CGFloat?,
    orderedComponentRowKeys: [String],
    rowFrames: [String: CGRect],
    placeholderHeight: CGFloat,
    spacing: CGFloat
) -> SidebarDropTarget? {
    guard sidebarFrame.contains(cursor) else { return nil }
    if let zoneTop, cursor.y < zoneTop { return nil }
    if let zoneBottom, cursor.y >= zoneBottom { return nil }
    guard !orderedComponentRowKeys.isEmpty else { return nil }
    let resolution = resolveRowDrop(
        cursorY: cursor.y,
        orderedRowIDs: orderedComponentRowKeys,
        rowFrames: rowFrames,
        placeholderHeight: placeholderHeight,
        spacing: spacing,
        containerFrame: .zero
    )
    return .component(position: resolution.position, insertionFrame: resolution.insertionFrame)
}

nonisolated func insertionIndex(
    for position: RowDropPosition,
    in orderedIDs: [String],
    idFromRowKey: (String) -> String?
) -> Int {
    switch position {
    case .empty:
        return orderedIDs.count
    case .before(let rowKey):
        guard let id = idFromRowKey(rowKey), let index = orderedIDs.firstIndex(of: id)
        else { return orderedIDs.count }
        return index
    case .after(let rowKey):
        guard let id = idFromRowKey(rowKey), let index = orderedIDs.firstIndex(of: id)
        else { return orderedIDs.count }
        return index + 1
    }
}
