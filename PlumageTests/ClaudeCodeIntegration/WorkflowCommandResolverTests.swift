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

    @Test("default plan template substitutes slug and inlines prompt in one line")
    func planDefault() throws {
        let fx = try makeFixture(prompt: "hello world")
        defer { fx.cleanup() }
        let lines = WorkflowCommandResolver.resolve(
            action: .plan, slug: "00099-feature", type: .feature,
            specURL: fx.specURL, promptURL: fx.promptURL,
            override: nil
        )
        #expect(lines == ["/plumage-plan 00099-feature - hello world"])
    }

    @Test("default implement template injects the slug for feature issues")
    func implementDefaultFeature() throws {
        let fx = try makeFixture()
        defer { fx.cleanup() }
        let lines = WorkflowCommandResolver.resolve(
            action: .implement, slug: "00099-feature", type: .feature,
            specURL: fx.specURL, promptURL: fx.promptURL,
            override: nil
        )
        #expect(lines == ["/plumage-implement 00099-feature"])
    }

    @Test("default implement template inlines prompt and spec for non-feature issues")
    func implementDefaultNonFeature() throws {
        let fx = try makeFixture(spec: "SPEC-BODY", prompt: "PROMPT-BODY")
        defer { fx.cleanup() }
        for type in [IssueType.chore, .spike, .refactor] {
            let lines = WorkflowCommandResolver.resolve(
                action: .implement, slug: "00104-chore", type: type,
                specURL: fx.specURL, promptURL: fx.promptURL,
                override: nil
            )
            #expect(lines == ["/plumage-implement PROMPT-BODY SPEC-BODY"])
        }
    }

    @Test("default review template only injects the slash command")
    func reviewDefault() throws {
        let fx = try makeFixture()
        defer { fx.cleanup() }
        let lines = WorkflowCommandResolver.resolve(
            action: .review, slug: "00099-feature", type: .feature,
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
            action: .plan, slug: "abc", type: .feature,
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
            action: .implement, slug: "abc", type: .feature,
            specURL: fx.specURL, promptURL: fx.promptURL,
            override: override
        )
        #expect(lines == ["/plumage-implement abc"])
    }

    @Test("missing prompt file substitutes empty string for <prompt>")
    func missingPromptEmpty() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WCR-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let specURL = dir.appendingPathComponent("spec.md")
        try "spec".write(to: specURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: dir) }

        let lines = WorkflowCommandResolver.resolve(
            action: .plan, slug: "x", type: .feature,
            specURL: specURL,
            promptURL: dir.appendingPathComponent("missing-prompt.md"),
            override: nil
        )
        // `<prompt>` resolves to "" when the file doesn't exist; the template
        // is otherwise non-empty, so the line stays with a trailing " - ".
        #expect(lines == ["/plumage-plan x - "])
    }

    @Test("missing spec file substitutes empty string for <spec>")
    func missingSpecEmpty() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WCR-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let override = WorkflowOverride(command: "/cmd <slug>\n<spec>")
        let lines = WorkflowCommandResolver.resolve(
            action: .review, slug: "x", type: .feature,
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
            action: .plan, slug: "x", type: .feature,
            specURL: fx.specURL, promptURL: fx.promptURL,
            override: override
        )
        #expect(lines == ["/cmd"])
    }

    @Test("substitution does not cascade — literal <spec> in prompt stays literal")
    func substitutionNoCascade() throws {
        // prompt.md contains the literal token "<spec>". A naive sequential
        // substitution (slug → prompt → spec) would expand the user's
        // literal text into the actual spec content. Single-pass resolver
        // must leave it alone. The default plan template inlines the prompt
        // after " - " so the whole thing is a single REPL line.
        let fx = try makeFixture(
            spec: "ACTUAL-SPEC-CONTENT",
            prompt: "Document the <spec> handling please."
        )
        defer { fx.cleanup() }
        let lines = WorkflowCommandResolver.resolve(
            action: .plan, slug: "x", type: .feature,
            specURL: fx.specURL, promptURL: fx.promptURL,
            override: nil
        )
        #expect(lines.count == 1)
        #expect(lines[0] == "/plumage-plan x - Document the <spec> handling please.")
        #expect(!lines[0].contains("ACTUAL-SPEC-CONTENT"))
    }

    @Test("substitution does not cascade — literal <prompt> in slug stays literal")
    func substitutionNoCascadeSlug() throws {
        let fx = try makeFixture(prompt: "PROMPT-BODY")
        defer { fx.cleanup() }
        // Unrealistic slug, but it stresses the same single-pass invariant:
        // the slug payload, once written into the line, must not be rescanned
        // for further token expansion.
        let override = WorkflowOverride(command: "/cmd <slug>")
        let lines = WorkflowCommandResolver.resolve(
            action: .plan, slug: "<prompt>", type: .feature,
            specURL: fx.specURL, promptURL: fx.promptURL,
            override: override
        )
        #expect(lines == ["/cmd <prompt>"])
        #expect(!(lines.first ?? "").contains("PROMPT-BODY"))
    }

    // MARK: - #if/#end directive filtering

    private func resolveOverride(
        _ command: String, type: IssueType,
        fixture: (specURL: URL, promptURL: URL?, cleanup: () -> Void)
    ) -> [String] {
        WorkflowCommandResolver.resolve(
            action: .plan, slug: "x", type: type,
            specURL: fixture.specURL, promptURL: fixture.promptURL,
            override: WorkflowOverride(command: command)
        )
    }

    @Test("guarded block passes only for the listed type")
    func directiveSingleType() throws {
        let fx = try makeFixture()
        defer { fx.cleanup() }
        let template = "/shared <slug>\n#if chore\n/chore-only\n#end\n/tail"
        #expect(
            resolveOverride(template, type: .chore, fixture: fx)
                == ["/shared x", "/chore-only", "/tail"]
        )
        #expect(
            resolveOverride(template, type: .feature, fixture: fx)
                == ["/shared x", "/tail"]
        )
    }

    @Test("multiple types on one #if are OR-ed")
    func directiveMultiTypeOr() throws {
        let fx = try makeFixture()
        defer { fx.cleanup() }
        let template = "#if chore spike\n/quick\n#end"
        #expect(resolveOverride(template, type: .chore, fixture: fx) == ["/quick"])
        #expect(resolveOverride(template, type: .spike, fixture: fx) == ["/quick"])
        #expect(resolveOverride(template, type: .feature, fixture: fx).isEmpty)
        #expect(resolveOverride(template, type: .refactor, fixture: fx).isEmpty)
    }

    @Test("a second #if ends the previous block without #end")
    func directiveIfEndsPreviousBlock() throws {
        let fx = try makeFixture()
        defer { fx.cleanup() }
        let template = "#if feature\n/plan-feature\n#if chore\n/plan-chore"
        #expect(resolveOverride(template, type: .feature, fixture: fx) == ["/plan-feature"])
        #expect(resolveOverride(template, type: .chore, fixture: fx) == ["/plan-chore"])
    }

    @Test("block without #end runs until end of template")
    func directiveBlockUntilEOF() throws {
        let fx = try makeFixture()
        defer { fx.cleanup() }
        let template = "/shared\n#if spike\n/spike-a\n/spike-b"
        #expect(
            resolveOverride(template, type: .spike, fixture: fx)
                == ["/shared", "/spike-a", "/spike-b"]
        )
        #expect(resolveOverride(template, type: .feature, fixture: fx) == ["/shared"])
    }

    @Test("unknown type token matches nothing; valid tokens in a mixed list still match")
    func directiveUnknownToken() throws {
        let fx = try makeFixture()
        defer { fx.cleanup() }
        let unknownOnly = "#if foobar\n/never\n#end\n/always"
        for type in IssueType.allCases {
            #expect(resolveOverride(unknownOnly, type: type, fixture: fx) == ["/always"])
        }
        let mixed = "#if chore foobar\n/mixed\n#end"
        #expect(resolveOverride(mixed, type: .chore, fixture: fx) == ["/mixed"])
        #expect(resolveOverride(mixed, type: .feature, fixture: fx).isEmpty)
    }

    @Test("directive lines are never emitted, with or without leading whitespace")
    func directiveLinesConsumed() throws {
        let fx = try makeFixture()
        defer { fx.cleanup() }
        let template = "  #if chore\n/chore-line\n\t#end\n#end\n/tail"
        let lines = resolveOverride(template, type: .chore, fixture: fx)
        #expect(lines == ["/chore-line", "/tail"])
        for type in IssueType.allCases {
            let all = resolveOverride(template, type: type, fixture: fx)
            #expect(!all.contains(where: { $0.contains("#if") || $0.contains("#end") }))
        }
    }

    @Test("stray #end without an open block is a consumed no-op")
    func directiveStrayEnd() throws {
        let fx = try makeFixture()
        defer { fx.cleanup() }
        let template = "#end\n/cmd"
        #expect(resolveOverride(template, type: .feature, fixture: fx) == ["/cmd"])
    }

    @Test("#else inverts the open block")
    func directiveElse() throws {
        let fx = try makeFixture()
        defer { fx.cleanup() }
        let template = "#if chore\n/chore-cmd\n#else\n/other-cmd\n#end\n/tail"
        #expect(
            resolveOverride(template, type: .chore, fixture: fx)
                == ["/chore-cmd", "/tail"]
        )
        for type in [IssueType.feature, .spike, .refactor] {
            #expect(
                resolveOverride(template, type: type, fixture: fx)
                    == ["/other-cmd", "/tail"]
            )
        }
    }

    @Test("#else of an unknown-token #if matches every type")
    func directiveElseUnknownToken() throws {
        let fx = try makeFixture()
        defer { fx.cleanup() }
        let template = "#if foobar\n/never\n#else\n/always\n#end"
        for type in IssueType.allCases {
            #expect(resolveOverride(template, type: type, fixture: fx) == ["/always"])
        }
    }

    @Test("stray and repeated #else are consumed no-ops")
    func directiveStrayAndRepeatedElse() throws {
        let fx = try makeFixture()
        defer { fx.cleanup() }
        // Stray: no open block — lines stay unguarded.
        #expect(
            resolveOverride("#else\n/cmd", type: .feature, fixture: fx) == ["/cmd"]
        )
        // Repeated: stays in the else branch.
        let repeated = "#if chore\n/a\n#else\n/b\n#else\n/c\n#end"
        #expect(resolveOverride(repeated, type: .feature, fixture: fx) == ["/b", "/c"])
        #expect(resolveOverride(repeated, type: .chore, fixture: fx) == ["/a"])
    }

    @Test("a new #if after #else starts a fresh block")
    func directiveIfAfterElse() throws {
        let fx = try makeFixture()
        defer { fx.cleanup() }
        let template = "#if chore\n/a\n#else\n/b\n#if spike\n/c"
        #expect(resolveOverride(template, type: .spike, fixture: fx) == ["/b", "/c"])
        #expect(resolveOverride(template, type: .chore, fixture: fx) == ["/a"])
        #expect(resolveOverride(template, type: .feature, fixture: fx) == ["/b"])
    }

    @Test("placeholders inside dropped blocks are not substituted")
    func directiveDroppedBlockSkipsSubstitution() throws {
        let fx = try makeFixture(spec: "ACTUAL-SPEC", prompt: "ACTUAL-PROMPT")
        defer { fx.cleanup() }
        let template = "/cmd\n#if chore\n<spec>\n<prompt>\n#end"
        let lines = resolveOverride(template, type: .feature, fixture: fx)
        #expect(lines == ["/cmd"])
        #expect(!lines.joined().contains("ACTUAL"))
    }

    @Test("filtersToEmpty detects per-type empty templates")
    func filtersToEmptyDetection() {
        let override = WorkflowOverride(command: "#if feature\n/plan-feature\n#end")
        #expect(
            !WorkflowCommandResolver.filtersToEmpty(
                action: .plan, type: .feature, override: override
            )
        )
        #expect(
            WorkflowCommandResolver.filtersToEmpty(
                action: .plan, type: .chore, override: override
            )
        )
        // Whitespace-only survivors still count as empty.
        let blanks = WorkflowOverride(command: "#if chore\n/x\n#end\n   ")
        #expect(
            WorkflowCommandResolver.filtersToEmpty(
                action: .plan, type: .feature, override: blanks
            )
        )
    }

    @Test("filtersToEmpty is false for defaults and directive-free overrides")
    func filtersToEmptyPassThrough() {
        for action in WorkflowAction.allCases {
            for type in IssueType.allCases {
                #expect(
                    !WorkflowCommandResolver.filtersToEmpty(
                        action: action, type: type, override: nil
                    )
                )
            }
        }
        let plain = WorkflowOverride(command: "/custom <slug>")
        #expect(
            !WorkflowCommandResolver.filtersToEmpty(action: .plan, type: .spike, override: plain)
        )
    }

    @Test("directive-free templates resolve byte-identically for every type")
    func directiveFreePassThrough() throws {
        let fx = try makeFixture(spec: "SPEC", prompt: "PROMPT")
        defer { fx.cleanup() }
        let template = "/my-plan <slug>\n<prompt>"
        let expected = ["/my-plan x", "PROMPT"]
        for type in IssueType.allCases {
            #expect(resolveOverride(template, type: type, fixture: fx) == expected)
        }
    }
}
