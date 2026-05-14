import Foundation
import Testing

@testable import Plumage

@MainActor
@Suite("IssueDetailModel")
struct IssueDetailModelTests {
    private let now = Date(timeIntervalSince1970: 1_750_000_000)
    private let nowISO = "2025-06-15T15:06:40Z"

    // Convenience that returns a TestEnvironment whose tmp dir is cleaned
    // up automatically when the value goes out of scope (TestEnvironment
    // is a class with a removing deinit). Tests use `try makeEnvironment`
    // instead of constructing directly so the cleanup contract is local
    // to one place.
    private func makeEnvironment(spec content: String) throws -> TestEnvironment {
        try TestEnvironment(spec: content)
    }

    @Test("load parses frontmatter and extracts body")
    func loadParses() async throws {
        let env = try makeEnvironment(spec: Self.baseSpec(status: "approved", body: "# Body\n\nHello."))
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
        let env = try makeEnvironment(spec: Self.baseSpec(status: "approved"))
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
        let env = try makeEnvironment(spec: Self.baseSpec(status: "approved"))
        let model = env.makeModel()
        await model.load()
        let originalContent = try String(contentsOf: env.specURL, encoding: .utf8)
        try await model.commitTitle("   ")
        let after = try String(contentsOf: env.specURL, encoding: .utf8)
        #expect(originalContent == after)
    }

    @Test("multi-field commits serialize without losing earlier writes")
    func serializesMultipleWrites() async throws {
        let env = try makeEnvironment(spec: Self.baseSpec(status: "approved"))
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
        let env = try makeEnvironment(spec: Self.baseSpec(status: "approved", body: "Hello."))
        let model = env.makeModel()
        await model.load()
        #expect(!model.isBodyDirty)
        model.bodyDraft = "Hello, world."
        #expect(model.isBodyDirty)
    }

    @Test("saveBody persists the new body and clears dirty state")
    func saveBodyPersists() async throws {
        let env = try makeEnvironment(spec: Self.baseSpec(status: "approved", body: "Hello."))
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
        let env = try makeEnvironment(spec: Self.baseSpec(status: "approved", body: "Hello."))
        let model = env.makeModel()
        await model.load()
        let updated = Self.baseSpec(status: "blocked", body: "Hello.")
        await model.handleExternalChange(diskContent: updated)
        #expect(model.conflict == nil)
        #expect(model.issue?.status == .blocked)
    }

    @Test("external change with dirty buffer raises conflict")
    func externalDirtyConflict() async throws {
        let env = try makeEnvironment(spec: Self.baseSpec(status: "approved", body: "Hello."))
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
        let env = try makeEnvironment(spec: Self.baseSpec(status: "approved", body: "Hello."))
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

    @Test("observeExternalChange skips disk read when issue snapshot unchanged")
    func observeExternalChangeDedup() async throws {
        let env = try makeEnvironment(spec: Self.baseSpec(status: "approved", body: "Hello."))
        let model = env.makeModel()
        await model.load()
        let issue = try #require(model.issue)
        let discovered = DiscoveredIssue.valid(issue)
        await model.observeExternalChange(currentIssue: discovered)
        // Mutate disk after the first observe: a second observe with the
        // same DiscoveredIssue must not cause a reload (lastSeenIssue dedup).
        try Self.baseSpec(status: "blocked", body: "Disk-changed.")
            .write(to: env.specURL, atomically: true, encoding: .utf8)
        await model.observeExternalChange(currentIssue: discovered)
        #expect(model.issue?.status == .approved)
        #expect(!model.loadedBodyContent.contains("Disk-changed."))
    }

    @Test("observeExternalChange triggers reload when issue snapshot changes")
    func observeExternalChangeReloads() async throws {
        let env = try makeEnvironment(spec: Self.baseSpec(status: "approved", body: "Hello."))
        let model = env.makeModel()
        await model.load()
        try Self.baseSpec(status: "blocked", body: "Disk-changed.")
            .write(to: env.specURL, atomically: true, encoding: .utf8)
        // A NEW snapshot with status=blocked from kanban triggers a fresh
        // disk read; the model picks up the external change silently.
        let discovered = DiscoveredIssue.valid(
            Issue(
                id: 1, folderName: "00001-test", title: "Sample", type: .feature,
                status: .blocked, created: .distantPast, updated: .distantPast,
                branch: "issue/00001-x", labels: [], model: nil
            )
        )
        await model.observeExternalChange(currentIssue: discovered)
        #expect(model.issue?.status == .blocked)
        #expect(model.loadedBodyContent.contains("Disk-changed."))
        #expect(model.conflict == nil)
    }

    @Test("saveBody throws SaveError.unresolvedConflict while external change is pending")
    func saveBodyRefusesWhenConflict() async throws {
        let env = try makeEnvironment(spec: Self.baseSpec(status: "approved", body: "Hello."))
        let model = env.makeModel()
        await model.load()
        model.bodyDraft = "Hello, dirty."
        // Simulate an external write while the user is editing.
        let disk = Self.baseSpec(status: "blocked", body: "Hello, disk.")
        await model.handleExternalChange(diskContent: disk)
        #expect(model.conflict != nil)
        await #expect(throws: IssueDetailModel.SaveError.unresolvedConflict) {
            try await model.saveBody()
        }
        // Disk content must be untouched — still the external version.
        let onDisk = try String(contentsOf: env.specURL, encoding: .utf8)
        #expect(onDisk.contains("Hello."))  // original body still present on disk
    }

    @Test("saveRaw throws SaveError.unresolvedConflict while external change is pending")
    func saveRawRefusesWhenConflict() async throws {
        let env = try makeEnvironment(spec: Self.baseSpec(status: "approved", body: "Hello."))
        let model = env.makeModel()
        await model.load()
        // Mark the buffer dirty so handleExternalChange actually raises a
        // conflict (clean buffers auto-adopt disk changes).
        model.bodyDraft = "Local edit."
        let disk = Self.baseSpec(status: "blocked", body: "Hello, disk.")
        await model.handleExternalChange(diskContent: disk)
        #expect(model.conflict != nil)
        let proposed = Self.baseSpec(status: "done", body: "Edited raw.")
        await #expect(throws: IssueDetailModel.SaveError.unresolvedConflict) {
            try await model.saveRaw(proposed)
        }
    }

    @Test("saveBody after resolveConflictKeep proceeds and overwrites disk")
    func saveBodyAfterKeepProceeds() async throws {
        let env = try makeEnvironment(spec: Self.baseSpec(status: "approved", body: "Hello."))
        let model = env.makeModel()
        await model.load()
        model.bodyDraft = "Mine wins."
        let disk = Self.baseSpec(status: "blocked", body: "External.")
        await model.handleExternalChange(diskContent: disk)
        model.resolveConflictKeep()
        try await model.saveBody()
        let written = try String(contentsOf: env.specURL, encoding: .utf8)
        #expect(written.contains("Mine wins."))
        #expect(!model.isBodyDirty)
    }

    @Test("saveRaw writes full content and re-applies frontmatter parse")
    func saveRawPersistsFullContent() async throws {
        let env = try makeEnvironment(spec: Self.baseSpec(status: "approved", body: "Hello."))
        let model = env.makeModel()
        await model.load()
        let raw = Self.baseSpec(status: "in-progress", body: "Raw replacement.")
        try await model.saveRaw(raw)
        let onDisk = try String(contentsOf: env.specURL, encoding: .utf8)
        #expect(onDisk.contains("status: in-progress"))
        #expect(onDisk.contains("Raw replacement."))
        // Model state reflects the freshly-written content.
        #expect(model.issue?.status == .inProgress)
        #expect(model.loadedBodyContent.contains("Raw replacement."))
    }

    @Test("creating-mode init pre-populates statusDraft and skips disk load")
    func creatingInitDefaults() async throws {
        let projectURL = URL(filePath: "/tmp/fake-project-\(UUID().uuidString)")
        let model = IssueDetailModel(
            creatingInitialStatus: .inProgress,
            projectURL: projectURL,
            clock: { self.now }
        )
        var creatingStatus: IssueStatus?
        if case .creating(let status) = model.kind { creatingStatus = status }
        #expect(creatingStatus == .inProgress)
        #expect(model.specURL == nil)
        #expect(model.folderName == nil)
        #expect(model.statusDraft == .inProgress)
        #expect(model.typeDraft == .feature)
        #expect(model.titleDraft.isEmpty)
        #expect(model.labelsDraft.isEmpty)
        #expect(model.bodyDraft.isEmpty)
        // Form should render immediately, not a ProgressView.
        #expect(model.loadState == .loaded)
        #expect(!model.canSaveInCreatingMode)
    }

    @Test("creating-mode save is gated on non-empty trimmed title")
    func creatingTitleGate() async throws {
        let projectURL = URL(filePath: "/tmp/fake-project-\(UUID().uuidString)")
        let model = IssueDetailModel(
            creatingInitialStatus: .draft,
            projectURL: projectURL,
            clock: { self.now }
        )
        #expect(!model.canSaveInCreatingMode)
        model.titleDraft = "   "
        #expect(!model.canSaveInCreatingMode)
        model.titleDraft = "Real title"
        #expect(model.canSaveInCreatingMode)
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
private final class TestEnvironment {
    // Class (not struct) so deinit removes the tmp dir automatically when
    // the local test value goes out of scope — otherwise UUID-named
    // directories accumulate in /tmp on every test run.
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

    deinit {
        try? FileManager.default.removeItem(at: tmpDir)
    }
}
