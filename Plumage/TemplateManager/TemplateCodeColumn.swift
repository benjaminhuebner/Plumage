import SwiftUI

// Right column: a strictly read-only view of the selected file's content.
//
// Deliberately NOT DocEditorView (the spec's suggested reuse): that component is
// an autosaving editor with no read-only mode — wiring it here would make the
// bundled/override scaffold assets editable and write edits back on teardown,
// which is the editing explicitly deferred to #00068. A selectable monospaced
// text view is the honest read-only browser this issue calls for.
struct TemplateCodeColumn: View {
    let file: FileNode?

    @State private var content: String?
    @State private var loadError: String?

    var body: some View {
        Group {
            if let file {
                fileBody(file)
            } else {
                ContentUnavailableView("No File Selected", systemImage: "doc.text")
            }
        }
        .navigationTitle(file?.name ?? "")
        .task(id: file) { await load(file) }
    }

    @ViewBuilder
    private func fileBody(_ file: FileNode) -> some View {
        if let content {
            ScrollView([.vertical, .horizontal]) {
                Text(content.isEmpty ? "(empty file)" : content)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .foregroundStyle(content.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
        } else if let loadError {
            ContentUnavailableView(
                "Can't Show File", systemImage: "doc.questionmark",
                description: Text(loadError))
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func load(_ file: FileNode?) async {
        content = nil
        loadError = nil
        guard let file else { return }
        let url = file.url
        let result = await Task.detached(priority: .userInitiated) {
            Result { try String(contentsOf: url, encoding: .utf8) }
        }.value
        switch result {
        case .success(let text): content = text
        case .failure(let error): loadError = error.localizedDescription
        }
    }
}
