import Foundation

// `settings.local.json` is intentionally minimal: machine-specific paths and
// MCP opt-ins don't belong in a generated, shared project.
nonisolated struct SettingsComposer {
    var catalog: TemplateCatalog = .bundledDefault

    // Canonical hook wiring. Order within an event is intentional: Bash safety
    // hooks before content scans; format before lint.
    private static let wirings: [(name: String, event: String, matcher: String?)] = [
        ("force-plumage-skill", "UserPromptSubmit", nil),
        ("block-dangerous-bash", "PreToolUse", "Bash"),
        ("block-git-commit", "PreToolUse", "Bash"),
        ("block-secret-files", "PreToolUse", "Read|Edit|Write"),
        ("block-secrets-in-content", "PreToolUse", "Edit|Write"),
        ("format-swift", "PostToolUse", "Edit|Write"),
        ("lint-swift", "PostToolUse", "Edit|Write"),
        ("stop-after-spec-approved", "PostToolUse", "Edit|Write|MultiEdit"),
    ]

    private static let commonPermissions = [
        "Bash(git status:*)", "Bash(git diff:*)", "Bash(git log:*)",
        "Bash(git branch:*)", "Bash(git show:*)", "Bash(git rev-parse:*)",
        "Bash(rg:*)", "Bash(jq:*)",
    ]

    func settingsJSON(
        for kind: ProjectKind, toggles: ScaffoldToggles = ScaffoldToggles(),
        userWirings: [HookWiring] = []
    ) throws -> Data {
        try settingsJSON(forTemplate: kind.rawValue, toggles: toggles, userWirings: userWirings)
    }

    func settingsJSON(
        forTemplate templateID: String, toggles: ScaffoldToggles = ScaffoldToggles(),
        userWirings: [HookWiring] = []
    ) throws -> Data {
        let selected = Set(catalog.effectiveHooks(forTemplate: templateID))
        var groupsByEvent: [HookEvent: [Settings.HookGroup]] = [:]

        // Built-in wirings: filtered to the kind's profile and the hooks toggle, in
        // declaration order (ordering within an event is intentional).
        for wiring in Self.wirings
        where selected.contains(wiring.name) && toggles.isEnabled(.hooks, wiring.name) {
            guard let event = HookEvent(rawValue: wiring.event) else { continue }
            groupsByEvent[event, default: []].append(
                Settings.HookGroup(
                    matcher: wiring.matcher, hooks: [.init(command: Self.command(for: wiring.name))]))
        }

        // User wirings: not gated by the kind profile (they fire in every project),
        // only by the hooks toggle. Appended after the built-ins per event.
        for wiring in userWirings where toggles.isEnabled(.hooks, wiring.name) {
            groupsByEvent[wiring.event, default: []].append(
                Settings.HookGroup(
                    matcher: wiring.matcher, hooks: [.init(command: Self.command(for: wiring.name))]))
        }

        let settings = Settings(
            hooks: Settings.Hooks(groupsByEvent: groupsByEvent),
            permissions: .init(allow: permissions(forTemplate: templateID)))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(settings)
    }

    func localSettingsJSON() -> Data {
        Data("{}\n".utf8)
    }

    func write(
        for kind: ProjectKind, toggles: ScaffoldToggles = ScaffoldToggles(),
        userWirings: [HookWiring] = [], toClaudeDir claudeDir: URL
    ) throws {
        try write(
            forTemplate: kind.rawValue, toggles: toggles, userWirings: userWirings,
            toClaudeDir: claudeDir)
    }

    func write(
        forTemplate templateID: String, toggles: ScaffoldToggles = ScaffoldToggles(),
        userWirings: [HookWiring] = [], toClaudeDir claudeDir: URL
    ) throws {
        try settingsJSON(forTemplate: templateID, toggles: toggles, userWirings: userWirings).write(
            to: claudeDir.appending(path: "settings.json"))
        try localSettingsJSON().write(to: claudeDir.appending(path: "settings.local.json"))
    }

    func permissions(for kind: ProjectKind) -> [String] {
        permissions(forTemplate: kind.rawValue)
    }

    func permissions(forTemplate templateID: String) -> [String] {
        var allow = Self.commonPermissions
        let gate = catalog.effectiveGateCommands(forTemplate: templateID)
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

    // Event-keyed dynamic encoding: any `HookEvent` round-trips as its own
    // `settings.json` key. Empty events are omitted; with `.sortedKeys` the key
    // order is deterministic, so built-in output is byte-identical to the prior
    // three-fixed-key encoder.
    struct Hooks: Encodable {
        let groupsByEvent: [HookEvent: [HookGroup]]

        struct EventKey: CodingKey {
            let stringValue: String
            let intValue: Int? = nil
            init(_ event: HookEvent) { stringValue = event.rawValue }
            init?(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { nil }
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: EventKey.self)
            for (event, groups) in groupsByEvent where !groups.isEmpty {
                try container.encode(groups, forKey: EventKey(event))
            }
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
