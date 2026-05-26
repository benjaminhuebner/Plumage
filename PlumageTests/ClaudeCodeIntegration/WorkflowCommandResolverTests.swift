import Foundation
import Testing

@testable import Plumage

@Suite("WorkflowCommandResolver")
struct WorkflowCommandResolverTests {
    private func makeFixture(
        spec: String = "spec body",
        prompt: String? = "prompt body"
    ) throws -> (specURL: URL, promptURL: URL?, cleanup: () -> Void) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WCR-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let specURL = dir.appendingPathComponent("spec.md")
        try spec.write(to: specURL, atomically: true, encoding: .utf8)
        var promptURL: URL?
        if let prompt {
            let url = dir.appendingPathComponent("prompt.md")
            try prompt.write(to: url, atomically: true, encoding: .utf8)
            promptURL = url
        }
        let cleanup: () -> Void = { _ = try? FileManager.default.removeItem(at: dir) }
        return (specURL, promptURL, cleanup)
    }

    @Test("default plan template substitutes slug and inlines prompt")
    func planDefault() throws {
        let fx = try makeFixture(prompt: "hello world")
        defer { fx.cleanup() }
        let lines = WorkflowCommandResolver.resolve(
            action: .plan, slug: "00099-feature",
            specURL: fx.specURL, promptURL: fx.promptURL,
            override: nil
        )
        #expect(lines == ["/plumage-plan 00099-feature", "hello world"])
    }

    @Test("default implement template only injects the slash command")
    func implementDefault() throws {
        let fx = try makeFixture()
        defer { fx.cleanup() }
        let lines = WorkflowCommandResolver.resolve(
            action: .implement, slug: "00099-feature",
            specURL: fx.specURL, promptURL: fx.promptURL,
            override: nil
        )
        #expect(lines == ["/plumage-implement 00099-feature"])
    }

    @Test("default review template only injects the slash command")
    func reviewDefault() throws {
        let fx = try makeFixture()
        defer { fx.cleanup() }
        let lines = WorkflowCommandResolver.resolve(
            action: .review, slug: "00099-feature",
            specURL: fx.specURL, promptURL: fx.promptURL,
            override: nil
        )
        #expect(lines == ["/plumage-review 00099-feature"])
    }

    @Test("override substitutes all three placeholders")
    func overrideAllPlaceholders() throws {
        let fx = try makeFixture(spec: "SPEC", prompt: "PROMPT")
        defer { fx.cleanup() }
        let override = WorkflowOverride(
            command: "/my-plan <slug> --inline\n<prompt>\n<spec>"
        )
        let lines = WorkflowCommandResolver.resolve(
            action: .plan, slug: "abc",
            specURL: fx.specURL, promptURL: fx.promptURL,
            override: override
        )
        #expect(lines == ["/my-plan abc --inline", "PROMPT", "SPEC"])
    }

    @Test("empty override command falls back to default template")
    func emptyOverrideFallback() throws {
        let fx = try makeFixture()
        defer { fx.cleanup() }
        let override = WorkflowOverride(command: "   \n  \t  ")
        let lines = WorkflowCommandResolver.resolve(
            action: .implement, slug: "abc",
            specURL: fx.specURL, promptURL: fx.promptURL,
            override: override
        )
        #expect(lines == ["/plumage-implement abc"])
    }

    @Test("missing prompt file substitutes empty string and filters")
    func missingPromptFiltered() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WCR-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let specURL = dir.appendingPathComponent("spec.md")
        try "spec".write(to: specURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: dir) }

        let lines = WorkflowCommandResolver.resolve(
            action: .plan, slug: "x",
            specURL: specURL,
            promptURL: dir.appendingPathComponent("missing-prompt.md"),
            override: nil
        )
        // The default plan template's second line "<prompt>" resolves to ""
        // when the file doesn't exist; it's filtered out.
        #expect(lines == ["/plumage-plan x"])
    }

    @Test("missing spec file substitutes empty string for <spec>")
    func missingSpecEmpty() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WCR-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let override = WorkflowOverride(command: "/cmd <slug>\n<spec>")
        let lines = WorkflowCommandResolver.resolve(
            action: .review, slug: "x",
            specURL: dir.appendingPathComponent("missing.md"),
            promptURL: nil,
            override: override
        )
        // Second line resolves to "" and is filtered.
        #expect(lines == ["/cmd x"])
    }

    @Test("blank lines in custom override are filtered out")
    func blankLinesFiltered() throws {
        let fx = try makeFixture(prompt: "")
        defer { fx.cleanup() }
        let override = WorkflowOverride(command: "/cmd\n\n   \n<prompt>")
        let lines = WorkflowCommandResolver.resolve(
            action: .plan, slug: "x",
            specURL: fx.specURL, promptURL: fx.promptURL,
            override: override
        )
        #expect(lines == ["/cmd"])
    }
}
