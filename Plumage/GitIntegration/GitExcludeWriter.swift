import Foundation

// Appends path patterns to a repo's `.git/info/exclude` — the local, uncommitted
// ignore list. Used to keep agent files (`.claude/`, `.plumage/`, `.mcp.json`)
// out of a repo when the user opted not to track them, without writing a shared
// `.gitignore`. Pure FileManager work, no git subcommand. Idempotent: lines that
// already exist are not re-appended.
nonisolated struct GitExcludeWriter {
    func append(paths: [String], repoURL: URL) throws {
        let toWrite = paths.filter { !$0.isEmpty }
        guard !toWrite.isEmpty else { return }

        let infoDir = repoURL.appending(path: ".git/info", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: infoDir, withIntermediateDirectories: true)
        let excludeURL = infoDir.appending(path: "exclude")

        let existing = (try? String(contentsOf: excludeURL, encoding: .utf8)) ?? ""
        let existingLines = Set(
            existing.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) })
        let newLines = toWrite.filter { !existingLines.contains($0) }
        guard !newLines.isEmpty else { return }

        var result = existing
        if !result.isEmpty, !result.hasSuffix("\n") { result += "\n" }
        result += newLines.joined(separator: "\n") + "\n"
        try result.write(to: excludeURL, atomically: true, encoding: .utf8)
    }
}
