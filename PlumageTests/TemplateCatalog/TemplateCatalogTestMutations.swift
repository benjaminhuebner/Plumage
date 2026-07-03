@testable import Plumage

nonisolated extension TemplateCatalog {
    // Test-only fixture helper for legacy-layout catalogs.
    mutating func addFile(toComponentID componentID: String, kind: SharedComponentKind, fileName: String) {
        guard let index = sharedComponents.firstIndex(where: { $0.id == componentID }),
            !sharedComponents[index].files.contains(where: { $0.kind == kind && $0.name == fileName })
        else { return }
        sharedComponents[index].files.append(ComponentFile(kind: kind, name: fileName))
    }
}
