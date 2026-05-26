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
}

@MainActor
private final class WriteCounter {
    var value: Int = 0
    func bump() { value += 1 }
}
