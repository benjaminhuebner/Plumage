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
            let substituted =
                line
                .replacingOccurrences(of: "<slug>", with: slug)
                .replacingOccurrences(of: "<prompt>", with: promptContents)
                .replacingOccurrences(of: "<spec>", with: specContents)
            // Filter lines that resolve to empty content. A bare `<prompt>`
            // template with an empty prompt would otherwise inject a blank
            // turn into claude's REPL.
            if substituted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return nil
            }
            return substituted
        }
    }
}
