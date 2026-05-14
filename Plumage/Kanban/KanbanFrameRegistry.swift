import SwiftUI

// Card- and column-frame storage shared between the column views and the
// drop-target resolver. `.onGeometryChange` (macOS 14+) writes straight into
// the registry — the equivalent PreferenceKey route emitted multiple values
// per frame during the column's multi-pass layout and triggered SwiftUI's
// "Bound preference X tried to update multiple times per frame" warning.
@Observable
@MainActor
final class KanbanFrameRegistry {
    var cards: [String: CGRect] = [:]
    var columns: [IssueColumn: CGRect] = [:]

    // Drop entries for cards that are no longer in the kanban. Card
    // `.onGeometryChange` writes into `cards` but never removes — so as
    // issues come and go over a long session, stale frames accumulate and
    // `resolveDropTarget` would iterate ghost rects. Called from
    // KanbanView whenever the issue list changes.
    func pruneCards(keeping ids: Set<String>) {
        guard !cards.isEmpty else { return }
        let stale = cards.keys.filter { !ids.contains($0) }
        guard !stale.isEmpty else { return }
        for id in stale {
            cards.removeValue(forKey: id)
        }
    }
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
