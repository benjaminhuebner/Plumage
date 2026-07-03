import Testing

@testable import Plumage

@Suite("TemplateCatalog loose-surface roots (#00078)")
struct TemplateCatalogLooseSurfacesTests {
    private let catalog = TemplateCatalog.bundledDefault

    @Test(
        "Roots are Base, member components in order, then the template last (#00084)",
        arguments: ProjectKind.allCases)
    func looseSurfaceRootsOrder(_ kind: ProjectKind) {
        let id = kind.rawValue
        let expectedComponents = catalog.sharedComponents(forTemplate: id).map { "components/\($0.id)" }
        #expect(
            catalog.looseSurfaceRoots(forTemplate: id) == [""] + expectedComponents + ["templates/\(id)"])
    }

    @Test("The template root sorts after every member component so the template wins (#00084)")
    func templateWinsOverComponents() {
        let id = ProjectKind.allCases.first?.rawValue ?? "swift"
        let roots = catalog.looseSurfaceRoots(forTemplate: id)
        let templateIndex = roots.firstIndex(of: "templates/\(id)")
        let componentIndices = catalog.sharedComponents(forTemplate: id)
            .compactMap { roots.firstIndex(of: "components/\($0.id)") }
        #expect(templateIndex == roots.count - 1)
        #expect(componentIndices.allSatisfy { $0 < (templateIndex ?? 0) })
    }

    @Test("An unknown template still yields Base first and its own (member-less) root last")
    func unknownTemplate() {
        #expect(catalog.looseSurfaceRoots(forTemplate: "nope") == ["", "templates/nope"])
    }
}
