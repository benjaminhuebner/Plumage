import SwiftUI

struct SkillTreeView: View {
    let skillName: String
    let children: [SkillNode]
    let projectURL: URL

    @Environment(NavigatorModel.self) private var navigator
    @State private var expanded: Bool = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            ForEach(children, id: \.self) { node in
                nodeView(skillName: skillName, relativePath: "", node: node)
            }
            if isPendingHere(relativePath: "") {
                inlineRow
            }
        } label: {
            HStack {
                Label(skillName, systemImage: "puzzlepiece")
                Spacer()
                addMenu(relativePath: "")
            }
        }
    }

    @ViewBuilder
    private func nodeView(skillName: String, relativePath: String, node: SkillNode) -> some View {
        switch node {
        case .file(let url):
            let rel = childPath(parent: relativePath, name: url.lastPathComponent)
            Label(url.lastPathComponent, systemImage: "doc")
                .tag(NavigatorRoute.skillFile(skill: skillName, relativePath: rel))
        case .folder(let name, let children):
            SkillFolderRow(
                skillName: skillName,
                folderName: name,
                parentPath: relativePath,
                children: children,
                projectURL: projectURL
            )
        }
    }

    @ViewBuilder
    private var inlineRow: some View {
        if let pending = navigator.pendingCreate {
            switch pending.section {
            case .skillFile:
                InlineCreateRow(projectURL: projectURL, icon: "doc")
            case .skillFolder:
                InlineCreateRow(projectURL: projectURL, icon: "folder")
            default:
                EmptyView()
            }
        }
    }

    private func isPendingHere(relativePath: String) -> Bool {
        switch navigator.pendingCreate?.section {
        case .skillFile(let skill, let path):
            return skill == skillName && path == relativePath
        case .skillFolder(let skill, let path):
            return skill == skillName && path == relativePath
        default:
            return false
        }
    }

    @ViewBuilder
    private func addMenu(relativePath: String) -> some View {
        Menu {
            Button("New File") {
                navigator.beginPendingCreate(
                    .skillFile(skillName: skillName, relativePath: relativePath))
            }
            Button("New Folder") {
                navigator.beginPendingCreate(
                    .skillFolder(skillName: skillName, relativePath: relativePath))
            }
        } label: {
            Image(systemName: "plus")
                .font(.caption)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Add to \(skillName)")
    }

    private func childPath(parent: String, name: String) -> String {
        parent.isEmpty ? name : parent + "/" + name
    }
}

private struct SkillFolderRow: View {
    let skillName: String
    let folderName: String
    let parentPath: String
    let children: [SkillNode]
    let projectURL: URL

    @Environment(NavigatorModel.self) private var navigator
    @State private var expanded: Bool = false

    var body: some View {
        let path = parentPath.isEmpty ? folderName : parentPath + "/" + folderName
        DisclosureGroup(isExpanded: $expanded) {
            ForEach(children, id: \.self) { node in
                childView(node: node, path: path)
            }
            if isPendingHere(path: path) {
                inlineRow
            }
        } label: {
            HStack {
                Label(folderName, systemImage: "folder")
                Spacer()
                addMenu(path: path)
            }
        }
    }

    @ViewBuilder
    private func childView(node: SkillNode, path: String) -> some View {
        switch node {
        case .file(let url):
            let rel = path + "/" + url.lastPathComponent
            Label(url.lastPathComponent, systemImage: "doc")
                .tag(NavigatorRoute.skillFile(skill: skillName, relativePath: rel))
        case .folder(let name, let children):
            SkillFolderRow(
                skillName: skillName,
                folderName: name,
                parentPath: path,
                children: children,
                projectURL: projectURL
            )
        }
    }

    @ViewBuilder
    private var inlineRow: some View {
        if let pending = navigator.pendingCreate {
            switch pending.section {
            case .skillFile:
                InlineCreateRow(projectURL: projectURL, icon: "doc")
            case .skillFolder:
                InlineCreateRow(projectURL: projectURL, icon: "folder")
            default:
                EmptyView()
            }
        }
    }

    private func isPendingHere(path: String) -> Bool {
        switch navigator.pendingCreate?.section {
        case .skillFile(let skill, let pendingPath):
            return skill == skillName && pendingPath == path
        case .skillFolder(let skill, let pendingPath):
            return skill == skillName && pendingPath == path
        default:
            return false
        }
    }

    @ViewBuilder
    private func addMenu(path: String) -> some View {
        Menu {
            Button("New File") {
                navigator.beginPendingCreate(
                    .skillFile(skillName: skillName, relativePath: path))
            }
            Button("New Folder") {
                navigator.beginPendingCreate(
                    .skillFolder(skillName: skillName, relativePath: path))
            }
        } label: {
            Image(systemName: "plus")
                .font(.caption)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Add to \(folderName)")
    }
}
