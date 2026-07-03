import Foundation

// Git-hygiene shared by scaffolder and migrator; the callers keep their own
// has-repo gates and init logic.
nonisolated enum ProjectGitHygiene {
    static func applyExcludes(
        name: String, plumageInGit: Bool, claudeInGit: Bool, root: URL
    ) throws {
        var excludes: [String] = []
        if plumageInGit {
            excludes += GitExcludeWriter.plumageEphemeralPaths
        } else {
            excludes += ["\(name).plumage/"]
            try excludeBundleFromSwiftLint(name: name, root: root)
        }
        if !claudeInGit { excludes += [".claude/", ".mcp.json"] }
        if !excludes.isEmpty {
            try GitExcludeWriter().append(paths: excludes, repoURL: root)
        }
    }

    // No-op when no .swiftlint.yml is present (non-Swift, or the user kept none);
    // the entry mirrors the bundle's .git/info/exclude line so neither tool scans it.
    private static func excludeBundleFromSwiftLint(name: String, root: URL) throws {
        let configURL = root.appending(path: ".swiftlint.yml")
        guard let yaml = try? String(contentsOf: configURL, encoding: .utf8) else { return }
        let updated = SwiftLintConfigEditor.addingExclude("\(name).plumage/", to: yaml)
        try updated.write(to: configURL, atomically: true, encoding: .utf8)
    }
}
