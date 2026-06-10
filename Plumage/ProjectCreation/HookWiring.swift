import Foundation
import os

// The Claude Code hook events a user-authored hook can bind to. Raw values are the
// exact keys Claude Code reads from `settings.json`, so they round-trip verbatim.
nonisolated enum HookEvent: String, Codable, Sendable, CaseIterable {
    case userPromptSubmit = "UserPromptSubmit"
    case preToolUse = "PreToolUse"
    case postToolUse = "PostToolUse"
    case notification = "Notification"
    case stop = "Stop"
    case subagentStop = "SubagentStop"
    case preCompact = "PreCompact"
    case sessionStart = "SessionStart"
    case sessionEnd = "SessionEnd"

    // Only the tool-use events match against a tool name; the rest fire
    // unconditionally and emit a group with `matcher: null`.
    var supportsMatcher: Bool {
        switch self {
        case .preToolUse, .postToolUse: return true
        default: return false
        }
    }

    var displayName: String { rawValue }
}

// The persisted trigger metadata for one user-authored hook: which event it binds
// to and an optional tool matcher (e.g. `Edit|Write`). The hook script itself lives
// in the override store under `hooks/<name>.sh`.
nonisolated struct HookWiring: Codable, Sendable, Equatable {
    let name: String
    // The hook's on-disk filename under `hooks/` (e.g. `my-hook.py`). It drives the
    // exact `settings.json` command path. Defaults to `<name>.sh`, so a call site that
    // only knows the base name — and every legacy Bash wiring — keeps its identity.
    let fileName: String
    let event: HookEvent
    let matcher: String?

    init(name: String, event: HookEvent, matcher: String? = nil, fileName: String? = nil) {
        self.name = name
        self.fileName = fileName ?? "\(name).sh"
        self.event = event
        // Normalise an empty/whitespace matcher to nil so it round-trips as
        // `matcher: null` rather than an empty string.
        let trimmed = matcher?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.matcher = (trimmed?.isEmpty == false) ? trimmed : nil
    }

    // Legacy `hook-wirings.json` predates `fileName`; a missing field decodes to the
    // back-compat default `<name>.sh`, so existing Bash wirings round-trip unchanged.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decode(String.self, forKey: .name)
        self.name = name
        self.fileName = try container.decodeIfPresent(String.self, forKey: .fileName) ?? "\(name).sh"
        self.event = try container.decode(HookEvent.self, forKey: .event)
        let raw = try container.decodeIfPresent(String.self, forKey: .matcher)
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.matcher = (trimmed?.isEmpty == false) ? trimmed : nil
    }
}

// Stores the wirings for user-authored hooks as a flat JSON array at
// `~/Library/Application Support/Plumage/hook-wirings.json`, mirroring the
// `ScaffoldToggles` idiom. The scaffolder/migrator load this and pass it to
// `SettingsComposer` so each user hook lands in `settings.json` under its event.
nonisolated struct HookWiringStore: Sendable, Equatable {
    private(set) var wirings: [HookWiring]

    init(wirings: [HookWiring] = []) {
        self.wirings = wirings
    }

    func wiring(named name: String) -> HookWiring? {
        wirings.first { $0.name == name }
    }

    // Insert or replace the wiring for a hook name (names are unique).
    mutating func upsert(_ wiring: HookWiring) {
        if let index = wirings.firstIndex(where: { $0.name == wiring.name }) {
            wirings[index] = wiring
        } else {
            wirings.append(wiring)
        }
    }

    mutating func remove(named name: String) {
        wirings.removeAll { $0.name == name }
    }

    // MARK: - Persistence

    static let fileName = "hook-wirings.json"

    static func standardURL() throws -> URL {
        try ApplicationSupport.appFolderURL().appending(path: fileName)
    }

    // Throws on a present-but-malformed file; returns an empty store when absent.
    // Element decode is lossy: a wiring with an unknown hook event (written
    // by a newer build) is skipped instead of discarding the whole store.
    static func load(from url: URL) throws -> HookWiringStore {
        guard FileManager.default.fileExists(atPath: url.path) else { return HookWiringStore() }
        let data = try Data(contentsOf: url)
        return HookWiringStore(
            wirings: try JSONDecoder().decode(LossyWirings.self, from: data).wirings)
    }

    private struct LossyWirings: Decodable {
        let wirings: [HookWiring]

        init(from decoder: Decoder) throws {
            var container = try decoder.unkeyedContainer()
            var result: [HookWiring] = []
            while !container.isAtEnd {
                if let wiring = try? container.decode(HookWiring.self) {
                    result.append(wiring)
                } else {
                    // Must still advance past the unreadable element —
                    // Discard's no-op init succeeds for any value shape.
                    _ = try? container.decode(Discard.self)
                }
            }
            self.wirings = result
        }

        private struct Discard: Decodable {
            init(from decoder: Decoder) throws {}
        }
    }

    // Production-safe load: any failure falls back to an empty store rather than
    // blocking project creation — but leave a trace, a silently-empty store
    // looks identical to "user has no hooks".
    static func loadStandard() -> HookWiringStore {
        do {
            return try load(from: standardURL())
        } catch {
            Logger(subsystem: "com.plumage", category: "HookWiring").error(
                "loadStandard failed, using empty store: \(String(describing: error), privacy: .public)"
            )
            return HookWiringStore()
        }
    }

    func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(wirings).write(to: url, options: .atomic)
    }

    func saveStandard() throws {
        try save(to: Self.standardURL())
    }
}
