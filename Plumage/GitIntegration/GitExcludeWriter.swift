import Foundation

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
