import Foundation

// Scalar tokens (project name, stack summary, the nested `<<<XCODE_MCP_LINE>>>`)
// are substituted last so they resolve even inside an inlined `%% SECTION %%`
// block.
nonisolated struct ClaudeMdComposer {
    let overrides: ScaffoldOverrides
    // The resolved catalog supplies the effective layer list and scalar tokens.
    // Defaults to the bundled catalog, which reproduces `ProjectKind.profile` exactly.
    var catalog: TemplateCatalog = .bundledDefault

    nonisolated struct Output: Hashable, Sendable {
        let claudeMd: String
        let skillKeywords: String
    }

    private static let sectionTokens: [(token: String, section: String)] = [
        ("<<<LAYOUT>>>", "LAYOUT"),
        ("<<<CONVENTIONS>>>", "CONVENTIONS"),
        ("<<<BUILD_AND_TEST>>>", "BUILD AND TEST"),
        ("<<<PITFALLS>>>", "PITFALLS"),
    ]

    func compose(spec: NewProjectSpec) throws -> Output {
        let templateID = spec.templateID
        let layers = catalog.effectiveLayers(forTemplate: templateID)
        let base = try overrides.string(atRelative: "templates/CLAUDE.md")

        var sections: [String: [String]] = [:]
        for layer in layers {
            let layerContent = try overrides.string(atRelative: "templates/\(layer)/CLAUDE.md")
            for parsed in Self.parseSections(layerContent) where !parsed.body.isEmpty {
                sections[parsed.name, default: []].append(parsed.body)
            }
        }

        let composed = Dictionary(
            uniqueKeysWithValues: Self.sectionTokens.map { entry in
                (entry.token, (sections[entry.section] ?? []).joined(separator: "\n\n"))
            })

        var result = Self.inlineSections(base, composed: composed)
        result =
            result
            .replacingOccurrences(of: "<<<PROJECT_NAME>>>", with: spec.name)
            .replacingOccurrences(of: "<<<PROJECT_TAGLINE>>>", with: spec.tagline)
            .replacingOccurrences(
                of: "<<<STACK_SUMMARY>>>",
                with: catalog.effectiveStackSummary(forTemplate: templateID)
            )
            .replacingOccurrences(
                of: "<<<XCODE_MCP_LINE>>>",
                with: catalog.effectiveXcodeMcpLine(forTemplate: templateID)
            )

        let skillKeywords = (sections["SKILL_KEYWORDS"] ?? []).joined(separator: ", ")
        return Output(claudeMd: result, skillKeywords: skillKeywords)
    }

    // Parse `%% SECTION %%` blocks in source order. A block runs from its header
    // to the next header or EOF; the body is trimmed of surrounding blank lines.
    static func parseSections(_ content: String) -> [(name: String, body: String)] {
        var result: [(name: String, lines: [String])] = []
        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("%%"), trimmed.hasSuffix("%%"), trimmed.count > 4 {
                let name = String(trimmed.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespaces)
                result.append((name, []))
            } else if !result.isEmpty {
                result[result.count - 1].lines.append(line)
            }
        }
        return result.map {
            ($0.name, $0.lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    // Replace each section token (alone on its line) with its composed content.
    // Empty content drops the token's line and the preceding `## Heading`.
    private static func inlineSections(_ base: String, composed: [String: String]) -> String {
        var out: [String] = []
        let lines = base.components(separatedBy: "\n")
        var index = 0
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if let content = composed[trimmed] {
                if content.isEmpty {
                    if let last = out.last, last.hasPrefix("## ") {
                        out.removeLast()
                    }
                    if index + 1 < lines.count,
                        lines[index + 1].trimmingCharacters(in: .whitespaces).isEmpty
                    {
                        index += 1
                    }
                } else {
                    out.append(content)
                }
            } else {
                out.append(lines[index])
            }
            index += 1
        }
        return out.joined(separator: "\n")
    }
}
