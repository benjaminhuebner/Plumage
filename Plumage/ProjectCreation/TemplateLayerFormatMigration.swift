import Foundation
import os

// Layer composition moved from `%% keyword %%` blocks to Markdown merged by heading;
// saved overrides in the old formats would leak literal markers into composed output.
// This pass rewrites them: markers become headings, skeleton placeholder lines go.
nonisolated enum TemplateLayerFormatMigration {
    private static let logger = Logger(
        subsystem: "com.plumage", category: "TemplateLayerFormatMigration")

    // Only `BUILD AND TEST` ever contained whitespace, so it is the sole rename.
    static let keywordRenames = ["BUILD AND TEST": "BUILD_AND_TEST"]

    // The historical block keywords and the skeleton headings they filled.
    static let sectionHeadings = [
        "LAYOUT": "## Project layout",
        "CONVENTIONS": "## Conventions",
        "BUILD_AND_TEST": "## Build and test",
        "PITFALLS": "## Common pitfalls",
    ]

    // Skeleton tokens that are scalar substitutions, not merge sections — the
    // composer replaces them per project, so migration must leave them alone.
    static let scalarKeywords: Set<String> = [
        "PROJECT_NAME", "PROJECT_TAGLINE", "STACK_SUMMARY", "XCODE_MCP_LINE",
    ]

    @discardableResult
    static func migrateStandard() -> [String] {
        guard let root = ScaffoldOverrides.standardOverrideRoot() else { return [] }
        return migrate(overrideRoot: root)
    }

    // Rewrites layer overrides to heading format, then strips the skeleton override
    // (scalars kept). The skeleton's keyword→heading pairs are the layers' heading
    // source, so it rewrites last — a failed layer rewrite can re-harvest next run.
    @discardableResult
    static func migrate(overrideRoot: URL) -> [String] {
        let fileManager = FileManager.default
        let templatesDir = overrideRoot.appending(path: "templates", directoryHint: .isDirectory)
        var migrated: [String] = []

        let skeleton = templatesDir.appending(path: "CLAUDE.md")
        let skeletonText = try? String(contentsOf: skeleton, encoding: .utf8)
        let headings = Self.headings(forSkeleton: skeletonText)

        let entries =
            (try? fileManager.contentsOfDirectory(
                at: templatesDir, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        for entry in entries {
            guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            else { continue }
            let file = entry.appending(path: "CLAUDE.md")
            if rewrite(file: file, using: { headingSections(from: $0, headings: headings) }) {
                migrated.append(entry.lastPathComponent)
            }
        }

        if rewrite(file: skeleton, using: strippingSectionPlaceholders(from:)) {
            migrated.append("templates/CLAUDE.md")
        }
        return migrated.sorted()
    }

    private static func rewrite(file: URL, using transform: (String) -> String) -> Bool {
        guard let original = try? String(contentsOf: file, encoding: .utf8) else { return false }
        let rewritten = transform(original)
        guard rewritten != original else { return false }
        do {
            try rewritten.write(to: file, atomically: true, encoding: .utf8)
            return true
        } catch {
            Self.logger.error(
                "couldn't rewrite \(file.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }

    // MARK: - Format conversion (shared with the composer as an in-memory fallback)

    // Open markers become their keyword's heading, close markers vanish, body lines
    // pass through verbatim — a heading-format file re-emits identically. `excluding`
    // drops those keywords' blocks (already consumed by the composer's inline pass).
    static func headingSections(
        from content: String, excluding consumed: Set<String> = [],
        headings: [String: String] = sectionHeadings
    ) -> String {
        var out: [String] = []
        var skippingKeyword: String?
        for line in content.components(separatedBy: "\n") {
            switch marker(ofLine: line) {
            case .open(let raw):
                let keyword = keywordRenames[raw] ?? raw
                skippingKeyword = consumed.contains(keyword) ? keyword : nil
                if skippingKeyword == nil {
                    let normalized = keyword.uppercased().replacingOccurrences(of: " ", with: "_")
                    out.append(headings[keyword] ?? headings[normalized] ?? "## \(keyword)")
                }
            case .close:
                skippingKeyword = nil
            case nil:
                if skippingKeyword == nil { out.append(line) }
            }
        }
        return out.joined(separator: "\n")
    }

    // A migrated skeleton's placeholders are gone but the headings they filled
    // survive — normalizing a heading title recovers the keyword it served
    // (`## Build and test` ⇄ BUILD_AND_TEST), so legacy blocks still find home.
    static func headingsByNormalizedTitle(inSkeleton content: String) -> [String: String] {
        var result: [String: String] = [:]
        for section in MarkdownSectionMerge.parse(content).sections {
            let heading = section.heading.trimmingCharacters(in: .whitespaces)
            let title = heading.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { continue }
            let keyword = title.uppercased().replacingOccurrences(of: " ", with: "_")
            if result[keyword] == nil { result[keyword] = heading }
        }
        return result
    }

    // Later sources win: defaults < title matches < placeholder harvest.
    static func headings(forSkeleton content: String?) -> [String: String] {
        sectionHeadings
            .merging(content.map(headingsByNormalizedTitle(inSkeleton:)) ?? [:]) { _, skeleton in
                skeleton
            }
            .merging(content.map(headingsByKeyword(inSkeleton:)) ?? [:]) { _, skeleton in skeleton }
    }

    // Keyword → the heading directly above its placeholder line, harvested from a
    // legacy skeleton so custom blocks migrate under their custom headings.
    static func headingsByKeyword(inSkeleton content: String) -> [String: String] {
        var result: [String: String] = [:]
        var previous = ""
        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let keyword = placeholderKeyword(ofLine: line), !scalarKeywords.contains(keyword),
                previous.hasPrefix("#")
            {
                result[keyword] = previous
            }
            if !trimmed.isEmpty { previous = trimmed }
        }
        return result
    }

    // Drops `<<<keyword>>>` placeholder lines from a skeleton while keeping their
    // headings (the heading is the merge anchor now) and every scalar token line.
    static func strippingSectionPlaceholders(from content: String) -> String {
        content.components(separatedBy: "\n").filter { line in
            guard let keyword = placeholderKeyword(ofLine: line) else { return true }
            return scalarKeywords.contains(keyword)
        }.joined(separator: "\n")
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

    private static func placeholderKeyword(ofLine line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("<<<"), trimmed.hasSuffix(">>>"), trimmed.count > 6 else { return nil }
        let inner = trimmed.dropFirst(3).dropLast(3).trimmingCharacters(in: .whitespaces)
        guard !inner.isEmpty, !inner.contains("<<<"), !inner.contains(">>>") else { return nil }
        return inner
    }
}
