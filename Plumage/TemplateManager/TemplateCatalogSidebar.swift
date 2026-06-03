import SwiftUI

// Left column: the three tiers in order — Base, then a Shared Components group,
// then each category with its templates. Selection-driven via the model. Category
// headers are editable: a toolbar "+" adds one, a context menu renames / reorders /
// deletes, and an inline `TextField` commits on Enter/blur (Escape cancels).
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
                Section {
                    ForEach(model.catalog.templates(inCategory: category.id)) { template in
                        Label(template.name, systemImage: template.image.sfSymbolName)
                            .tag(TemplateCatalogItem.template(template.id))
                    }
                } header: {
                    categoryHeader(category)
                }
            }
        }
        .navigationTitle("Templates")
        .toolbar {
            ToolbarItem {
                Menu {
                    Button("New Category", systemImage: "folder.badge.plus") {
                        model.beginAddCategory()
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
        }
        .overlay(alignment: .bottom) { errorBanner }
    }

    @ViewBuilder
    private func categoryHeader(_ category: TemplateCategory) -> some View {
        if model.categoryRename?.id == category.id {
            StemSelectingTextField(
                text: renameBinding(for: category.id),
                placeholder: category.name,
                onSubmit: { model.commitCategoryRename() },
                onCancel: { model.cancelCategoryRename() },
                onBlur: { model.commitCategoryRename() }
            )
        } else {
            Text(category.name)
                .contextMenu { categoryMenu(category) }
        }
    }

    @ViewBuilder
    private func categoryMenu(_ category: TemplateCategory) -> some View {
        Button("Rename", systemImage: "pencil") {
            model.beginRenameCategory(id: category.id)
        }
        Button("Move Up", systemImage: "arrow.up") {
            model.moveCategory(id: category.id, by: -1)
        }
        Button("Move Down", systemImage: "arrow.down") {
            model.moveCategory(id: category.id, by: 1)
        }
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) {
            model.deleteCategory(id: category.id)
        }
        .disabled(!model.canDeleteCategory(id: category.id))
    }

    @ViewBuilder
    private var errorBanner: some View {
        if let error = model.structuralError {
            Text(error)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(10)
                .frame(maxWidth: .infinity)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                .padding(8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func renameBinding(for id: String) -> Binding<String> {
        Binding(
            get: { model.categoryRename?.name ?? "" },
            set: { newValue in
                guard model.categoryRename != nil else { return }
                model.categoryRename?.name = newValue
            }
        )
    }
}
