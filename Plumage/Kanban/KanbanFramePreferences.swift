import SwiftUI

// Frame registry replaces the PreferenceKey-based reporting. SwiftUI's
// preference system fires "Bound preference … tried to update multiple times
// per frame" warnings during the column's multi-pass layout (LazyVStack +
// ScrollView + placeholder reflow) when many cards emit fresh frame values
// inside the same render pass. `.onGeometryChange` is the post-iOS-17 / macOS
// 14 replacement that bypasses the preference-value graph entirely: each card
// writes its own frame straight into the registry on settle.
@Observable
@MainActor
final class KanbanFrameRegistry {
    var cards: [String: CGRect] = [:]
    var columns: [IssueColumn: CGRect] = [:]
}

extension EnvironmentValues {
    @Entry var kanbanFrameRegistry: KanbanFrameRegistry = KanbanFrameRegistry()
}

extension View {
    func reportCardFrame(folderName: String, registry: KanbanFrameRegistry) -> some View {
        onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named(KanbanCoordinateSpace.name))
        } action: { frame in
            if registry.cards[folderName] != frame {
                registry.cards[folderName] = frame
            }
        }
    }

    func reportColumnFrame(column: IssueColumn, registry: KanbanFrameRegistry) -> some View {
        onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named(KanbanCoordinateSpace.name))
        } action: { frame in
            if registry.columns[column] != frame {
                registry.columns[column] = frame
            }
        }
    }
}

nonisolated enum KanbanCoordinateSpace {
    static let name = "kanban"
}
