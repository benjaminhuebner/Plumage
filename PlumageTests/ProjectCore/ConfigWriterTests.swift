import Foundation
import Testing

@testable import Plumage

@Suite("ConfigWriter")
struct ConfigWriterTests {
    private func tempBundle(content: String?) throws -> (project: URL, bundle: URL) {
        let project = try TempProject.make(content: content)
        let bundle = project.appendingPathComponent("Test.plumage", isDirectory: true)
        return (project, bundle)
    }

    private static let sampleConfig: String = """
        {
          "schemaVersion": 2,
          "minPlumageVersion": "0.1.0",
          "createdWithPlumageVersion": "0.1.0-bootstrap",
          "name": "Plumage",
          "projectType": "macOS",
          "createdAt": "2026-05-12T00:00:00Z",
          "issueIdPadding": 5,
          "agentTimeouts": {
            "planModeProbeMs": 5000
          },
          "git": {
            "branchPrefix": "issue/",
            "defaultBranch": "main",
            "agentFilesInGit": true
          },
          "paths": {
            "issues": ".claude/issues",
            "archive": ".claude/issues/archive"
          },
          "plumageManaged": {
            "mcps": [
              { "name": "XcodeBuildMCP", "version": "2.3.2" }
            ],
            "skills": [
              { "name": "plan-issue" }
            ]
          }
        }
        """

    @Test("write preserves all unknown keys verbatim")
    func unknownKeysPreserved() throws {
        let (project, bundle) = try tempBundle(content: Self.sampleConfig)
        defer { try? FileManager.default.removeItem(at: project) }

        let loaded = try ConfigLoader.load(at: project)
        var mutated = loaded
        mutated.models = ModelsConfig(chat: .opus)
        try ConfigWriter.write(mutated, atBundle: bundle)

        let configURL = bundle.appendingPathComponent("config.json")
        let written = try Data(contentsOf: configURL)
        let parsed = try #require(
            JSONSerialization.jsonObject(with: written) as? [String: Any]
        )

        // Unknown top-level keys survive bit-exact via JSONSerialization
        // round-trip (atomic JSON types compare by Equatable).
        #expect(parsed["minPlumageVersion"] as? String == "0.1.0")
        #expect(parsed["createdWithPlumageVersion"] as? String == "0.1.0-bootstrap")
        #expect(parsed["projectType"] as? String == "macOS")
        #expect(parsed["createdAt"] as? String == "2026-05-12T00:00:00Z")
        let agentTimeouts = try #require(parsed["agentTimeouts"] as? [String: Any])
        #expect(agentTimeouts["planModeProbeMs"] as? Int == 5000)
        let paths = try #require(parsed["paths"] as? [String: Any])
        #expect(paths["issues"] as? String == ".claude/issues")
        #expect(paths["archive"] as? String == ".claude/issues/archive")
        let managed = try #require(parsed["plumageManaged"] as? [String: Any])
        let mcps = try #require(managed["mcps"] as? [[String: Any]])
        #expect(mcps.first?["name"] as? String == "XcodeBuildMCP")
        let git = try #require(parsed["git"] as? [String: Any])
        #expect(git["branchPrefix"] as? String == "issue/")
        #expect(git["defaultBranch"] as? String == "main")
        #expect(git["agentFilesInGit"] as? Bool == true)

        // Known keys are also present.
        let models = try #require(parsed["models"] as? [String: Any])
        #expect(models["chat"] as? String == "opus")
    }

    @Test("per-type workflow slot writes the object form to disk")
    func perTypeSlotWritesObject() throws {
        let (project, bundle) = try tempBundle(content: Self.sampleConfig)
        defer { try? FileManager.default.removeItem(at: project) }

        var loaded = try ConfigLoader.load(at: project)
        loaded.models = ModelsConfig(implement: .perType([.feature: .opus, .chore: .haiku]))
        try ConfigWriter.write(loaded, atBundle: bundle)

        let configURL = bundle.appendingPathComponent("config.json")
        let written = try Data(contentsOf: configURL)
        let parsed = try #require(JSONSerialization.jsonObject(with: written) as? [String: Any])
        let models = try #require(parsed["models"] as? [String: Any])
        let implement = try #require(models["implement"] as? [String: String])
        #expect(
            implement == [
                "feature": "opus", "chore": "haiku", "spike": "default", "refactor": "default",
            ])
    }

    @Test("identical per-type values collapse to the plain string on disk")
    func identicalPerTypeCollapsesOnDisk() throws {
        let (project, bundle) = try tempBundle(content: Self.sampleConfig)
        defer { try? FileManager.default.removeItem(at: project) }

        var loaded = try ConfigLoader.load(at: project)
        let allOpus = Dictionary(uniqueKeysWithValues: IssueType.allCases.map { ($0, ModelChoice.opus) })
        loaded.models = ModelsConfig(plan: .perType(allOpus))
        try ConfigWriter.write(loaded, atBundle: bundle)

        let configURL = bundle.appendingPathComponent("config.json")
        let written = try Data(contentsOf: configURL)
        let parsed = try #require(JSONSerialization.jsonObject(with: written) as? [String: Any])
        let models = try #require(parsed["models"] as? [String: Any])
        #expect(models["plan"] as? String == "opus")

        let reloaded = try ConfigLoader.load(at: project)
        #expect(reloaded.models?.plan == .uniform(.opus))
    }

    @Test("write removes a known section that is now nil")
    func nilSectionRemoved() throws {
        let (project, bundle) = try tempBundle(content: Self.sampleConfig)
        defer { try? FileManager.default.removeItem(at: project) }

        var loaded = try ConfigLoader.load(at: project)
        loaded.models = ModelsConfig(chat: .opus)
        try ConfigWriter.write(loaded, atBundle: bundle)

        var second = try ConfigLoader.load(at: project)
        second.models = nil
        try ConfigWriter.write(second, atBundle: bundle)

        let configURL = bundle.appendingPathComponent("config.json")
        let written = try Data(contentsOf: configURL)
        let parsed = try #require(
            JSONSerialization.jsonObject(with: written) as? [String: Any]
        )
        #expect(parsed["models"] == nil)
        // Unknown keys still survive.
        #expect(parsed["plumageManaged"] != nil)
    }

    @Test("write round-trips workflows section")
    func workflowsRoundTrip() throws {
        let (project, bundle) = try tempBundle(content: Self.sampleConfig)
        defer { try? FileManager.default.removeItem(at: project) }

        var loaded = try ConfigLoader.load(at: project)
        loaded.workflows = WorkflowsConfig(
            plan: WorkflowOverride(command: "/my-plan <slug>\n<spec>"),
            implement: nil,
            review: WorkflowOverride(command: "/review-cmd")
        )
        try ConfigWriter.write(loaded, atBundle: bundle)

        let reloaded = try ConfigLoader.load(at: project)
        #expect(reloaded.workflows?.plan?.command == "/my-plan <slug>\n<spec>")
        #expect(reloaded.workflows?.implement == nil)
        #expect(reloaded.workflows?.review?.command == "/review-cmd")
    }

    @Test("missing config.json gets created containing only the writable subset")
    func missingConfigCreatesFile() throws {
        let project = try TempProject.make(content: nil)
        let bundle = project.appendingPathComponent("Test.plumage", isDirectory: true)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: project) }

        // ConfigWriter is scoped to workflows/models — name/schemaVersion/etc.
        // are caller-owned and stay untouched on disk. Asserting via raw JSON
        // because ConfigLoader.load would fail (no required `name` field).
        let config = ProjectConfig(
            name: "Fresh", schemaVersion: 2, issueIdPadding: 5,
            git: nil,
            workflows: nil,
            models: ModelsConfig(chat: .sonnet)
        )
        try ConfigWriter.write(config, atBundle: bundle)

        let configURL = bundle.appendingPathComponent("config.json")
        let written = try Data(contentsOf: configURL)
        let parsed = try #require(
            JSONSerialization.jsonObject(with: written) as? [String: Any]
        )
        let models = try #require(parsed["models"] as? [String: Any])
        #expect(models["chat"] as? String == "sonnet")
        // Non-writable keys do NOT appear in the freshly-created file.
        #expect(parsed["name"] == nil)
        #expect(parsed["schemaVersion"] == nil)
    }

    @Test("write leaves git untouched even when snapshot's git differs")
    func gitNotClobbered() throws {
        let (project, bundle) = try tempBundle(content: Self.sampleConfig)
        defer { try? FileManager.default.removeItem(at: project) }

        // Simulate an external tool changing git.defaultBranch between the
        // in-app load and the in-app save. ConfigWriter must NOT overwrite
        // the external edit with the in-memory baseConfig's `git`.
        let configURL = bundle.appendingPathComponent("config.json")
        let original = try Data(contentsOf: configURL)
        var parsed = try #require(
            JSONSerialization.jsonObject(with: original) as? [String: Any]
        )
        var git = try #require(parsed["git"] as? [String: Any])
        git["defaultBranch"] = "trunk"
        parsed["git"] = git
        let mutatedJSON = try JSONSerialization.data(
            withJSONObject: parsed, options: [.prettyPrinted]
        )
        try mutatedJSON.write(to: configURL, options: [.atomic])

        // Stale in-memory loaded config still has git.defaultBranch=main.
        var loaded = try ConfigLoader.load(at: project)
        loaded = ProjectConfig(
            name: loaded.name, schemaVersion: loaded.schemaVersion,
            issueIdPadding: loaded.issueIdPadding,
            git: GitConfig(defaultBranch: "main"),
            workflows: nil, models: ModelsConfig(chat: .sonnet)
        )
        try ConfigWriter.write(loaded, atBundle: bundle)

        let after = try Data(contentsOf: configURL)
        let afterParsed = try #require(
            JSONSerialization.jsonObject(with: after) as? [String: Any]
        )
        let afterGit = try #require(afterParsed["git"] as? [String: Any])
        // External edit survives: trunk, NOT main.
        #expect(afterGit["defaultBranch"] as? String == "trunk")
        // Sibling git keys also preserved.
        #expect(afterGit["branchPrefix"] as? String == "issue/")
    }

    @Test("setting a sub-field of models to nil removes it from disk")
    func partialModelsOverwrite() throws {
        let (project, bundle) = try tempBundle(content: Self.sampleConfig)
        defer { try? FileManager.default.removeItem(at: project) }

        var loaded = try ConfigLoader.load(at: project)
        loaded.models = ModelsConfig(chat: .opus, terminals: .sonnet)
        try ConfigWriter.write(loaded, atBundle: bundle)

        var second = try ConfigLoader.load(at: project)
        second.models = ModelsConfig(chat: nil, terminals: .haiku)
        try ConfigWriter.write(second, atBundle: bundle)

        let reloaded = try ConfigLoader.load(at: project)
        #expect(reloaded.models?.chat == nil)
        #expect(reloaded.models?.terminals == .haiku)
    }

    @Test("missing bundle throws bundleMissing")
    func missingBundleThrows() throws {
        let project = try TempProject.make(content: nil)
        defer { try? FileManager.default.removeItem(at: project) }
        let bundle = project.appendingPathComponent("NotThere.plumage", isDirectory: true)

        let config = ProjectConfig(
            name: "X", schemaVersion: 2, issueIdPadding: nil,
            git: nil, workflows: nil, models: nil
        )
        #expect {
            try ConfigWriter.write(config, atBundle: bundle)
        } throws: { error in
            if case ConfigWriter.WriteError.bundleMissing = error { return true }
            return false
        }
    }

    @Test("writeName updates name and preserves every other key bit-exact")
    func writeNamePreservesSiblings() throws {
        let (project, bundle) = try tempBundle(content: Self.sampleConfig)
        defer { try? FileManager.default.removeItem(at: project) }

        try ConfigWriter.writeName("Renamed", atBundle: bundle)

        let configURL = bundle.appendingPathComponent("config.json")
        let parsed = try #require(
            JSONSerialization.jsonObject(with: try Data(contentsOf: configURL)) as? [String: Any]
        )

        #expect(parsed["name"] as? String == "Renamed")
        // Every sibling key from the sample survives untouched.
        #expect(parsed["schemaVersion"] as? Int == 2)
        #expect(parsed["minPlumageVersion"] as? String == "0.1.0")
        #expect(parsed["createdWithPlumageVersion"] as? String == "0.1.0-bootstrap")
        #expect(parsed["projectType"] as? String == "macOS")
        #expect(parsed["createdAt"] as? String == "2026-05-12T00:00:00Z")
        #expect(parsed["issueIdPadding"] as? Int == 5)
        let agentTimeouts = try #require(parsed["agentTimeouts"] as? [String: Any])
        #expect(agentTimeouts["planModeProbeMs"] as? Int == 5000)
        let git = try #require(parsed["git"] as? [String: Any])
        #expect(git["branchPrefix"] as? String == "issue/")
        #expect(git["defaultBranch"] as? String == "main")
        #expect(git["agentFilesInGit"] as? Bool == true)
        let paths = try #require(parsed["paths"] as? [String: Any])
        #expect(paths["issues"] as? String == ".claude/issues")
        let managed = try #require(parsed["plumageManaged"] as? [String: Any])
        #expect((managed["mcps"] as? [[String: Any]])?.first?["name"] as? String == "XcodeBuildMCP")
    }

    @Test("writeName does not introduce workflows or models keys")
    func writeNameLeavesWritableSectionsAbsent() throws {
        let (project, bundle) = try tempBundle(content: Self.sampleConfig)
        defer { try? FileManager.default.removeItem(at: project) }

        try ConfigWriter.writeName("Renamed", atBundle: bundle)

        let configURL = bundle.appendingPathComponent("config.json")
        let parsed = try #require(
            JSONSerialization.jsonObject(with: try Data(contentsOf: configURL)) as? [String: Any]
        )
        // The sample has no workflows/models; writeName must not add them.
        #expect(parsed["workflows"] == nil)
        #expect(parsed["models"] == nil)
    }

    @Test("writeName on a missing bundle throws bundleMissing")
    func writeNameMissingBundleThrows() throws {
        let project = try TempProject.make(content: nil)
        defer { try? FileManager.default.removeItem(at: project) }
        let bundle = project.appendingPathComponent("NotThere.plumage", isDirectory: true)

        #expect {
            try ConfigWriter.writeName("X", atBundle: bundle)
        } throws: { error in
            if case ConfigWriter.WriteError.bundleMissing = error { return true }
            return false
        }
    }
}
