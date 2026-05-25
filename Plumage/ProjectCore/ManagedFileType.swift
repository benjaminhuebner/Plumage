import Foundation

nonisolated enum ManagedFileType: String, CaseIterable, Sendable, Hashable, Codable {
    case docs
    case hooks
    case agents
    case rules
    case outputStyles

    var relativePath: String {
        switch self {
        case .docs: return ".claude/docs"
        case .hooks: return ".claude/hooks"
        case .agents: return ".claude/agents"
        case .rules: return ".claude/rules"
        case .outputStyles: return ".claude/output-styles"
        }
    }

    var allowedExtensions: Set<String> {
        switch self {
        case .docs, .agents, .rules, .outputStyles: return ["md"]
        case .hooks: return ["sh", "py"]
        }
    }

    var defaultExtension: String {
        switch self {
        case .docs, .agents, .rules, .outputStyles: return "md"
        case .hooks: return "sh"
        }
    }

    // Recursive enumeration: agents and rules are addressed as `<group>/<name>.md`
    // in user docs; we list every `.md` below the root. Output-styles, docs and
    // hooks stay top-level.
    var recursive: Bool {
        switch self {
        case .agents, .rules: return true
        case .docs, .hooks, .outputStyles: return false
        }
    }

    // Whether Finder-drops of full folders are accepted into this section.
    // Recursive sections accept them (they expand into nested files); hooks
    // also accepts (existing behavior). Single-file sections reject.
    var allowsSubfolders: Bool {
        switch self {
        case .agents, .rules, .hooks: return true
        case .docs, .outputStyles: return false
        }
    }

    var sectionTitle: String {
        switch self {
        case .docs: return "Docs"
        case .hooks: return "Hooks"
        case .agents: return "Agents"
        case .rules: return "Rules"
        case .outputStyles: return "Output Styles"
        }
    }

    // Singular form used in context-menu buttons ("New Agent", "New Rule",
    // "New Output Style") and in keyboard-shortcut menu items.
    var singularName: String {
        switch self {
        case .docs: return "Doc"
        case .hooks: return "Hook"
        case .agents: return "Agent"
        case .rules: return "Rule"
        case .outputStyles: return "Output Style"
        }
    }

    var systemImage: String {
        switch self {
        case .docs: return "doc.text"
        case .hooks: return "terminal"
        case .agents: return "person.crop.rectangle.stack"
        case .rules: return "checklist"
        case .outputStyles: return "paintpalette"
        }
    }

    // Icon used on individual file rows (not the section header).
    var fileRowSystemImage: String {
        switch self {
        case .docs, .agents, .rules, .outputStyles: return "doc.text"
        case .hooks: return "scroll"
        }
    }

    var defaultName: String {
        "untitled.\(defaultExtension)"
    }

    var rejectionMessage: String {
        switch self {
        case .docs:
            return "Only .md files allowed in Docs"
        case .hooks:
            return "Only .sh/.py files or folders allowed in Hooks"
        case .agents:
            return "Only .md files or folders allowed in Agents"
        case .rules:
            return "Only .md files or folders allowed in Rules"
        case .outputStyles:
            return "Only .md files allowed in Output Styles"
        }
    }

    // Default file body for create flows. Agents/rules/output-styles get a
    // minimal YAML frontmatter stub so the new file is immediately a valid
    // Claude-Code artifact. Docs stay blank (consistent with prior createDoc).
    // Hooks return a shebang based on extension.
    func defaultStub(filename: String) -> String {
        switch self {
        case .docs:
            return ""
        case .hooks:
            let ext = (filename as NSString).pathExtension.lowercased()
            switch ext {
            case "py": return "#!/usr/bin/env python3\n"
            default: return "#!/usr/bin/env bash\nset -euo pipefail\n"
            }
        case .agents:
            return frontmatterStub(name: stem(filename), kind: "agent")
        case .rules:
            return frontmatterStub(name: stem(filename), kind: "rule")
        case .outputStyles:
            return frontmatterStub(name: stem(filename), kind: "output-style")
        }
    }

    private func stem(_ filename: String) -> String {
        (filename as NSString).deletingPathExtension
    }

    private func frontmatterStub(name: String, kind: String) -> String {
        """
        ---
        name: \(name)
        description: TODO describe what this \(kind) does
        ---

        """
    }
}
