import Foundation

nonisolated enum WorkflowCommandResolver {
    // Built-in templates, used when override is nil or the override command
    // is empty/whitespace. Each entry is a sequence of lines that the caller
    // injects into the workflow tab as separate REPL turns.
    static let defaultTemplates: [WorkflowAction: [String]] = [
        .plan: ["/plumage-plan <slug>", "<prompt>"],
        .implement: ["/plumage-implement <slug>"],
        .review: ["/plumage-review <slug>"],
    ]

    // Matches each placeholder token in a single left-to-right scan so
    // substituted content can never re-enter the substitution chain
    // (prompt.md containing literal `<spec>` no longer expands recursively).
    private static let tokenPattern: NSRegularExpression = {
        guard let regex = try? NSRegularExpression(pattern: "<(slug|prompt|spec)>", options: []) else {
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

        let promptContents: String =
            promptURL.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        let specContents: String =
            (try? String(contentsOf: specURL, encoding: .utf8)) ?? ""

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
