import AppKit
import SwiftUI

// Selection identity of the upper sidebar List. Distinct from NavigatorRoute
// so a pinned row and its tree row can never share a selection tag — that
// shared tag was how both used to highlight at once.
enum SidebarListSelection: Hashable {
    case kanban
    case issue(folderName: String)
    case pinned(relativePath: String)
}

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
    // Whether the current .projectFile route was produced by the tree (true)
    // or the PINNED list (false) — the two regions never highlight together.
    @State private var treeOwnsSelection = true
    @Environment(\.controlActiveState) private var controlActiveState

    var body: some View {
        VStack(spacing: 0) {
            issuesAndPinnedList
                .frame(maxHeight: listHeightEstimate)
            SidebarSectionHeader(title: "Files")
                .padding(.leading, 16)
                .padding(.trailing, 12)
            fileTree
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            projectSettingsRow
        }
        // Derived isPresented binding is the standard confirmationDialog
        // shape; the model owns the actual pending state.
        .confirmationDialog(
            navigator.pendingTrashTitle,
            isPresented: Binding(
                get: { navigator.pendingTrash != nil },
                set: { if !$0 { navigator.cancelPendingTrash() } }
            )
        ) {
            Button("Move to Trash", role: .destructive) {
                Task { await navigator.confirmPendingTrash(projectURL: projectURL) }
            }
        } message: {
            Text("You can restore from the Trash.")
        }
    }

    private var issuesAndPinnedList: some View {
        List(selection: listSelectionBinding) {
            SidebarSectionHeader(title: "Issues", help: "New Issue") {
                openCreateIssue(.draft)
            }
            Label("Board", systemImage: "rectangle.3.group.fill")
                .tag(SidebarListSelection.kanban)
            ForEach(IssueColumn.allCases) { column in
                columnRow(column)
            }

            PinnedSectionView(model: pinnedFiles, projectURL: projectURL)
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
    private var fileTree: some View {
        if navigator.rootNodes.isEmpty {
            Spacer(minLength: 0)
        } else {
            FinderFileTree(
                nodes: navigator.rootNodes,
                style: .sidebar,
                expandedPaths: Bindable(navigator).fileTreeExpansion,
                selectedPath: treeSelectedPath,
                revealRequest: navigator.sidebarReveal,
                contextMenu: { nodes in
                    guard !nodes.isEmpty else { return nil }
                    return NSHostingMenu(
                        rootView: NavigatorFileMenu(
                            nodes: nodes, projectURL: projectURL,
                            navigator: navigator, pinModel: pinnedFiles))
                },
                onRenameRequest: { node in
                    guard navigator.renaming == nil else { return }
                    navigator.beginRename(url: node.url)
                },
                onTrashRequest: { nodes in
                    guard navigator.renaming == nil, !nodes.isEmpty else { return }
                    navigator.requestTrash(urls: nodes.map(\.url))
                },
                validateDrop: { _, target in
                    guard let target else { return false }
                    return FileTreeDropResolver.isInsideWhitelistedTree(
                        target.url, projectURL: projectURL)
                },
                onDrop: handleTreeDrop,
                onSelect: { node in
                    guard let node else { return }
                    treeOwnsSelection = true
                    selection = .projectFile(relativePath: node.relativePath)
                }
            ) { node in
                NavigatorFileRow(
                    node: node, projectURL: projectURL,
                    navigator: navigator, pinModel: pinnedFiles)
            }
        }
    }

    private var treeSelectedPath: String? {
        guard treeOwnsSelection, case .projectFile(let rel) = selection else { return nil }
        return rel
    }

    private func handleTreeDrop(_ payload: FileTreeDropPayload, target: FileNode?) -> Bool {
        guard let target else { return false }
        switch payload {
        case .internalMove(let sources):
            Task {
                await navigator.handleInternalMove(
                    sources: sources, targetFolder: target.url, projectURL: projectURL)
            }
        case .finderCopy(let urls):
            Task {
                await navigator.handleFinderDrop(
                    urls: urls, targetFolder: target.url, projectURL: projectURL)
            }
        }
        return true
    }

    // The List hugs its (countable) content so the file tree below gets the
    // remaining height; in a too-small sidebar the VStack splits fairly and
    // the List scrolls internally.
    private var listHeightEstimate: CGFloat {
        let rowHeight: CGFloat = 28
        let headerHeight: CGFloat = 34
        var height: CGFloat = headerHeight + rowHeight + 4 * rowHeight
        for column in IssueColumn.allCases where expansionBinding(for: column).wrappedValue {
            height += CGFloat((kanban.groupedIssues[column] ?? []).count) * rowHeight
        }
        if !pinnedFiles.pinned.isEmpty {
            height += headerHeight + CGFloat(pinnedFiles.pinned.count) * rowHeight
        }
        return height + 20
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
        // Semantic, not .white: the system color adapts to accent/contrast
        // settings the literal can't follow.
        return controlActiveState == .key
            ? Color(nsColor: .alternateSelectedControlTextColor)
            : .primary
    }

    private var listSelectionBinding: Binding<SidebarListSelection?> {
        Binding(
            get: {
                switch selection {
                case .kanban:
                    return .kanban
                case .issue(let folderName):
                    return .issue(folderName: folderName)
                case .projectFile(let rel) where !treeOwnsSelection && pinnedFiles.contains(rel):
                    return .pinned(relativePath: rel)
                default:
                    return nil
                }
            },
            set: { newValue in
                guard let newValue else { return }
                switch newValue {
                case .kanban:
                    selection = .kanban
                case .issue(let folderName):
                    selection = .issue(folderName: folderName)
                case .pinned(let rel):
                    treeOwnsSelection = false
                    selection = .projectFile(relativePath: rel)
                }
            }
        )
    }

    @ViewBuilder
    private func columnRow(_ column: IssueColumn) -> some View {
        // Child view reads the kanban model itself, so an FSEvent snapshot
        // invalidates only the four column sections — not the whole sidebar
        // List body (pins + file tree included).
        SidebarColumnSection(
            column: column,
            projectURL: projectURL,
            isExpanded: expansionBinding(for: column)
        )
    }

    private func expansionBinding(for column: IssueColumn) -> Binding<Bool> {
        switch column {
        case .todo: return $todoExpanded
        case .inProgress: return $inProgressExpanded
        case .waitingForReview: return $waitingExpanded
        case .done: return $doneExpanded
        }
    }

    private func handleReturnKey() -> KeyPress.Result {
        guard navigator.renaming == nil else { return .ignored }
        guard let url = selection.managedFileURL(in: projectURL) else { return .ignored }
        navigator.beginRename(url: url)
        return .handled
    }

    private func handleDeleteKey() -> KeyPress.Result {
        guard navigator.renaming == nil else { return .ignored }
        guard let url = selection.managedFileURL(in: projectURL) else { return .ignored }
        navigator.requestTrash(url: url)
        return .handled
    }
}

private struct SidebarColumnSection: View {
    let column: IssueColumn
    let projectURL: URL
    @Binding var isExpanded: Bool

    @Environment(ProjectKanbanModel.self) private var kanban

    var body: some View {
        let items = kanban.groupedIssues[column] ?? []
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(items, id: \.id) { issue in
                issueRow(issue)
            }
        } label: {
            HStack {
                Label(column.name, systemImage: column.systemImage)
                Spacer()
                Text("\(items.count)")
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            .dropDestination(for: IssueDragPayload.self) { payloads, _ in
                handleColumnDrop(payloads)
            }
        }
    }

    @discardableResult
    private func handleColumnDrop(_ payloads: [IssueDragPayload]) -> Bool {
        guard let payload = payloads.first else { return false }
        kanban.applyOptimisticDrop(
            payload, to: .column(column), projectURL: projectURL)
        return true
    }

    @ViewBuilder
    private func issueRow(_ issue: DiscoveredIssue) -> some View {
        HStack(spacing: 6) {
            IssueTypePill(type: issue.typeForPill)
            Text(issue.titleForRow)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .tag(SidebarListSelection.issue(folderName: issue.id))
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
}
