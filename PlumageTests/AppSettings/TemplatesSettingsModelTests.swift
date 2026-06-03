import Foundation
import Testing

@testable import Plumage

@MainActor
@Suite("TemplatesSettingsModel (reduced)")
struct TemplatesSettingsModelTests {
    // A model backed by a temp manifest so enable toggles persist hermetically.
    private func makeModel() -> (model: TemplatesSettingsModel, url: URL) {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "TemplatesSettings-\(UUID().uuidString).json")
        return (TemplatesSettingsModel(store: TemplateCatalogStore(manifestURL: url)), url)
    }

    @Test("Grouped templates cover the bundled categories and templates")
    func groupedTemplatesCoverBundled() {
        let (model, url) = makeModel()
        defer { try? FileManager.default.removeItem(at: url) }
        model.reload()

        let categoryIDs = model.groupedTemplates.map(\.category.id)
        #expect(categoryIDs == ProjectKindGroup.allCases.map(\.rawValue))
        let allTemplateIDs = model.groupedTemplates.flatMap { $0.templates.map(\.id) }
        #expect(Set(allTemplateIDs) == Set(ProjectKind.allCases.map(\.rawValue)))
    }

    @Test("Templates are enabled by default")
    func enabledByDefault() {
        let (model, url) = makeModel()
        defer { try? FileManager.default.removeItem(at: url) }
        model.reload()
        for group in model.groupedTemplates {
            for template in group.templates { #expect(model.isEnabled(template)) }
        }
    }

    @Test("Disabling a template persists and survives a reload")
    func setEnabledPersists() {
        let (model, url) = makeModel()
        defer { try? FileManager.default.removeItem(at: url) }
        model.reload()

        model.setEnabled(ProjectKind.macOS.rawValue, false)
        #expect(model.catalog.template(id: ProjectKind.macOS.rawValue)?.enabled == false)

        // A fresh model reading the same manifest sees the disabled state.
        let reloaded = TemplatesSettingsModel(store: TemplateCatalogStore(manifestURL: url))
        reloaded.reload()
        #expect(reloaded.catalog.template(id: ProjectKind.macOS.rawValue)?.enabled == false)
        #expect(reloaded.catalog.template(id: ProjectKind.iOS.rawValue)?.enabled == true)
    }

    @Test("Re-enabling a template clears its persisted overlay")
    func reEnableClearsOverlay() {
        let (model, url) = makeModel()
        defer { try? FileManager.default.removeItem(at: url) }
        model.reload()
        model.setEnabled(ProjectKind.macOS.rawValue, false)
        model.setEnabled(ProjectKind.macOS.rawValue, true)
        #expect(model.catalog == .bundledDefault)
    }
}
