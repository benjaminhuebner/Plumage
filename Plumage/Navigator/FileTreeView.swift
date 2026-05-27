import AppKit
import SwiftUI

// Recursive renderer for the unified "Files" sidebar section. Consumes
// `NavigatorModel.rootNodes` and emits one `FileTreeRow` per tree level.
// Selection state lives at the enclosing `List(selection:)`; rows tag
// themselves with `NavigatorRoute.projectFile(...)`.
struct FileTreeView: View {
    let nodes: [FileNode]
    let projectURL: URL

    var body: some View {
        ForEach(nodes) { node in
            FileTreeRow(node: node, projectURL: projectURL, depth: 0)
        }
    }
}

// One row in the tree. Folders render as a hand-rolled chevron+button
// disclosure with their children below; files render as an icon+label row
// tagged with the projectFile route. The hand-rolled pattern is required —
// see notes.md #00028: `DisclosureGroup` in `List(.sidebar)` loses its
// chevron and click-toggle whenever the label isn't a stock `Label`.
struct FileTreeRow: View {
    let node: FileNode
    let projectURL: URL
    let depth: Int

    @Environment(NavigatorModel.self) private var navigator
    @State private var expanded: Bool = false

    var body: some View {
        Group {
            if node.isDirectory {
                folderRow
                if expanded, let children = node.children {
                    ForEach(children) { child in
                        FileTreeRow(node: child, projectURL: projectURL, depth: depth + 1)
                    }
                    if let pending = navigator.pendingCreate,
                        case .treeNode(let parent, let isFolder) = pending.section,
                        parent.standardizedFileURL.path == node.url.standardizedFileURL.path
                    {
                        InlineCreateRow(
                            projectURL: projectURL,
                            icon: isFolder ? "folder" : "doc"
                        )
                        .padding(.leading, CGFloat((depth + 1) * 16))
                    }
                }
            } else {
                fileRow
            }
        }
    }

    @ViewBuilder
    private var folderRow: some View {
        if navigator.renaming?.url == node.url {
            HStack(spacing: 6) {
                chevron
                StemSelectingTextField(
                    text: renameBinding,
                    placeholder: node.name,
                    onSubmit: commitRename,
                    onCancel: { navigator.cancelRename() },
                    onBlur: commitRename
                )
            }
            .padding(.leading, CGFloat(depth * 16))
        } else {
            Button {
                expanded.toggle()
            } label: {
                HStack(spacing: 6) {
                    chevron
                    folderIcon
                    Text(node.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
            .padding(.leading, CGFloat(depth * 16))
            .contextMenu { folderMenu }
            .draggable(FileTreeDragPayload(url: node.url))
            .dropDestination(for: URL.self) { urls, _ in
                return handleFinderDrop(urls)
            }
            .dropDestination(for: FileTreeDragPayload.self) { payloads, _ in
                return handleInternalMove(payloads)
            }
        }
    }

    @ViewBuilder
    private var fileRow: some View {
        if navigator.renaming?.url == node.url {
            HStack(spacing: 6) {
                Color.clear.frame(width: 14)
                StemSelectingTextField(
                    text: renameBinding,
                    placeholder: node.name,
                    onSubmit: commitRename,
                    onCancel: { navigator.cancelRename() },
                    onBlur: commitRename
                )
            }
            .padding(.leading, CGFloat(depth * 16))
            .tag(NavigatorRoute.projectFile(relativePath: node.relativePath))
        } else {
            HStack(spacing: 6) {
                Color.clear.frame(width: 14)
                fileIcon
                Text(node.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.leading, CGFloat(depth * 16))
            .tag(NavigatorRoute.projectFile(relativePath: node.relativePath))
            .contextMenu { fileMenu }
            .draggable(FileTreeDragPayload(url: node.url))
            .dropDestination(for: URL.self) { urls, _ in
                return handleFinderDrop(urls)
            }
            .dropDestination(for: FileTreeDragPayload.self) { payloads, _ in
                return handleInternalMove(payloads)
            }
        }
    }

    private func handleInternalMove(_ payloads: [FileTreeDragPayload]) -> Bool {
        guard !payloads.isEmpty else { return false }
        guard
            let target = FileTreeDropResolver.resolveDropTarget(
                for: node, projectURL: projectURL)
        else {
            Task { @MainActor in
                navigator.showBanner("Drop target outside managed area")
            }
            return false
        }
        let sources = payloads.map(\.url)
        Task { @MainActor in
            await navigator.handleInternalMove(
                sources: sources, targetFolder: target, projectURL: projectURL)
        }
        return true
    }

    private func handleFinderDrop(_ urls: [URL]) -> Bool {
        guard !urls.isEmpty else { return false }
        guard
            let target = FileTreeDropResolver.resolveDropTarget(
                for: node, projectURL: projectURL)
        else {
            Task { @MainActor in
                navigator.showBanner("Drop target outside managed area")
            }
            return false
        }
        Task { @MainActor in
            await navigator.handleFinderDrop(
                urls: urls, targetFolder: target, projectURL: projectURL)
        }
        return true
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 10, weight: .semibold))
            .rotationEffect(.degrees(expanded ? 90 : 0))
            .foregroundStyle(.secondary)
            .frame(width: 14, alignment: .center)
    }

    private var folderIcon: some View {
        // For folders we use the system folder icon — NSWorkspace's
        // generic-folder icon — keeping the row visually consistent across
        // .claude/, .plumage/, and any nested folder. Real files get the
        // type-specific icon via NSWorkspace.shared.icon(forFile:).
        Image(nsImage: NSWorkspace.shared.icon(forFile: node.url.path))
            .resizable()
            .frame(width: 16, height: 16)
    }

    private var fileIcon: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: node.url.path))
            .resizable()
            .frame(width: 16, height: 16)
    }

    @ViewBuilder
    private var folderMenu: some View {
        Button("New File") {
            navigator.beginPendingCreate(.treeNode(parent: node.url, isFolder: false))
            expanded = true
        }
        Button("New Folder") {
            navigator.beginPendingCreate(.treeNode(parent: node.url, isFolder: true))
            expanded = true
        }
        Divider()
        Button("Show in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([node.url])
        }
        Button("Rename") { navigator.beginRename(url: node.url) }
        Button("Move to Trash", role: .destructive) {
            Task { @MainActor in
                await navigator.trash(url: node.url, projectURL: projectURL)
            }
        }
    }

    @ViewBuilder
    private var fileMenu: some View {
        Button("Show in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([node.url])
        }
        Button("Rename") { navigator.beginRename(url: node.url) }
        Button("Move to Trash", role: .destructive) {
            Task { @MainActor in
                await navigator.trash(url: node.url, projectURL: projectURL)
            }
        }
    }

    private var renameBinding: Binding<String> {
        Binding(
            get: { navigator.renaming?.name ?? node.name },
            set: { newValue in
                guard navigator.renaming != nil else { return }
                navigator.renaming?.name = newValue
            }
        )
    }

    private func commitRename() {
        Task { @MainActor in
            _ = await navigator.commitRename(projectURL: projectURL)
        }
    }
}
