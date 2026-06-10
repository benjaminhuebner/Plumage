import Foundation
import SwiftUI

// Reduced Settings → Templates model (#00070). Owns just the per-template enable/
// disable state of the resolved catalog; all authoring, editing, membership and
// preview moved to the Template Manager window (#00067–#00069). State-as-bridge:
// the catalog load and the enable persistence funnel through this @MainActor type.
//
// The `enabled` flag lives on the template's manifest record, so persistence reuses
// the shared `TemplateCatalogStore`. To avoid clobbering a concurrent Template
// Manager structural edit, each toggle reloads the catalog from disk before flipping
// the single field and saving (the residual cross-window race is noted in notes.md).
@MainActor
@Observable
final class TemplatesSettingsModel {
    private(set) var catalog: TemplateCatalog = .bundledDefault
    private let store: TemplateCatalogStore
    private let overrides: ScaffoldOverrides

    init(
        store: TemplateCatalogStore = TemplateCatalogStore(),
        overrides: ScaffoldOverrides = .standard()
    ) {
        self.store = store
        self.overrides = overrides
    }

    // Reloads the catalog from disk. Called on appear so the list reflects templates
    // authored or removed in the Template Manager since the tab was last shown.
    func reload() {
        catalog = store.load()
    }

    // Categories (in catalog order) with their templates (in display order). Disabled
    // templates are listed too — this is where they are re-enabled.
    var groupedTemplates: [(category: TemplateCategory, templates: [TemplateDescriptor])] {
        catalog.sortedCategories.compactMap { category in
            let templates = catalog.templates(inCategory: category.id)
            return templates.isEmpty ? nil : (category, templates)
        }
    }

    func isEnabled(_ template: TemplateDescriptor) -> Bool { template.enabled }

    // Model-owned binding keeps Binding(get:set:) out of the view body.
    func enabledBinding(for template: TemplateDescriptor) -> Binding<Bool> {
        Binding(
            get: { self.isEnabled(template) },
            set: { self.setEnabled(template.id, $0) }
        )
    }

    // Flips a template's enabled flag and persists immediately so the New/Migrate
    // grids pick it up. Reloads first so a concurrent Manager edit isn't clobbered.
    func setEnabled(_ templateID: String, _ enabled: Bool) {
        var updated = store.load()
        updated.setTemplateEnabled(id: templateID, enabled)
        catalog = updated
        try? store.save(updated)
    }

    // Resolves a `TemplateImage.file` relative path to its on-disk URL (override
    // store), or nil when absent — the row falls back to a placeholder symbol.
    func imageURL(forRelative relativePath: String) -> URL? {
        let url = overrides.url(forRelative: relativePath)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
