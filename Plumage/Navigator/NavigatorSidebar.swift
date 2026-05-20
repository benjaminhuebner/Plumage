import AppKit
import SwiftUI

struct NavigatorSidebar: View {
    @Binding var selection: NavigatorRoute
    let projectURL: URL

    @Environment(ProjectKanbanModel.self) private var kanban
    @Environment(NavigatorModel.self) private var navigator
    @Environment(\.openCreateIssue) private var openCreateIssue

    // Section-header y-anchors so the list-level dropDestination can
    // resolve which section a drop lands in based on cursor position.
    // Each header reports its own minY into this dict; the lookup
    // walks the entries top-down to find the matching section range.
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
            // Custom synthetic "section headers" rendered as ordinary rows
            // so the trailing plus button stays interactive. Native
            // `Section { } header: { … }` in `List(.sidebar)` routes the
            // header through NSTableView's group-header path, which kills
            // button/tap hit-testing.

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
                navigator.beginPendingCreate(.docs)
            }
            .trackSectionAnchor(.docs, in: $sectionAnchors)
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

    private func isPending(_ section: PendingCreate.Section) -> Bool {
        navigator.isPendingCreate(at: section)
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

    // List-level Finder drop resolver. Section anchors are reported via
    // `onGeometryChange`; we look up the section whose header is the last
    // one above the drop point. Drops above the first anchor (e.g. on the
    // Issues area) are rejected outright rather than silently routed to
    // Docs. FS I/O happens off-Main via `navigator.handleFinderDrop`.
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
        let relative = NavigatorModel.relativePath(from: projectURL, to: url)
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
        SidebarRowWithMenu(
            label: Label("Hooks", systemImage: "terminal"),
            help: "New Hook",
            expanded: $hooksExpanded
        ) {
            Button("New Hook") { navigator.beginPendingCreate(.hookFile) }
            Button("New Folder") { navigator.beginPendingCreate(.hookFolder) }
        }
        .clickableSidebarRow()
        .trackSectionAnchor(.hooks, in: $sectionAnchors)
        if hooksExpanded {
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
        }
    }

    @ViewBuilder
    private var skillsGroup: some View {
        SidebarRowWithMenu(
            label: Label("Skills", systemImage: "puzzlepiece.extension"),
            help: "New Skill",
            expanded: $skillsExpanded
        ) {
            Button("New Skill") { navigator.beginPendingCreate(.skill) }
        }
        .clickableSidebarRow()
        .trackSectionAnchor(.skillsTopLevel, in: $sectionAnchors)
        if skillsExpanded {
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
        }
    }

    @ViewBuilder
    private var settingsGroup: some View {
        SidebarRowWithMenu(
            label: Label("Settings", systemImage: "gearshape.2"),
            expanded: $settingsExpanded
        )
        .clickableSidebarRow()
        if settingsExpanded {
            ForEach(SettingsFile.allCases, id: \.self) { file in
                Label(file.rawValue, systemImage: "gearshape")
                    .tag(NavigatorRoute.settings(file))
                    .clickableSidebarRow()
            }
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

    // MARK: - Keyboard

    private func handleReturnKey() -> KeyPress.Result {
        // Don't fight the existing Inline-Create / Inline-Rename TextFields
        // for the Enter key — both forward Enter to commit via .onSubmit.
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

// Tracks the section header's minY in the sidebar coordinate space.
// The list-level dropDestination uses these anchors to dispatch drops
// to the right section based on cursor position.
extension View {
    fileprivate func trackSectionAnchor(
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

// Sidebar section header rendered as an ordinary list row so the
// trailing plus button stays clickable. Native `Section { } header: { … }`
// in `List(.sidebar)` routes the header through NSTableView's group-
// header path, which kills button/tap hit-testing — so we synthesize
// the look here (uppercase tertiary title, top padding) instead.
//
// If `action == nil` the row is plain (e.g. for the Issues section that
// shouldn't expose a "+" per the project owner). Otherwise the plus
// fades up on hover and right-click mirrors the same action.
struct SidebarSectionHeader: View {
    let title: String
    var help: String?
    var action: (() -> Void)?
    @State private var hovering = false

    init(title: String, action: (() -> Void)? = nil, help: String? = nil) {
        self.title = title
        self.action = action
        self.help = help
    }

    init(title: String, help: String, action: @escaping () -> Void) {
        self.title = title
        self.help = help
        self.action = action
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
                .tracking(0.3)
            Spacer()
            if let action {
                Button(action: action) {
                    Image(systemName: "plus")
                        .imageScale(.small)
                        .foregroundStyle(hovering ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(hovering ? 1 : 0.5)
                .help(help ?? "")
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 2)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .listRowSeparator(.hidden)
        .selectionDisabled()
        .contextMenu {
            if let action, let help {
                Button(help, action: action)
            }
        }
    }
}

// Disclosure-style sidebar row used by Hooks, Skills, Settings, and the
// per-skill folder rows. Hand-rolled instead of `DisclosureGroup { }
// label:` because `List(.sidebar)` drops the system chevron AND silently
// kills the toggle as soon as the label is anything more than a primitive
// `Label`. Same rationale as `SidebarSectionHeader` (which exists as a
// row rather than `Section { } header:`).
//
// New-File / New-Folder actions ride on the row's `.contextMenu`
// (right-click) plus the File-menu shortcuts. We previously rendered a
// hover-+ menu via `.overlay(alignment: .trailing) { Menu }`, but that
// shifted the row's measured width and pushed the chevron one indent
// level deeper than peer rows (Settings was 6 pt further left). Trading
// the hover affordance for a consistent layout — context menu + File
// menu cover the same intents.
struct SidebarRowWithMenu<Label: View, MenuContent: View>: View {
    let label: Label
    let help: String
    @Binding var expanded: Bool
    @ViewBuilder let menu: () -> MenuContent

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.right")
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                label
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .contextMenu {
            menu()
        }
    }
}

extension SidebarRowWithMenu where MenuContent == EmptyView {
    init(label: Label, expanded: Binding<Bool>) {
        self.label = label
        self.help = ""
        self._expanded = expanded
        self.menu = { EmptyView() }
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
