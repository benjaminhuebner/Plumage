import AppKit
import SwiftUI

// The sidebar's "Pinned" section: a flat, ordered list of pinned files between
// the Issues block and the Files tree. Emits List rows directly (header +
// one PinnedRow per pin) and renders nothing when the pin set is empty, so the
// whole section disappears in the empty state.
struct PinnedSectionView: View {
    let model: PinnedFilesModel
    let projectURL: URL

    var body: some View {
        if !model.pinned.isEmpty {
            SidebarSectionHeader(title: "Pinned")
            ForEach(model.pinned, id: \.self) { relativePath in
                PinnedRow(relativePath: relativePath, projectURL: projectURL)
            }
        }
    }
}

// One pinned file. Shares the `NavigatorRoute.projectFile` tag with its tree
// row, so selection + detail dispatch come for free from the enclosing
// `List(selection:)`. A hover-revealed filled-pin button unpins; the context
// menu mirrors it and adds "Show in Finder".
struct PinnedRow: View {
    let relativePath: String
    let projectURL: URL

    @Environment(PinnedFilesModel.self) private var pinModel
    // Read the navigator directly so this row is invalidated the moment its
    // file's empty-state flips, without relying on the List to re-diff it.
    @Environment(NavigatorModel.self) private var navigator
    @State private var hovering = false

    private var url: URL { projectURL.appendingPathComponent(relativePath) }

    private var isEmptyContextFile: Bool {
        navigator.emptyContextFilePaths.contains(relativePath)
    }

    // Carries the warning because the icon is `accessibilityHidden` — otherwise
    // VoiceOver stops twice on a warned row (once on the name, once on the icon).
    private var accessibilityLabel: String {
        isEmptyContextFile
            ? "\(url.lastPathComponent), \(EmptyContextWarningIcon.fileMessage(url.lastPathComponent))"
            : url.lastPathComponent
    }

    var body: some View {
        HStack(spacing: 6) {
            // Match the leading inset of tree file rows (past the chevron slot)
            // so PINNED and FILES rows line up visually.
            Color.clear.frame(width: 14)
            Image(nsImage: WorkspaceIconCache.icon(forPath: url.path))
                .resizable()
                .frame(width: 16, height: 16)
            Text(url.lastPathComponent)
                .lineLimit(1)
                .truncationMode(.middle)
                .accessibilityLabel(accessibilityLabel)
            if isEmptyContextFile {
                EmptyContextWarningIcon(
                    message: EmptyContextWarningIcon.fileMessage(url.lastPathComponent))
            }
            Spacer(minLength: 0)
            unpinButton
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .tag(NavigatorRoute.projectFile(relativePath: relativePath))
        .contextMenu {
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            Button("Unpin") {
                pinModel.unpin(relativePath: relativePath, projectURL: projectURL)
            }
        }
    }

    @ViewBuilder
    private var unpinButton: some View {
        Button {
            pinModel.unpin(relativePath: relativePath, projectURL: projectURL)
        } label: {
            Image(systemName: "pin.fill")
                .imageScale(.small)
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Unpin")
        .accessibilityLabel("Unpin")
        // Opacity, not conditional existence: a hover-only button never
        // exists for VoiceOver/keyboard users.
        .opacity(hovering ? 1 : 0)
    }
}
