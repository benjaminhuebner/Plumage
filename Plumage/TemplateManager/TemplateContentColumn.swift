import SwiftUI

// Middle column: the selected item's files (selectable, drive the right column)
// plus a read-only membership section. A ● marks a file whose override diverges
// from the bundled original.
struct TemplateContentColumn: View {
    @Bindable var model: TemplateManagerModel

    var body: some View {
        List(selection: $model.selectedFile) {
            if !model.contentFiles.isEmpty {
                Section("Files") {
                    ForEach(model.contentFiles) { node in
                        fileRow(node)
                            .tag(node)
                    }
                }
            }

            if let membership = model.membership {
                Section(membership.title) {
                    if membership.names.isEmpty {
                        Text("None")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(membership.names, id: \.self) { name in
                            Label(name, systemImage: "puzzlepiece")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if model.contentFiles.isEmpty && model.membership == nil {
                Text("No files")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(model.selectionTitle)
    }

    private func fileRow(_ node: FileNode) -> some View {
        HStack(spacing: 6) {
            Label(node.name, systemImage: "doc.text")
            Spacer(minLength: 0)
            if model.isOverridden(node) {
                Image(systemName: "circle.fill")
                    .font(.system(size: 7))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityLabel("Overridden")
            }
        }
    }
}
