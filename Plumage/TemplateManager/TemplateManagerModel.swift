import Foundation

// Scene-scoped state for the Template Manager window. Loads the resolved catalog
// off-main (state-as-bridge) and tracks the selected left-column item. File
// selection for the middle/right columns is layered on in later Phase C tasks.
@MainActor
@Observable
final class TemplateManagerModel {
    private(set) var catalog: TemplateCatalog = .bundledDefault
    var selection: TemplateCatalogItem? = .base

    private let store: TemplateCatalogStore

    init(store: TemplateCatalogStore = TemplateCatalogStore()) {
        self.store = store
    }

    func load() async {
        let store = self.store
        let loaded = await Task.detached(priority: .userInitiated) { store.load() }.value
        catalog = loaded
        if selection == nil { selection = .base }
    }
}
