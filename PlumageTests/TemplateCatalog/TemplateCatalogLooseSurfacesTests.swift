import Foundation
import Testing

@testable import Plumage

@Suite("TemplateCatalog loose-surface roots (#00078)")
struct TemplateCatalogLooseSurfacesTests {
    private let catalog = TemplateCatalog.bundledDefault

    @Test(
        "Roots are Base, the template, then member components in order",
        arguments: ProjectKind.allCases)
    func looseSurfaceRootsOrder(_ kind: ProjectKind) {
        let id = kind.rawValue
        let expectedComponents = catalog.sharedComponents(forTemplate: id).map { "components/\($0.id)" }
        #expect(catalog.looseSurfaceRoots(forTemplate: id) == ["", "templates/\(id)"] + expectedComponents)
    }

    @Test("An unknown template still yields Base and its own (member-less) root")
    func unknownTemplate() {
        #expect(catalog.looseSurfaceRoots(forTemplate: "nope") == ["", "templates/nope"])
    }
}
