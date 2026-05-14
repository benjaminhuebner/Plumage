import Foundation
import Testing

@testable import Plumage

@MainActor
@Suite("IssueDetailModel")
struct IssueDetailModelTests {
    private let now = Date(timeIntervalSince1970: 1_750_000_000)
    private let nowISO = "2025-06-15T15:06:40Z"

    @Test("load parses frontmatter and extracts body")
    func loadParses() async throws {
        let env = try TestEnvironment(spec: Self.baseSpec(status: "approved", body: "# Body\n\nHello."))
        let model = env.makeModel()
        await model.load()
        let issue = try #require(model.issue)
        #expect(issue.title == "Sample")
        #expect(issue.status == .approved)
        #expect(model.loadedBodyContent == "# Body\n\nHello.")
        #expect(!model.isBodyDirty)
    }

    @Test("commitStatus writes status, stamps updated, reloads from disk")
    func commitStatusWrites() async throws {
        let env = try TestEnvironment(spec: Self.baseSpec(status: "approved"))
        let model = env.makeModel()
        await model.load()
        try await model.commitStatus(.inProgress)
        let written = try String(contentsOf: env.specURL, encoding: .utf8)
        #expect(written.contains("status: in-progress"))
        #expect(written.contains("updated: \(nowISO)"))
        #expect(model.issue?.status == .inProgress)
    }

    @Test("commitTitle skips empty titles")
    func commitTitleSkipsEmpty() async throws {
        let env = try TestEnvironment(spec: Self.baseSpec(status: "approved"))
        let model = env.makeModel()
        await model.load()
        let originalContent = try String(contentsOf: env.specURL, encoding: .utf8)
        try await model.commitTitle("   ")
        let after = try String(contentsOf: env.specURL, encoding: .utf8)
        #expect(originalContent == after)
    }

    @Test("multi-field commits serialize without losing earlier writes")
    func serializesMultipleWrites() async throws {
        let env = try TestEnvironment(spec: Self.baseSpec(status: "approved"))
        let model = env.makeModel()
        await model.load()
        async let titleWrite: Void = model.commitTitle("New Title")
        async let labelsWrite: Void = model.commitLabels(["ui", "ux"])
        async let typeWrite: Void = model.commitType(.spike)
        _ = try await (titleWrite, labelsWrite, typeWrite)
        let written = try String(contentsOf: env.specURL, encoding: .utf8)
        #expect(written.contains("title: New Title"))
        #expect(written.contains("labels: [ui, ux]"))
        #expect(written.contains("type: spike"))
    }

    @Test("isBodyDirty flips when body is edited")
    func dirtyBodyDetected() async throws {
        let env = try TestEnvironment(spec: Self.baseSpec(status: "approved", body: "Hello."))
        let model = env.makeModel()
        await model.load()
        #expect(!model.isBodyDirty)
        model.bodyDraft = "Hello, world."
        #expect(model.isBodyDirty)
    }

    @Test("saveBody persists the new body and clears dirty state")
    func saveBodyPersists() async throws {
        let env = try TestEnvironment(spec: Self.baseSpec(status: "approved", body: "Hello."))
        let model = env.makeModel()
        await model.load()
        model.bodyDraft = "Hello, world."
        try await model.saveBody()
        let written = try String(contentsOf: env.specURL, encoding: .utf8)
        #expect(written.contains("Hello, world."))
        #expect(!written.contains("\nHello.\n"))
        #expect(!model.isBodyDirty)
        #expect(written.contains("updated: \(nowISO)"))
    }

    @Test("external change with clean buffer reloads silently")
    func externalCleanReload() async throws {
        let env = try TestEnvironment(spec: Self.baseSpec(status: "approved", body: "Hello."))
        let model = env.makeModel()
        await model.load()
        let updated = Self.baseSpec(status: "blocked", body: "Hello.")
        await model.handleExternalChange(diskContent: updated)
        #expect(model.conflict == nil)
        #expect(model.issue?.status == .blocked)
    }

    @Test("external change with dirty buffer raises conflict")
    func externalDirtyConflict() async throws {
        let env = try TestEnvironment(spec: Self.baseSpec(status: "approved", body: "Hello."))
        let model = env.makeModel()
        await model.load()
        model.bodyDraft = "Hello, dirty."
        let disk = Self.baseSpec(status: "blocked", body: "Hello, disk.")
        await model.handleExternalChange(diskContent: disk)
        #expect(model.conflict != nil)
        // Issue still reflects pre-conflict state.
        #expect(model.issue?.status == .approved)
    }

    @Test("resolveConflictReload adopts disk content")
    func resolveReload() async throws {
        let env = try TestEnvironment(spec: Self.baseSpec(status: "approved", body: "Hello."))
        let model = env.makeModel()
        await model.load()
        model.bodyDraft = "dirty"
        let disk = Self.baseSpec(status: "blocked", body: "fresh.")
        await model.handleExternalChange(diskContent: disk)
        model.resolveConflictReload()
        #expect(model.conflict == nil)
        #expect(model.issue?.status == .blocked)
        #expect(model.bodyDraft == "fresh.")
    }

    @Test("extractBody strips frontmatter and leading blank line")
    func extractBodyTrims() {
        let content = """
            ---
            id: 1
            ---

            # Body

            text
            """
        #expect(IssueDetailModel.extractBody(from: content) == "# Body\n\ntext")
    }

    @Test("replaceBody preserves frontmatter")
    func replaceBodyPreserves() {
        let content = """
            ---
            id: 1
            status: approved
            ---

            old body
            """
        let updated = IssueDetailModel.replaceBody(in: content, with: "new body")
        #expect(updated.contains("status: approved"))
        #expect(updated.hasSuffix("new body"))
        #expect(!updated.contains("old body"))
    }

    private static func baseSpec(status: String, body: String = "Some content.") -> String {
        """
        ---
        id: 1
        title: Sample
        type: feature
        status: \(status)
        created: 2026-05-12T09:00:00Z
        updated: 2026-05-12T10:00:00Z
        branch: issue/00001-x
        labels: []
        model: null
        ---

        \(body)
        """
    }
}

@MainActor
private struct TestEnvironment {
    let tmpDir: URL
    let specURL: URL
    let now = Date(timeIntervalSince1970: 1_750_000_000)

    init(spec content: String) throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("IssueDetailModelTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        specURL = tmpDir.appendingPathComponent("spec.md")
        try content.write(to: specURL, atomically: true, encoding: .utf8)
    }

    func makeModel() -> IssueDetailModel {
        IssueDetailModel(specURL: specURL, folderName: "00001-test", clock: { self.now })
    }
}
