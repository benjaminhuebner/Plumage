import Foundation
import Testing

@testable import Plumage

@Suite("Template enabled flag")
struct TemplateEnabledFlagTests {
    @Test("Bundled templates default to enabled")
    func bundledTemplatesEnabled() {
        for template in TemplateCatalog.bundledDefault.templates {
            #expect(template.enabled)
        }
    }

    @Test("A descriptor JSON without an `enabled` key decodes to enabled (back-compat)")
    func legacyDescriptorDecodesEnabled() throws {
        // Encode a real descriptor, then strip `enabled` to mimic an older record.
        let descriptor = try #require(
            TemplateCatalog.bundledDefault.template(id: ProjectKind.macOS.rawValue))
        let data = try JSONEncoder().encode(descriptor)
        var object = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "enabled")
        let legacy = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(TemplateDescriptor.self, from: legacy)
        #expect(decoded.enabled)
    }

    @Test("enabledTemplates(inCategory:) hides disabled templates")
    func enabledTemplatesFiltersDisabled() {
        var catalog = TemplateCatalog.bundledDefault
        let categoryID = ProjectKindGroup.appleApps.rawValue
        let all = catalog.templates(inCategory: categoryID)
        #expect(!all.isEmpty)

        catalog.setTemplateEnabled(id: ProjectKind.macOS.rawValue, false)
        let enabled = catalog.enabledTemplates(inCategory: categoryID)
        #expect(enabled.count == all.count - 1)
        #expect(!enabled.contains { $0.id == ProjectKind.macOS.rawValue })

        for template in catalog.templates(inCategory: categoryID) {
            catalog.setTemplateEnabled(id: template.id, false)
        }
        #expect(catalog.enabledTemplates(inCategory: categoryID).isEmpty)
    }

    @Test("Disabling a predefined template survives a store save/load round-trip")
    func disabledFlagPersistsThroughStore() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "manifest-enabled-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = TemplateCatalogStore(manifestURL: url)

        var catalog = store.load()
        catalog.setTemplateEnabled(id: ProjectKind.macOS.rawValue, false)
        try store.save(catalog)

        let reloaded = store.load()
        #expect(reloaded.template(id: ProjectKind.macOS.rawValue)?.enabled == false)
        // Untouched predefined templates stay enabled.
        #expect(reloaded.template(id: ProjectKind.iOS.rawValue)?.enabled == true)
    }

    @Test("Re-enabling a predefined template drops it from the overlay (equals bundled)")
    func reEnableDropsOverlay() {
        var catalog = TemplateCatalog.bundledDefault
        catalog.setTemplateEnabled(id: ProjectKind.macOS.rawValue, false)
        catalog.setTemplateEnabled(id: ProjectKind.macOS.rawValue, true)
        #expect(catalog == .bundledDefault)
    }
}
