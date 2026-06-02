import Foundation

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
    let event: HookEvent
    let matcher: String?

    init(name: String, event: HookEvent, matcher: String? = nil) {
        self.name = name
        self.event = event
        // Normalise an empty/whitespace matcher to nil so it round-trips as
        // `matcher: null` rather than an empty string.
        let trimmed = matcher?.trimmingCharacters(in: .whitespacesAndNewlines)
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
    static func load(from url: URL) throws -> HookWiringStore {
        guard FileManager.default.fileExists(atPath: url.path) else { return HookWiringStore() }
        let data = try Data(contentsOf: url)
        return HookWiringStore(wirings: try JSONDecoder().decode([HookWiring].self, from: data))
    }

    // Production-safe load: any failure falls back to an empty store rather than
    // blocking project creation.
    static func loadStandard() -> HookWiringStore {
        guard let url = try? standardURL(), let store = try? load(from: url) else {
            return HookWiringStore()
        }
        return store
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
