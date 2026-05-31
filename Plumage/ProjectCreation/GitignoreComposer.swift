import Foundation

// The macOS block is always appended — contributors on macOS produce
// `.DS_Store` etc. regardless of the project's platform.
nonisolated struct GitignoreComposer {
    let fragmentsDir: URL

    func compose(for kind: ProjectKind) throws -> String {
        var tags = kind.profile.gitignoreTags
        if !tags.contains("macos") {
            tags.append("macos")
        }
        let fragments = try tags.map { tag in
            try String(contentsOf: fragmentsDir.appending(path: "\(tag).gitignore"), encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return fragments.joined(separator: "\n\n") + "\n"
    }
}
