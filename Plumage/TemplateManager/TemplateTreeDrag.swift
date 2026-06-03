import SwiftUI

// Live drag for the Template Manager content tree, modelled on the Kanban card drag
// (`KanbanDragController` + `FloatingDragCard`): the grabbed row is rendered 1:1 under
// the cursor via a floating overlay instead of relying on the system `.draggable`
// preview. The tree has no reordering (files are alphabetical), so this only carries a
// move-into-folder — no placeholder gap.
nonisolated enum TemplateTreeCoordinateSpace {
    static let name = "template-content-tree"
}

@MainActor
@Observable
final class TemplateTreeDragController {
    private(set) var isActive = false
    private(set) var sourceNode: FileNode?
    // The grabbed row's frame at lift time, in the tree coordinate space; the floating
    // copy is offset from here by the live drag translation.
    private(set) var sourceFrame: CGRect = .zero
    private(set) var translation: CGSize = .zero
    private(set) var cursorLocation: CGPoint = .zero
    // relativePath of the folder row the cursor is currently over (drop destination),
    // so it can show a light highlight while dragging.
    var targetPath: String?

    func startLift(node: FileNode, frame: CGRect) {
        sourceNode = node
        sourceFrame = frame
        translation = .zero
        cursorLocation = CGPoint(x: frame.midX, y: frame.midY)
        isActive = true
    }

    func updateCursor(location: CGPoint, translation: CGSize) {
        cursorLocation = location
        self.translation = translation
    }

    func clear() {
        isActive = false
        sourceNode = nil
        sourceFrame = .zero
        translation = .zero
        targetPath = nil
    }
}

@MainActor
@Observable
final class TemplateTreeFrameRegistry {
    // Row frames keyed by `relativePath`, reported via `.onGeometryChange`, used to find
    // the row under the cursor during a drag.
    var rows: [String: CGRect] = [:]
}

extension View {
    // Records this row's frame (in the tree coordinate space) so the drag can resolve
    // which row the cursor is over.
    func reportTreeRowFrame(_ path: String, registry: TemplateTreeFrameRegistry) -> some View {
        onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named(TemplateTreeCoordinateSpace.name))
        } action: { frame in
            registry.rows[path] = frame
        }
    }
}
