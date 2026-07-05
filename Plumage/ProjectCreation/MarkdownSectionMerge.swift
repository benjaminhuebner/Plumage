import Foundation

// Merges layered Markdown by heading (exact trimmed heading line, level included):
// a repeated heading fuses the contribution's block before its first blank line into
// the base block; lines the base already has are skipped, new headings append last.
nonisolated enum MarkdownSectionMerge {
    struct Document {
        var frontmatter: [String]
        var preamble: [String]
        var sections: [(heading: String, body: [String])]
    }

    static func merge(variants: [String]) -> String {
        guard var document = variants.first.map(parse) else { return "" }
        for variant in variants.dropFirst() {
            let contribution = parse(variant)
            // YAML frontmatter is structured metadata, not prose — the most
            // specific variant's frontmatter wins wholesale, never line-merged.
            if !contribution.frontmatter.isEmpty { document.frontmatter = contribution.frontmatter }
            appendUnmatched(contribution.preamble, to: &document)
            for section in contribution.sections {
                if let index = document.sections.firstIndex(where: {
                    sectionKey($0.heading) == sectionKey(section.heading)
                }) {
                    document.sections[index].body = mergedBody(
                        base: document.sections[index].body, contribution: section.body)
                } else {
                    document.sections.append(section)
                }
            }
        }
        return render(document)
    }

    // A heading whose section carries no content is an orphan after composition —
    // used by the composer so an unfilled skeleton section leaves no trace. Level-1
    // headings stay, as does a parent whose content lives in a surviving subheading.
    static func droppingEmptySections(_ text: String) -> String {
        var document = parse(text)
        var kept = [Bool](repeating: false, count: document.sections.count)
        for index in document.sections.indices.reversed() {
            let section = document.sections[index]
            if sectionKey(section.heading).hasPrefix("# ")
                || section.body.contains(where: { !isBlank($0) })
            {
                kept[index] = true
                continue
            }
            let level = headingLevel(section.heading)
            var next = index + 1
            while next < document.sections.count,
                headingLevel(document.sections[next].heading) > level
            {
                if kept[next] {
                    kept[index] = true
                    break
                }
                next += 1
            }
        }
        document.sections = zip(document.sections, kept).filter { $0.1 }.map { $0.0 }
        return render(document)
    }

    // MARK: - Parse / render

    static func parse(_ text: String) -> Document {
        var lines = text.components(separatedBy: "\n")
        var frontmatter: [String] = []
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---",
            let close = lines.dropFirst().firstIndex(where: {
                $0.trimmingCharacters(in: .whitespaces) == "---"
            })
        {
            frontmatter = Array(lines[0...close])
            lines.removeSubrange(0...close)
        }
        var preamble: [String] = []
        var sections: [(heading: String, body: [String])] = []
        var inFence = false
        for line in lines {
            if !inFence, isHeading(line) {
                sections.append((heading: line, body: []))
                continue
            }
            if isFenceDelimiter(line) { inFence.toggle() }
            if sections.isEmpty {
                preamble.append(line)
            } else {
                sections[sections.count - 1].body.append(line)
            }
        }
        return Document(frontmatter: frontmatter, preamble: preamble, sections: sections)
    }

    private static func render(_ document: Document) -> String {
        var lines = document.frontmatter + document.preamble
        for (index, section) in document.sections.enumerated() {
            lines.append(section.heading)
            lines.append(contentsOf: section.body)
            // A following heading needs a separating blank line; merged fragments
            // may end flush with their last item.
            if index < document.sections.count - 1, let last = lines.last, !isBlank(last) {
                lines.append("")
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Merge mechanics

    // Contribution prose that matches no heading lands at the document's bottom,
    // never above the base's sections. Lines the document already has anywhere
    // are skipped so merging an identical copy stays a no-op.
    private static func appendUnmatched(_ contribution: [String], to document: inout Document) {
        let existing = document.preamble + document.sections.flatMap { [$0.heading] + $0.body }
        let existingFences = fenceBlocks(in: existing)
        let fresh = units(of: contribution).filter { unit in
            switch unit {
            case .line(let line):
                return !isBlank(line) && !existing.contains { equivalent($0, line) }
            case .fence(let block):
                return !existingFences.contains(trimmedLines(block))
            }
        }.flatMap(\.lines)
        guard !fresh.isEmpty else { return }
        var target =
            document.sections.isEmpty
            ? document.preamble : document.sections[document.sections.count - 1].body
        let trailingBlanks = suffixBlanks(of: target)
        target.removeLast(trailingBlanks.count)
        if !target.isEmpty || !document.sections.isEmpty { target.append("") }
        target.append(contentsOf: fresh)
        target.append(contentsOf: trailingBlanks)
        if document.sections.isEmpty {
            document.preamble = target
        } else {
            document.sections[document.sections.count - 1].body = target
        }
    }

    private static func mergedBody(base: [String], contribution: [String]) -> [String] {
        guard base.contains(where: { !isBlank($0) }) else { return contribution }
        let baseFences = fenceBlocks(in: base)
        let fresh = units(of: contribution).filter { unit in
            switch unit {
            case .line(let line):
                return isBlank(line) || !base.contains { equivalent($0, line) }
            case .fence(let block):
                return !baseFences.contains(trimmedLines(block))
            }
        }
        var attached: [String] = []
        var tail: [String] = []
        var pastBlank = false
        for unit in fresh {
            switch unit {
            case .line(let line) where isBlank(line):
                pastBlank = true
            case .line, .fence:
                if pastBlank {
                    tail.append(contentsOf: unit.lines)
                } else {
                    attached.append(contentsOf: unit.lines)
                }
            }
        }
        var result = base
        let insertion = insertionIndex(in: result)
        result.insert(contentsOf: attached, at: insertion)
        if !tail.isEmpty {
            // Keep the section's trailing blank run where it was: tail content
            // slots in before it, so a file-final newline survives the merge.
            let trailingBlanks = suffixBlanks(of: result)
            result.removeLast(trailingBlanks.count)
            if !result.isEmpty { result.append("") }
            result.append(contentsOf: tail)
            result.append(contentsOf: trailingBlanks)
        }
        return result
    }

    // Merge granule: a fenced code block travels, dedups, and splits as one unit —
    // line-wise treatment would strip its delimiters or tear it at internal blanks.
    private enum Unit {
        case line(String)
        case fence([String])

        var lines: [String] {
            switch self {
            case .line(let line): return [line]
            case .fence(let block): return block
            }
        }
    }

    private static func units(of lines: [String]) -> [Unit] {
        var result: [Unit] = []
        var open: [String]?
        for line in lines {
            if open != nil {
                open?.append(line)
                if isFenceDelimiter(line) {
                    result.append(.fence(open ?? []))
                    open = nil
                }
            } else if isFenceDelimiter(line) {
                open = [line]
            } else {
                result.append(.line(line))
            }
        }
        // An unterminated fence still runs to the end, mirroring `parse`.
        if let dangling = open { result.append(.fence(dangling)) }
        return result
    }

    private static func fenceBlocks(in lines: [String]) -> [[String]] {
        units(of: lines).compactMap { unit in
            guard case .fence(let block) = unit else { return nil }
            return trimmedLines(block)
        }
    }

    private static func trimmedLines(_ lines: [String]) -> [String] {
        lines.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func suffixBlanks(of lines: [String]) -> [String] {
        var result: [String] = []
        for line in lines.reversed() {
            guard isBlank(line) else { break }
            result.append(line)
        }
        return result.reversed()
    }

    // First blank line after content ends the attached block — but a blank inside
    // a fenced block doesn't count, or the insertion point would tear the fence.
    private static func insertionIndex(in body: [String]) -> Int {
        var offset = 0
        var seenContent = false
        for unit in units(of: body) {
            switch unit {
            case .line(let line) where isBlank(line):
                if seenContent { return offset }
            case .line, .fence:
                seenContent = true
            }
            offset += unit.lines.count
        }
        return body.count
    }

    // MARK: - Line predicates

    private static func isHeading(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let level = trimmed.prefix { $0 == "#" }
        guard (1...6).contains(level.count) else { return false }
        return trimmed.dropFirst(level.count).first == " "
    }

    private static func isFenceDelimiter(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~")
    }

    private static func headingLevel(_ heading: String) -> Int {
        sectionKey(heading).prefix { $0 == "#" }.count
    }

    private static func sectionKey(_ heading: String) -> String {
        heading.trimmingCharacters(in: .whitespaces)
    }

    private static func isBlank(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private static func equivalent(_ lhs: String, _ rhs: String) -> Bool {
        lhs.trimmingCharacters(in: .whitespaces) == rhs.trimmingCharacters(in: .whitespaces)
    }
}
