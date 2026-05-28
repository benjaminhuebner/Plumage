import Foundation

// Reads/writes the per-project pinned-file set as `<bundle>/pins.json`.
// Mirrors the ClaudeProjectFiles/ConfigLoader pattern: a nonisolated enum of
// static functions over project-local paths, no Claude Code internals.
nonisolated enum PinnedFilesStore {
    static let fileName = "pins.json"

    // Small forward-compatible envelope. A future field can be added without
    // breaking older readers (unknown keys are ignored by JSONDecoder).
    struct Stored: Codable, Sendable {
        var pinned: [String]
    }

    // nil  → pins.json absent (never seeded) → caller may seed defaults.
    // []   → present but empty, OR present-but-corrupt: a deliberate/!-recoverable
    //        empty set the caller must NOT reseed over.
    static func load(bundle: URL) -> [String]? {
        let url = bundle.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let data = try? Data(contentsOf: url) else { return [] }
        guard let decoded = try? JSONDecoder().decode(Stored.self, from: data) else {
            return []
        }
        return decoded.pinned
    }

    // Atomic JSON write. Pretty-printed for human-readability; the array order
    // is the pin order and is preserved (only object keys would be sorted,
    // which we don't request).
    static func save(_ paths: [String], bundle: URL) throws {
        let url = bundle.appendingPathComponent(fileName)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        let data = try encoder.encode(Stored(pinned: paths))
        try data.write(to: url, options: [.atomic])
    }

    // Default pin set for a project that has never been seeded. Resolves
    // `CLAUDE.md` at the root, falling back to `.claude/CLAUDE.md`, plus
    // `.claude/docs/PROJECT.md`. Only existing paths are returned — a missing
    // default is skipped rather than producing a dead pin.
    static func seedDefaults(projectURL: URL) -> [String] {
        let fm = FileManager.default
        var result: [String] = []

        let rootClaude = projectURL.appendingPathComponent("CLAUDE.md")
        let nestedClaude = projectURL.appendingPathComponent(".claude/CLAUDE.md")
        if fm.fileExists(atPath: rootClaude.path) {
            result.append("CLAUDE.md")
        } else if fm.fileExists(atPath: nestedClaude.path) {
            result.append(".claude/CLAUDE.md")
        }

        let project = projectURL.appendingPathComponent(".claude/docs/PROJECT.md")
        if fm.fileExists(atPath: project.path) {
            result.append(".claude/docs/PROJECT.md")
        }

        return result
    }
}
