import Foundation

// The archive-import flow: read an archive into a pending preview (drives the
// import sheet), then apply the selected subset or cancel. The catalog and
// wirings in memory only change when apply succeeds.
extension TemplateManagerModel {
    func beginImport(fromArchive url: URL) async {
        // The double-click route can fire before the window's initial load;
        // conflicts must be computed against the loaded catalog, so load first.
        await load()
        let importer = TemplateArchiveImporter(catalog: catalog, overrides: overrides)
        do {
            let contents = try await importer.read(archiveURL: url)
            pendingImport?.cleanup()
            pendingImport = contents
            // Conflicting items overwrite local edits without undo — opt-in only.
            pendingImportSelection = Set(contents.items.filter { !$0.conflict }.map(\.id))
        } catch {
            showStructuralError(Self.archiveErrorMessage(error))
        }
    }

    func export(_ selection: TemplateArchiveSelection, to url: URL) async {
        let exporter = TemplateArchiveExporter(
            catalog: catalog, overrides: overrides, hookWirings: hookWirings)
        do {
            try await exporter.export(selection, to: url)
        } catch {
            showStructuralError(Self.archiveErrorMessage(error))
        }
    }

    func exportSuggestedFileName(for selection: TemplateArchiveSelection) -> String {
        let stem: String
        switch selection {
        case .base: stem = catalog.base.name
        case .template(let id): stem = catalog.template(id: id)?.name ?? id
        case .sharedComponent(let id): stem = catalog.sharedComponent(id: id)?.name ?? id
        case .fullCatalog: stem = "Plumage Templates"
        }
        return "\(stem).\(TemplateArchiveFileType.fileExtension)"
    }

    static func archiveErrorMessage(_ error: any Error) -> String {
        error.localizedDescription
    }
}
