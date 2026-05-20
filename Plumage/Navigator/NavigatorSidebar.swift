import AppKit
import SwiftUI

struct NavigatorSidebar: View {
    @Binding var selection: NavigatorRoute
    let projectURL: URL

    @Environment(ProjectKanbanModel.self) private var kanban
    @Environment(NavigatorModel.self) private var navigator
    @Environment(\.openCreateIssue) private var openCreateIssue

    @SceneStorage("nav.expansion.hooks") private var hooksExpanded = false
    @SceneStorage("nav.expansion.skills") private var skillsExpanded = false
    @SceneStorage("nav.expansion.settings") private var settingsExpanded = false
    @SceneStorage("nav.expansion.col.todo") private var todoExpanded = false
    @SceneStorage("nav.expansion.col.inProgress") private var inProgressExpanded = false
    @SceneStorage("nav.expansion.col.waitingForReview") private var waitingExpanded = false
    @SceneStorage("nav.expansion.col.done") private var doneExpanded = false

    var body: some View {
        List(selection: selectionBinding) {
            Section(header: sectionHeader(title: "Issues", action: { openCreateIssue(.draft) }, help: "New Issue")) {
                Label("Board", systemImage: "rectangle.3.group.fill")
                    .tag(NavigatorRoute.kanban)
                    .clickableSidebarRow()
                ForEach(IssueColumn.allCases) { column in
                    columnRow(column)
                }
            }

            Section(
                header: sectionHeader(title: "Docs", action: { navigator.beginPendingCreate(.docs) }, help: "New Doc")
            ) {
                if navigator.docs.isEmpty && !isPending(.docs) {
                    emptyPlaceholder("No docs yet")
                } else {
                    ForEach(navigator.docs, id: \.absoluteString) { url in
                        docRow(url)
                    }
                    if isPending(.docs) {
                        InlineCreateRow(projectURL: projectURL, icon: "doc.text")
                    }
                }
            }

            Section(
                header: sectionHeader(
                    title: "Claude", action: { navigator.beginPendingCreate(.claudeMarkdown) }, help: "New Markdown")
            ) {
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
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private func sectionHeader(title: String, action: @escaping () -> Void, help: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            SectionHeaderAddButton(action: action, help: help)
        }
    }

    private func isPending(_ section: PendingCreate.Section) -> Bool {
        navigator.pendingCreate?.section == section
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
        Label(url.lastPathComponent, systemImage: "doc.text")
            .tag(NavigatorRoute.claudeMarkdown(name: url.lastPathComponent))
            .clickableSidebarRow()
    }

    @ViewBuilder
    private func docRow(_ url: URL) -> some View {
        let relative = relativePath(for: url)
        Label(url.lastPathComponent, systemImage: "doc.text")
            .tag(NavigatorRoute.doc(relativePath: relative))
            .clickableSidebarRow()
    }

    @ViewBuilder
    private var hooksGroup: some View {
        DisclosureGroup(isExpanded: $hooksExpanded) {
            if navigator.hooks.isEmpty && !isPending(.hookFile) && !isPending(.hookFolder) {
                emptyPlaceholder("No hooks")
            } else {
                ForEach(navigator.hooks, id: \.absoluteString) { url in
                    Label(url.lastPathComponent, systemImage: "scroll")
                        .tag(NavigatorRoute.hook(name: url.lastPathComponent))
                        .clickableSidebarRow()
                }
                if isPending(.hookFile) {
                    InlineCreateRow(projectURL: projectURL, icon: "scroll")
                } else if isPending(.hookFolder) {
                    InlineCreateRow(projectURL: projectURL, icon: "folder")
                }
            }
        } label: {
            HStack {
                Label("Hooks", systemImage: "terminal")
                Spacer()
                hooksAddMenu
            }
            .clickableSidebarRow()
        }
    }

    @ViewBuilder
    private var hooksAddMenu: some View {
        Menu {
            Button("New File") { navigator.beginPendingCreate(.hookFile) }
            Button("New Folder") { navigator.beginPendingCreate(.hookFolder) }
        } label: {
            Image(systemName: "plus")
                .font(.caption)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("New Hook")
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
            HStack {
                Label("Skills", systemImage: "puzzlepiece.extension")
                Spacer()
                skillsAddMenu
            }
            .clickableSidebarRow()
        }
    }

    @ViewBuilder
    private var skillsAddMenu: some View {
        Menu {
            Button("New Skill") { navigator.beginPendingCreate(.skill) }
        } label: {
            Image(systemName: "plus")
                .font(.caption)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("New Skill")
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

    private func relativePath(for url: URL) -> String {
        let components = url.pathComponents
        if let idx = components.lastIndex(of: ".claude") {
            return components[idx..<components.count].joined(separator: "/")
        }
        return url.lastPathComponent
    }
}

private struct ClickableSidebarRowModifier: ViewModifier {
    @State private var pushed = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                // push/pop must stay balanced — track local state so a
                // missed exit callback (view removed mid-hover) can pop in
                // .onDisappear.
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
    fileprivate func clickableSidebarRow() -> some View {
        modifier(ClickableSidebarRowModifier())
    }
}

extension DiscoveredIssue {
    fileprivate var typeForPill: IssueType {
        switch self {
        case .valid(let issue): issue.type
        case .invalid: .chore
        }
    }

    fileprivate var titleForRow: String {
        switch self {
        case .valid(let issue): issue.title
        case .invalid(let folder, _): folder.lastPathComponent
        }
    }
}

private struct IssueRowDraggable: ViewModifier {
    let issue: DiscoveredIssue
    let column: IssueColumn

    func body(content: Content) -> some View {
        // Invalid rows (frontmatter parse errors) have no canonical status —
        // skip them; user must fix the spec first before reorder/move
        // becomes meaningful.
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
