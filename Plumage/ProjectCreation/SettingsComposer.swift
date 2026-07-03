import Foundation

// `settings.local.json` is intentionally minimal: machine-specific paths and
// MCP opt-ins don't belong in a generated, shared project.
nonisolated struct SettingsComposer {
    var catalog: TemplateCatalog = .bundledDefault
    // Resolves the template's scope-owned user hooks. The default carries no override
    // store, so user wirings only land when a caller passes its real store.
    var overrides: ScaffoldOverrides = ScaffoldOverrides()

    // Canonical hook wiring. Order within an event is intentional: Bash safety
    // hooks before content scans; format before lint.
    private static let wirings: [(name: String, event: String, matcher: String?)] = [
        ("force-plumage-skill", "UserPromptSubmit", nil),
        ("block-dangerous-bash", "PreToolUse", "Bash"),
        ("block-git-commit", "PreToolUse", "Bash"),
        ("block-secret-files", "PreToolUse", "Read|Edit|Write|Glob|Grep"),
        ("block-secrets-in-content", "PreToolUse", "Edit|Write"),
        ("block-during-plumage-plan", "PreToolUse", "Write|Edit|MultiEdit|ExitPlanMode"),
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
        forTemplate templateID: String, toggles: ScaffoldToggles = ScaffoldToggles(),
        userWirings: [HookWiring] = []
    ) throws -> Data {
        let selected = Set(catalog.effectiveHooks(forTemplate: templateID))
        let userHooks = catalog.effectiveUserHooks(forTemplate: templateID, overrides: overrides)
        let userHookBases = Set(userHooks.map(\.base))

        // A component/template tier's own settings.json override is authoritative — its hooks
        // replace that tier's auto-wiring (Base's override wins the whole file upstream).
        // Invalid JSON throws rather than silently dropping hooks; empty here = byte-identical.
        var overriddenRoots = Set<String>()
        var tierOverrides: [ParsedTierSettings] = []
        for root in catalog.looseSurfaceRoots(forTemplate: templateID) where !root.isEmpty {
            guard let data = overrides.tierSettingsOverrideData(forStorageRoot: root) else { continue }
            tierOverrides.append(try JSONDecoder().decode(ParsedTierSettings.self, from: data))
            overriddenRoots.insert(root)
        }
        let builtinTier = builtinHookTiers(forTemplate: templateID)
        var userTier: [String: String] = [:]
        for hook in userHooks { userTier[hook.base] = Self.tierRoot(ofHookRelativePath: hook.relativePath) }

        var groupsByEvent: [HookEvent: [Settings.HookGroup]] = [:]
        // Built-in wirings in declaration order (intentional within an event), minus any
        // whose owning tier is overridden.
        for wiring in Self.wirings
        where selected.contains(wiring.name) && toggles.isEnabled(.hooks, wiring.name)
            && !overriddenRoots.contains(builtinTier[wiring.name] ?? "")
        {
            guard let event = HookEvent(rawValue: wiring.event) else { continue }
            groupsByEvent[event, default: []].append(
                Settings.HookGroup(
                    matcher: wiring.matcher,
                    hooks: [.init(command: Self.command(forFileName: "\(wiring.name).sh"))]))
        }

        // User wirings: gated by the template's scope-owned user hooks (directory =
        // membership) and the hooks toggle, minus any whose owning tier is overridden. The
        // wiring carries the real filename so a `.py` hook points at `…/hooks/<name>.py`.
        for wiring in userWirings
        where userHookBases.contains(wiring.name) && toggles.isEnabled(.hooks, wiring.name)
            && !wiring.event.isUnknown
            && !overriddenRoots.contains(userTier[wiring.name] ?? "")
        {
            groupsByEvent[wiring.event, default: []].append(
                Settings.HookGroup(
                    matcher: wiring.matcher,
                    hooks: [.init(command: Self.command(forFileName: wiring.fileName))]))
        }

        // Override tiers contribute their parsed hooks last (base → components → template
        // order), and union their permissions onto the generated set.
        var allow = permissions(forTemplate: templateID)
        for parsed in tierOverrides {
            for event in parsed.hooks.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
                groupsByEvent[event, default: []].append(contentsOf: parsed.hooks[event] ?? [])
            }
            for permission in parsed.permissions where !allow.contains(permission) {
                allow.append(permission)
            }
        }

        let settings = Settings(
            hooks: Settings.Hooks(groupsByEvent: groupsByEvent),
            permissions: .init(allow: allow))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(settings)
    }

    // Built-in hook name → owning tier storage root: workflow hooks belong to Base (""),
    // a shared component's manifest hooks to that component. Drives which built-in wirings a
    // tier override suppresses.
    private func builtinHookTiers(forTemplate templateID: String) -> [String: String] {
        var tiers: [String: String] = [:]
        for name in catalog.base.workflowHooks { tiers[name] = "" }
        for component in catalog.sharedComponents(forTemplate: templateID) {
            for name in component.files(ofKind: .hook) { tiers[name] = "components/\(component.id)" }
        }
        return tiers
    }

    // The storage root a scoped user-hook path belongs to: "hooks/x" → Base (""),
    // "components/<id>/hooks/x" or "templates/<id>/hooks/x" → that tier.
    static func tierRoot(ofHookRelativePath relativePath: String) -> String {
        guard let range = relativePath.range(of: "/hooks/") else { return "" }
        return String(relativePath[relativePath.startIndex..<range.lowerBound])
    }

    func localSettingsJSON() -> Data {
        Data("{}\n".utf8)
    }

    // The hooks-only settings fragment one tier contributes — the manager's per-tier
    // read-only preview. Built-ins resolve through the static wirings table.
    func tierHooksJSON(builtinNames: [String], userWirings: [HookWiring]) throws -> Data {
        var groupsByEvent: [HookEvent: [Settings.HookGroup]] = [:]
        let selected = Set(builtinNames)
        for wiring in Self.wirings where selected.contains(wiring.name) {
            guard let event = HookEvent(rawValue: wiring.event) else { continue }
            groupsByEvent[event, default: []].append(
                Settings.HookGroup(
                    matcher: wiring.matcher,
                    hooks: [.init(command: Self.command(forFileName: "\(wiring.name).sh"))]))
        }
        for wiring in userWirings where !wiring.event.isUnknown {
            groupsByEvent[wiring.event, default: []].append(
                Settings.HookGroup(
                    matcher: wiring.matcher,
                    hooks: [.init(command: Self.command(forFileName: wiring.fileName))]))
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(HooksOnly(hooks: Settings.Hooks(groupsByEvent: groupsByEvent)))
    }

    private func permissions(forTemplate templateID: String) -> [String] {
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

    private static func command(forFileName fileName: String) -> String {
        "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/\(fileName)"
    }
}

private nonisolated struct HooksOnly: Encodable {
    let hooks: Settings.Hooks
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

    struct HookGroup: Codable {
        let matcher: String?
        let hooks: [HookCommand]
    }

    struct HookCommand: Codable {
        let type = "command"
        let command: String

        enum CodingKeys: String, CodingKey { case type, command }

        init(command: String) { self.command = command }

        // `type` is the constant "command"; decode only `command` so a hand-edited tier
        // override parses, while encoding still emits both keys (byte-identical).
        init(from decoder: any Decoder) throws {
            command = try decoder.container(keyedBy: CodingKeys.self).decode(
                String.self, forKey: .command)
        }
    }

    struct Permissions: Encodable {
        let allow: [String]
    }
}

// A tier's hand-edited settings.json, parsed back into the composer's hook structures so it
// can replace that tier's auto-wiring. Unknown event keys round-trip via `HookEvent.unknown`;
// malformed JSON throws (the caller surfaces it rather than dropping the tier's hooks).
private nonisolated struct ParsedTierSettings: Decodable {
    let hooks: [HookEvent: [Settings.HookGroup]]
    let permissions: [String]

    private enum CodingKeys: String, CodingKey { case hooks, permissions }
    private struct PermissionsBlock: Decodable { let allow: [String]? }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var parsed: [HookEvent: [Settings.HookGroup]] = [:]
        if container.contains(.hooks) {
            let events = try container.nestedContainer(
                keyedBy: Settings.Hooks.EventKey.self, forKey: .hooks)
            for key in events.allKeys {
                guard let event = HookEvent(rawValue: key.stringValue) else { continue }
                parsed[event] = try events.decode([Settings.HookGroup].self, forKey: key)
            }
        }
        hooks = parsed
        permissions =
            try container.decodeIfPresent(PermissionsBlock.self, forKey: .permissions)?.allow ?? []
    }
}
