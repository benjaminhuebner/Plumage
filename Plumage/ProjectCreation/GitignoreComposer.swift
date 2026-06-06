import Foundation

// The macOS block is always appended — contributors on macOS produce
// `.DS_Store` etc. regardless of the project's platform. The plumage block is
// likewise always appended so a committed `<name>.plumage/` bundle never
// carries its ephemeral `runs/`/`sessions/` subfolders into git.
nonisolated struct GitignoreComposer {
    let overrides: ScaffoldOverrides
    var catalog: TemplateCatalog = .bundledDefault

    func compose(forTemplate templateID: String) throws -> String {
        var tags = catalog.effectiveGitignoreTags(forTemplate: templateID)
        if !tags.contains("macos") {
            tags.append("macos")
        }
        if !tags.contains("plumage") {
            tags.append("plumage")
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
