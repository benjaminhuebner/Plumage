import Foundation

nonisolated enum WorkflowCommandResolver {
    // Plan inlines the prompt after " - " (rather than a second `<prompt>`
    // line) so it stays a single REPL turn — the terminal submits it with one
    // \r instead of two.
    // Implement defaults per type: non-feature issues inline prompt+spec so
    // the skill gets full context without a planned spec; the skill resolves
    // the issue folder from the inlined frontmatter.
    static let defaultTemplates: [WorkflowAction: [String]] = [
        .plan: ["/plumage-plan <slug> - <prompt>"],
        .implement: [
            "#if feature",
            "/plumage-implement <slug>",
            "#else",
            "/plumage-implement <prompt> <spec>",
            "#end",
        ],
        .review: ["/plumage-review <slug>"],
    ]

    static func defaultCommand(for action: WorkflowAction) -> String {
        (defaultTemplates[action] ?? []).joined(separator: "\n")
    }

    // Matches each placeholder token in a single left-to-right scan so
    // substituted content can never re-enter the substitution chain
    // (prompt.md containing literal `<spec>` no longer expands recursively).
    private static let tokenPattern: NSRegularExpression = {
        guard
            let regex = try? NSRegularExpression(
                pattern: "<(slug|prompt|spec)>", options: []
            )
        else {
            preconditionFailure("Invariant: workflow token regex must compile")
        }
        return regex
    }()

    static func resolve(
        action: WorkflowAction,
        slug: String,
        type: IssueType,
        specURL: URL,
        promptURL: URL?,
        override: WorkflowOverride?
    ) -> [String] {
        let template = filteredTemplate(action: action, type: type, override: override)

        let promptContents = promptURL.map { readCapped($0) } ?? ""
        let specContents = readCapped(specURL)

        return template.compactMap { line in
            let substituted = substitute(
                line: line,
                slug: slug,
                prompt: promptContents,
                spec: specContents
            )
            // Filter lines that resolve to empty content. A bare `<prompt>`
            // template with an empty prompt would otherwise inject a blank
            // turn into claude's REPL.
            if substituted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return nil
            }
            return substituted
        }
    }

    // Pure (no disk I/O), so UI can derive button availability from it. A
    // template whose lines are all consumed by directives or guarded away for
    // this type yields no command to inject.
    static func filtersToEmpty(
        action: WorkflowAction,
        type: IssueType,
        override: WorkflowOverride?
    ) -> Bool {
        filteredTemplate(action: action, type: type, override: override)
            .allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    // Directive lines are consumed, never emitted; a `#if` guards until the
    // next `#if`/`#end` or EOF, `#else` inverts the open guard (a stray or
    // repeated `#else` is a consumed no-op). Flat blocks only — no nesting.
    private static func filteredTemplate(
        action: WorkflowAction,
        type: IssueType,
        override: WorkflowOverride?
    ) -> [String] {
        let template: [String] = {
            if let raw = override?.command,
                !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                return raw.components(separatedBy: "\n")
            }
            return defaultTemplates[action] ?? []
        }()

        var activeGuard: WorkflowCommandDirective?
        var inElseBranch = false
        var result: [String] = []
        for line in template {
            if let directive = WorkflowCommandDirective.parse(line: line) {
                switch directive {
                case .open:
                    activeGuard = directive
                    inElseBranch = false
                case .elseBranch:
                    if activeGuard != nil { inElseBranch = true }
                case .end:
                    activeGuard = nil
                    inElseBranch = false
                }
                continue
            }
            if let activeGuard, activeGuard.matches(type) == inElseBranch { continue }
            result.append(line)
        }
        return result
    }

    // Spec/prompt contents expand inline into a single REPL turn (one \r). A
    // pathologically large file would otherwise become one enormous line, which
    // some terminal emulators truncate or split unpredictably. Cap at the same
    // 64 KB the IssueDetail editor uses for its preload, so a spec that already
    // wouldn't display fully also won't inject fully — and mark the cut rather
    // than dropping it silently.
    private static let tokenByteCap = 64 * 1024

    private static func readCapped(_ url: URL) -> String {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return ""
        }
        guard contents.utf8.count > tokenByteCap else { return contents }
        let prefix = String(decoding: contents.utf8.prefix(tokenByteCap), as: UTF8.self)
        return prefix + "\n… [truncated by Plumage: exceeds \(tokenByteCap / 1024) KB]"
    }

    // Single-pass substitution: walks the line once, replaces every matched
    // token with the corresponding payload. Substituted payloads are NOT
    // rescanned, so a `<prompt>` substitution that happens to expand to a
    // string containing `<spec>` stays literal.
    private static func substitute(
        line: String, slug: String, prompt: String, spec: String
    ) -> String {
        let nsLine = line as NSString
        let range = NSRange(location: 0, length: nsLine.length)
        let matches = tokenPattern.matches(in: line, options: [], range: range)
        guard !matches.isEmpty else { return line }

        var result = ""
        var cursor = 0
        for match in matches {
            if match.range.location > cursor {
                result.append(
                    nsLine.substring(
                        with: NSRange(
                            location: cursor,
                            length: match.range.location - cursor
                        )
                    )
                )
            }
            let tokenName = nsLine.substring(with: match.range(at: 1))
            switch tokenName {
            case "slug": result.append(slug)
            case "prompt": result.append(prompt)
            case "spec": result.append(spec)
            default: result.append(nsLine.substring(with: match.range))
            }
            cursor = match.range.location + match.range.length
        }
        if cursor < nsLine.length {
            result.append(
                nsLine.substring(
                    with: NSRange(
                        location: cursor,
                        length: nsLine.length - cursor
                    )
                )
            )
        }
        return result
    }
}
