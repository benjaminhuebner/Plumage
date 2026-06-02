import SwiftUI

// Middle column: the selected item's files (selectable, drive the right column)
// plus a read-only membership section. Read-only browse — no add/edit/drag.
struct TemplateContentColumn: View {
    @Bindable var model: TemplateManagerModel

    var body: some View {
        List(selection: $model.selectedFile) {
            if !model.contentFiles.isEmpty {
                Section("Files") {
                    ForEach(model.contentFiles) { node in
                        Label(node.name, systemImage: "doc.text")
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
}
