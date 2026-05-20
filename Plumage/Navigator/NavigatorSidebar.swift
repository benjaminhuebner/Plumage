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
            Section {
                Label("Board", systemImage: "rectangle.3.group.fill")
                    .tag(NavigatorRoute.kanban)
                    .clickableSidebarRow()
                ForEach(IssueColumn.allCases) { column in
                    columnRow(column)
                }
            } header: {
                Text("Issues")
            }

            Section {
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
            } header: {
                sectionHeader(title: "Docs") {
                    Button("New Doc") { navigator.beginPendingCreate(.docs) }
                }
            }

            Section {
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
            } header: {
                sectionHeader(title: "Claude") {
                    Button("New Markdown") { navigator.beginPendingCreate(.claudeMarkdown) }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            sidebarFooter
        }
        // Keyboard shortcuts on the focused list selection:
        //  - Enter on a managed row → inline rename
        //  - Backspace on a managed row → move to Trash
        // `.onDeleteCommand` is the macOS responder-chain entry point for
        // backspace; `.onKeyPress(.delete)` doesn't fire on List(.sidebar)
        // because the underlying NSTableView absorbs the keystroke. Return
        // works fine via `.onKeyPress` because no AppKit handler claims it.
        .onKeyPress(.return) {
            handleReturnKey()
        }
        .onDeleteCommand {
            _ = handleDeleteKey()
        }
    }

    // Xcode-style sidebar footer: thin bar at the bottom with a single
    // `+` pull-down Menu, no extra material (lets the sidebar's own
    // material show through), divider on top. Matches Project Navigator
    // and Mail's "New Mailbox" pull-down.
    @ViewBuilder
    private var sidebarFooter: some View {
        HStack(spacing: 0) {
            Menu {
                Button("New Issue") { openCreateIssue(.draft) }
                Divider()
                Button("New Doc") { navigator.beginPendingCreate(.docs) }
                Button("New Markdown") {
                    navigator.beginPendingCreate(.claudeMarkdown)
                }
                Divider()
                Button("New Hook") { navigator.beginPendingCreate(.hookFile) }
                Button("New Hook Folder") {
                    navigator.beginPendingCreate(.hookFolder)
                }
                Divider()
                Button("New Skill") { navigator.beginPendingCreate(.skill) }
            } label: {
                Image(systemName: "plus")
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 22)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("New…")
            Spacer()
        }
        .padding(.horizontal, 6)
        .frame(height: 28)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    // Section header with a context menu. The plain Text header is too thin
    // a hitbox for right-click in the sidebar (List(.sidebar) renders it
    // ~14pt high); wrapping in an HStack with maxWidth + a contentShape
    // gives the user the full section-header bar to right-click on.
    @ViewBuilder
    private func sectionHeader<Menu: View>(
        title: String, @ViewBuilder menu: () -> Menu
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
        }
        .contentShape(Rectangle())
        .contextMenu {
            menu()
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

    // MARK: - Issues / columns

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

    // MARK: - Managed file rows (Docs / Claude markdown / Hooks)

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
        let relative = relativePath(for: url)
        managedFileRow(
            url: url,
            tag: .doc(relativePath: relative),
            icon: "doc.text"
        )
    }

    // Shared row layout used by docs, claude markdown, hooks, and skill-files.
    // When `navigator.renaming?.url == url`, the row swaps to an inline
    // TextField for rename. Otherwise it's the normal Label + context menu.
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
            if navigator.hooks.isEmpty && !isPending(.hookFile) && !isPending(.hookFolder) {
                emptyPlaceholder("No hooks")
            } else {
                ForEach(navigator.hooks, id: \.absoluteString) { url in
                    managedFileRow(
                        url: url,
                        tag: .hook(name: url.lastPathComponent),
                        icon: "scroll"
                    )
                }
                if isPending(.hookFile) {
                    InlineCreateRow(projectURL: projectURL, icon: "scroll")
                } else if isPending(.hookFolder) {
                    InlineCreateRow(projectURL: projectURL, icon: "folder")
                }
            }
        } label: {
            Label("Hooks", systemImage: "terminal")
                .clickableSidebarRow()
                .contextMenu {
                    Button("New Hook") { navigator.beginPendingCreate(.hookFile) }
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

    private func relativePath(for url: URL) -> String {
        let components = url.pathComponents
        if let idx = components.lastIndex(of: ".claude") {
            return components[idx..<components.count].joined(separator: "/")
        }
        return url.lastPathComponent
    }

    // MARK: - Keyboard

    private func handleReturnKey() -> KeyPress.Result {
        // Don't fight the existing Inline-Create / Inline-Rename TextFields
        // for the Enter key — both forward Enter to commit via .onSubmit.
        guard navigator.pendingCreate == nil, navigator.renaming == nil else {
            return .ignored
        }
        guard let url = selectedManagedFileURL() else { return .ignored }
        navigator.beginRename(url: url)
        return .handled
    }

    private func handleDeleteKey() -> KeyPress.Result {
        guard navigator.pendingCreate == nil, navigator.renaming == nil else {
            return .ignored
        }
        guard let url = selectedManagedFileURL() else { return .ignored }
        Task { @MainActor in
            await navigator.trash(url: url, projectURL: projectURL)
        }
        return .handled
    }

    // Resolves the current sidebar selection to the on-disk URL of a managed
    // doc/hook/markdown/skill-file row. Returns nil for routes that don't
    // map to a single user-owned file (kanban, issues, claudeMD, settings).
    private func selectedManagedFileURL() -> URL? {
        switch selection {
        case .doc(let rel):
            return projectURL.appendingPathComponent(rel)
        case .claudeMarkdown(let name):
            return
                projectURL
                .appendingPathComponent(ClaudeProjectFiles.settingsRootRelativePath, isDirectory: true)
                .appendingPathComponent(name)
        case .hook(let name):
            return
                projectURL
                .appendingPathComponent(ClaudeProjectFiles.hooksRelativePath, isDirectory: true)
                .appendingPathComponent(name)
        case .skillFile(let skill, let path):
            return
                projectURL
                .appendingPathComponent(ClaudeProjectFiles.skillsRelativePath, isDirectory: true)
                .appendingPathComponent(skill, isDirectory: true)
                .appendingPathComponent(path)
        default:
            return nil
        }
    }
}

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
