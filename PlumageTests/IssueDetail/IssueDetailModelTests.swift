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

    @Test("load mirrors parsed issue into drafts so the view has one source of truth")
    func loadSyncsDrafts() async throws {
        let env = try makeEnvironment(
            spec: Self.baseSpec(status: "in-progress", body: "Body."))
        let model = env.makeModel()
        await model.load()
        let issue = try #require(model.issue)
        #expect(model.titleDraft == issue.title)
        #expect(model.typeDraft == issue.type)
        #expect(model.statusDraft == issue.status)
        #expect(model.labelsDraft == issue.labels)
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

    @Test("createIssueFromDraft passes body as prompt, flips non-draft status, seeds prompt fields")
    func createIssueAllocatorThenMutatorSequence() async throws {
        let env = try makeEnvironment(spec: Self.baseSpec(status: "draft", body: "Loaded body."))
        let recorder = AllocatorMutatorRecorder(allocatedSpecURL: env.specURL)
        let projectURL = env.tmpDir
        let model = IssueDetailModel(
            creatingInitialStatus: .inProgress,
            projectURL: projectURL,
            allocator: recorder,
            mutator: recorder,
            clock: { self.now }
        )
        model.titleDraft = "My New Issue"
        model.typeDraft = .chore
        model.labelsDraft = ["ui"]
        model.bodyDraft = "Some body content"

        try await model.createIssueFromDraft()

        let calls = recorder.calls
        #expect(calls.count == 2)
        if case .allocate(let slug, let title, let type, let labels, let prompt, let now) = calls[0] {
            #expect(slug == "my-new-issue")
            #expect(title == "My New Issue")
            #expect(type == .chore)
            #expect(labels == ["ui"])
            #expect(prompt == "Some body content")
            #expect(now == self.now)
        } else {
            #expect(Bool(false), "first call should be allocate, was \(calls[0])")
        }
        if case .mutate(let specURL, let mutation, let now) = calls[1] {
            #expect(specURL == env.specURL)
            #expect(mutation.status == .set(.inProgress))
            #expect(mutation.body == .keep)
            #expect(now == self.now)
        } else {
            #expect(Bool(false), "second call should be mutate, was \(calls[1])")
        }
        if case .loaded(let folderName) = model.kind {
            #expect(folderName == env.specURL.deletingLastPathComponent().lastPathComponent)
        } else {
            #expect(Bool(false), "expected .loaded kind after save")
        }
        #expect(model.specURL == env.specURL)
        #expect(model.allocationError == nil)
        #expect(model.promptDraft == "Some body content")
        #expect(model.loadedPromptContent == "Some body content")
    }

    @Test("createIssueFromDraft with empty title throws and does not call allocator")
    func createIssueRejectsEmptyTitle() async throws {
        let env = try makeEnvironment(spec: Self.baseSpec(status: "draft"))
        let recorder = AllocatorMutatorRecorder(allocatedSpecURL: env.specURL)
        let model = IssueDetailModel(
            creatingInitialStatus: .draft,
            projectURL: env.tmpDir,
            allocator: recorder,
            mutator: recorder,
            clock: { self.now }
        )
        model.titleDraft = "   "
        await #expect(throws: IssueDetailModel.SaveError.emptyTitle) {
            try await model.createIssueFromDraft()
        }
        #expect(recorder.calls.isEmpty)
        if case .creating = model.kind {
        } else {
            #expect(Bool(false), "kind should remain .creating after failed save")
        }
    }

    @Test("createIssueFromDraft skips mutator when status is template-default draft")
    func createIssueSkipsMutatorForDraftStatus() async throws {
        let env = try makeEnvironment(spec: Self.baseSpec(status: "draft"))
        let recorder = AllocatorMutatorRecorder(allocatedSpecURL: env.specURL)
        let model = IssueDetailModel(
            creatingInitialStatus: .draft,
            projectURL: env.tmpDir,
            allocator: recorder,
            mutator: recorder,
            clock: { self.now }
        )
        model.titleDraft = "Title"
        model.bodyDraft = "An idea."

        try await model.createIssueFromDraft()

        #expect(recorder.calls.count == 1)
        if case .allocate(_, _, _, _, let prompt, _) = recorder.calls[0] {
            #expect(prompt == "An idea.")
        } else {
            #expect(Bool(false), "expected allocate call, got \(recorder.calls[0])")
        }
        #expect(model.promptDraft == "An idea.")
        #expect(model.loadedPromptContent == "An idea.")
    }

    @Test("defaultTab maps status to expected smart-default tab")
    func defaultTabPerStatus() {
        #expect(IssueDetailModel.defaultTab(for: .draft) == .prompt)
        #expect(IssueDetailModel.defaultTab(for: .approved) == .spec)
        #expect(IssueDetailModel.defaultTab(for: .inProgress) == .spec)
        #expect(IssueDetailModel.defaultTab(for: .waitingForReview) == .pullRequest)
        #expect(IssueDetailModel.defaultTab(for: .done) == .spec)
        #expect(IssueDetailModel.defaultTab(for: .blocked) == .spec)
    }

    @Test("prompt round-trip: missing → save → reload")
    func promptRoundTrip() async throws {
        let env = try LayoutTestEnvironment()
        let model = env.makeModel()
        await model.loadPrompt()
        #expect(model.loadedPromptContent.isEmpty)
        #expect(!model.isPromptDirty)

        model.promptDraft = "An idea worth exploring."
        #expect(model.isPromptDirty)
        try await model.savePrompt()
        #expect(!model.isPromptDirty)
        #expect(model.loadedPromptContent == "An idea worth exploring.")

        let onDisk = try String(contentsOf: env.promptURL, encoding: .utf8)
        #expect(onDisk == "An idea worth exploring.")

        let fresh = env.makeModel()
        await fresh.loadPrompt()
        #expect(fresh.loadedPromptContent == "An idea worth exploring.")
    }

    @Test("loadPR returns nil when pr.md missing, content when present")
    func loadPRBehavior() async throws {
        let env = try LayoutTestEnvironment()
        let model = env.makeModel()
        await model.loadPR()
        #expect(model.prContent == nil)

        try "## Summary\nDone.".write(to: env.prURL, atomically: true, encoding: .utf8)
        await model.loadPR()
        #expect(model.prContent == "## Summary\nDone.")
    }

    // MARK: - mergeToMain

    @Test("mergeToMain happy path flips status to done and clears isMerging")
    func mergeToMainHappyPath() async throws {
        let env = try makeEnvironment(spec: Self.baseSpec(status: "waiting-for-review"))
        let mock = MockGitProcessRunner()
        Self.primeMockForCleanRepo(mock, tmpDir: env.tmpDir, defaultBranch: "main", issueBranch: "issue/00001-x")
        let model = env.makeModel(
            mergeRunner: GitMergeRunner(runner: mock, resolveBinary: { Self.fakeBinary }),
            configLoader: { _ in Self.configWith(defaultBranch: "main") }
        )
        await model.load()

        let success = await model.mergeToMain(mode: .fastForward, commitSubject: nil, deleteBranch: false)

        #expect(success == true)
        #expect(model.isMerging == false)
        #expect(model.lastMergeError == nil)
        #expect(model.lastMergeCriticalError == nil)
        #expect(model.lastMergeNotice == nil)
        let onDisk = try String(contentsOf: env.specURL, encoding: .utf8)
        #expect(onDisk.contains("status: done"))
        #expect(model.issue?.status == .done)
    }

    @Test("mergeToMain working-tree-dirty leaves spec untouched and surfaces lastMergeError")
    func mergeToMainWorkingTreeDirty() async throws {
        let env = try makeEnvironment(spec: Self.baseSpec(status: "waiting-for-review"))
        let mock = MockGitProcessRunner()
        mock.stdoutForArgs[Self.statusArgs(tmpDir: env.tmpDir)] = " M Plumage/Foo.swift\n"
        let model = env.makeModel(
            mergeRunner: GitMergeRunner(runner: mock, resolveBinary: { Self.fakeBinary }),
            configLoader: { _ in Self.configWith(defaultBranch: "main") }
        )
        await model.load()

        let success = await model.mergeToMain(mode: .fastForward, commitSubject: nil, deleteBranch: true)

        #expect(success == false)
        #expect(model.lastMergeError == .workingTreeDirty(files: ["Plumage/Foo.swift"]))
        let onDisk = try String(contentsOf: env.specURL, encoding: .utf8)
        #expect(onDisk.contains("status: waiting-for-review"))
    }

    @Test("mergeToMain not-fast-forward sets lastMergeError to .notFastForward")
    func mergeToMainNotFastForward() async throws {
        let env = try makeEnvironment(spec: Self.baseSpec(status: "waiting-for-review"))
        let mock = MockGitProcessRunner()
        mock.stdoutForArgs[Self.revParseArgs(tmpDir: env.tmpDir, branch: "issue/00001-x")] = "abc\n"
        mock.exitCodeForArgs[Self.mergeBaseArgs(tmpDir: env.tmpDir, base: "main", branch: "issue/00001-x")] = 1
        let model = env.makeModel(
            mergeRunner: GitMergeRunner(runner: mock, resolveBinary: { Self.fakeBinary }),
            configLoader: { _ in Self.configWith(defaultBranch: "main") }
        )
        await model.load()

        let success = await model.mergeToMain(mode: .fastForward, commitSubject: nil, deleteBranch: true)

        #expect(success == false)
        #expect(model.lastMergeError == .notFastForward(defaultBranch: "main", issueBranch: "issue/00001-x"))
        #expect(model.issue?.status == .waitingForReview)
    }

    @Test("mergeToMain non-fatal branch-delete-failure still flips status and returns true")
    func mergeToMainBranchDeleteFails() async throws {
        let env = try makeEnvironment(spec: Self.baseSpec(status: "waiting-for-review"))
        let mock = MockGitProcessRunner()
        Self.primeMockForCleanRepo(mock, tmpDir: env.tmpDir, defaultBranch: "main", issueBranch: "issue/00001-x")
        let deleteArgs = Self.deleteArgs(tmpDir: env.tmpDir, branch: "issue/00001-x")
        mock.exitCodeForArgs[deleteArgs] = 1
        mock.stderrForArgs[deleteArgs] = "error: branch 'issue/00001-x' not fully merged\n"
        let model = env.makeModel(
            mergeRunner: GitMergeRunner(runner: mock, resolveBinary: { Self.fakeBinary }),
            configLoader: { _ in Self.configWith(defaultBranch: "main") }
        )
        await model.load()

        let success = await model.mergeToMain(mode: .fastForward, commitSubject: nil, deleteBranch: true)

        #expect(success == true)
        #expect(model.lastMergeError == nil)
        #expect(model.lastMergeNotice?.contains("not deleted") == true)
        #expect(model.issue?.status == .done)
    }

    @Test("mergeToMain reads defaultBranch via configLoader")
    func mergeToMainReadsConfig() async throws {
        let env = try makeEnvironment(spec: Self.baseSpec(status: "waiting-for-review"))
        let mock = MockGitProcessRunner()
        Self.primeMockForCleanRepo(mock, tmpDir: env.tmpDir, defaultBranch: "trunk", issueBranch: "issue/00001-x")
        let model = env.makeModel(
            mergeRunner: GitMergeRunner(runner: mock, resolveBinary: { Self.fakeBinary }),
            configLoader: { _ in Self.configWith(defaultBranch: "trunk") }
        )
        await model.load()

        let success = await model.mergeToMain(mode: .fastForward, commitSubject: nil, deleteBranch: false)

        #expect(success == true)
        #expect(
            mock.recordedCalls.contains(Self.mergeBaseArgs(tmpDir: env.tmpDir, base: "trunk", branch: "issue/00001-x")))
        #expect(mock.recordedCalls.contains(Self.checkoutArgs(tmpDir: env.tmpDir, branch: "trunk")))
    }

    @Test("mergeToMain noop when projectURL is nil")
    func mergeToMainNoopWithoutProjectURL() async throws {
        let env = try makeEnvironment(spec: Self.baseSpec(status: "waiting-for-review"))
        let mock = MockGitProcessRunner()
        let model = IssueDetailModel(
            specURL: env.specURL,
            folderName: "00001-test",
            projectURL: nil,
            mergeRunner: GitMergeRunner(runner: mock, resolveBinary: { Self.fakeBinary }),
            configLoader: { _ in nil },
            clock: { env.now }
        )
        await model.load()

        let success = await model.mergeToMain(mode: .fastForward, commitSubject: nil, deleteBranch: false)
        #expect(success == false)
        #expect(mock.recordedCalls.isEmpty)
    }

    @Test("mergeToMain squash passes mode and subject through to the runner")
    func mergeToMainSquashPassesSubject() async throws {
        let env = try makeEnvironment(spec: Self.baseSpec(status: "waiting-for-review"))
        let mock = MockGitProcessRunner()
        Self.primeMockForCleanRepo(mock, tmpDir: env.tmpDir, defaultBranch: "main", issueBranch: "issue/00001-x")
        let model = env.makeModel(
            mergeRunner: GitMergeRunner(runner: mock, resolveBinary: { Self.fakeBinary }),
            configLoader: { _ in Self.configWith(defaultBranch: "main") }
        )
        await model.load()

        let success = await model.mergeToMain(
            mode: .squash, commitSubject: "Add squash mode to issue merge", deleteBranch: false)

        #expect(success == true)
        #expect(
            mock.recordedCalls.contains(
                Self.squashMergeArgs(tmpDir: env.tmpDir, branch: "issue/00001-x")))
        #expect(
            mock.recordedCalls.contains(
                Self.commitArgs(tmpDir: env.tmpDir, subject: "Add squash mode to issue merge")))
        #expect(model.issue?.status == .done)
    }

    @Test("mergeToMain squash trims the subject before passing it on")
    func mergeToMainSquashTrimsSubject() async throws {
        let env = try makeEnvironment(spec: Self.baseSpec(status: "waiting-for-review"))
        let mock = MockGitProcessRunner()
        Self.primeMockForCleanRepo(mock, tmpDir: env.tmpDir, defaultBranch: "main", issueBranch: "issue/00001-x")
        let model = env.makeModel(
            mergeRunner: GitMergeRunner(runner: mock, resolveBinary: { Self.fakeBinary }),
            configLoader: { _ in Self.configWith(defaultBranch: "main") }
        )
        await model.load()

        let success = await model.mergeToMain(
            mode: .squash, commitSubject: "  Tidy subject  ", deleteBranch: false)

        #expect(success == true)
        #expect(
            mock.recordedCalls.contains(
                Self.commitArgs(tmpDir: env.tmpDir, subject: "Tidy subject")))
    }

    @Test("mergeToMain squash with empty subject never spawns git")
    func mergeToMainSquashEmptySubject() async throws {
        let env = try makeEnvironment(spec: Self.baseSpec(status: "waiting-for-review"))
        let mock = MockGitProcessRunner()
        let model = env.makeModel(
            mergeRunner: GitMergeRunner(runner: mock, resolveBinary: { Self.fakeBinary }),
            configLoader: { _ in Self.configWith(defaultBranch: "main") }
        )
        await model.load()

        let emptyResult = await model.mergeToMain(mode: .squash, commitSubject: "", deleteBranch: true)
        let whitespaceResult = await model.mergeToMain(mode: .squash, commitSubject: "  \n", deleteBranch: true)
        let nilResult = await model.mergeToMain(mode: .squash, commitSubject: nil, deleteBranch: true)

        #expect(emptyResult == false)
        #expect(whitespaceResult == false)
        #expect(nilResult == false)
        #expect(mock.recordedCalls.isEmpty)
        #expect(model.issue?.status == .waitingForReview)
    }

    @Test("mergeSubjectPrefill prefers frontmatter mergeSubject over title")
    func mergeSubjectPrefillFromFrontmatter() async throws {
        let spec = """
            ---
            id: 1
            title: Sample
            type: feature
            status: waiting-for-review
            created: 2026-05-12T09:00:00Z
            updated: 2026-05-12T10:00:00Z
            branch: issue/00001-x
            labels: []
            model: null
            mergeSubject: Add squash mode to issue merge
            ---

            Some content.
            """
        let env = try makeEnvironment(spec: spec)
        let model = env.makeModel()
        await model.load()

        #expect(model.mergeSubjectPrefill == "Add squash mode to issue merge")
    }

    @Test("mergeSubjectPrefill falls back to the issue title")
    func mergeSubjectPrefillFallsBackToTitle() async throws {
        let env = try makeEnvironment(spec: Self.baseSpec(status: "waiting-for-review"))
        let model = env.makeModel()
        await model.load()

        #expect(model.mergeSubjectPrefill == "Sample")
    }

    // MARK: - mergeToMain helpers

    nonisolated static let fakeBinary = URL(filePath: "/usr/bin/git")

    nonisolated private static func primeMockForCleanRepo(
        _ mock: MockGitProcessRunner,
        tmpDir: URL,
        defaultBranch: String,
        issueBranch: String
    ) {
        // status: empty stdout, exit 0 (default).
        mock.stdoutForArgs[revParseArgs(tmpDir: tmpDir, branch: issueBranch)] = "abc\n"
        // merge-base: exit 0 (default).
        // checkout / merge / branch -d: all default exit 0, no stdout/stderr.
        _ = defaultBranch
    }

    nonisolated static func statusArgs(tmpDir: URL) -> [String] {
        ["-C", tmpDir.path, "status", "--porcelain"]
    }
    nonisolated static func revParseArgs(tmpDir: URL, branch: String) -> [String] {
        ["-C", tmpDir.path, "rev-parse", "--verify", branch]
    }
    nonisolated static func mergeBaseArgs(tmpDir: URL, base: String, branch: String) -> [String] {
        ["-C", tmpDir.path, "merge-base", "--is-ancestor", base, branch]
    }
    nonisolated static func checkoutArgs(tmpDir: URL, branch: String) -> [String] {
        ["-C", tmpDir.path, "checkout", branch]
    }
    nonisolated static func squashMergeArgs(tmpDir: URL, branch: String) -> [String] {
        ["-C", tmpDir.path, "merge", "--squash", branch]
    }
    nonisolated static func commitArgs(tmpDir: URL, subject: String) -> [String] {
        ["-C", tmpDir.path, "commit", "-m", subject]
    }
    nonisolated static func deleteArgs(tmpDir: URL, branch: String) -> [String] {
        ["-C", tmpDir.path, "branch", "-d", branch]
    }

    nonisolated private static func configWith(defaultBranch: String) -> ProjectConfig {
        ProjectConfig(
            name: "Test", schemaVersion: 2, issueIdPadding: 5,
            git: GitConfig(defaultBranch: defaultBranch)
        )
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
        IssueDetailModel(
            specURL: specURL,
            folderName: "00001-test",
            projectURL: tmpDir,
            clock: { self.now }
        )
    }

    func makeModel(
        mergeRunner: any GitMergeRunning,
        configLoader: @escaping @Sendable (URL) -> ProjectConfig?
    ) -> IssueDetailModel {
        IssueDetailModel(
            specURL: specURL,
            folderName: "00001-test",
            projectURL: tmpDir,
            mergeRunner: mergeRunner,
            configLoader: configLoader,
            clock: { self.now }
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: tmpDir)
    }
}

@MainActor
private final class LayoutTestEnvironment {
    let tmpDir: URL
    let projectURL: URL
    let folderName: String
    let specURL: URL
    let promptURL: URL
    let prURL: URL
    let now = Date(timeIntervalSince1970: 1_750_000_000)

    init(folderName: String = "00001-test") throws {
        self.folderName = folderName
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("IssueDetailModelLayoutTests-\(UUID().uuidString)")
        projectURL = tmpDir
        let issueFolder = IssueLayout.issueFolder(in: projectURL, folderName: folderName)
        try FileManager.default.createDirectory(at: issueFolder, withIntermediateDirectories: true)
        specURL = IssueLayout.specURL(in: projectURL, folderName: folderName)
        promptURL = IssueLayout.promptURL(in: projectURL, folderName: folderName)
        prURL = IssueLayout.prURL(in: projectURL, folderName: folderName)
        let spec = """
            ---
            id: 1
            title: Layout
            type: feature
            status: approved
            created: 2026-05-12T09:00:00Z
            updated: 2026-05-12T10:00:00Z
            branch: issue/00001-test
            labels: []
            model: null
            ---

            body.
            """
        try spec.write(to: specURL, atomically: true, encoding: .utf8)
    }

    func makeModel() -> IssueDetailModel {
        IssueDetailModel(
            specURL: specURL,
            folderName: folderName,
            projectURL: projectURL,
            clock: { self.now }
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: tmpDir)
    }
}

private enum RecordedCall: Sendable {
    case allocate(slug: String, title: String, type: IssueType, labels: [String], prompt: String, now: Date)
    case mutate(specURL: URL, mutation: FrontmatterMutation, now: Date)
}

private final class AllocatorMutatorRecorder: IssueAllocating, FrontmatterMutating, @unchecked Sendable {
    // Sequence of allocate/mutate invocations recorded in call order so tests
    // can pin that allocate runs before mutate.
    let allocatedSpecURL: URL
    private let lock = NSLock()
    private var _calls: [RecordedCall] = []

    init(allocatedSpecURL: URL) {
        self.allocatedSpecURL = allocatedSpecURL
    }

    var calls: [RecordedCall] {
        lock.withLock { _calls }
    }

    func allocate(
        slug: String,
        title: String,
        type: IssueType,
        labels: [String],
        prompt: String,
        now: Date
    ) throws -> URL {
        lock.withLock {
            _calls.append(.allocate(slug: slug, title: title, type: type, labels: labels, prompt: prompt, now: now))
        }
        return allocatedSpecURL
    }

    func mutate(specURL: URL, mutation: FrontmatterMutation, now: Date) throws {
        lock.withLock {
            _calls.append(.mutate(specURL: specURL, mutation: mutation, now: now))
        }
    }
}
