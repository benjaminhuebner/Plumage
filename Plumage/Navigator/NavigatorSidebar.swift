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
                Group {
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
                .modifier(SectionDropModifier(section: .docs, projectURL: projectURL, navigator: navigator))
            }

            Section(
                header: sectionHeader(
                    title: "Claude", action: { navigator.beginPendingCreate(.claudeMarkdown) }, help: "New Markdown")
            ) {
                Group {
                    Label("CLAUDE.md", systemImage: "doc.badge.gearshape")
                        .tag(NavigatorRoute.claudeMD)
                        .clickableSidebarRow()
                    ForEach(navigator.claudeMarkdown, id: \.absoluteString) { url in
                        claudeMarkdownRow(url)
                    }
                    if isPending(.claudeMarkdown) {
                        InlineCreateRow(projectURL: projectURL, icon: "doc.text")
                    }
                }
                .modifier(SectionDropModifier(section: .claudeMarkdown, projectURL: projectURL, navigator: navigator))
                Group {
                    hooksGroup
                }
                .modifier(SectionDropModifier(section: .hooks, projectURL: projectURL, navigator: navigator))
                Group {
                    skillsGroup
                }
                .modifier(SectionDropModifier(section: .skillsTopLevel, projectURL: projectURL, navigator: navigator))
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
        .overlay(alignment: .top) {
            reorderDropZone(folderName: issue.id, column: column, position: .above)
        }
        .overlay(alignment: .bottom) {
            reorderDropZone(folderName: issue.id, column: column, position: .below)
        }
        .contextMenu {
            IssueContextMenuItems(
                folderName: issue.id,
                folderURL: issueFolderURL(issue),
                projectURL: projectURL
            )
        }
    }

    // Half-height transparent slot — splitting the row into two SwiftUI drop
    // targets is the pattern used historically (decisions.md 2026-05-14
    // #00013 above/below zones) and avoids the location-math fragility of a
    // single drop target. Each zone holds its own `isTargeted` state so the
    // 2pt indicator line can flip independently.
    @ViewBuilder
    private func reorderDropZone(
        folderName: String, column: IssueColumn, position: ReorderPosition
    ) -> some View {
        ReorderDropZone(
            folderName: folderName,
            column: column,
            position: position,
            projectURL: projectURL,
            kanban: kanban
        )
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

private struct SectionDropModifier: ViewModifier {
    let section: SidebarDropTarget.Section
    let projectURL: URL
    let navigator: NavigatorModel

    func body(content: Content) -> some View {
        content.dropDestination(for: URL.self) { urls, _ in
            performDrop(urls)
        }
    }

    @discardableResult
    private func performDrop(_ urls: [URL]) -> Bool {
        guard !urls.isEmpty else { return false }
        do {
            let outcome = try SidebarDropTarget.performDrop(
                sources: urls, section: section, projectURL: projectURL)
            if let banner = SidebarDropTarget.bannerMessage(
                outcome: outcome, section: section)
            {
                navigator.showBanner(banner)
            }
            if !outcome.accepted.isEmpty {
                Task { @MainActor in
                    await navigator.reload(projectURL: projectURL)
                }
            }
            return !outcome.accepted.isEmpty
        } catch {
            navigator.showBanner("Couldn't copy: \(error.localizedDescription)")
            return false
        }
    }
}

enum ReorderPosition {
    case above
    case below
}

private struct ReorderDropZone: View {
    let folderName: String
    let column: IssueColumn
    let position: ReorderPosition
    let projectURL: URL
    let kanban: ProjectKanbanModel

    @State private var isTargeted = false

    var body: some View {
        // 8pt slot at the row's top/bottom. The 2pt indicator centers in the
        // slot when targeted; otherwise the slot is fully transparent so the
        // row's normal hit-testing keeps working.
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
