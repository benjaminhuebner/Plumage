import SwiftUI

struct SkillTreeView: View {
    let skillName: String
    let children: [SkillNode]

    @State private var expanded: Bool = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            ForEach(Array(children.enumerated()), id: \.offset) { _, node in
                nodeView(skillName: skillName, relativePath: skillName, node: node)
            }
        } label: {
            Label(skillName, systemImage: "puzzlepiece")
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
                children: children
            )
        }
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

    @State private var expanded: Bool = false

    var body: some View {
        let path = parentPath.isEmpty ? folderName : parentPath + "/" + folderName
        DisclosureGroup(isExpanded: $expanded) {
            ForEach(Array(children.enumerated()), id: \.offset) { _, node in
                childView(node: node, path: path)
            }
        } label: {
            Label(folderName, systemImage: "folder")
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
                children: children
            )
        }
    }
}
