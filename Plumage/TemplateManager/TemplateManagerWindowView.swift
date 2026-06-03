import SwiftUI

// App-global window for editing the template catalog. Three columns: left = the
// three tiers (Base / Shared Components / categories → templates), middle = the
// selected item's files + memberships, right = an editable view of the selected
// file that saves to the per-user override store.
struct TemplateManagerWindowView: View {
    @State private var model = TemplateManagerModel()

    var body: some View {
        NavigationSplitView {
            TemplateCatalogSidebar(model: model)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } content: {
            TemplateContentColumn(model: model)
                .navigationSplitViewColumnWidth(min: 260, ideal: 320)
        } detail: {
            TemplateEditorColumn(model: model)
        }
        .frame(minWidth: 820, minHeight: 520)
        .task { await model.load() }
        .onChange(of: model.selection) { model.refreshContent() }
        .onChange(of: model.selectedFile) { _, file in model.beginEditing(file) }
    }
}
