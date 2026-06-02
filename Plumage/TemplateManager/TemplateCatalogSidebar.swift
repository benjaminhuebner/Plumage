import SwiftUI

// Left column: the three tiers in order — Base, then a Shared Components group,
// then each category with its templates. Selection-driven via the model.
struct TemplateCatalogSidebar: View {
    @Bindable var model: TemplateManagerModel

    var body: some View {
        List(selection: $model.selection) {
            Label(model.catalog.base.name, systemImage: "square.grid.2x2")
                .tag(TemplateCatalogItem.base)

            Section("Shared Components") {
                ForEach(model.catalog.sortedSharedComponents) { component in
                    Label(component.name, systemImage: component.kind.sfSymbolName)
                        .tag(TemplateCatalogItem.sharedComponent(component.id))
                }
            }

            ForEach(model.catalog.sortedCategories) { category in
                Section(category.name) {
                    ForEach(model.catalog.templates(inCategory: category.id)) { template in
                        Label(template.name, systemImage: template.image.sfSymbolName)
                            .tag(TemplateCatalogItem.template(template.id))
                    }
                }
            }
        }
        .navigationTitle("Templates")
    }
}
