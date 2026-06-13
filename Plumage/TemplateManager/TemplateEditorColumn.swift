import SwiftUI

// Right column: an editable view of the selected file. The editor saves to the
// override slot (`model.editingFileURL`) while seeding its buffer from the bundled
// fallback (`model.editingFallbackURL`), so browsing a file writes nothing and only
// a real edit materializes an override — the same write model the Templates settings
// tab uses. The header offers Reset to Default for a bundled-backed file (the moment
// it is edited) or Delete for a user-authored one. A directory or empty selection
// shows a placeholder.
struct TemplateEditorColumn: View {
    @Bindable var model: TemplateManagerModel

    var body: some View {
        Group {
            if let fileURL = model.editingFileURL, let file = model.selectedFile {
                VStack(spacing: 0) {
                    header(file)
                    Divider()
                    DocEditorView(
                        fileURL: fileURL,
                        displayName: file.name,
                        fallbackURL: model.editingFallbackURL,
                        onSave: { model.notifySaved(relativePath: file.relativePath) },
                        onDirtyChange: { model.setEditorDirty($0) },
                        resetToken: model.editorResetToken,
                        onResetComplete: { model.finishReset() }
                    )
                    // Stable per file so saving (which leaves the override slot URL
                    // unchanged) never tears down the editor; the reload token bumps
                    // after a reset to remount and reseed from the bundled original.
                    .id("\(fileURL.path)#\(model.editorReloadToken)")
                }
            } else if let preview = model.editingPreviewText, let file = model.selectedFile {
                VStack(spacing: 0) {
                    previewHeader(file)
                    Divider()
                    ScrollView {
                        Text(preview)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                    }
                }
            } else if let folder = model.selectedFile, folder.isDirectory {
                ContentUnavailableView {
                    Label(folder.name, systemImage: "folder")
                } description: {
                    Text(folderItemCountText(folder))
                }
            } else {
                ContentUnavailableView("No File Selected", systemImage: "doc.text")
            }
        }
    }

    private func folderItemCountText(_ folder: FileNode) -> String {
        let count = folder.children?.count ?? 0
        return count == 1 ? "1 item" : "\(count) items"
    }

    private func previewHeader(_ file: FileNode) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(file.name)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text("Generated · read-only")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text("To edit settings.json, select Base in the sidebar.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func header(_ file: FileNode) -> some View {
        HStack {
            Text(file.name)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if model.isUserAuthored(file) {
                Button("Delete", role: .destructive) { model.requestDelete(file) }
            } else if model.isOverridden(file) || model.isEditorDirty {
                // Reset appears the moment the bundled file is edited (dirty), not
                // only after a save has created an override on disk.
                Button("Reset to Default") { model.resetToDefault(file) }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
