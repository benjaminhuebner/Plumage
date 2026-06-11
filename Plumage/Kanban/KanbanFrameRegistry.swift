import SwiftUI

typealias KanbanFrameRegistry = DragReorderFrameRegistry<IssueColumn>

extension EnvironmentValues {
    @Entry var kanbanFrameRegistry: KanbanFrameRegistry = KanbanFrameRegistry()
}

extension View {
    func reportCardFrame(folderName: String, registry: KanbanFrameRegistry) -> some View {
        reportRowFrame(
            id: folderName, registry: registry, coordinateSpace: KanbanCoordinateSpace.name)
    }

    func reportColumnFrame(column: IssueColumn, registry: KanbanFrameRegistry) -> some View {
        reportContainerFrame(
            column, registry: registry, coordinateSpace: KanbanCoordinateSpace.name)
    }
}

nonisolated enum KanbanCoordinateSpace {
    static let name = "kanban"
}
