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
        // Single-pass: only rebuild `cards` if at least one stale entry is
        // present. Avoids the intermediate `[String]` allocation of the
        // prior filter+loop approach. Mutating `cards` reassigns the
        // @Observable storage; the early-return when nothing is stale keeps
        // FSEvent-frequent calls free of unnecessary notifications.
        let filtered = cards.filter { ids.contains($0.key) }
        if filtered.count != cards.count {
            cards = filtered
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
            // Floor-rounding the rect on the transform side (earlier approach)
            // shifted maxX/maxY down by up to 1pt and broke `contains(cursor)`
            // and midY classification on edges. Tolerance equality stops the
            // multi-pass-layout FP oscillation without touching the rect.
            if let existing = registry.cards[folderName],
                KanbanGeometry.framesNearlyEqual(existing, frame)
            {
                return
            }
            registry.cards[folderName] = frame
        }
    }

    func reportColumnFrame(column: IssueColumn, registry: KanbanFrameRegistry) -> some View {
        onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named(KanbanCoordinateSpace.name))
        } action: { frame in
            if let existing = registry.columns[column],
                KanbanGeometry.framesNearlyEqual(existing, frame)
            {
                return
            }
            registry.columns[column] = frame
        }
    }
}

nonisolated enum KanbanCoordinateSpace {
    static let name = "kanban"
}

nonisolated enum KanbanGeometry {
    // Sub-pixel oscillation from multi-pass column layout produces frame
    // deltas below half a point. Treating those as "no change" stops the
    // onGeometryChange feedback cycle without rounding the stored rect.
    static func framesNearlyEqual(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat = 0.5) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) < tolerance
            && abs(lhs.origin.y - rhs.origin.y) < tolerance
            && abs(lhs.size.width - rhs.size.width) < tolerance
            && abs(lhs.size.height - rhs.size.height) < tolerance
    }
}
