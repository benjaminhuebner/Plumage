import AppKit
import SwiftUI

struct NavigatorSidebar: View {
    @Binding var selection: NavigatorRoute
    let projectURL: URL

    @Environment(ProjectKanbanModel.self) private var kanban
    @Environment(NavigatorModel.self) private var navigator
    @Environment(\.openCreateIssue) private var openCreateIssue

    @State private var sectionAnchors: [SidebarDropTarget.Section: CGFloat] = [:]

    @SceneStorage("nav.expansion.hooks") private var hooksExpanded = false
    @SceneStorage("nav.expansion.skills") private var skillsExpanded = false
    @SceneStorage("nav.expansion.settings") private var settingsExpanded = false
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

            SidebarSectionHeader(title: "Docs", help: "New Doc") {
                navigator.beginPendingCreate(.managedFile(type: .docs))
            }
            .trackSectionAnchor(.docs, in: $sectionAnchors)
            if navigator.docs.isEmpty && !isPending(.managedFile(type: .docs)) {
                emptyPlaceholder("No docs yet")
            } else {
                ForEach(navigator.docs, id: \.absoluteString) { url in
                    docRow(url)
                }
                if isPending(.managedFile(type: .docs)) {
                    InlineCreateRow(projectURL: projectURL, icon: "doc.text")
                }
            }

            SidebarSectionHeader(title: "Claude", help: "New Markdown") {
                navigator.beginPendingCreate(.claudeMarkdown)
            }
            .trackSectionAnchor(.claudeMarkdown, in: $sectionAnchors)
            Label("CLAUDE.md", systemImage: "doc.badge.gearshape")
                .tag(NavigatorRoute.claudeMD)
                .clickableSidebarRow()
            ForEach(navigator.claudeMarkdown, id: \.absoluteString) { url in
                claudeMarkdownRow(url)
            }
            if isPending(.claudeMarkdown) {
                InlineCreateRow(projectURL: projectURL, icon: "doc.text")
            }
            hooksGroup
            skillsGroup
            settingsGroup
        }
        .listStyle(.sidebar)
        .coordinateSpace(.named("navigator.sidebar"))
        .dropDestination(for: URL.self) { urls, location in
            handleListDrop(urls: urls, location: location)
        }
        .onKeyPress(.return) {
            handleReturnKey()
        }
        .onDeleteCommand {
            _ = handleDeleteKey()
        }
    }

    private func isPending(_ section: PendingCreate.Section) -> Bool {
        navigator.isPendingCreate(at: section)
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

    private func handleListDrop(urls: [URL], location: CGPoint) -> Bool {
        guard !urls.isEmpty else { return false }
        guard
            let section = SidebarDropTarget.resolveSection(
                at: location.y, anchors: sectionAnchors)
        else {
            return false
        }
        Task { @MainActor in
            await navigator.handleFinderDrop(
                urls: urls, section: section, projectURL: projectURL)
        }
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

    @ViewBuilder
    private func claudeMarkdownRow(_ url: URL) -> some View {
        managedFileRow(
            url: url,
            tag: .claudeMarkdown(name: url.lastPathComponent),
            icon: "doc.text"
        )
    }

    @ViewBuilder
    private func docRow(_ url: URL) -> some View {
        let relative = url.lastPathComponent
        managedFileRow(
            url: url,
            tag: .managedFile(type: .docs, relativePath: relative),
            icon: "doc.text"
        )
    }

    @ViewBuilder
    private func managedFileRow(
        url: URL, tag: NavigatorRoute, icon: String
    ) -> some View {
        if navigator.renaming?.url == url {
            InlineRenameRow(projectURL: projectURL, icon: icon)
                .tag(tag)
        } else {
            Label(url.lastPathComponent, systemImage: icon)
                .tag(tag)
                .clickableSidebarRow()
                .contextMenu {
                    Button("Rename") { navigator.beginRename(url: url) }
                    Divider()
                    Button("Move to Trash", role: .destructive) {
                        Task { @MainActor in
                            await navigator.trash(url: url, projectURL: projectURL)
                        }
                    }
                }
        }
    }

    @ViewBuilder
    private var hooksGroup: some View {
        DisclosureGroup(isExpanded: $hooksExpanded) {
            if navigator.hooks.isEmpty && !isPending(.managedFile(type: .hooks)) && !isPending(.hookFolder) {
                emptyPlaceholder("No hooks")
            } else {
                ForEach(navigator.hooks, id: \.absoluteString) { url in
                    managedFileRow(
                        url: url,
                        tag: .managedFile(type: .hooks, relativePath: url.lastPathComponent),
                        icon: "scroll"
                    )
                }
                if isPending(.managedFile(type: .hooks)) {
                    InlineCreateRow(projectURL: projectURL, icon: "scroll")
                } else if isPending(.hookFolder) {
                    InlineCreateRow(projectURL: projectURL, icon: "folder")
                }
            }
        } label: {
            Label("Hooks", systemImage: "terminal")
                .clickableSidebarRow()
                .trackSectionAnchor(.hooks, in: $sectionAnchors)
                .contextMenu {
                    Button("New Hook") { navigator.beginPendingCreate(.managedFile(type: .hooks)) }
                    Button("New Folder") { navigator.beginPendingCreate(.hookFolder) }
                }
        }
    }

    @ViewBuilder
    private var skillsGroup: some View {
        DisclosureGroup(isExpanded: $skillsExpanded) {
            if navigator.skills.isEmpty && !isPending(.skill) {
                emptyPlaceholder("No skills")
            } else {
                ForEach(navigator.skills, id: \.self) { node in
                    if case .folder(let name, let children) = node {
                        SkillTreeView(skillName: name, children: children, projectURL: projectURL)
                    }
                }
                if isPending(.skill) {
                    InlineCreateRow(projectURL: projectURL, icon: "puzzlepiece")
                }
            }
        } label: {
            Label("Skills", systemImage: "puzzlepiece.extension")
                .clickableSidebarRow()
                .trackSectionAnchor(.skillsTopLevel, in: $sectionAnchors)
                .contextMenu {
                    Button("New Skill") { navigator.beginPendingCreate(.skill) }
                }
        }
    }

    @ViewBuilder
    private var settingsGroup: some View {
        DisclosureGroup(isExpanded: $settingsExpanded) {
            ForEach(SettingsFile.allCases, id: \.self) { file in
                Label(file.rawValue, systemImage: "gearshape")
                    .tag(NavigatorRoute.settings(file))
                    .clickableSidebarRow()
            }
        } label: {
            Label("Settings", systemImage: "gearshape.2")
                .clickableSidebarRow()
        }
    }

    @ViewBuilder
    private func emptyPlaceholder(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.tertiary)
            .font(.callout)
            .disabled(true)
            .selectionDisabled()
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
