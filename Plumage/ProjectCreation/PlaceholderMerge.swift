import Foundation

// A keyword-driven placeholder merge for composing same-named text files from layered
// contributions. A skeleton carries `<<<keyword>>>` placeholders (each alone on a
// line); every contribution carries `%% keyword %% … %% /keyword %%` blocks whose
// bodies fill the matching placeholder. Pure and SwiftUI-free so it stays testable.
//
// Matching is exact and case-sensitive: `<<<refdocs>>>` is filled only by
// `%% refdocs %%`, never by `%% ref docs %%`. Multiple blocks with the same keyword
// (within one contribution or across several) join in source order with a blank line
// between them. Whitespace around a keyword inside its markers is ignored; no other
// normalization happens.
nonisolated enum PlaceholderMerge {
    enum MergeError: Error, Equatable {
        // A `%% keyword %%` block was opened but never closed with `%% /keyword %%`
        // (reached EOF or a new block opened first).
        case unclosedBlock(keyword: String)
        // A `%% /keyword %%` close has no matching open, or closes a different keyword
        // than the one currently open.
        case danglingClose(keyword: String)
    }

    static let blockJoinSeparator = "\n\n"

    // MARK: - Harvest

    // The `%% keyword %% … %% /keyword %%` blocks in `contribution`, in source order.
    // Each body is trimmed of surrounding blank lines. Text outside any block is
    // ignored. Throws on an unclosed or dangling block — validation, never silent.
    static func blocks(in contribution: String) throws -> [(keyword: String, body: String)] {
        var result: [(keyword: String, body: String)] = []
        var open: (keyword: String, lines: [String])?
        for line in contribution.components(separatedBy: "\n") {
            switch blockMarker(ofLine: line) {
            case .open(let keyword):
                if let open { throw MergeError.unclosedBlock(keyword: open.keyword) }
                open = (keyword, [])
            case .close(let keyword):
                guard let current = open, current.keyword == keyword else {
                    throw MergeError.danglingClose(keyword: keyword)
                }
                result.append((keyword, joinBody(current.lines)))
                open = nil
            case nil:
                open?.lines.append(line)
            }
        }
        if let open { throw MergeError.unclosedBlock(keyword: open.keyword) }
        return result
    }

    // The harvested blocks of every contribution keyed by keyword, the bodies joined in
    // contribution order. Empty bodies contribute nothing (no stray separator). Throws
    // via `blocks` on any malformed block.
    static func resolvedBlocks(from contributions: [String]) throws -> [String: String] {
        var collected: [String: [String]] = [:]
        for contribution in contributions {
            for block in try blocks(in: contribution) where !block.body.isEmpty {
                collected[block.keyword, default: []].append(block.body)
            }
        }
        return collected.mapValues { $0.joined(separator: blockJoinSeparator) }
    }

    // MARK: - Inline

    // Whether `skeleton` carries at least one `<<<keyword>>>` placeholder (alone on a
    // line). Drives the opt-in decision for same-named-file merging: no placeholder
    // means the file-level override stays untouched.
    static func hasPlaceholders(_ skeleton: String) -> Bool {
        skeleton.components(separatedBy: "\n").contains { placeholderKeyword(ofLine: $0) != nil }
    }

    // Replace each `<<<keyword>>>` line that has a non-empty body in `resolved` with
    // that body. Placeholders without a body are left in place for `dropUnresolved`.
    static func inline(_ skeleton: String, resolved: [String: String]) -> String {
        skeleton.components(separatedBy: "\n").map { line in
            if let keyword = placeholderKeyword(ofLine: line),
                let body = resolved[keyword], !body.isEmpty
            {
                return body
            }
            return line
        }.joined(separator: "\n")
    }

    // Drop every remaining `<<<keyword>>>` line. When a dropped placeholder is
    // immediately preceded by a `## ` heading, that heading goes too, and a single
    // following blank line is consumed — so an unfilled section leaves no orphan.
    static func dropUnresolved(_ text: String) -> String {
        var out: [String] = []
        let lines = text.components(separatedBy: "\n")
        var index = 0
        while index < lines.count {
            if placeholderKeyword(ofLine: lines[index]) != nil {
                if let last = out.last, last.hasPrefix("## ") { out.removeLast() }
                if index + 1 < lines.count,
                    lines[index + 1].trimmingCharacters(in: .whitespaces).isEmpty
                {
                    index += 1
                }
            } else {
                out.append(lines[index])
            }
            index += 1
        }
        return out.joined(separator: "\n")
    }

    // MARK: - Generic merge (non-`CLAUDE.md`, no scalar pass)

    // Compose `skeleton` with `contributions` end to end: harvest blocks, inline them,
    // then drop unfilled placeholders. Used for same-named files other than `CLAUDE.md`,
    // which keeps its own scalar-token pass between inline and drop.
    static func merge(skeleton: String, contributions: [String]) throws -> String {
        let resolved = try resolvedBlocks(from: contributions)
        return dropUnresolved(inline(skeleton, resolved: resolved))
    }

    // MARK: - Markers

    private enum BlockMarker {
        case open(keyword: String)
        case close(keyword: String)
    }

    private static func blockMarker(ofLine line: String) -> BlockMarker? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("%%"), trimmed.hasSuffix("%%"), trimmed.count > 4 else { return nil }
        let inner = trimmed.dropFirst(2).dropLast(2).trimmingCharacters(in: .whitespaces)
        guard !inner.isEmpty else { return nil }
        if inner.hasPrefix("/") {
            let keyword = inner.dropFirst().trimmingCharacters(in: .whitespaces)
            guard !keyword.isEmpty else { return nil }
            return .close(keyword: keyword)
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

    private static func joinBody(_ lines: [String]) -> String {
        lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
