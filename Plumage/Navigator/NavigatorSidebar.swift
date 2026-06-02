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

    @State private var settingsHovering = false
    @Environment(\.controlActiveState) private var controlActiveState

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

            PinnedSectionView(
                model: pinnedFiles,
                projectURL: projectURL,
                emptyContextPaths: navigator.emptyContextFilePaths
            )

            SidebarSectionHeader(title: "Files")
            FileTreeView(nodes: navigator.rootNodes, projectURL: projectURL)
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            projectSettingsRow
        }
        .onKeyPress(.return) {
            handleReturnKey()
        }
        .onDeleteCommand {
            _ = handleDeleteKey()
        }
    }

    // Pinned outside the List (via safeAreaInset) so it stays put as the file
    // tree scrolls, hand-styled to read as an ordinary source-list row: same
    // Label, native accent selection fill, subtle hover tint, and a leading
    // inset that lines the icon up with the top-level rows ("Board" reserves
    // the same space the disclosure rows use for their chevron). A nested
    // sidebar List would match automatically but steals first-responder
    // status, greying out the main list's active selection — hence the manual
    // styling. The "selected" VoiceOver announcement is re-added by hand since
    // the row isn't a List(selection:) member.
    @ViewBuilder
    private var projectSettingsRow: some View {
        let isSelected = selection == .projectSettings
        VStack(spacing: 0) {
            Divider()
            Button {
                selection = .projectSettings
            } label: {
                Label("Project Settings", systemImage: "gearshape")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 18)
                    .padding(.trailing, 6)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                    .foregroundStyle(settingsRowTextColor(isSelected: isSelected))
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(settingsRowFill(isSelected: isSelected))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Project Settings")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .clickableSidebarRow()
            .onHover { settingsHovering = $0 }
            .padding(.leading, 15)
            .padding(.trailing, 8)
            .padding(.top, 8)
            .padding(.bottom, 10)
        }
    }

    // Selection must follow window-key state, not a constant accent:
    // otherwise this hand-styled row stays fully accented while the native
    // List rows beside it grey out when the window resigns key.
    private func settingsRowFill(isSelected: Bool) -> Color {
        if isSelected {
            return controlActiveState == .key
                ? Color(nsColor: .selectedContentBackgroundColor)
                : Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
        }
        if settingsHovering { return Color.primary.opacity(0.08) }
        return .clear
    }

    private func settingsRowTextColor(isSelected: Bool) -> Color {
        guard isSelected else { return .primary }
        return controlActiveState == .key ? .white : .primary
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
