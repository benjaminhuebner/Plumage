import SwiftUI

// `.onGeometryChange` writes straight into the registry — the PreferenceKey
// route emitted multiple values per frame during multi-pass layout and
// triggered SwiftUI's "tried to update multiple times per frame" warning.
@Observable
@MainActor
final class DragReorderFrameRegistry<Container: Hashable> {
    var rows: [String: CGRect] = [:]
    var containers: [Container: CGRect] = [:]

    // Row `.onGeometryChange` writes into `rows` but never removes — without
    // pruning on list changes, stale frames accumulate over a long session
    // and the drop resolver iterates ghost rects.
    func pruneRows(keeping ids: Set<String>) {
        guard !rows.isEmpty else { return }
        // Targeted removeValue instead of rebuilding the dictionary: a
        // typical change has zero or one stale entry, and the no-stale case
        // stays mutation-free (no spurious @Observable notification).
        for key in rows.keys where !ids.contains(key) {
            rows.removeValue(forKey: key)
        }
    }
}

extension View {
    func reportRowFrame<Container: Hashable>(
        id: String, registry: DragReorderFrameRegistry<Container>, coordinateSpace: String
    ) -> some View {
        onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named(coordinateSpace))
        } action: { frame in
            // Floor-rounding the rect shifted maxX/maxY by up to 1pt and broke
            // `contains(cursor)`/midY edge classification. Tolerance equality
            // stops the multi-pass-layout FP oscillation without rounding.
            if let existing = registry.rows[id],
                DragGeometry.framesNearlyEqual(existing, frame)
            {
                return
            }
            registry.rows[id] = frame
        }
    }

    func reportContainerFrame<Container: Hashable>(
        _ container: Container, registry: DragReorderFrameRegistry<Container>,
        coordinateSpace: String
    ) -> some View {
        onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named(coordinateSpace))
        } action: { frame in
            if let existing = registry.containers[container],
                DragGeometry.framesNearlyEqual(existing, frame)
            {
                return
            }
            registry.containers[container] = frame
        }
    }
}

nonisolated enum DragGeometry {
    // Sub-pixel oscillation from multi-pass layout produces frame deltas
    // below half a point. Treating those as "no change" stops the
    // onGeometryChange feedback cycle without rounding the stored rect.
    static func framesNearlyEqual(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat = 0.5) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) < tolerance
            && abs(lhs.origin.y - rhs.origin.y) < tolerance
            && abs(lhs.size.width - rhs.size.width) < tolerance
            && abs(lhs.size.height - rhs.size.height) < tolerance
    }
}
