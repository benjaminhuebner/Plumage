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
        // The dropped "opusplan" alias migrates to .opus via ModelChoice's
        // custom decoder, so a stale on-disk config keeps the Opus model.
        #expect(config.models?.plan == .uniform(.opus))
        #expect(config.models?.implement == nil)
    }

    @Test("pre-existing plain-string workflow slots load as uniform values")
    func plainStringSlotsLoadUnchanged() throws {
        let json = """
            {
              "name": "Legacy",
              "schemaVersion": 2,
              "models": {
                "plan": "opus",
                "implement": "sonnet",
                "review": "haiku"
              }
            }
            """
        let data = try #require(json.data(using: .utf8))
        let config = try JSONDecoder().decode(ProjectConfig.self, from: data)
        #expect(config.models?.plan == .uniform(.opus))
        #expect(config.models?.implement == .uniform(.sonnet))
        #expect(config.models?.review == .uniform(.haiku))
        for type in IssueType.allCases {
            #expect(config.models?.workflowResolved(.plan, type: type) == .opus)
        }
    }

    @Test("per-type object slot decodes and resolves per issue type")
    func perTypeSlotDecodes() throws {
        let json = """
            {
              "name": "Split",
              "schemaVersion": 2,
              "models": {
                "implement": { "feature": "opus", "chore": "haiku" }
              }
            }
            """
        let data = try #require(json.data(using: .utf8))
        let config = try JSONDecoder().decode(ProjectConfig.self, from: data)
        let models = try #require(config.models)
        #expect(models.workflowResolved(.implement, type: .feature) == .opus)
        #expect(models.workflowResolved(.implement, type: .chore) == .haiku)
        #expect(models.workflowResolved(.implement, type: .spike) == .default)
        #expect(models.workflowResolved(.implement, type: .refactor) == .default)
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

    @Test("ModelsConfig workflow(_:) returns per-action setting")
    func modelsWorkflowAccessor() {
        let models = ModelsConfig(
            chat: .opus, terminals: nil,
            plan: .uniform(.sonnet), implement: .uniform(.haiku), review: .uniform(.opus)
        )
        #expect(models.workflow(.plan) == .uniform(.sonnet))
        #expect(models.workflow(.implement) == .uniform(.haiku))
        #expect(models.workflow(.review) == .uniform(.opus))
    }

    @Test("every slot falls back to .default when nothing is set on disk")
    func slotFallbacksAreDefault() {
        let empty = ModelsConfig()
        #expect(empty.chatResolved == .default)
        #expect(empty.terminalsResolved == .default)
        for type in IssueType.allCases {
            #expect(empty.workflowResolved(.plan, type: type) == .default)
            #expect(empty.workflowResolved(.implement, type: type) == .default)
            #expect(empty.workflowResolved(.review, type: type) == .default)
        }
        for slot in ModelSlot.allCases {
            #expect(ModelsConfig.slotDefault(for: slot) == .default)
        }
    }

    @Test("workflowResolved: per-type hit beats uniform beats slot default")
    func workflowResolutionPrecedence() {
        let models = ModelsConfig(
            plan: .uniform(.sonnet),
            implement: .perType([.feature: .opus])
        )
        #expect(models.workflowResolved(.plan, type: .feature) == .sonnet)
        #expect(models.workflowResolved(.plan, type: .chore) == .sonnet)
        #expect(models.workflowResolved(.implement, type: .feature) == .opus)
        #expect(models.workflowResolved(.implement, type: .chore) == .default)
        #expect(models.workflowResolved(.review, type: .feature) == .default)
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

    @Test("mixed per-type slot round-trips through ProjectConfig")
    func perTypeRoundTrip() throws {
        let original = ProjectConfig(
            name: "RT2",
            schemaVersion: 2,
            issueIdPadding: 5,
            git: nil,
            workflows: nil,
            models: ModelsConfig(
                implement: .perType([
                    .feature: .opus, .chore: .haiku, .spike: .default, .refactor: .sonnet,
                ])
            )
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ProjectConfig.self, from: data)
        #expect(decoded == original)
    }
}
