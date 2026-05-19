import SwiftUI

struct NavigatorSidebar: View {
    @Binding var selection: NavigatorRoute

    @Environment(ProjectKanbanModel.self) private var kanban
    @Environment(NavigatorModel.self) private var navigator

    @State private var kanbanExpanded = true
    @State private var docsExpanded = true
    @State private var claudeExpanded = true
    @State private var hooksExpanded = false
    @State private var skillsExpanded = false
    @State private var settingsExpanded = false

    var body: some View {
        List(selection: selectionBinding) {
            kanbanSection
            docsSection
            claudeSection
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
    private var kanbanSection: some View {
        Section {
            DisclosureGroup(isExpanded: $kanbanExpanded) {
                ForEach(IssueColumn.allCases) { column in
                    columnRow(column)
                }
            } label: {
                Label("Kanban", systemImage: "rectangle.3.group.fill")
                    .font(.headline)
            }
            .tag(NavigatorRoute.kanban)
        }
    }

    @ViewBuilder
    private func columnRow(_ column: IssueColumn) -> some View {
        let items = kanban.groupedIssues[column] ?? []
        DisclosureGroup {
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
    private var docsSection: some View {
        Section {
            DisclosureGroup(isExpanded: $docsExpanded) {
                if navigator.docs.isEmpty {
                    Text("No docs")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                } else {
                    ForEach(navigator.docs, id: \.self) { url in
                        docRow(url)
                    }
                }
            } label: {
                Label("Docs", systemImage: "doc.text")
                    .font(.headline)
            }
        }
    }

    @ViewBuilder
    private func docRow(_ url: URL) -> some View {
        let relative = relativePath(for: url)
        Label(url.lastPathComponent, systemImage: "doc")
            .tag(NavigatorRoute.doc(relativePath: relative))
    }

    @ViewBuilder
    private var claudeSection: some View {
        Section {
            DisclosureGroup(isExpanded: $claudeExpanded) {
                Label("CLAUDE.md", systemImage: "doc.badge.gearshape")
                    .tag(NavigatorRoute.claudeMD)
                hooksGroup
                skillsGroup
                settingsGroup
            } label: {
                Label("Claude", systemImage: "doc.badge.gearshape")
                    .font(.headline)
            }
        }
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
                    Label(url.lastPathComponent, systemImage: "doc")
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
                ForEach(Array(navigator.skills.enumerated()), id: \.offset) { _, node in
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
                Label(file.rawValue, systemImage: "doc")
                    .tag(NavigatorRoute.settings(file))
            }
        } label: {
            Label("Settings", systemImage: "gearshape")
        }
    }

    private func relativePath(for url: URL) -> String {
        // Docs URLs live under `.claude/docs/<file>.md`; record the path
        // segment from `.claude/` downward so the route survives across
        // project-root moves and round-trips through @SceneStorage.
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
