import Foundation
import Testing

@testable import Plumage

@Suite("SettingsHookMerge")
struct SettingsHookMergeTests {
    private func obj(_ data: Data) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func commands(_ data: Data) throws -> Set<String> {
        let hooks = try #require(try obj(data)["hooks"] as? [String: Any])
        var result: Set<String> = []
        for value in hooks.values {
            for group in value as? [[String: Any]] ?? [] {
                for hook in group["hooks"] as? [[String: Any]] ?? [] {
                    if let command = hook["command"] as? String { result.insert(command) }
                }
            }
        }
        return result
    }

    private func generatedSettings(
        hookFiles: [String], wirings: [HookWiring]
    ) throws -> (
        data: Data, cleanup: () -> Void
    ) {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "MergeGen-\(UUID().uuidString)", directoryHint: .isDirectory)
        for rel in hookFiles {
            let url = root.appending(path: rel)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try "#!/bin/sh\n".write(to: url, atomically: true, encoding: .utf8)
        }
        let composer = SettingsComposer(
            overrides: ScaffoldOverrides(bundledRoot: RepoAssets.root, overrideRoot: root))
        let data = try composer.settingsJSON(for: .other, userWirings: wirings)
        return (data, { try? FileManager.default.removeItem(at: root) })
    }

    @Test("The same command under a different event is merged, not deduped away")
    func sameCommandUnderOtherEventMerges() throws {
        let command = "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/my-hook.sh"
        let existing = """
            {
              "hooks": {
                "PreToolUse": [
                  {
                    "hooks": [
                      { "type": "command", "command": "\\"$CLAUDE_PROJECT_DIR\\"/.claude/hooks/my-hook.sh" }
                    ]
                  }
                ]
              }
            }
            """
        let gen = try generatedSettings(
            hookFiles: ["hooks/my-hook.sh"],
            wirings: [HookWiring(name: "my-hook", event: .stop)])
        defer { gen.cleanup() }

        let outcome = SettingsHookMerge.merge(
            existing: Data(existing.utf8), generated: gen.data)
        guard case .merged(let merged, _) = outcome else {
            Issue.record("expected merge, got \(outcome)")
            return
        }
        let hooks = try #require(try obj(merged)["hooks"] as? [String: Any])
        let stopCommands = ((hooks["Stop"] as? [[String: Any]]) ?? [])
            .flatMap { ($0["hooks"] as? [[String: Any]]) ?? [] }
            .compactMap { $0["command"] as? String }
        #expect(stopCommands.contains(command))
    }

    @Test("Missing hook groups are inserted; every other byte is preserved")
    func insertsMissingPreservesBytes() throws {
        let existing = """
            {
              "myCustomKey":   { "weird":  "spacing" },
              "hooks": {
                "Stop": [
                  {
                    "hooks" : [
                      { "type" : "command", "command" : "echo user-made" }
                    ]
                  }
                ]
              },
              "permissions": { "allow": ["Bash(zzz:*)", "Bash(aaa:*)"] }
            }
            """
        let gen = try generatedSettings(
            hookFiles: ["hooks/my-hook.sh"],
            wirings: [HookWiring(name: "my-hook", event: .stop)])
        defer { gen.cleanup() }

        let outcome = SettingsHookMerge.merge(
            existing: Data(existing.utf8), generated: gen.data)
        guard case .merged(let merged, let added) = outcome else {
            Issue.record("expected merge, got \(outcome)")
            return
        }
        let text = String(decoding: merged, as: UTF8.self)
        // The new group landed under Stop; the user's group survives.
        #expect(try commands(merged).contains("\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/my-hook.sh"))
        #expect(try commands(merged).contains("echo user-made"))
        #expect(added.count >= 1)
        // Hand-made content outside the insertion is byte-identical (odd spacing included).
        #expect(text.contains("\"myCustomKey\":   { \"weird\":  \"spacing\" }"))
        #expect(text.contains("\"permissions\": { \"allow\": [\"Bash(zzz:*)\", \"Bash(aaa:*)\"] }"))
        #expect(text.contains("{ \"type\" : \"command\", \"command\" : \"echo user-made\" }"))
        // Removing the inserted bytes restores the original exactly.
        let insertedRange = try #require(rangeOfInsertion(original: existing, merged: text))
        var restored = text
        restored.removeSubrange(insertedRange)
        #expect(restored == existing)
    }

    // The single contiguous run the merge inserted (insertion-only diff).
    private func rangeOfInsertion(original: String, merged: String) -> Range<String.Index>? {
        guard merged.count > original.count else { return nil }
        let prefix = zip(original, merged).prefix { $0 == $1 }.count
        let insertedCount = merged.count - original.count
        let start = merged.index(merged.startIndex, offsetBy: prefix)
        // Inserted text may share a boundary with what follows; backing off to the
        // common prefix keeps the removal aligned.
        return start..<merged.index(start, offsetBy: insertedCount)
    }

    @Test("A second merge is a no-op (idempotent)")
    func idempotent() throws {
        let existing = Data("{\n  \"hooks\": {}\n}\n".utf8)
        let gen = try generatedSettings(
            hookFiles: ["hooks/my-hook.sh"],
            wirings: [HookWiring(name: "my-hook", event: .stop)])
        defer { gen.cleanup() }

        guard
            case .merged(let merged, _) = SettingsHookMerge.merge(
                existing: existing, generated: gen.data)
        else {
            Issue.record("expected merge")
            return
        }
        #expect(
            SettingsHookMerge.merge(existing: merged, generated: gen.data) == .unchanged)
    }

    @Test("An entry under its own event is not re-added there")
    func presentEntryNotDuplicated() throws {
        let gen = try generatedSettings(
            hookFiles: ["hooks/my-hook.sh"],
            wirings: [HookWiring(name: "my-hook", event: .stop)])
        defer { gen.cleanup() }
        let existing = """
            {
              "hooks": {
                "Stop": [
                  { "hooks": [{ "type": "command", "command": "\\"$CLAUDE_PROJECT_DIR\\"/.claude/hooks/my-hook.sh" }] }
                ]
              }
            }
            """
        let outcome = SettingsHookMerge.merge(existing: Data(existing.utf8), generated: gen.data)
        if case .merged(_, let added) = outcome {
            #expect(!added.contains { $0.contains("my-hook") })
        }
    }

    @Test("Missing hooks key and missing event key are both created")
    func createsHooksAndEventKeys() throws {
        let gen = try generatedSettings(
            hookFiles: ["hooks/my-hook.sh"],
            wirings: [HookWiring(name: "my-hook", event: .stop)])
        defer { gen.cleanup() }
        let noHooksKey = Data("{\n  \"permissions\": { \"allow\": [] }\n}\n".utf8)

        guard
            case .merged(let merged, _) = SettingsHookMerge.merge(
                existing: noHooksKey, generated: gen.data)
        else {
            Issue.record("expected merge")
            return
        }
        #expect(try commands(merged).contains("\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/my-hook.sh"))
        let text = String(decoding: merged, as: UTF8.self)
        #expect(text.contains("\"permissions\": { \"allow\": [] }"))
    }

    @Test("Invalid JSON is left untouched and reported unparseable")
    func unparseableSkipped() throws {
        let gen = try generatedSettings(hookFiles: [], wirings: [])
        defer { gen.cleanup() }
        let outcome = SettingsHookMerge.merge(
            existing: Data("{ not json".utf8), generated: gen.data)
        #expect(outcome == .unparseable)
    }

    @Test("A hooks value that is not an object is unparseable for the merge")
    func nonObjectHooksUnparseable() throws {
        let gen = try generatedSettings(
            hookFiles: ["hooks/my-hook.sh"],
            wirings: [HookWiring(name: "my-hook", event: .stop)])
        defer { gen.cleanup() }
        let outcome = SettingsHookMerge.merge(
            existing: Data("{ \"hooks\": [1, 2] }".utf8), generated: gen.data)
        #expect(outcome == .unparseable)
    }
}
