import AppKit
import SwiftUI

struct NavigatorSidebar: View {
    @Binding var selection: NavigatorRoute
    let projectURL: URL

    @Environment(ProjectKanbanModel.self) private var kanban
    @Environment(NavigatorModel.self) private var navigator
    @Environment(PinnedFilesModel.self) private var pinnedFiles
    @Environment(\.openCreateIssue) private var openCreateIssue

    @SceneStorage("nav.expansion.col.todo") private var todoExpanded = false
    @SceneStorage("nav.expansion.col.inProgress") private var inProgressExpanded = false
    @SceneStorage("nav.expansion.col.waitingForReview") private var waitingExpanded = false
    @SceneStorage("nav.expansion.col.done") private var doneExpanded = false

    var body: some View {
        List(selection: selectionBinding) {
            SidebarSectionHeader(title: "Issues", help: "New Issue") {
                openCreateIssue(.draft)
            }
            Label("Board", systemImage: "rectangle.3.group.fill")
                .tag(NavigatorRoute.kanban)
                .clickableSidebarRow()
            ForEach(IssueColumn.allCases) { column in
                columnRow(column)
            }

            PinnedSectionView(model: pinnedFiles, projectURL: projectURL)

            filesSectionHeader
            FileTreeView(nodes: navigator.rootNodes, projectURL: projectURL)
        }
        .listStyle(.sidebar)
        .onKeyPress(.return) {
            handleReturnKey()
        }
        .onDeleteCommand {
            _ = handleDeleteKey()
        }
    }

    @ViewBuilder
    private var filesSectionHeader: some View {
        HStack(spacing: 4) {
            Text("FILES")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
                .tracking(0.3)
            Spacer()
            Button {
                selection = .projectSettings
            } label: {
                Image(systemName: "gearshape")
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Project Settings")
        }
        .padding(.top, 8)
        .padding(.bottom, 2)
        .contentShape(Rectangle())
        .listRowSeparator(.hidden)
        .selectionDisabled()
    }

    private var selectionBinding: Binding<NavigatorRoute?> {
        Binding(
            get: { selection },
            set: { if let value = $0 { selection = value } }
        )
    }

    @ViewBuilder
    private func columnRow(_ column: IssueColumn) -> some View {
        let items = kanban.groupedIssues[column] ?? []
        DisclosureGroup(isExpanded: expansionBinding(for: column)) {
            ForEach(items, id: \.id) { issue in
                issueRow(issue, in: column)
            }
        } label: {
            HStack {
                Label(column.name, systemImage: column.systemImage)
                Spacer()
                Text("\(items.count)")
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            .clickableSidebarRow()
            .dropDestination(for: IssueDragPayload.self) { payloads, _ in
                handleColumnDrop(payloads, into: column)
            }
        }
    }

    @discardableResult
    private func handleColumnDrop(
        _ payloads: [IssueDragPayload], into column: IssueColumn
    ) -> Bool {
        guard let payload = payloads.first else { return false }
        kanban.applyOptimisticDrop(
            payload, to: .column(column), projectURL: projectURL)
        return true
    }

    private func expansionBinding(for column: IssueColumn) -> Binding<Bool> {
        switch column {
        case .todo: return $todoExpanded
        case .inProgress: return $inProgressExpanded
        case .waitingForReview: return $waitingExpanded
        case .done: return $doneExpanded
        }
    }

    @ViewBuilder
    private func issueRow(_ issue: DiscoveredIssue, in column: IssueColumn) -> some View {
        HStack(spacing: 6) {
            IssueTypePill(type: issue.typeForPill)
            Text(issue.titleForRow)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .tag(NavigatorRoute.issue(folderName: issue.id))
        .clickableSidebarRow()
        .modifier(IssueRowDraggable(issue: issue, column: column))
        .overlay(alignment: .top) {
            ReorderDropZone(
                folderName: issue.id, column: column, position: .above,
                projectURL: projectURL, kanban: kanban)
        }
        .overlay(alignment: .bottom) {
            ReorderDropZone(
                folderName: issue.id, column: column, position: .below,
                projectURL: projectURL, kanban: kanban)
        }
        .contextMenu {
            IssueContextMenuItems(
                folderName: issue.id,
                folderURL: issueFolderURL(issue),
                projectURL: projectURL
            )
        }
    }

    private func issueFolderURL(_ issue: DiscoveredIssue) -> URL {
        switch issue {
        case .valid(let value):
            return IssueLayout.issueFolder(in: projectURL, folderName: value.folderName)
        case .invalid(let folder, _):
            return folder
        }
    }

    private func handleReturnKey() -> KeyPress.Result {
        guard navigator.pendingCreate == nil, navigator.renaming == nil else {
            return .ignored
        }
        guard let url = selection.managedFileURL(in: projectURL) else { return .ignored }
        navigator.beginRename(url: url)
        return .handled
    }

    private func handleDeleteKey() -> KeyPress.Result {
        guard navigator.pendingCreate == nil, navigator.renaming == nil else {
            return .ignored
        }
        guard let url = selection.managedFileURL(in: projectURL) else { return .ignored }
        Task { @MainActor in
            await navigator.trash(url: url, projectURL: projectURL)
        }
        return .handled
    }
}
