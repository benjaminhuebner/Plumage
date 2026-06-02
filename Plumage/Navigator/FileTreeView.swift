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
    @Environment(PinnedFilesModel.self) private var pinModel
    @State private var expanded: Bool = false
    @State private var isDropTargeted: Bool = false
    @State private var hovering: Bool = false

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
                    folderWarning
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, CGFloat(depth * 16))
            .dropHighlight(isDropTargeted)
            .contextMenu { folderMenu }
            .draggable(FileTreeDragPayload(url: node.url))
            .dropDestination(for: DroppableTreeItem.self) { items, _ in
                return handleDrop(items)
            } isTargeted: { targeted in
                isDropTargeted = targeted
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
                emptyContextWarning
                Spacer(minLength: 0)
                pinButton
            }
            .contentShape(Rectangle())
            .padding(.leading, CGFloat(depth * 16))
            .dropHighlight(isDropTargeted)
            .onHover { hovering = $0 }
            .tag(NavigatorRoute.projectFile(relativePath: node.relativePath))
            .contextMenu { fileMenu }
            .draggable(FileTreeDragPayload(url: node.url))
            .dropDestination(for: DroppableTreeItem.self) { items, _ in
                return handleDrop(items)
            } isTargeted: { targeted in
                isDropTargeted = targeted
            }
        }
    }

    // Resolves the drop folder (folder row → itself, file row → parent;
    // rejects outside the whitelist), then dispatches by item kind: Finder
    // URLs copy, internal nodes move. Mixed payloads are split.
    private func handleDrop(_ items: [DroppableTreeItem]) -> Bool {
        guard !items.isEmpty else { return false }
        guard
            let target = FileTreeDropResolver.resolveDropTarget(
                for: node, projectURL: projectURL)
        else {
            Task { @MainActor in
                navigator.showBanner("Drop target outside managed area")
            }
            return false
        }
        var finderURLs: [URL] = []
        var moveSources: [URL] = []
        for item in items {
            switch item {
            case .finderURL(let url): finderURLs.append(url)
            case .internalNode(let payload): moveSources.append(payload.url)
            }
        }
        Task { @MainActor in
            if !moveSources.isEmpty {
                await navigator.handleInternalMove(
                    sources: moveSources, targetFolder: target, projectURL: projectURL)
            }
            if !finderURLs.isEmpty {
                await navigator.handleFinderDrop(
                    urls: finderURLs, targetFolder: target, projectURL: projectURL)
            }
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
        // NSWorkspace's icon for the folder — generic folder glyph, consistent
        // across `.claude/` and any nested folder. Files get the type-specific
        // icon via the same call.
        Image(nsImage: NSWorkspace.shared.icon(forFile: node.url.path))
            .resizable()
            .frame(width: 16, height: 16)
    }

    private var fileIcon: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: node.url.path))
            .resizable()
            .frame(width: 16, height: 16)
    }

    // Always-visible warning on an effectively-empty foundation context file
    // (CLAUDE.md / PROJECT.md). Unlike the pin button this is not hover-gated —
    // its job is to catch the eye that the agent starts with no context.
    @ViewBuilder
    private var emptyContextWarning: some View {
        if node.isEmptyContextFile {
            EmptyContextWarningIcon(message: EmptyContextWarningIcon.fileMessage(node.name))
        }
    }

    // Same warning surfaced on a collapsed folder that hides an empty context
    // file, so the signal isn't lost when the row is folded away. Once expanded
    // the child rows carry their own icons, so this hides to avoid doubling up.
    @ViewBuilder
    private var folderWarning: some View {
        if !expanded && node.containsEmptyContextFileDescendant {
            EmptyContextWarningIcon(message: EmptyContextWarningIcon.folderMessage)
        }
    }

    // Hover-revealed pin toggle, files only. Filled glyph + "Unpin" when the
    // file is already pinned. Plain button so the tap toggles the pin instead
    // of selecting the row.
    @ViewBuilder
    private var pinButton: some View {
        if hovering {
            let isPinned = pinModel.contains(node.relativePath)
            Button {
                pinModel.toggle(relativePath: node.relativePath, projectURL: projectURL)
            } label: {
                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isPinned ? "Unpin" : "Pin")
        }
    }

    @ViewBuilder
    private var folderMenu: some View {
        Button("New File") {
            navigator.beginPendingCreate(parent: node.url, isFolder: false)
            expanded = true
        }
        Button("New Folder") {
            navigator.beginPendingCreate(parent: node.url, isFolder: true)
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

extension View {
    // Accent-tinted rounded background drawn while a drag hovers over a drop
    // target, so the user sees exactly which folder will receive the drop.
    @ViewBuilder
    fileprivate func dropHighlight(_ active: Bool) -> some View {
        background {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.accentColor.opacity(active ? 0.20 : 0))
        }
    }
}
