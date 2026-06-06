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
    case agent
    // Typeless authoring: an arbitrary file (name taken literally, extension and all)
    // or an empty folder, created relative to the selected tree folder rather than a
    // fixed category directory.
    case file
    case folder

    var id: String { rawValue }

    // Singular noun for the "Add …" affordance.
    var addNoun: String {
        switch self {
        case .hook: return "Hook"
        case .skill: return "Skill"
        case .doc: return "Doc"
        case .agent: return "Agent"
        case .file: return "File"
        case .folder: return "Folder"
        }
    }

    // A skill or a plain folder is a directory; the rest are single files.
    var isFolder: Bool { self == .skill || self == .folder }

    // True when the item is created relative to the selected tree folder (no fixed
    // category directory) — the typeless `.file` / `.folder` kinds.
    var usesTargetDirectory: Bool { self == .file || self == .folder }

    // The override directory a typed kind lives in. Typeless kinds carry no fixed
    // directory — they are created under the caller-supplied target.
    var directory: String {
        switch self {
        case .hook: return "hooks"
        case .skill: return "skills"
        case .doc: return "docs"
        case .agent: return "agents"
        case .file, .folder: return ""
        }
    }

    // The leaf file name (or skill/folder name) for a sanitized base name. A typeless
    // file keeps the name verbatim (the user types the extension); a folder is named
    // as typed.
    func fileName(forSanitized name: String) -> String {
        switch self {
        case .hook:
            let base = name.hasSuffix(".sh") ? String(name.dropLast(3)) : name
            return "\(base).sh"
        case .skill, .file, .folder:
            return name
        case .doc, .agent:
            return name.hasSuffix(".md") ? name : name + ".md"
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
        case .doc:
            return "# \(Self.stem(leafName))\n\n"
        case .agent:
            return "# \(Self.stem(leafName))\n\nDescribe what this agent does.\n"
        case .skill:
            return Self.skillStarter(name: leafName)
        case .file, .folder:
            // An arbitrary file starts empty; a folder has no file content.
            return ""
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
