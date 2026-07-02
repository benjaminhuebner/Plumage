import Foundation
import Testing

@testable import Plumage

@MainActor
@Suite("IssueDetailModel evidence and done-when")
struct IssueDetailModelEvidenceTests {
    @Test("loadEvidence parses the file and asks git about the staleness reference")
    func loadEvidenceFreshAndStale() async throws {
        let env = try EvidenceTestEnvironment()
        try env.writeEvidence(
            """
            {"version": 1, "issue": "00001-test", "branch": "issue/00001-test", "totalTasks": 2,
             "tasks": [{"task": 1, "attempts": 1, "passedAt": "2026-07-02T10:00:00Z", "head": "aaa1111", "flags": []}],
             "finalGate": {"attempts": 1, "passedAt": "2026-07-02T11:00:00Z", "head": "bbb2222", "flags": ["--full"]}}
            """)

        let queried = LockedBox<[String]>(value: [])
        let freshModel = env.makeModel(evidenceCommitCounter: { _, head, branch in
            queried.mutate { $0.append("\(head)..\(branch)") }
            return 0
        })
        await freshModel.load()
        await freshModel.loadEvidence()
        guard case .loaded(let evidence) = freshModel.evidence else {
            Testing.Issue.record("expected .loaded, got \(freshModel.evidence)")
            return
        }
        #expect(evidence.tasks.count == 1)
        #expect(queried.value == ["bbb2222..issue/00001-test"])
        #expect(!freshModel.evidenceIsStale)

        let staleModel = env.makeModel(evidenceCommitCounter: { _, _, _ in 1 })
        await staleModel.load()
        await staleModel.loadEvidence()
        #expect(staleModel.evidenceIsStale)
    }

    @Test("missing and malformed evidence map to their states without a git query")
    func loadEvidenceMissingAndMalformed() async throws {
        let env = try EvidenceTestEnvironment()
        let model = env.makeModel(evidenceCommitCounter: { _, _, _ in
            Testing.Issue.record("staleness must not be queried without evidence")
            return nil
        })
        await model.load()
        await model.loadEvidence()
        #expect(model.evidence == .missing)
        #expect(!model.evidenceIsStale)

        try env.writeEvidence(#"{"version": 1, "tasks": [broken"#)
        await model.loadEvidence()
        guard case .unreadable = model.evidence else {
            Testing.Issue.record("expected .unreadable, got \(model.evidence)")
            return
        }
        #expect(!model.evidenceIsStale)
    }

    @Test("toggling a criterion changes exactly one byte on disk and reloads criteria")
    func toggleWritesByteMinimal() async throws {
        let env = try EvidenceTestEnvironment()
        let model = env.makeModel()
        await model.load()
        #expect(model.doneWhenCriteria.map(\.isChecked) == [false, true])

        let original = try String(contentsOf: env.specURL, encoding: .utf8)
        await model.toggleDoneWhenCriterion(at: 0, to: true)
        let written = try String(contentsOf: env.specURL, encoding: .utf8)
        #expect(
            written
                == original.replacingOccurrences(
                    of: "- [ ] first criterion", with: "- [x] first criterion"))
        #expect(model.doneWhenCriteria.map(\.isChecked) == [true, true])
        #expect(model.conflict == nil)
    }

    @Test("an unresolved external-change conflict blocks the tick")
    func toggleRefusedUnderConflict() async throws {
        let env = try EvidenceTestEnvironment()
        let model = env.makeModel()
        await model.load()
        model.bodyDraft += "\nlocal edit"
        await model.handleExternalChange(diskContent: env.spec + "\nforeign edit\n")
        guard case .externalChange = model.conflict else {
            Testing.Issue.record("expected externalChange conflict, got \(String(describing: model.conflict))")
            return
        }

        let before = try String(contentsOf: env.specURL, encoding: .utf8)
        await model.toggleDoneWhenCriterion(at: 0, to: true)
        let after = try String(contentsOf: env.specURL, encoding: .utf8)
        #expect(before == after)
        #expect(model.doneWhenCriteria.map(\.isChecked) == [false, true])
    }

    @Test("a dirty draft is patched so auto-save cannot undo the tick")
    func togglePatchesDirtyDraft() async throws {
        let env = try EvidenceTestEnvironment()
        let model = env.makeModel()
        await model.load()
        model.bodyDraft += "\ntrailing unsaved edit"

        await model.toggleDoneWhenCriterion(at: 0, to: true)
        #expect(model.bodyDraft.contains("- [x] first criterion"))
        #expect(model.bodyDraft.contains("trailing unsaved edit"))
        #expect(model.isBodyDirty)
        let written = try String(contentsOf: env.specURL, encoding: .utf8)
        #expect(written.contains("- [x] first criterion"))
        #expect(!written.contains("trailing unsaved edit"))
    }

    @Test("a waiting-for-review spec opens on the pull-request tab before any async load")
    func defaultTabAppliedSynchronously() throws {
        let env = try EvidenceTestEnvironment()
        let model = env.makeModel()
        #expect(model.selectedBodyTab == .pullRequest)
    }
}

@MainActor
private final class EvidenceTestEnvironment {
    let tmpDir: URL
    let projectURL: URL
    let folderName = "00001-test"
    let specURL: URL
    let now = Date(timeIntervalSince1970: 1_750_000_000)
    let spec = """
        ---
        id: 1
        title: Evidence
        type: feature
        status: waiting-for-review
        created: 2026-05-12T09:00:00Z
        updated: 2026-05-12T10:00:00Z
        branch: issue/00001-test
        labels: []
        ---

        # Evidence

        ## Done when

        - [ ] first criterion
        - [x] second criterion
        """

    init() throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("IssueDetailModelEvidenceTests-\(UUID().uuidString)")
        projectURL = tmpDir
        let issueFolder = IssueLayout.issueFolder(in: projectURL, folderName: folderName)
        try FileManager.default.createDirectory(at: issueFolder, withIntermediateDirectories: true)
        specURL = IssueLayout.specURL(in: projectURL, folderName: folderName)
        try spec.write(to: specURL, atomically: true, encoding: .utf8)
    }

    func writeEvidence(_ json: String) throws {
        try json.write(
            to: IssueLayout.evidenceURL(in: projectURL, folderName: folderName),
            atomically: true, encoding: .utf8)
    }

    func makeModel(
        evidenceCommitCounter: @escaping @Sendable (URL, String, String) async -> Int? = { _, _, _ in 0 }
    ) -> IssueDetailModel {
        IssueDetailModel(
            specURL: specURL,
            folderName: folderName,
            projectURL: projectURL,
            clock: { self.now },
            evidenceCommitCounter: evidenceCommitCounter
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: tmpDir)
    }
}
