import SwiftUI

// Right column: an editable view of the selected file. The editor saves to the
// override slot (`model.editingFileURL`) while seeding its buffer from the bundled
// fallback (`model.editingFallbackURL`), so browsing a file writes nothing and only
// a real edit materializes an override — the same write model the Templates settings
// tab uses. A directory selection or empty state shows a placeholder.
struct TemplateEditorColumn: View {
    @Bindable var model: TemplateManagerModel

    var body: some View {
        Group {
            if let fileURL = model.editingFileURL {
                DocEditorView(
                    fileURL: fileURL,
                    displayName: model.selectedFile?.name,
                    fallbackURL: model.editingFallbackURL
                )
                // Stable per file: the override slot URL does not change when the
                // override materializes on save, so saving never tears down the
                // editor; switching files swaps it in with a fresh model.
                .id(fileURL)
            } else {
                ContentUnavailableView("No File Selected", systemImage: "doc.text")
            }
        }
    }
}
