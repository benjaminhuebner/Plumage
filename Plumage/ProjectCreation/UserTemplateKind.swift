import Foundation

// The user-authorable scaffold surfaces: the asset kinds a user can create from
// scratch into the override store and have the scaffolder pick up *without* any
// manifest membership (the scaffolder unions override files in these directories).
// Shared by the Templates settings tab and the Template Manager so the target
// paths, starter content and name sanitization have a single source of truth.
nonisolated enum UserTemplateKind: String, CaseIterable, Identifiable, Sendable {
    case hook
    case skill
    case doc
    case script
    case agent

    var id: String { rawValue }

    // Singular noun for the "Add …" affordance.
    var addNoun: String {
        switch self {
        case .hook: return "Hook"
        case .skill: return "Skill"
        case .doc: return "Doc"
        case .script: return "Script"
        case .agent: return "Agent"
        }
    }

    // A skill is a directory (`skills/<name>/SKILL.md`); the rest are single files.
    var isFolder: Bool { self == .skill }

    // The override directory this kind lives in.
    var directory: String {
        switch self {
        case .hook: return "hooks"
        case .skill: return "skills"
        case .doc: return "docs"
        case .script: return "plumage"
        case .agent: return "agents"
        }
    }

    // The leaf file name (or skill folder name) for a sanitized base name.
    func fileName(forSanitized name: String) -> String {
        switch self {
        case .hook:
            let base = name.hasSuffix(".sh") ? String(name.dropLast(3)) : name
            return "\(base).sh"
        case .skill:
            return name
        case .doc, .agent:
            return name.hasSuffix(".md") ? name : name + ".md"
        case .script:
            return name
        }
    }

    // The override relative path for a freshly authored item with a sanitized name.
    func relativePath(forSanitized name: String) -> String {
        switch self {
        case .skill:
            return "skills/\(name)/SKILL.md"
        default:
            return "\(directory)/\(fileName(forSanitized: name))"
        }
    }

    // Starter content for a new item, keyed off its final leaf name (post collision
    // suffix-walk, so the heading matches the actual file).
    func starter(forLeaf leafName: String) -> String {
        switch self {
        case .hook:
            return "#!/bin/sh\n"
        case .script:
            return leafName.hasSuffix(".py") ? "#!/usr/bin/env python3\n" : "#!/bin/sh\n"
        case .doc:
            return "# \(Self.stem(leafName))\n\n"
        case .agent:
            return "# \(Self.stem(leafName))\n\nDescribe what this agent does.\n"
        case .skill:
            return Self.skillStarter(name: leafName)
        }
    }

    private static func stem(_ fileName: String) -> String {
        (fileName as NSString).deletingPathExtension
    }

    static func skillStarter(name: String) -> String {
        """
        ---
        name: \(name)
        description: Describe when this skill should be used.
        ---

        # \(name)

        Describe what this skill does.
        """ + "\n"
    }

    // Slashes collapse to `-` and `.`/`..`/control chars are rejected so the name can
    // never escape its category folder or resolve to an odd spot under the override root.
    static func sanitizedName(from raw: String) -> String? {
        let collapsed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
        guard !collapsed.isEmpty, collapsed != ".", collapsed != "..",
            collapsed.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
        else { return nil }
        return collapsed
    }

    // The hook base name (toggle key / wiring name) for a `hooks/<name>.sh` path.
    static func hookBaseName(forRelativePath rel: String) -> String? {
        guard rel.hasPrefix("hooks/"), rel.hasSuffix(".sh") else { return nil }
        return String(rel.dropFirst("hooks/".count).dropLast(".sh".count))
    }
}
