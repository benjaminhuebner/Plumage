import SwiftUI

// Second Settings tab: lets the user edit the bundled scaffold assets that
// Plumage writes into every new and migrated project, toggle which hooks/skills/
// agents get scaffolded, and author agents — all persisted to a per-user override
// store so edits survive app updates. The catalog, selection, override read/write
// and live preview are owned by `TemplatesSettingsModel`.
struct TemplatesSettingsTab: View {
    @State private var model = TemplatesSettingsModel()

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 0) {
            catalogList
                .frame(width: 240)
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: model.selection) { _, _ in
            if let entry = model.selectedEntry {
                model.beginEditing(entry)
            }
        }
    }

    private var catalogList: some View {
        @Bindable var model = model
        return List(selection: $model.selection) {
            ForEach(model.groupedEntries, id: \.category.id) { group in
                Section(group.category.title) {
                    ForEach(group.entries) { entry in
                        catalogRow(entry)
                            .tag(entry.id)
                    }
                }
            }
        }
    }

    private func catalogRow(_ entry: TemplatesSettingsModel.CatalogEntry) -> some View {
        HStack(spacing: 6) {
            Image(systemName: model.isOverridden(entry) ? "circle.fill" : "circle")
                .font(.system(size: 7))
                .foregroundStyle(model.isOverridden(entry) ? Color.accentColor : .secondary)
            Text(entry.label)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let url = model.editingFileURL, let entry = model.selectedEntry {
            VStack(spacing: 0) {
                detailHeader(entry)
                Divider()
                DocEditorView(fileURL: url, displayName: entry.label)
                    .id(url)
            }
        } else {
            ContentUnavailableView(
                "Select a Template",
                systemImage: "doc.text",
                description: Text("Edit any bundled asset; your copy is used for every new project."))
        }
    }

    private func detailHeader(_ entry: TemplatesSettingsModel.CatalogEntry) -> some View {
        HStack {
            Text(entry.label)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if model.isOverridden(entry) {
                Button("Reset to Default") {
                    model.resetToDefault(entry)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
