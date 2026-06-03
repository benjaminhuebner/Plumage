import SwiftUI

// Left column: the three tiers in order — Base, then a Shared Components group,
// then each category with its templates. Selection-driven via the model. Category
// headers are editable: a toolbar "+" adds one, a context menu renames / reorders /
// deletes, and an inline `TextField` commits on Enter/blur (Escape cancels).
struct TemplateCatalogSidebar: View {
    @Bindable var model: TemplateManagerModel

    var body: some View {
        catalogList
            .navigationTitle("Templates")
            .toolbar { toolbar }
            .modifier(TemplateSidebarSheets(model: model))
            .modifier(TemplateSidebarDialogs(model: model))
            .overlay(alignment: .bottom) { errorBanner }
    }

    private var catalogList: some View {
        List(selection: $model.selection) {
            Label(model.catalog.base.name, systemImage: "square.grid.2x2")
                .tag(TemplateCatalogItem.base)

            Section("Shared Components") {
                ForEach(model.catalog.sortedSharedComponents) { component in
                    Label(component.name, systemImage: component.kind.sfSymbolName)
                        .tag(TemplateCatalogItem.sharedComponent(component.id))
                        .contextMenu { sharedComponentMenu(component) }
                }
            }

            ForEach(model.catalog.sortedCategories) { category in
                categorySection(category)
            }
        }
    }

    private func categorySection(_ category: TemplateCategory) -> some View {
        Section {
            ForEach(model.catalog.templates(inCategory: category.id)) { template in
                templateRow(template)
            }
        } header: {
            categoryHeader(category)
                .dropDestination(for: TemplateDragPayload.self) { payloads, _ in
                    for payload in payloads {
                        model.moveTemplate(id: payload.templateID, toCategory: category.id)
                    }
                    return !payloads.isEmpty
                }
        }
    }

    private func templateRow(_ template: TemplateDescriptor) -> some View {
        Label {
            Text(template.name)
        } icon: {
            TemplateImageView(
                image: template.image,
                resolve: { model.imageFileURL(forRelative: $0) }
            )
            .frame(width: 18, height: 18)
        }
        .tag(TemplateCatalogItem.template(template.id))
        .draggable(TemplateDragPayload(templateID: template.id))
        .contextMenu { templateMenu(template) }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem {
            Menu {
                Button("New Category", systemImage: "folder.badge.plus") {
                    model.beginAddCategory()
                }
                Button("New Template", systemImage: "doc.badge.plus") {
                    model.isAddingTemplate = true
                }
                .disabled(model.catalog.categories.isEmpty)
                Button("New Shared Component", systemImage: "puzzlepiece") {
                    model.isAddingSharedComponent = true
                }
            } label: {
                Label("Add", systemImage: "plus")
            }
        }
        ToolbarItem {
            Menu {
                if !model.restorableItems.isEmpty {
                    Menu("Restore Item") {
                        ForEach(model.restorableItems) { item in
                            Button(item.menuLabel) { model.restore(item) }
                        }
                    }
                    Divider()
                }
                Button("Restore Defaults…", role: .destructive) {
                    model.isConfirmingRestoreAll = true
                }
            } label: {
                Label("Restore", systemImage: "arrow.uturn.backward")
            }
        }
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
    private func sharedComponentMenu(_ component: SharedComponent) -> some View {
        Button("Delete", systemImage: "trash", role: .destructive) {
            model.requestDeleteSharedComponent(id: component.id)
        }
    }

    @ViewBuilder
    private func templateMenu(_ template: TemplateDescriptor) -> some View {
        let others = model.catalog.sortedCategories.filter { $0.id != template.categoryID }
        Menu("Move to…", systemImage: "folder") {
            ForEach(others) { destination in
                Button(destination.name) {
                    model.moveTemplate(id: template.id, toCategory: destination.id)
                }
            }
        }
        .disabled(others.isEmpty)
        Button("Move Up", systemImage: "arrow.up") {
            model.moveTemplate(id: template.id, withinCategoryBy: -1)
        }
        Button("Move Down", systemImage: "arrow.down") {
            model.moveTemplate(id: template.id, withinCategoryBy: 1)
        }
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) {
            model.deleteTemplate(id: template.id)
        }
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

// Authoring sheets, split into a modifier so the sidebar body type-checks fast.
private struct TemplateSidebarSheets: ViewModifier {
    @Bindable var model: TemplateManagerModel

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $model.isAddingTemplate) {
                NewTemplateSheet(catalog: model.catalog) { model.addTemplate($0) }
            }
            .sheet(isPresented: $model.isAddingSharedComponent) {
                NewSharedComponentSheet(catalog: model.catalog) { model.addSharedComponent($0) }
            }
    }
}

// Destructive confirmations (component / template delete, restore-all), split out
// for the same reason.
private struct TemplateSidebarDialogs: ViewModifier {
    @Bindable var model: TemplateManagerModel

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                model.pendingComponentDeletion.map { "Delete “\($0.name)”?" } ?? "",
                isPresented: Binding(
                    get: { model.pendingComponentDeletion != nil },
                    set: { if !$0 { model.pendingComponentDeletion = nil } }),
                titleVisibility: .visible,
                presenting: model.pendingComponentDeletion
            ) { _ in
                Button("Delete", role: .destructive) { model.confirmDeleteSharedComponent() }
                Button("Cancel", role: .cancel) { model.pendingComponentDeletion = nil }
            } message: { component in
                let names = model.catalog.templates(memberOf: component.id).map(\.name)
                Text(
                    names.isEmpty
                        ? "No templates include this component."
                        : "These templates will stop including it: \(names.joined(separator: ", ")).")
            }
            .confirmationDialog(
                model.pendingTemplateDeletion.map { "Delete “\($0.name)”?" } ?? "",
                isPresented: Binding(
                    get: { model.pendingTemplateDeletion != nil },
                    set: { if !$0 { model.pendingTemplateDeletion = nil } }),
                titleVisibility: .visible,
                presenting: model.pendingTemplateDeletion
            ) { _ in
                Button("Delete", role: .destructive) { model.confirmDeleteTemplate() }
                Button("Cancel", role: .cancel) { model.pendingTemplateDeletion = nil }
            } message: { _ in
                Text("This custom template and its files will be deleted. This can't be undone.")
            }
            .confirmationDialog(
                "Restore default templates?",
                isPresented: $model.isConfirmingRestoreAll,
                titleVisibility: .visible
            ) {
                Button("Restore Defaults", role: .destructive) { model.restoreAllDefaults() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "Categories, templates and shared components return to the bundled defaults. "
                        + "Custom items are removed. Your file edits are kept.")
            }
    }
}
