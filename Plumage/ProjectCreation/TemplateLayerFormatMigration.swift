import Foundation
import os

// Without this, an older saved layer edit silently loses its Build-and-Test section:
// those layers use the spaced `%% BUILD AND TEST %%`, which the now exact-match
// `PlaceholderMerge` no longer maps to `<<<BUILD_AND_TEST>>>`. Only this pass can do the keyword rename.
nonisolated enum TemplateLayerFormatMigration {
    private static let logger = Logger(
        subsystem: "com.plumage", category: "TemplateLayerFormatMigration")

    // Only `BUILD AND TEST` ever contained whitespace, so it is the sole rename.
    static let keywordRenames = ["BUILD AND TEST": "BUILD_AND_TEST"]

    @discardableResult
    static func migrateStandard() -> [String] {
        guard let root = ScaffoldOverrides.standardOverrideRoot() else { return [] }
        return migrate(overrideRoot: root)
    }

    // Scans layer subdirs only, so the base skeleton (`templates/CLAUDE.md` — placeholders,
    // not blocks) is never touched. Returns the layer names that changed.
    @discardableResult
    static func migrate(overrideRoot: URL) -> [String] {
        let fileManager = FileManager.default
        let templatesDir = overrideRoot.appending(path: "templates", directoryHint: .isDirectory)
        guard
            let entries = try? fileManager.contentsOfDirectory(
                at: templatesDir, includingPropertiesForKeys: [.isDirectoryKey])
        else { return [] }

        var migrated: [String] = []
        for entry in entries {
            guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            else { continue }
            let layer = entry.lastPathComponent
            let file = entry.appending(path: "CLAUDE.md")
            guard let original = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let rewritten = closeOpenBlocks(in: original)
            guard rewritten != original else { continue }
            do {
                try rewritten.write(to: file, atomically: true, encoding: .utf8)
            } catch {
                Self.logger.error(
                    "couldn't rewrite layer \(layer, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
                continue
            }
            migrated.append(layer)
        }
        return migrated.sorted()
    }

    // Only marker lines are canonicalized (body lines pass through verbatim), so a file
    // already in the new format re-emits identically — that is what lets the caller run it
    // unconditionally and write only on a real change.
    static func closeOpenBlocks(in content: String) -> String {
        var out: [String] = []
        var openKeyword: String?
        for line in content.components(separatedBy: "\n") {
            switch marker(ofLine: line) {
            case .open(let raw):
                if let openKeyword { out.append("%% /\(openKeyword) %%") }
                let keyword = keywordRenames[raw] ?? raw
                out.append("%% \(keyword) %%")
                openKeyword = keyword
            case .close:
                // A close terminates whatever block is open (its keyword is canonicalized
                // from the open marker); a close with no open block is dangling and dropped.
                if let openKeyword { out.append("%% /\(openKeyword) %%") }
                openKeyword = nil
            case nil:
                out.append(line)
            }
        }
        if let openKeyword { out.append("%% /\(openKeyword) %%") }
        return out.joined(separator: "\n")
    }

    private enum Marker {
        case open(keyword: String)
        case close(keyword: String)
    }

    private static func marker(ofLine line: String) -> Marker? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("%%"), trimmed.hasSuffix("%%"), trimmed.count > 4 else { return nil }
        let inner = trimmed.dropFirst(2).dropLast(2).trimmingCharacters(in: .whitespaces)
        guard !inner.isEmpty else { return nil }
        if inner.hasPrefix("/") {
            let keyword = inner.dropFirst().trimmingCharacters(in: .whitespaces)
            return keyword.isEmpty ? nil : .close(keyword: keyword)
        }
        return .open(keyword: inner)
    }
}
