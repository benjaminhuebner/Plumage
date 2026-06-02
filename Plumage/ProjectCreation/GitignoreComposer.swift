import Foundation

// The macOS block is always appended — contributors on macOS produce
// `.DS_Store` etc. regardless of the project's platform.
nonisolated struct GitignoreComposer {
    let overrides: ScaffoldOverrides
    var catalog: TemplateCatalog = .bundledDefault

    func compose(for kind: ProjectKind) throws -> String {
        var tags = catalog.effectiveGitignoreTags(forTemplate: kind.rawValue)
        if !tags.contains("macos") {
            tags.append("macos")
        }
        let fragments = try tags.map { tag in
            try overrides.string(atRelative: "templates/gitignore/\(tag).gitignore")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return fragments.joined(separator: "\n\n") + "\n"
    }
}
