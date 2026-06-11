import SwiftUI

// App-global window for editing the template catalog. Three columns: left = the
// three tiers (Base / Shared Components / categories → templates), middle = the
// selected item's files + memberships, right = an editable view of the selected
// file that saves to the per-user override store.
struct TemplateManagerWindowView: View {
    @State private var model = TemplateManagerModel()
    @Environment(TemplateArchiveImportRequest.self) private var importRequest: TemplateArchiveImportRequest?

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
        // Window-level (not sidebar) so the buttons stay visible at minimum
        // sidebar width; explicit titleAndIcon because icon-only toolbar
        // glyphs hide what import/export even is.
        .toolbar {
            ToolbarItemGroup {
                Button {
                    TemplateArchivePanels.presentImport(model: model)
                } label: {
                    Label("Import…", systemImage: "square.and.arrow.down")
                        .labelStyle(.titleAndIcon)
                }
                .help("Import templates from a .\(TemplateArchiveFileType.fileExtension) file")
                Button {
                    TemplateArchivePanels.presentExport(for: .fullCatalog, model: model)
                } label: {
                    Label("Export All…", systemImage: "square.and.arrow.up")
                        .labelStyle(.titleAndIcon)
                }
                .help("Export the entire template catalog")
            }
        }
        .task { await model.load() }
        .task(id: importRequest?.generation) {
            guard let importRequest, let url = importRequest.archiveURL else { return }
            await model.beginImport(fromArchive: url)
        }
        .sheet(isPresented: importSheetPresented) {
            if let pending = model.pendingImport {
                TemplateArchiveImportSheet(model: model, items: pending.items)
            }
        }
        .onChange(of: model.selection) { model.refreshContent() }
        .onChange(of: model.selectedFile) { _, file in model.beginEditing(file) }
    }

    // Dismissal (Esc, programmatic close) routes through cancelImport so the
    // staging dir never leaks; after a confirm the cancel is a no-op.
    private var importSheetPresented: Binding<Bool> {
        Binding(
            get: { model.pendingImport != nil },
            set: { presented in
                if !presented { model.cancelImport() }
            }
        )
    }
}
