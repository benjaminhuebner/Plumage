import Foundation

// The macOS block is always appended — contributors on macOS produce
// `.DS_Store` etc. regardless of the project's platform. Plumage's own
// ephemeral state (`*.plumage/runs/`, `*.plumage/sessions/`) is intentionally
// NOT added here: it goes into the repo-local `.git/info/exclude` via
// GitExcludeWriter, so the shared `.gitignore` stays free of Plumage internals.
nonisolated struct GitignoreComposer {
    let overrides: ScaffoldOverrides
    var catalog: TemplateCatalog = .bundledDefault

    func compose(forTemplate templateID: String) throws -> String {
        var tags = catalog.effectiveGitignoreTags(forTemplate: templateID)
        if !tags.contains("macos") {
            tags.append("macos")
        }
        let fragments = try tags.map { tag in
            try overrides.string(atRelative: "templates/gitignore/\(tag).gitignore")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return fragments.joined(separator: "\n\n") + "\n"
    }

    func compose(for kind: ProjectKind) throws -> String {
        try compose(forTemplate: kind.rawValue)
    }
}
