import Foundation

// Builds `.claude/settings.json` for a project kind: the hook wiring (only the
// hooks the profile selects, in the canonical event order) plus a permission
// allowlist matching the kind's tooling. `settings.local.json` is intentionally
// minimal — machine-specific paths and MCP opt-ins don't belong in a generated,
// shared project.
nonisolated struct SettingsComposer {
    // Canonical hook wiring. Order within an event is intentional: Bash safety
    // hooks before content scans; format before lint.
    private static let wirings: [(name: String, event: String, matcher: String?)] = [
        ("force-plumage-skill", "UserPromptSubmit", nil),
        ("block-dangerous-bash", "PreToolUse", "Bash"),
        ("block-git-commit", "PreToolUse", "Bash"),
        ("guard-xcodebuild", "PreToolUse", "Bash"),
        ("block-secret-files", "PreToolUse", "Read|Edit|Write"),
        ("block-secrets-in-content", "PreToolUse", "Edit|Write"),
        ("no-doc-comments", "PreToolUse", "Write|Edit|MultiEdit"),
        ("format-swift", "PostToolUse", "Edit|Write"),
        ("lint-swift", "PostToolUse", "Edit|Write"),
        ("stop-after-spec-approved", "PostToolUse", "Edit|Write|MultiEdit"),
    ]

    private static let commonPermissions = [
        "Bash(git status:*)", "Bash(git diff:*)", "Bash(git log:*)",
        "Bash(git branch:*)", "Bash(git show:*)", "Bash(git rev-parse:*)",
        "Bash(rg:*)", "Bash(jq:*)",
    ]

    func settingsJSON(for kind: ProjectKind) throws -> Data {
        let selected = Set(kind.profile.hookNames)
        func groups(_ event: String) -> [Settings.HookGroup]? {
            let groups = Self.wirings
                .filter { $0.event == event && selected.contains($0.name) }
                .map {
                    Settings.HookGroup(
                        matcher: $0.matcher, hooks: [.init(command: Self.command(for: $0.name))])
                }
            return groups.isEmpty ? nil : groups
        }
        let settings = Settings(
            hooks: .init(
                userPromptSubmit: groups("UserPromptSubmit"),
                preToolUse: groups("PreToolUse"),
                postToolUse: groups("PostToolUse")),
            permissions: .init(allow: permissions(for: kind)))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(settings)
    }

    func localSettingsJSON() -> Data {
        Data("{}\n".utf8)
    }

    func write(for kind: ProjectKind, toClaudeDir claudeDir: URL) throws {
        try settingsJSON(for: kind).write(to: claudeDir.appending(path: "settings.json"))
        try localSettingsJSON().write(to: claudeDir.appending(path: "settings.local.json"))
    }

    func permissions(for kind: ProjectKind) -> [String] {
        var allow = Self.commonPermissions
        let gate = kind.profile.gateCommands
        if let build = gate.build {
            if build.contains("xcodebuild") { allow.append("Bash(xcodebuild:*)") }
            if build.contains("swift build") {
                allow += ["Bash(swift build:*)", "Bash(swift test:*)", "Bash(swift package:*)"]
            }
        }
        if gate.format != nil { allow.append("Bash(swift-format:*)") }
        if gate.lint != nil { allow.append("Bash(swiftlint:*)") }
        return allow
    }

    private static func command(for hookName: String) -> String {
        "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/\(hookName).sh"
    }
}

private nonisolated struct Settings: Encodable {
    let hooks: Hooks
    let permissions: Permissions

    struct Hooks: Encodable {
        let userPromptSubmit: [HookGroup]?
        let preToolUse: [HookGroup]?
        let postToolUse: [HookGroup]?

        enum CodingKeys: String, CodingKey {
            case userPromptSubmit = "UserPromptSubmit"
            case preToolUse = "PreToolUse"
            case postToolUse = "PostToolUse"
        }
    }

    struct HookGroup: Encodable {
        let matcher: String?
        let hooks: [HookCommand]
    }

    struct HookCommand: Encodable {
        let type = "command"
        let command: String
    }

    struct Permissions: Encodable {
        let allow: [String]
    }
}
