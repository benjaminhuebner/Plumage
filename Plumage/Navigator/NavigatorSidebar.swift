import SwiftUI

struct NavigatorSidebar: View {
    @Binding var selection: NavigatorRoute

    @Environment(ProjectKanbanModel.self) private var kanban
    @Environment(NavigatorModel.self) private var navigator

    @SceneStorage("nav.expansion.hooks") private var hooksExpanded = false
    @SceneStorage("nav.expansion.skills") private var skillsExpanded = false
    @SceneStorage("nav.expansion.settings") private var settingsExpanded = false
    @SceneStorage("nav.expansion.col.todo") private var todoExpanded = true
    @SceneStorage("nav.expansion.col.inProgress") private var inProgressExpanded = true
    @SceneStorage("nav.expansion.col.waitingForReview") private var waitingExpanded = false
    @SceneStorage("nav.expansion.col.done") private var doneExpanded = false

    var body: some View {
        List(selection: selectionBinding) {
            Section("Kanban") {
                Label("Board", systemImage: "rectangle.3.group.fill")
                    .tag(NavigatorRoute.kanban)
                ForEach(IssueColumn.allCases) { column in
                    columnRow(column)
                }
            }

            Section("Docs") {
                if navigator.docs.isEmpty {
                    Text("No docs yet")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                } else {
                    ForEach(navigator.docs, id: \.self) { url in
                        docRow(url)
                    }
                }
            }

            Section("Claude") {
                Label("CLAUDE.md", systemImage: "doc.badge.gearshape")
                    .tag(NavigatorRoute.claudeMD)
                hooksGroup
                skillsGroup
                settingsGroup
            }
        }
        .listStyle(.sidebar)
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
                issueRow(issue)
            }
        } label: {
            HStack {
                Text(column.name)
                Spacer()
                Text("\(items.count)")
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
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
    private func issueRow(_ issue: DiscoveredIssue) -> some View {
        HStack(spacing: 6) {
            IssueTypePill(type: issue.typeForPill)
            Text(issue.titleForRow)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .tag(NavigatorRoute.issue(folderName: issue.id))
    }

    @ViewBuilder
    private func docRow(_ url: URL) -> some View {
        let relative = relativePath(for: url)
        Label(url.lastPathComponent, systemImage: "doc.text")
            .tag(NavigatorRoute.doc(relativePath: relative))
    }

    @ViewBuilder
    private var hooksGroup: some View {
        DisclosureGroup(isExpanded: $hooksExpanded) {
            if navigator.hooks.isEmpty {
                Text("No hooks")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } else {
                ForEach(navigator.hooks, id: \.self) { url in
                    Label(url.lastPathComponent, systemImage: "scroll")
                        .tag(NavigatorRoute.hook(name: url.lastPathComponent))
                }
            }
        } label: {
            Label("Hooks", systemImage: "terminal")
        }
    }

    @ViewBuilder
    private var skillsGroup: some View {
        DisclosureGroup(isExpanded: $skillsExpanded) {
            if navigator.skills.isEmpty {
                Text("No skills")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } else {
                ForEach(navigator.skills, id: \.self) { node in
                    if case .folder(let name, let children) = node {
                        SkillTreeView(skillName: name, children: children)
                    }
                }
            }
        } label: {
            Label("Skills", systemImage: "puzzlepiece.extension")
        }
    }

    @ViewBuilder
    private var settingsGroup: some View {
        DisclosureGroup(isExpanded: $settingsExpanded) {
            ForEach(SettingsFile.allCases, id: \.self) { file in
                Label(file.rawValue, systemImage: "gearshape")
                    .tag(NavigatorRoute.settings(file))
            }
        } label: {
            Label("Settings", systemImage: "gearshape.2")
        }
    }

    private func relativePath(for url: URL) -> String {
        let components = url.pathComponents
        if let idx = components.lastIndex(of: ".claude") {
            return components[idx..<components.count].joined(separator: "/")
        }
        return url.lastPathComponent
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
