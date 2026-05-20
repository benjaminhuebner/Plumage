import AppKit
import SwiftUI

private struct ClickableSidebarRowModifier: ViewModifier {
    @State private var pushed = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                if hovering {
                    if !pushed {
                        NSCursor.pointingHand.push()
                        pushed = true
                    }
                } else if pushed {
                    NSCursor.pop()
                    pushed = false
                }
            }
            .onDisappear {
                if pushed {
                    NSCursor.pop()
                    pushed = false
                }
            }
    }
}

extension View {
    func clickableSidebarRow() -> some View {
        modifier(ClickableSidebarRowModifier())
    }

    func trackSectionAnchor(
        _ section: SidebarDropTarget.Section,
        in anchors: Binding<[SidebarDropTarget.Section: CGFloat]>
    ) -> some View {
        self.onGeometryChange(for: CGFloat.self) { proxy in
            proxy.frame(in: .named("navigator.sidebar")).minY
        } action: { minY in
            anchors.wrappedValue[section] = minY
        }
    }
}

extension DiscoveredIssue {
    var typeForPill: IssueType {
        switch self {
        case .valid(let issue): issue.type
        case .invalid: .chore
        }
    }

    var titleForRow: String {
        switch self {
        case .valid(let issue): issue.title
        case .invalid(let folder, _): folder.lastPathComponent
        }
    }
}

struct IssueRowDraggable: ViewModifier {
    let issue: DiscoveredIssue
    let column: IssueColumn

    func body(content: Content) -> some View {
        if case .valid(let value) = issue {
            content.draggable(
                IssueDragPayload(
                    folderName: value.folderName,
                    currentStatus: value.status
                )
            )
        } else {
            content
        }
    }
}

enum ReorderPosition {
    case above
    case below
}

struct ReorderDropZone: View {
    let folderName: String
    let column: IssueColumn
    let position: ReorderPosition
    let projectURL: URL
    let kanban: ProjectKanbanModel

    @State private var isTargeted = false

    var body: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .frame(height: 8)
            if isTargeted {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 2)
            }
        }
        .frame(maxWidth: .infinity)
        .dropDestination(for: IssueDragPayload.self) { payloads, _ in
            guard let payload = payloads.first else { return false }
            let target: ProjectKanbanModel.DropTarget =
                position == .above
                ? .aboveCard(folderName: folderName, column: column)
                : .belowCard(folderName: folderName, column: column)
            kanban.applyOptimisticDrop(payload, to: target, projectURL: projectURL)
            return true
        } isTargeted: { hovering in
            isTargeted = hovering
        }
    }
}
