import Foundation
import Testing

@testable import Plumage

@Suite("ProjectConfig additive fields")
struct ProjectConfigTests {
    @Test("decodes minimal config without workflows or models")
    func minimalDecode() throws {
        let json = """
            {
              "name": "Minimal",
              "schemaVersion": 2,
              "issueIdPadding": 5
            }
            """
        let data = try #require(json.data(using: .utf8))
        let config = try JSONDecoder().decode(ProjectConfig.self, from: data)
        #expect(config.workflows == nil)
        #expect(config.models == nil)
    }

    @Test("decodes workflows and models when present")
    func richDecode() throws {
        let json = """
            {
              "name": "Rich",
              "schemaVersion": 2,
              "issueIdPadding": 5,
              "workflows": {
                "plan": { "command": "/my-plan <slug>" },
                "implement": { "command": "/my-impl <slug>" }
              },
              "models": {
                "chat": "opus",
                "terminals": "sonnet",
                "plan": "opusplan"
              }
            }
            """
        let data = try #require(json.data(using: .utf8))
        let config = try JSONDecoder().decode(ProjectConfig.self, from: data)
        #expect(config.workflows?.plan?.command == "/my-plan <slug>")
        #expect(config.workflows?.implement?.command == "/my-impl <slug>")
        #expect(config.workflows?.review == nil)
        #expect(config.models?.chat == .opus)
        #expect(config.models?.terminals == .sonnet)
        // The dropped "opusplan" alias coerces to .default via ModelChoice's
        // custom decoder, so a stale on-disk config loads without error.
        #expect(config.models?.plan == .default)
        #expect(config.models?.implement == nil)
    }

    @Test("WorkflowsConfig subscript maps action → override")
    func workflowsSubscript() {
        var workflows = WorkflowsConfig()
        workflows[.plan] = WorkflowOverride(command: "/plan-x")
        workflows[.implement] = WorkflowOverride(command: "/impl-x")
        workflows[.review] = WorkflowOverride(command: "/review-x")
        #expect(workflows.plan?.command == "/plan-x")
        #expect(workflows.implement?.command == "/impl-x")
        #expect(workflows.review?.command == "/review-x")
        #expect(workflows[.plan]?.command == "/plan-x")
    }

    @Test("ModelsConfig workflow(_:) returns per-action choice")
    func modelsWorkflowAccessor() {
        let models = ModelsConfig(
            chat: .opus, terminals: nil,
            plan: .sonnet, implement: .haiku, review: .opus
        )
        #expect(models.workflow(.plan) == .sonnet)
        #expect(models.workflow(.implement) == .haiku)
        #expect(models.workflow(.review) == .opus)
    }

    @Test("round-trip encode/decode preserves additive fields")
    func roundTrip() throws {
        let original = ProjectConfig(
            name: "RT",
            schemaVersion: 2,
            issueIdPadding: 5,
            git: nil,
            workflows: WorkflowsConfig(
                plan: WorkflowOverride(command: "/x <slug>"),
                implement: nil,
                review: WorkflowOverride(command: "/y")
            ),
            models: ModelsConfig(chat: .sonnet, terminals: .opus, plan: nil, implement: nil, review: nil)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ProjectConfig.self, from: data)
        #expect(decoded == original)
    }
}
