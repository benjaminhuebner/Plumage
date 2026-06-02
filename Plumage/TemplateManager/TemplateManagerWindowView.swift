import SwiftUI

// Read-only, app-global window for browsing the template catalog. Three columns:
// left = the three tiers (Base / Shared Components / categories → templates),
// middle = the selected item's files + memberships, right = read-only file view.
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
            TemplateCodeColumn(model: model)
        }
        .frame(minWidth: 820, minHeight: 520)
        .task { await model.load() }
    }
}
