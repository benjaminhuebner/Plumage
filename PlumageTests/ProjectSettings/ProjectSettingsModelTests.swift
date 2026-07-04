import Foundation
import Testing

@testable import Plumage

@MainActor
@Suite("ProjectSettingsModel")
struct ProjectSettingsModelTests {
    private static let baseConfig: String = """
        {
          "schemaVersion": 2,
          "name": "Sample",
          "issueIdPadding": 5,
          "plumageManaged": { "skills": [{ "name": "x" }] }
        }
        """

    private func makeProject() throws -> URL {
        try TempProject.make(content: Self.baseConfig)
    }

    @Test("load populates fields from existing config")
    func loadPopulates() async throws {
        let project = try makeProject()
        defer { try? FileManager.default.removeItem(at: project) }

        let model = ProjectSettingsModel(projectURL: project)
        await model.load()

        #expect(model.loadState == .loaded)
        // No override on disk → picker resolves to the spec'd slot default.
        #expect(model.chatModel == ModelsConfig.chatDefault)
        // Editor pre-fills with the default template so the user always
        // sees the command that will actually be injected.
        #expect(model.planCommand == ProjectSettingsModel.planDefault)
    }

    @Test("setModel triggers debounced write that lands on disk")
    func setModelDebouncedWrite() async throws {
        let project = try makeProject()
        defer { try? FileManager.default.removeItem(at: project) }

        let model = ProjectSettingsModel(projectURL: project)
        await model.load()
        // Pick a non-default value to actually persist; opus is already
        // the chat slot's default and would be elided to nil on disk.
        model.setModel(.sonnet, for: .chat)
        await model.saveNow()

        let reloaded = try ConfigLoader.load(at: project)
        #expect(reloaded.models?.chat == .sonnet)
    }

    @Test("picker-at-slot-default elides override from disk")
    func slotDefaultElidesOverride() async throws {
        let project = try makeProject()
        defer { try? FileManager.default.removeItem(at: project) }

        let model = ProjectSettingsModel(projectURL: project)
        await model.load()
        // Move to a non-default first…
        model.setModel(.sonnet, for: .chat)
        await model.saveNow()
        #expect(try ConfigLoader.load(at: project).models?.chat == .sonnet)
        // …then back to the default. Disk should drop the override.
        model.setModel(ModelsConfig.chatDefault, for: .chat)
        await model.saveNow()
        #expect(try ConfigLoader.load(at: project).models?.chat == nil)
    }

    @Test("per-type pick persists the object form; mixed detection flips")
    func perTypePickPersistsObject() async throws {
        let project = try makeProject()
        defer { try? FileManager.default.removeItem(at: project) }

        let model = ProjectSettingsModel(projectURL: project)
        await model.load()
        #expect(!model.isWorkflowMixed(.implementAction))

        model.setWorkflowModel(.opus, for: .implementAction, type: .feature)
        #expect(model.isWorkflowMixed(.implementAction))
        #expect(model.uniformWorkflowModel(for: .implementAction) == nil)
        await model.saveNow()

        let reloaded = try ConfigLoader.load(at: project)
        #expect(
            reloaded.models?.implement
                == .perType([
                    .feature: .opus, .chore: .default, .spike: .default, .refactor: .default,
                ]))
    }

    @Test("top pick while mixed overwrites all four types")
    func topPickOverwritesAllTypes() async throws {
        let project = try makeProject()
        defer { try? FileManager.default.removeItem(at: project) }

        let model = ProjectSettingsModel(projectURL: project)
        await model.load()
        model.setWorkflowModel(.opus, for: .planAction, type: .feature)
        model.setWorkflowModel(.haiku, for: .planAction, type: .chore)
        #expect(model.isWorkflowMixed(.planAction))

        model.setModel(.sonnet, for: .planAction)
        #expect(!model.isWorkflowMixed(.planAction))
        #expect(model.model(for: .planAction) == .sonnet)
        for type in IssueType.allCases {
            #expect(model.workflowModels(for: .planAction)[type] == .sonnet)
        }
        await model.saveNow()
        #expect(try ConfigLoader.load(at: project).models?.plan == .uniform(.sonnet))
    }

    @Test("setting all four sub-rows to one value collapses to the plain string on disk")
    func collapseBackToUniform() async throws {
        let project = try makeProject()
        defer { try? FileManager.default.removeItem(at: project) }

        let model = ProjectSettingsModel(projectURL: project)
        await model.load()
        model.setWorkflowModel(.opus, for: .implementAction, type: .feature)
        await model.saveNow()

        for type in IssueType.allCases {
            model.setWorkflowModel(.opus, for: .implementAction, type: type)
        }
        #expect(!model.isWorkflowMixed(.implementAction))
        await model.saveNow()

        let configURL = try #require(
            try? BundleResolver.findBundle(in: project).appendingPathComponent("config.json"))
        let parsed = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: configURL)) as? [String: Any])
        let models = try #require(parsed["models"] as? [String: Any])
        #expect(models["implement"] as? String == "opus")
    }

    @Test("all-default workflow slot is elided from disk")
    func allDefaultWorkflowSlotElided() async throws {
        let project = try makeProject()
        defer { try? FileManager.default.removeItem(at: project) }

        let model = ProjectSettingsModel(projectURL: project)
        await model.load()
        model.setWorkflowModel(.opus, for: .reviewAction, type: .spike)
        await model.saveNow()
        #expect(try ConfigLoader.load(at: project).models?.review != nil)

        model.setWorkflowModel(.default, for: .reviewAction, type: .spike)
        await model.saveNow()
        #expect(try ConfigLoader.load(at: project).models?.review == nil)
    }

    @Test("load seeds per-type values from a mixed config object")
    func loadSeedsPerTypeValues() async throws {
        let config = """
            {
              "schemaVersion": 2,
              "name": "Sample",
              "models": {
                "implement": { "feature": "opus", "chore": "haiku" }
              }
            }
            """
        let project = try TempProject.make(content: config)
        defer { try? FileManager.default.removeItem(at: project) }

        let model = ProjectSettingsModel(projectURL: project)
        await model.load()
        #expect(model.isWorkflowMixed(.implementAction))
        #expect(model.workflowModels(for: .implementAction)[.feature] == .opus)
        #expect(model.workflowModels(for: .implementAction)[.chore] == .haiku)
        #expect(model.workflowModels(for: .implementAction)[.spike] == .default)
    }

    @Test("setCommand persists override and trims-empty-falls-back-to-nil")
    func setCommandPersists() async throws {
        let project = try makeProject()
        defer { try? FileManager.default.removeItem(at: project) }

        let model = ProjectSettingsModel(projectURL: project)
        await model.load()
        model.setCommand("/my-plan <slug>", for: .plan)
        await model.saveNow()

        var reloaded = try ConfigLoader.load(at: project)
        #expect(reloaded.workflows?.plan?.command == "/my-plan <slug>")

        // Empty / whitespace-only command falls back to nil override.
        model.setCommand("   ", for: .plan)
        await model.saveNow()
        reloaded = try ConfigLoader.load(at: project)
        #expect(reloaded.workflows?.plan == nil)
    }

    @Test("reset restores the spec default template")
    func resetRestoresDefault() async throws {
        let project = try makeProject()
        defer { try? FileManager.default.removeItem(at: project) }

        let model = ProjectSettingsModel(projectURL: project)
        await model.load()
        model.resetCommand(for: .plan)
        #expect(model.planCommand == ProjectSettingsModel.planDefault)
        model.resetCommand(for: .implement)
        #expect(model.implementCommand == ProjectSettingsModel.implementDefault)
        model.resetCommand(for: .review)
        #expect(model.reviewCommand == ProjectSettingsModel.reviewDefault)
    }

    @Test("preserves unknown top-level keys after a model change")
    func preservesUnknownKeys() async throws {
        let project = try makeProject()
        defer { try? FileManager.default.removeItem(at: project) }

        let model = ProjectSettingsModel(projectURL: project)
        await model.load()
        model.setModel(.opus, for: .chat)
        await model.saveNow()

        let bundle = try BundleResolver.findBundle(in: project)
        let data = try Data(contentsOf: bundle.appendingPathComponent("config.json"))
        let parsed = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(parsed["plumageManaged"] != nil)
        let managed = try #require(parsed["plumageManaged"] as? [String: Any])
        let skills = try #require(managed["skills"] as? [[String: Any]])
        #expect(skills.first?["name"] as? String == "x")
    }

    @Test("load seeds the rename draft from config.name")
    func loadSeedsRenameDraft() async throws {
        let project = try makeProject()
        defer { try? FileManager.default.removeItem(at: project) }

        let model = ProjectSettingsModel(projectURL: project)
        await model.load()

        #expect(model.projectName == "Sample")
        #expect(model.currentName == "Sample")
        // Unchanged draft → button stays disabled.
        #expect(!model.canRename)
    }

    @Test("canRename reflects validity and difference from current name")
    func canRenameLogic() async throws {
        let project = try makeProject()
        defer { try? FileManager.default.removeItem(at: project) }

        let model = ProjectSettingsModel(projectURL: project)
        await model.load()

        model.projectName = "Sample"
        #expect(!model.canRename)  // unchanged
        model.projectName = "  Sample  "
        #expect(!model.canRename)  // trims to the same name
        model.projectName = "a/b"
        #expect(!model.canRename)  // invalid
        model.projectName = ""
        #expect(!model.canRename)  // empty
        model.projectName = "Renamed"
        #expect(model.canRename)  // valid and different
    }

    @Test("rename moves the bundle, updates state, and fires onRenamed")
    func renameHappyPath() async throws {
        let project = try makeProject()
        defer { try? FileManager.default.removeItem(at: project) }

        let model = ProjectSettingsModel(projectURL: project)
        await model.load()

        final class Box {
            var config: ProjectConfig?
            var url: URL?
        }
        let box = Box()
        model.onRenamed = { config, url in
            box.config = config
            box.url = url
        }

        model.projectName = "Renamed"
        await model.rename()

        #expect(model.renameStatus == .idle)
        #expect(model.currentName == "Renamed")
        #expect(model.projectName == "Renamed")
        #expect(!model.canRename)

        // Disk reflects the rename.
        #expect(FileManager.default.fileExists(atPath: project.appendingPathComponent("Renamed.plumage").path))
        #expect(!FileManager.default.fileExists(atPath: project.appendingPathComponent("Test.plumage").path))
        #expect(try ConfigLoader.load(at: project).name == "Renamed")

        // Callback delivered the reloaded config + new bundle URL.
        #expect(box.config?.name == "Renamed")
        #expect(box.url?.lastPathComponent == "Renamed.plumage")
    }

    @Test("a no-op or invalid draft never touches disk")
    func renameGuardedByCanRename() async throws {
        let project = try makeProject()
        defer { try? FileManager.default.removeItem(at: project) }

        let model = ProjectSettingsModel(projectURL: project)
        await model.load()

        model.projectName = "a/b"  // invalid → canRename false
        await model.rename()

        #expect(model.renameStatus == .idle)
        // Original bundle untouched.
        #expect(FileManager.default.fileExists(atPath: project.appendingPathComponent("Test.plumage").path))
        #expect(try ConfigLoader.load(at: project).name == "Sample")
    }

    @Test("rename preserves a pending workflow override and retargets the bundle")
    func renamePreservesAndRetargets() async throws {
        let project = try makeProject()
        defer { try? FileManager.default.removeItem(at: project) }

        let model = ProjectSettingsModel(projectURL: project)
        await model.load()
        model.setCommand("/my-plan <slug>", for: .plan)

        model.projectName = "Renamed"
        await model.rename()

        // The override survived the bundle move (saveNow-before-move + writeName
        // preservation).
        let reloaded = try ConfigLoader.load(at: project)
        #expect(reloaded.name == "Renamed")
        #expect(reloaded.workflows?.plan?.command == "/my-plan <slug>")

        // A subsequent auto-save lands in the moved bundle, not the gone one.
        model.setModel(.sonnet, for: .chat)
        await model.saveNow()
        #expect(model.saveStatus == .saved)
        #expect(try ConfigLoader.load(at: project).models?.chat == .sonnet)
    }

    @Test("debounced save coalesces back-to-back mutations")
    func debounceCoalesces() async throws {
        let project = try makeProject()
        defer { try? FileManager.default.removeItem(at: project) }

        // Capture write count via injectable writer so we can prove the
        // debounce filtered intermediate states.
        let counter = WriteCounter()
        let model = ProjectSettingsModel(projectURL: project) { config, bundle in
            counter.bump()
            try ConfigWriter.write(config, atBundle: bundle)
        }
        await model.load()
        model.setCommand("/a", for: .plan)
        model.setCommand("/ab", for: .plan)
        model.setCommand("/abc", for: .plan)
        await model.saveNow()
        #expect(counter.value == 1)

        let reloaded = try ConfigLoader.load(at: project)
        #expect(reloaded.workflows?.plan?.command == "/abc")
    }

    @Test("setEffort triggers debounced write that lands on disk")
    func setEffortDebouncedWrite() async throws {
        let project = try makeProject()
        defer { try? FileManager.default.removeItem(at: project) }

        let model = ProjectSettingsModel(projectURL: project)
        await model.load()
        model.setEffort(.high, for: .chat)
        await model.saveNow()

        #expect(try ConfigLoader.load(at: project).efforts?.chat == .high)
    }

    @Test("effort at slot default elides the override from disk")
    func effortSlotDefaultElides() async throws {
        let project = try makeProject()
        defer { try? FileManager.default.removeItem(at: project) }

        let model = ProjectSettingsModel(projectURL: project)
        await model.load()
        model.setEffort(.max, for: .terminals)
        await model.saveNow()
        #expect(try ConfigLoader.load(at: project).efforts?.terminals == .max)

        model.setEffort(EffortsConfig.terminalsDefault, for: .terminals)
        await model.saveNow()
        #expect(try ConfigLoader.load(at: project).efforts?.terminals == nil)
    }

    @Test("per-type effort pick persists the object form and flips mixed")
    func perTypeEffortPersists() async throws {
        let project = try makeProject()
        defer { try? FileManager.default.removeItem(at: project) }

        let model = ProjectSettingsModel(projectURL: project)
        await model.load()
        #expect(!model.isWorkflowEffortMixed(.implementAction))

        model.setWorkflowEffort(.max, for: .implementAction, type: .feature)
        #expect(model.isWorkflowEffortMixed(.implementAction))
        #expect(model.uniformWorkflowEffort(for: .implementAction) == nil)
        await model.saveNow()

        #expect(
            try ConfigLoader.load(at: project).efforts?.implement
                == .perType([
                    .feature: .max, .chore: .default, .spike: .default, .refactor: .default,
                ]))
    }

    @Test("switching to a model without the current effort resets it; supported effort stays")
    func setModelClampsChatEffort() async throws {
        let project = try makeProject()
        defer { try? FileManager.default.removeItem(at: project) }

        let model = ProjectSettingsModel(projectURL: project)
        await model.load()

        model.setEffort(.xhigh, for: .chat)
        model.setModel(.sonnet, for: .chat)
        #expect(model.effort(for: .chat) == .default)

        model.setEffort(.high, for: .chat)
        model.setModel(.haiku, for: .chat)
        #expect(model.effort(for: .chat) == .default)

        model.setEffort(.high, for: .terminals)
        model.setModel(.sonnet, for: .terminals)
        #expect(model.effort(for: .terminals) == .high)
    }

    @Test("collapsed-header model change clamps each per-type effort individually")
    func setModelClampsWorkflowEffortsPerType() async throws {
        let project = try makeProject()
        defer { try? FileManager.default.removeItem(at: project) }

        let model = ProjectSettingsModel(projectURL: project)
        await model.load()

        model.setWorkflowEffort(.xhigh, for: .planAction, type: .feature)
        model.setWorkflowEffort(.max, for: .planAction, type: .chore)

        model.setModel(.sonnet, for: .planAction)
        #expect(model.workflowEfforts(for: .planAction)[.feature] == .default)
        #expect(model.workflowEfforts(for: .planAction)[.chore] == .max)
    }

    @Test("per-type model pick clamps that type's effort")
    func setWorkflowModelClampsEffort() async throws {
        let project = try makeProject()
        defer { try? FileManager.default.removeItem(at: project) }

        let model = ProjectSettingsModel(projectURL: project)
        await model.load()

        model.setWorkflowEffort(.xhigh, for: .implementAction, type: .feature)
        model.setWorkflowModel(.sonnet, for: .implementAction, type: .feature)
        #expect(model.workflowEfforts(for: .implementAction)[.feature] == .default)
    }

    @Test("switching off an xhigh-tier model clamps a stored ultracode back to default")
    func setModelClampsUltracode() async throws {
        let project = try makeProject()
        defer { try? FileManager.default.removeItem(at: project) }

        let model = ProjectSettingsModel(projectURL: project)
        await model.load()

        model.setModel(.opus, for: .chat)
        model.setEffort(.ultracode, for: .chat)
        #expect(model.effort(for: .chat) == .ultracode)
        model.setModel(.sonnet, for: .chat)
        #expect(model.effort(for: .chat) == .default)

        model.setModel(.opus, for: .implementAction)
        model.setWorkflowEffort(.ultracode, for: .implementAction, type: .feature)
        #expect(model.workflowEfforts(for: .implementAction)[.feature] == .ultracode)
        model.setModel(.haiku, for: .implementAction)
        #expect(model.workflowEfforts(for: .implementAction)[.feature] == .default)
    }

    @Test("load seeds per-type efforts from a mixed config object")
    func loadSeedsPerTypeEfforts() async throws {
        let config = """
            {
              "schemaVersion": 2,
              "name": "Sample",
              "efforts": {
                "implement": { "feature": "max", "chore": "low" }
              }
            }
            """
        let project = try TempProject.make(content: config)
        defer { try? FileManager.default.removeItem(at: project) }

        let model = ProjectSettingsModel(projectURL: project)
        await model.load()
        #expect(model.isWorkflowEffortMixed(.implementAction))
        #expect(model.workflowEfforts(for: .implementAction)[.feature] == .max)
        #expect(model.workflowEfforts(for: .implementAction)[.chore] == .low)
        #expect(model.workflowEfforts(for: .implementAction)[.spike] == .default)
    }

    @Test("load seeds defaultBranch from the config git block, else falls back to main")
    func loadSeedsDefaultBranch() async throws {
        let project = try makeProject()  // baseConfig has no git block
        defer { try? FileManager.default.removeItem(at: project) }
        let model = ProjectSettingsModel(projectURL: project)
        await model.load()
        #expect(model.defaultBranch == "main")

        let withGit = """
            {
              "schemaVersion": 2,
              "name": "Sample",
              "git": { "defaultBranch": "trunk", "branchPrefix": "issue/" }
            }
            """
        let project2 = try TempProject.make(content: withGit)
        defer { try? FileManager.default.removeItem(at: project2) }
        let model2 = ProjectSettingsModel(projectURL: project2)
        await model2.load()
        #expect(model2.defaultBranch == "trunk")
    }

    @Test("setDefaultBranch persists through the pipeline and preserves sibling git keys")
    func setDefaultBranchPersists() async throws {
        let config = """
            {
              "schemaVersion": 2,
              "name": "Sample",
              "git": { "defaultBranch": "main", "branchPrefix": "issue/", "agentFilesInGit": true },
              "plumageManaged": { "skills": [{ "name": "x" }] }
            }
            """
        let project = try TempProject.make(content: config)
        defer { try? FileManager.default.removeItem(at: project) }

        let model = ProjectSettingsModel(projectURL: project)
        await model.load()
        #expect(model.defaultBranch == "main")

        model.setDefaultBranch("develop")
        await model.saveNow()

        #expect(try ConfigLoader.load(at: project).gitDefaultBranch == "develop")
        let bundle = try BundleResolver.findBundle(in: project)
        let parsed = try #require(
            JSONSerialization.jsonObject(
                with: Data(contentsOf: bundle.appendingPathComponent("config.json")))
                as? [String: Any])
        let git = try #require(parsed["git"] as? [String: Any])
        #expect(git["branchPrefix"] as? String == "issue/")
        #expect(git["agentFilesInGit"] as? Bool == true)
        #expect(parsed["plumageManaged"] != nil)
    }
}

// @unchecked Sendable: the writer closure runs off MainActor since the
// production write happens in a detached task. NSLock keeps bump/value safe
// regardless of which actor calls in.
private final class WriteCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Int = 0
    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }
    func bump() {
        lock.lock()
        defer { lock.unlock() }
        _value += 1
    }
}
