import Foundation

// A subtractive mask over the artifacts a project kind would otherwise scaffold.
// Semantics: a missing entry means "enabled" — an empty store scaffolds exactly
// what the kind's profile lists (byte-identical to pre-override behavior). Only an
// explicit `false` removes an artifact. Persisted flat as `[category: [name: Bool]]`
// at `~/Library/Application Support/Plumage/scaffold-toggles.json`.
nonisolated struct ScaffoldToggles: Codable, Equatable, Sendable {
    enum Category: String, Codable, Sendable, CaseIterable {
        case hooks
        case skills
        case agents
    }

    private var values: [String: [String: Bool]]

    init(values: [String: [String: Bool]] = [:]) {
        self.values = values
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        values = try container.decode([String: [String: Bool]].self)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(values)
    }

    func isEnabled(_ category: Category, _ name: String) -> Bool {
        values[category.rawValue]?[name] ?? true
    }

    mutating func setEnabled(_ category: Category, _ name: String, _ enabled: Bool) {
        values[category.rawValue, default: [:]][name] = enabled
    }

    // The subset of `names` that is enabled, preserving input order.
    func enabledNames(in category: Category, from names: [String]) -> [String] {
        names.filter { isEnabled(category, $0) }
    }

    // MARK: - Persistence

    static let fileName = "scaffold-toggles.json"

    static func standardURL() throws -> URL {
        try ApplicationSupport.appFolderURL().appending(path: fileName)
    }

    // Throws on a present-but-malformed file; returns an empty (all-on) store when
    // the file is absent.
    static func load(from url: URL) throws -> ScaffoldToggles {
        guard FileManager.default.fileExists(atPath: url.path) else { return ScaffoldToggles() }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ScaffoldToggles.self, from: data)
    }

    // Production-safe load: any failure (missing, unreadable, malformed) falls back
    // to the all-on default rather than blocking project creation.
    static func loadStandard() -> ScaffoldToggles {
        guard let url = try? standardURL(), let toggles = try? load(from: url) else {
            return ScaffoldToggles()
        }
        return toggles
    }

    func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    func saveStandard() throws {
        try save(to: Self.standardURL())
    }
}
