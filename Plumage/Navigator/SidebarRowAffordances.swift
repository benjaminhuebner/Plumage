import SwiftUI

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
            content.draggable(IssueDragPayload(folderName: value.folderName))
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
