import Foundation

// Rewrites the name-specific bundle exclude line in `.git/info/exclude` when a
// project is renamed: `<old>.plumage/` → `<new>.plumage/`. Sister to
// GitExcludeWriter (which appends that line at scaffold/migrate time when
// `plumageInGit == false`). Pure file edit — no `git mv`, no subprocess: a
// committed bundle is auto-detected as a rename by git itself, and an excluded
// bundle just needs its exclude line repointed so it stays out of `git status`.
//
// Tolerant by design: a no-op (returns false) when there is no
// `.git/info/exclude` (project not in git, or never excluded) or when the line
// isn't present (committed bundle / `plumageInGit == true`).
nonisolated struct GitExcludeRenamer {
    @discardableResult
    func rename(oldBundleName: String, newBundleName: String, repoURL: URL) throws -> Bool {
        guard oldBundleName != newBundleName else { return false }

        let excludeURL = repoURL.appending(path: ".git/info/exclude")
        guard let existing = try? String(contentsOf: excludeURL, encoding: .utf8) else {
            return false
        }

        let oldLine = "\(oldBundleName).plumage/"
        let newLine = "\(newBundleName).plumage/"

        var changed = false
        let rewritten =
            existing
            .components(separatedBy: "\n")
            .map { line -> String in
                // Match the exact exclude entry (whitespace-trimmed) the
                // scaffolder/migrator wrote; every other line is left verbatim.
                if line.trimmingCharacters(in: .whitespaces) == oldLine {
                    changed = true
                    return newLine
                }
                return line
            }
            .joined(separator: "\n")

        guard changed else { return false }
        try rewritten.write(to: excludeURL, atomically: true, encoding: .utf8)
        return true
    }
}
