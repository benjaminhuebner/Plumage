import Foundation

nonisolated enum WorkflowCommandResolver {
    // Built-in templates, used when override is nil or the override command
    // is empty/whitespace. Each entry is a sequence of lines that the caller
    // injects into the workflow tab as separate REPL turns.
    //
    // <prompt-suffix> expands to " - <prompt>" when prompt.md is non-empty,
    // or to "" when it is absent — so Plan stays a single REPL turn regardless,
    // which lets the terminal submit it with one \r instead of two.
    static let defaultTemplates: [WorkflowAction: [String]] = [
        .plan: ["/plumage-plan <slug><prompt-suffix>"],
        .implement: ["/plumage-implement <slug>"],
        .review: ["/plumage-review <slug>"],
    ]

    // Matches each placeholder token in a single left-to-right scan so
    // substituted content can never re-enter the substitution chain
    // (prompt.md containing literal `<spec>` no longer expands recursively).
    // Alternation is longest-first (prompt-suffix before prompt) so the match
    // doesn't depend on ICU backtracking — a non-backtracking refactor stays
    // correct.
    private static let tokenPattern: NSRegularExpression = {
        guard
            let regex = try? NSRegularExpression(
                pattern: "<(slug|prompt-suffix|prompt|spec)>", options: []
            )
        else {
            preconditionFailure("Invariant: workflow token regex must compile")
        }
        return regex
    }()

    static func resolve(
        action: WorkflowAction,
        slug: String,
        specURL: URL,
        promptURL: URL?,
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
            case "prompt-suffix": result.append(prompt.isEmpty ? "" : " - \(prompt)")
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
