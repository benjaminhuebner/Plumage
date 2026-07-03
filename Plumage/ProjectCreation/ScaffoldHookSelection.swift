import Foundation

// Hook selection shared by scaffolder and migrator. Only the WRITE logic is
// deliberately duplicated between the two; which hooks a template gets is one rule.
nonisolated enum ScaffoldHookSelection {
    // The hooks enabled for a template, as (base name, store path) pairs: built-ins
    // (a content override wins by stem, carrying its extension) plus the template's
    // scope-owned user hooks. The toggle key stays the base name.
    static func enabledHookFiles(
        forTemplate templateID: String, catalog: TemplateCatalog,
        overrides: ScaffoldOverrides, toggles: ScaffoldToggles
    ) -> [(base: String, relativePath: String)] {
        let effective = catalog.effectiveHooks(forTemplate: templateID)
        var pathByBase: [String: String] = [:]
        for base in effective { pathByBase[base] = "hooks/\(base).sh" }
        for file in overrides.overrideFileNames(inRelativeDir: "hooks") {
            let base = (file as NSString).deletingPathExtension
            if pathByBase[base] != nil { pathByBase[base] = "hooks/\(file)" }
        }
        let effectiveSet = Set(effective)
        let userHooks = catalog.effectiveUserHooks(forTemplate: templateID, overrides: overrides)
            .filter { !effectiveSet.contains($0.base) }
        for hook in userHooks { pathByBase[hook.base] = hook.relativePath }
        return toggles.enabledNames(in: .hooks, from: effective + userHooks.map(\.base))
            .map { ($0, pathByBase[$0] ?? "hooks/\($0).sh") }
    }
}
