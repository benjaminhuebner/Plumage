import AppKit
import SwiftUI

// Left column: the three tiers in order — Base, then a Shared Components group,
// then each category with its templates. A custom scroll surface (not `List`)
// so the drag pipeline can own row geometry, gaps and the floating row.
struct TemplateCatalogSidebar: View {
    @Bindable var model: TemplateManagerModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drag = SidebarDragController()
    @State private var frames = SidebarFrameRegistry()
    @State private var autoScroll = VerticalAutoScroller()
    @State private var sidebarFrame: CGRect = .zero

    var body: some View {
        catalogList
            .navigationTitle("Templates")
            .toolbar { toolbar }
            .modifier(TemplateSidebarSheets(model: model))
            .modifier(TemplateSidebarDialogs(model: model))
            .overlay(alignment: .bottom) { errorBanner }
    }

    private var catalogList: some View {
        @Bindable var autoScroll = autoScroll

        return ScrollViewReader { proxy in
            ScrollView {
                // Plain VStack, not LazyVStack: catalogs are small, and eager rows
                // keep every row frame measured for the drop resolver and make
                // programmatic scrollTo(selection) reliable.
                VStack(alignment: .leading, spacing: TemplateSidebarLayout.rowSpacing) {
                    baseRow
                    sectionHeader("Shared Components")
                        .reportContainerFrame(
                            SidebarContainer.componentsHeader, registry: frames,
                            coordinateSpace: TemplateSidebarLayout.coordinateSpace)
                    let componentMarkers = componentPlaceholderMarkers()
                    ForEach(model.catalog.sortedSharedComponents) { component in
                        if TemplateCatalogItem.sharedComponent(component.id).id
                            == componentMarkers.beforeID
                        {
                            placeholderSlot
                        }
                        sharedComponentRow(component)
                    }
                    if componentMarkers.atEnd {
                        placeholderSlot
                    }

                    // Hairline marking the structural boundary: everything above (Base +
                    // Shared Components) is protected — not a category, so not deletable —
                    // while the categories below are.
                    Divider()
                        .padding(.horizontal, 4)
                        .padding(.vertical, 6)
                        .reportContainerFrame(
                            SidebarContainer.divider, registry: frames,
                            coordinateSpace: TemplateSidebarLayout.coordinateSpace)

                    let categoryMarkers = categoryPlaceholderMarkers()
                    ForEach(model.catalog.sortedCategories) { category in
                        if SidebarRowKey.category(category.id) == categoryMarkers.beforeID {
                            placeholderSlot
                        }
                        categorySection(category)
                    }
                    if categoryMarkers.atEnd {
                        placeholderSlot
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
            .scrollPosition($autoScroll.position)
            .scrollDisabled(drag.isActive)
            .coordinateSpace(name: TemplateSidebarLayout.coordinateSpace)
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named(TemplateSidebarLayout.coordinateSpace))
            } action: { frame in
                if !DragGeometry.framesNearlyEqual(sidebarFrame, frame) {
                    sidebarFrame = frame
                }
            }
            .overlay(alignment: .topLeading) {
                FloatingDragOverlay(controller: drag) { payload in
                    floatingRow(payload)
                }
            }
            .onChange(of: model.selection) { _, selection in
                guard let selection else { return }
                proxy.scrollTo(selection.id, anchor: nil)
            }
            .onChange(of: drag.cursorLocation) { _, _ in
                updateResolvedTarget()
                updateAutoScroll()
            }
            .onChange(of: drag.isActive) { _, active in
                if !active {
                    autoScroll.stop()
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase != .active {
                    cancelDrag()
                }
            }
            .onChange(of: model.catalog) { _, newCatalog in
                var live: Set<String> = []
                for template in newCatalog.templates {
                    live.insert(TemplateCatalogItem.template(template.id).id)
                }
                for category in newCatalog.categories {
                    live.insert(SidebarRowKey.category(category.id))
                }
                for component in newCatalog.sharedComponents {
                    live.insert(TemplateCatalogItem.sharedComponent(component.id).id)
                }
                frames.pruneRows(keeping: live)
                // The dragged item can vanish under the cursor (external
                // edit, restore) — without a source the drop could not commit.
                guard drag.isActive else { return }
                switch drag.payload {
                case .template(let descriptor) where newCatalog.template(id: descriptor.id) == nil:
                    cancelDrag()
                case .category(let category) where newCatalog.category(id: category.id) == nil:
                    cancelDrag()
                case .component(let component)
                where newCatalog.sharedComponent(id: component.id) == nil:
                    cancelDrag()
                default:
                    break
                }
            }
            .task(id: drag.isActive) {
                guard drag.isActive else { return }
                await DragEscapeMonitor.run { cancelDrag() }
            }
        }
    }

    private var baseRow: some View {
        SidebarItemRow(
            title: model.catalog.base.name,
            isSelected: model.selection == .base,
            hoverEnabled: !drag.isActive
        ) {
            Image(systemName: "square.grid.2x2")
        }
        .onTapGesture { model.selection = .base }
        .contextMenu {
            Button("Export…", systemImage: "square.and.arrow.up") {
                presentExportPanel(for: .base)
            }
        }
        .id(TemplateCatalogItem.base.id)
    }

    private func sharedComponentRow(_ component: SharedComponent) -> some View {
        let item = TemplateCatalogItem.sharedComponent(component.id)
        let isDragSource = drag.isActive && drag.sourceID == item.id
        return SidebarItemRow(
            title: component.name,
            isSelected: model.selection == item,
            hoverEnabled: !drag.isActive
        ) {
            Image(systemName: component.sfSymbolName)
        }
        .opacity(isDragSource ? 0 : 1)
        .frame(maxHeight: isDragSource ? 0 : nil)
        .clipped()
        .id(item.id)
        .reportRowFrame(
            id: item.id, registry: frames,
            coordinateSpace: TemplateSidebarLayout.coordinateSpace
        )
        .accessibilityActions {
            // Reorder is otherwise gesture-only — the non-drag path for
            // VoiceOver and keyboard users.
            let ids = model.catalog.sortedSharedComponents.map(\.id)
            if ids.first != component.id {
                Button("Move Up") { model.moveSharedComponent(id: component.id, by: -1) }
            }
            if ids.last != component.id {
                Button("Move Down") { model.moveSharedComponent(id: component.id, by: 1) }
            }
        }
        .contextMenu { sharedComponentMenu(component) }
        .modifier(
            SidebarRowDragInteraction(
                rowID: item.id,
                payload: .component(component),
                drag: drag,
                frames: frames,
                onSelect: { model.selection = item },
                onLiftWillStart: { model.commitCategoryRename() },
                onDispatch: { payload, target in commitDrop(payload, target: target) }
            )
        )
    }

    @ViewBuilder
    private func categorySection(_ category: TemplateCategory) -> some View {
        let rowKey = SidebarRowKey.category(category.id)
        let isDragSource = drag.isActive && drag.sourceID == rowKey
        let templates = model.catalog.templates(inCategory: category.id)
        let markers = placeholderMarkers(forCategory: category.id, templates: templates)
        // While the category floats as a header, its section collapses: the
        // header keeps identity (live gesture), the rows leave the layout.
        categoryHeader(category)
            .opacity(isDragSource ? 0 : 1)
            .frame(maxHeight: isDragSource ? 0 : nil)
            .clipped()
            .reportRowFrame(
                id: rowKey, registry: frames,
                coordinateSpace: TemplateSidebarLayout.coordinateSpace)
        if !isDragSource {
            ForEach(templates) { template in
                if TemplateCatalogItem.template(template.id).id == markers.beforeID {
                    placeholderSlot
                }
                templateRow(template)
            }
            if markers.atEnd {
                placeholderSlot
            }
        }
    }

    private func templateRow(_ template: TemplateDescriptor) -> some View {
        let item = TemplateCatalogItem.template(template.id)
        let isDragSource = drag.isActive && drag.sourceID == item.id
        return SidebarItemRow(
            title: template.name,
            isSelected: model.selection == item,
            hoverEnabled: !drag.isActive
        ) {
            TemplateImageView(
                image: template.image,
                resolve: { model.imageFileURL(forRelative: $0) }
            )
        }
        // Collapse (not remove) the source row while it floats: the layout
        // shows only the gap, but view identity — and the live DragGesture —
        // survive the drag.
        .opacity(isDragSource ? 0 : 1)
        .frame(maxHeight: isDragSource ? 0 : nil)
        .clipped()
        .id(item.id)
        .reportRowFrame(
            id: item.id, registry: frames,
            coordinateSpace: TemplateSidebarLayout.coordinateSpace
        )
        .accessibilityActions {
            let ids = model.catalog.templates(inCategory: template.categoryID).map(\.id)
            if ids.first != template.id {
                Button("Move Up") { model.moveTemplate(id: template.id, withinCategoryBy: -1) }
            }
            if ids.last != template.id {
                Button("Move Down") { model.moveTemplate(id: template.id, withinCategoryBy: 1) }
            }
            ForEach(model.catalog.sortedCategories.filter { $0.id != template.categoryID }) {
                destination in
                Button("Move to \(destination.name)") {
                    model.moveTemplate(id: template.id, toCategory: destination.id)
                }
            }
        }
        .contextMenu { templateMenu(template) }
        .modifier(
            SidebarRowDragInteraction(
                rowID: item.id,
                payload: .template(template),
                drag: drag,
                frames: frames,
                onSelect: { model.selection = item },
                onLiftWillStart: { model.commitCategoryRename() },
                onDispatch: { payload, target in commitDrop(payload, target: target) }
            )
        )
    }

    private var placeholderSlot: some View {
        Color.clear
            .frame(height: max(drag.sourceFrame.height, 1))
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func floatingRow(_ payload: SidebarDragPayload) -> some View {
        switch payload {
        case .template(let descriptor):
            SidebarItemRow(title: descriptor.name, isSelected: false, hoverEnabled: false) {
                TemplateImageView(
                    image: descriptor.image,
                    resolve: { model.imageFileURL(forRelative: $0) }
                )
            }
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.background)
            )
        case .category(let category):
            Text(category.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.background)
                )
        case .component(let component):
            SidebarItemRow(title: component.name, isSelected: false, hoverEnabled: false) {
                Image(systemName: component.sfSymbolName)
            }
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.background)
            )
        }
    }

    private func placeholderMarkers(
        forCategory categoryID: String, templates: [TemplateDescriptor]
    ) -> PlaceholderMarkers {
        guard case .template(let position, let targetCategory, _)? = drag.target,
            targetCategory == categoryID
        else {
            return PlaceholderMarkers(placeholderIndex: nil, items: templates) { _ in "" }
        }
        let rowIDs = templates.map { TemplateCatalogItem.template($0.id).id }
        return PlaceholderMarkers(
            placeholderIndex: placeholderIndex(for: position, rowIDs: rowIDs),
            items: templates
        ) { TemplateCatalogItem.template($0.id).id }
    }

    private func updateResolvedTarget() {
        guard drag.isActive, let sourceID = drag.sourceID, let payload = drag.payload else {
            return
        }
        let resolved: SidebarDropTarget? =
            switch payload {
            case .template: resolveTemplateTarget(sourceID: sourceID)
            case .category: resolveCategoryTarget(sourceID: sourceID)
            case .component: resolveComponentTarget(sourceID: sourceID)
            }
        guard drag.target != resolved else { return }
        withAnimation(DragAnimations.placeholder(reduceMotion: reduceMotion)) {
            drag.setTarget(resolved)
        }
    }

    private func resolveTemplateTarget(sourceID: String) -> SidebarDropTarget? {
        var headerFrames: [String: CGRect] = [:]
        for category in model.catalog.sortedCategories {
            if let frame = frames.rows[SidebarRowKey.category(category.id)] {
                headerFrames[category.id] = frame
            }
        }
        let categories = model.catalog.sortedCategories.map { category in
            (
                id: category.id,
                rowIDs: model.catalog.templates(inCategory: category.id)
                    .map { TemplateCatalogItem.template($0.id).id }
                    .filter { $0 != sourceID }
            )
        }
        return resolveTemplateSidebarDrop(
            cursor: drag.cursorLocation,
            sidebarFrame: sidebarFrame,
            categories: categories,
            headerFrames: headerFrames,
            rowFrames: frames.rows,
            placeholderHeight: drag.sourceFrame.height,
            spacing: TemplateSidebarLayout.rowSpacing
        )
    }

    private func resolveComponentTarget(sourceID: String) -> SidebarDropTarget? {
        resolveComponentSidebarDrop(
            cursor: drag.cursorLocation,
            sidebarFrame: sidebarFrame,
            zoneTop: frames.containers[.componentsHeader]?.minY,
            zoneBottom: frames.containers[.divider]?.minY,
            orderedComponentRowKeys: model.catalog.sortedSharedComponents
                .map { TemplateCatalogItem.sharedComponent($0.id).id }
                .filter { $0 != sourceID },
            rowFrames: frames.rows,
            placeholderHeight: drag.sourceFrame.height,
            spacing: TemplateSidebarLayout.rowSpacing
        )
    }

    private func resolveCategoryTarget(sourceID: String) -> SidebarDropTarget? {
        let categories = model.catalog.sortedCategories
        var blockFrames: [String: CGRect] = [:]
        for category in categories {
            let key = SidebarRowKey.category(category.id)
            guard var block = frames.rows[key] else { continue }
            for template in model.catalog.templates(inCategory: category.id) {
                if let frame = frames.rows[TemplateCatalogItem.template(template.id).id] {
                    block = block.union(frame)
                }
            }
            blockFrames[key] = block
        }
        return resolveCategorySidebarDrop(
            cursor: drag.cursorLocation,
            sidebarFrame: sidebarFrame,
            zoneTop: frames.containers[.divider]?.maxY,
            orderedCategoryRowKeys:
                categories
                .map { SidebarRowKey.category($0.id) }
                .filter { $0 != sourceID },
            blockFrames: blockFrames,
            placeholderHeight: drag.sourceFrame.height,
            spacing: TemplateSidebarLayout.rowSpacing
        )
    }

    private func updateAutoScroll() {
        guard drag.isActive else {
            autoScroll.stop()
            return
        }
        let status = drag.status
        autoScroll.update(
            active: status == .dragging || status == .lifting,
            cursorY: drag.cursorLocation.y,
            frame: sidebarFrame
        )
    }

    private func cancelDrag() {
        guard drag.isActive else { return }
        withAnimation(DragAnimations.cancel(reduceMotion: reduceMotion)) {
            drag.beginCancel()
        }
        drag.scheduleSettle(after: .milliseconds(reduceMotion ? 50 : 300))
    }

    private func commitDrop(_ payload: SidebarDragPayload, target: SidebarDropTarget) {
        switch (payload, target) {
        case (.template(let descriptor), .template(let position, let categoryID, _)):
            let ids = model.catalog.templates(inCategory: categoryID)
                .map(\.id)
                .filter { $0 != descriptor.id }
            model.dropTemplate(
                id: descriptor.id,
                intoCategory: categoryID,
                at: insertionIndex(
                    for: position, in: ids,
                    idFromRowKey: SidebarRowKey.templateID(fromRowKey:))
            )
        case (.category(let category), .category(let position, _)):
            let ids = model.catalog.sortedCategories
                .map(\.id)
                .filter { $0 != category.id }
            model.dropCategory(
                id: category.id,
                at: insertionIndex(
                    for: position, in: ids,
                    idFromRowKey: SidebarRowKey.categoryID(fromRowKey:))
            )
        case (.component(let component), .component(let position, _)):
            let ids = model.catalog.sortedSharedComponents
                .map(\.id)
                .filter { $0 != component.id }
            model.dropSharedComponent(
                id: component.id,
                at: insertionIndex(
                    for: position, in: ids,
                    idFromRowKey: SidebarRowKey.componentID(fromRowKey:))
            )
        default:
            break
        }
    }

    private func componentPlaceholderMarkers() -> PlaceholderMarkers {
        let components = model.catalog.sortedSharedComponents
        guard case .component(let position, _)? = drag.target else {
            return PlaceholderMarkers(placeholderIndex: nil, items: components) { _ in "" }
        }
        let rowKeys = components.map { TemplateCatalogItem.sharedComponent($0.id).id }
        return PlaceholderMarkers(
            placeholderIndex: placeholderIndex(for: position, rowIDs: rowKeys),
            items: components
        ) { TemplateCatalogItem.sharedComponent($0.id).id }
    }

    private func categoryPlaceholderMarkers() -> PlaceholderMarkers {
        let categories = model.catalog.sortedCategories
        guard case .category(let position, _)? = drag.target else {
            return PlaceholderMarkers(placeholderIndex: nil, items: categories) { _ in "" }
        }
        let rowKeys = categories.map { SidebarRowKey.category($0.id) }
        return PlaceholderMarkers(
            placeholderIndex: placeholderIndex(for: position, rowIDs: rowKeys),
            items: categories
        ) { SidebarRowKey.category($0.id) }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func categoryHeader(_ category: TemplateCategory) -> some View {
        Group {
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
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .contextMenu { categoryMenu(category) }
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityActions {
            let ids = model.catalog.sortedCategories.map(\.id)
            if ids.first != category.id {
                Button("Move Up") { model.moveCategory(id: category.id, by: -1) }
            }
            if ids.last != category.id {
                Button("Move Down") { model.moveCategory(id: category.id, by: 1) }
            }
        }
        .modifier(
            SidebarRowDragInteraction(
                // The rename TextField owns mouse events while editing — no
                // drag gesture competing with text selection.
                enabled: model.categoryRename?.id != category.id,
                rowID: SidebarRowKey.category(category.id),
                payload: .category(category),
                drag: drag,
                frames: frames,
                onSelect: {},
                onLiftWillStart: { model.commitCategoryRename() },
                onDispatch: { payload, target in commitDrop(payload, target: target) }
            )
        )
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
                Button("Reset to Factory Defaults…", role: .destructive) {
                    model.isConfirmingResetEverything = true
                }
            } label: {
                Label("Restore", systemImage: "arrow.uturn.backward")
            }
        }
    }

    @ViewBuilder
    private func categoryMenu(_ category: TemplateCategory) -> some View {
        Button("Rename", systemImage: "pencil") {
            model.beginRenameCategory(id: category.id)
        }
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) {
            model.deleteCategory(id: category.id)
        }
        .disabled(!model.canDeleteCategory(id: category.id))
    }

    @ViewBuilder
    private func sharedComponentMenu(_ component: SharedComponent) -> some View {
        Button("Export…", systemImage: "square.and.arrow.up") {
            presentExportPanel(for: .sharedComponent(component.id))
        }
        Divider()
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
        Button("Export…", systemImage: "square.and.arrow.up") {
            presentExportPanel(for: .template(template.id))
        }
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) {
            model.deleteTemplate(id: template.id)
        }
    }

    private func presentExportPanel(for selection: TemplateArchiveSelection) {
        TemplateArchivePanels.presentExport(for: selection, model: model)
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
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
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
                isPresented: model.componentDeletionDialogBinding,
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
            .confirmationDialog(
                "Reset everything to factory defaults?",
                isPresented: $model.isConfirmingResetEverything,
                titleVisibility: .visible
            ) {
                Button("Reset to Factory Defaults", role: .destructive) {
                    model.resetToFactoryDefaults()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "Everything returns to the bundled defaults: structure, all file edits, "
                        + "files you added, and hook wiring. Removed files are moved to the Trash.")
            }
    }
}
