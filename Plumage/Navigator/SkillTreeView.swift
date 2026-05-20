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
                inlineCreateRow
            }
        } label: {
            skillFolderLabel(
                folderName: skillName,
                icon: "puzzlepiece",
                path: "",
                url: skillFolderURL(skillName: skillName, relativePath: ""))
        }
    }

    @ViewBuilder
    private func nodeView(skillName: String, relativePath: String, node: SkillNode) -> some View {
        switch node {
        case .file(let url):
            let rel = childPath(parent: relativePath, name: url.lastPathComponent)
            skillFileRow(url: url, skillName: skillName, relativePath: rel)
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
    private var inlineCreateRow: some View {
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

    private func childPath(parent: String, name: String) -> String {
        parent.isEmpty ? name : parent + "/" + name
    }

    private func skillFolderURL(skillName: String, relativePath: String) -> URL {
        var url =
            projectURL
            .appendingPathComponent(ClaudeProjectFiles.skillsRelativePath, isDirectory: true)
            .appendingPathComponent(skillName, isDirectory: true)
        let trimmed = relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !trimmed.isEmpty {
            for component in trimmed.split(separator: "/") {
                url = url.appendingPathComponent(String(component), isDirectory: true)
            }
        }
        return url
    }

    @ViewBuilder
    fileprivate func skillFileRow(url: URL, skillName: String, relativePath: String) -> some View {
        if navigator.renaming?.url == url {
            InlineRenameRow(projectURL: projectURL, icon: "doc")
                .tag(NavigatorRoute.skillFile(skill: skillName, relativePath: relativePath))
        } else {
            Label(url.lastPathComponent, systemImage: "doc")
                .tag(NavigatorRoute.skillFile(skill: skillName, relativePath: relativePath))
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
    fileprivate func skillFolderLabel(
        folderName: String, icon: String, path: String, url: URL
    ) -> some View {
        Label(folderName, systemImage: icon)
            .contextMenu {
                Button("New File") {
                    navigator.beginPendingCreate(
                        .skillFile(skillName: skillName, relativePath: path))
                }
                Button("New Folder") {
                    navigator.beginPendingCreate(
                        .skillFolder(skillName: skillName, relativePath: path))
                }
                Divider()
                Button("Rename") { navigator.beginRename(url: url) }
                Button("Move to Trash", role: .destructive) {
                    Task { @MainActor in
                        await navigator.trash(url: url, projectURL: projectURL)
                    }
                }
            }
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
                inlineCreateRow
            }
        } label: {
            folderLabel(path: path)
        }
    }

    @ViewBuilder
    private func childView(node: SkillNode, path: String) -> some View {
        switch node {
        case .file(let url):
            let rel = path + "/" + url.lastPathComponent
            if navigator.renaming?.url == url {
                InlineRenameRow(projectURL: projectURL, icon: "doc")
                    .tag(NavigatorRoute.skillFile(skill: skillName, relativePath: rel))
            } else {
                Label(url.lastPathComponent, systemImage: "doc")
                    .tag(NavigatorRoute.skillFile(skill: skillName, relativePath: rel))
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
    private var inlineCreateRow: some View {
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
    private func folderLabel(path: String) -> some View {
        let url = folderURL(path: path)
        if navigator.renaming?.url == url {
            InlineRenameRow(projectURL: projectURL, icon: "folder")
        } else {
            Label(folderName, systemImage: "folder")
                .contextMenu {
                    Button("New File") {
                        navigator.beginPendingCreate(
                            .skillFile(skillName: skillName, relativePath: path))
                    }
                    Button("New Folder") {
                        navigator.beginPendingCreate(
                            .skillFolder(skillName: skillName, relativePath: path))
                    }
                    Divider()
                    Button("Rename") { navigator.beginRename(url: url) }
                    Button("Move to Trash", role: .destructive) {
                        Task { @MainActor in
                            await navigator.trash(url: url, projectURL: projectURL)
                        }
                    }
                }
        }
    }

    private func folderURL(path: String) -> URL {
        var url =
            projectURL
            .appendingPathComponent(ClaudeProjectFiles.skillsRelativePath, isDirectory: true)
            .appendingPathComponent(skillName, isDirectory: true)
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !trimmed.isEmpty {
            for component in trimmed.split(separator: "/") {
                url = url.appendingPathComponent(String(component), isDirectory: true)
            }
        }
        return url
    }
}
