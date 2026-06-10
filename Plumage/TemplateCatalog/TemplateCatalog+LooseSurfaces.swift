import Foundation

// Loose-file scope roots for a template — deliberately separate from the composition
// resolvers (`effectiveLayers`/`effectiveHooks`). A scaffolded project composes its
// loose files from Base ∪ that template's member components ∪ the chosen Template, in
// that precedence order (Base < Component < Template). Composition assets are
// untouched by this.
nonisolated extension TemplateCatalog {
    // The override-store roots whose loose files a project built from `templateID`
    // draws on: Base first (`""`), then each member component in concatenation order,
    // then the template's own subtree last. Later roots win on a name clash, so the
    // template — the most specific choice — overrides a member component's file
    func looseSurfaceRoots(forTemplate templateID: String) -> [String] {
        var roots = [""]
        roots += sharedComponents(forTemplate: templateID).map { "components/\($0.id)" }
        roots.append("templates/\(templateID)")
        return roots
    }
}
