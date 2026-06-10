import AppKit
import SwiftUI

struct NavigatorFileRow: View {
    let node: FileNode
    let projectURL: URL
    let navigator: NavigatorModel
    let pinModel: PinnedFilesModel

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            icon
            if navigator.renaming?.url == node.url {
                FinderFileTreeRenameField(
                    text: navigator.renameNameBinding,
                    placeholder: node.name,
                    onCommit: commitRename,
                    onCancel: { navigator.cancelRename() })
            } else {
                Text(node.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .accessibilityLabel(accessibilityLabel)
                warningIcon
                Spacer(minLength: 0)
                if !node.isDirectory {
                    pinButton
                }
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    private var icon: some View {
        Image(
            nsImage: WorkspaceIconCache.icon(
                forPath: node.url.path, isDirectory: node.isDirectory)
        )
        .resizable()
        .frame(width: 16, height: 16)
    }

    private var isEmptyContextFile: Bool {
        navigator.emptyContextFilePaths.contains(node.relativePath)
    }

    // Same warning surfaced on a collapsed folder that hides an empty context
    // file, so the signal isn't lost when the row is folded away. Once expanded
    // the child rows carry their own icons, so this hides to avoid doubling up.
    private var isCollapsedFolderHidingEmptyContext: Bool {
        node.isDirectory
            && !navigator.fileTreeExpansion.contains(node.relativePath)
            && navigator.foldersHidingEmptyContextFile.contains(node.relativePath)
    }

    @ViewBuilder
    private var warningIcon: some View {
        if node.isDirectory {
            if isCollapsedFolderHidingEmptyContext {
                EmptyContextWarningIcon(message: EmptyContextWarningIcon.folderMessage)
            }
        } else if isEmptyContextFile {
            EmptyContextWarningIcon(message: EmptyContextWarningIcon.fileMessage(node.name))
        }
    }

    // Carries the warning because the icon is `accessibilityHidden` — otherwise
    // VoiceOver stops twice on a warned row (once on the name, once on the icon).
    private var accessibilityLabel: String {
        if node.isDirectory {
            return isCollapsedFolderHidingEmptyContext
                ? "\(node.name), \(EmptyContextWarningIcon.folderMessage)"
                : node.name
        }
        return isEmptyContextFile
            ? "\(node.name), \(EmptyContextWarningIcon.fileMessage(node.name))"
            : node.name
    }

    @ViewBuilder
    private var pinButton: some View {
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
        .accessibilityLabel(isPinned ? "Unpin" : "Pin")
        // Opacity, not conditional existence: a hover-only button never
        // exists for VoiceOver/keyboard users.
        .opacity(hovering ? 1 : 0)
    }

    private func commitRename() {
        Task { @MainActor in
            _ = await navigator.commitRename(projectURL: projectURL)
        }
    }
}
