import Foundation

// Loose-file scope roots for a template — deliberately separate from the composition
// resolvers (`effectiveLayers`/`effectiveHooks`). A scaffolded project composes its
// loose files from Base ∪ the chosen Template ∪ that template's member components, in
// that precedence order (#00078). Composition assets are untouched by this.
nonisolated extension TemplateCatalog {
    // The override-store roots whose loose files a project built from `templateID`
    // draws on: Base first (`""`), then the template's own subtree, then each member
    // component in concatenation order. Later roots win on a name clash (most specific
    // scope: Base < Template < Component).
    func looseSurfaceRoots(forTemplate templateID: String) -> [String] {
        var roots = ["", "templates/\(templateID)"]
        roots += sharedComponents(forTemplate: templateID).map { "components/\($0.id)" }
        return roots
    }
}
