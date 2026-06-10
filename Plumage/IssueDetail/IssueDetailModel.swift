import AppKit
import Foundation

@MainActor
@Observable
final class IssueDetailModel {
    enum ConflictState: Equatable {
        case externalChange(diskContent: String)
        case fileDeleted
    }

    enum LoadState: Equatable {
        case idle
        case loaded
        case failed(String)
    }

    enum SaveError: Error, Equatable {
        case unresolvedConflict
        case missingProjectURL
        case emptyTitle
    }

    enum Kind: Equatable, Sendable {
        case creating(initialStatus: IssueStatus)
        case loaded(folderName: String)
    }

    private(set) var kind: Kind
    private(set) var specURL: URL?
    let projectURL: URL?

    var folderName: String? {
        switch kind {
        case .creating: nil
        case .loaded(let folderName): folderName
        }
    }

    // Drafts used in creating mode. In loaded mode the existing form-commit
    // path writes directly through to disk and these stay untouched.
    var titleDraft: String = ""
    var typeDraft: IssueType = .feature
    var statusDraft: IssueStatus = .draft
    var labelsDraft: [String] = []

    private(set) var issue: Issue?
    private(set) var loadState: LoadState = .idle
    private(set) var loadedSpecContent: String = ""
    private(set) var loadedBodyContent: String = ""
    var bodyDraft: String = ""
    private(set) var loadedPromptContent: String = ""
    var promptDraft: String = ""
    private(set) var prContent: String?
    // Pre-parsed PR.md blocks so PRTabView renders without re-parsing on every
    // body evaluation. Populated together with prContent in loadPR().
    private(set) var prBlocks: [PRMarkdownParser.Block] = []
    var selectedBodyTab: BodyTab = .spec
    private(set) var conflict: ConflictState?
    private(set) var frontmatterError: FrontmatterError?
    private(set) var lastWrittenContent: String?
    private(set) var lastSeenIssue: DiscoveredIssue?
    private(set) var allocationError: String?
    private(set) var isMerging: Bool = false
    private(set) var lastMergeError: GitMergeError?
    // Set when the merge wrote to disk but the spec-status flip failed
    // afterwards — surfaced as a critical banner so the user knows to fix
    // spec.md manually. Distinct from lastMergeError because the git side
    // already succeeded.
    private(set) var lastMergeCriticalError: String?
    // Non-fatal info after a successful merge — e.g. the branch delete
    // failed but the merge itself landed.
    private(set) var lastMergeNotice: String?

    private var pendingFormWrite: Task<Void, Error>?
    private var pendingBodySave: Task<Void, Error>?
    private var pendingPromptSave: Task<Void, Error>?
    private var observeTask: Task<Void, Never>?

    // Called from the view's .onDisappear. Cancels the in-flight save chain
    // and any pending kanban observation so subsequent state mutations that
    // would land on a popped view stop firing. Cancellation propagates into
    // any awaiting Task.detached but the inner synchronous mutator call has
    // no cancellation point; an already-in-progress disk write still
    // completes (autosave-on-disappear semantics).
    func cancelPendingWork() {
        pendingFormWrite?.cancel()
        pendingFormWrite = nil
        pendingBodySave?.cancel()
        pendingBodySave = nil
        pendingPromptSave?.cancel()
        pendingPromptSave = nil
        observeTask?.cancel()
        observeTask = nil
    }

    private static let preloadByteCap = 64 * 1024

    private nonisolated let allocator: IssueAllocating?
    private nonisolated let writer: SpecWriting
    private nonisolated let mutator: FrontmatterMutating
    private nonisolated let mergeRunner: any GitMergeRunning
    private nonisolated let configLoader: @Sendable (URL) -> ProjectConfig?
    private nonisolated let clock: @Sendable () -> Date

    var isBodyDirty: Bool { bodyDraft != loadedBodyContent }

    var isCreating: Bool {
        if case .creating = kind { return true }
        return false
    }

    var canSaveInCreatingMode: Bool {
        guard isCreating else { return false }
        return !titleDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(
        specURL: URL,
        folderName: String,
        projectURL: URL? = nil,
        allocator: IssueAllocating? = nil,
        writer: SpecWriting = DefaultSpecWriter(),
        mutator: FrontmatterMutating = DefaultFrontmatterMutator(),
        mergeRunner: any GitMergeRunning = GitMergeRunner(),
        configLoader: @escaping @Sendable (URL) -> ProjectConfig? = {
            try? ConfigLoader.load(at: $0)
        },
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.kind = .loaded(folderName: folderName)
        self.specURL = specURL
        self.projectURL = projectURL
        self.allocator = allocator
        self.writer = writer
        self.mutator = mutator
        self.mergeRunner = mergeRunner
        self.configLoader = configLoader
        self.clock = clock
        // Pre-load synchronously so the view renders content immediately on
        // first mount — avoids the ProgressView flash caused by idle→loaded
        // transition after the async load() task fires. Local volumes only:
        // even the stat can stall on a network mount; remote specs take the
        // async load() path with the ProgressView placeholder. Capped at
        // 64 KB so a pathological spec can't stall view construction.
        if Self.volumeIsLocal(specURL),
            let attrs = try? FileManager.default.attributesOfItem(atPath: specURL.path),
            let size = attrs[.size] as? Int, size <= Self.preloadByteCap,
            let content = try? String(contentsOf: specURL, encoding: .utf8)
        {
            applyLoaded(content: content)
        }
    }

    private nonisolated static func volumeIsLocal(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.volumeIsLocalKey])
        return values?.volumeIsLocal ?? false
    }

    // Safety net for abnormal teardown paths where .onDisappear is skipped.
    // Primary cleanup remains the view's .onDisappear → cancelPendingWork.
    // isolated deinit (Swift 6.2) so we can touch the @MainActor state.
    isolated deinit {
        pendingFormWrite?.cancel()
        pendingBodySave?.cancel()
        pendingPromptSave?.cancel()
        observeTask?.cancel()
    }

    init(
        creatingInitialStatus: IssueStatus,
        projectURL: URL,
        allocator: IssueAllocating? = nil,
        writer: SpecWriting = DefaultSpecWriter(),
        mutator: FrontmatterMutating = DefaultFrontmatterMutator(),
        mergeRunner: any GitMergeRunning = GitMergeRunner(),
        configLoader: @escaping @Sendable (URL) -> ProjectConfig? = {
            try? ConfigLoader.load(at: $0)
        },
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.kind = .creating(initialStatus: creatingInitialStatus)
        self.specURL = nil
        self.projectURL = projectURL
        self.allocator = allocator ?? DefaultIssueAllocator(projectURL: projectURL)
        self.writer = writer
        self.mutator = mutator
        self.mergeRunner = mergeRunner
        self.configLoader = configLoader
        self.clock = clock
        self.statusDraft = creatingInitialStatus
        // In creating mode the form must render immediately — there is
        // nothing on disk to load. Mark loaded so the view skips the
        // ProgressView path.
        self.loadState = .loaded
    }

    func noteSeenIssue(_ issue: DiscoveredIssue?) {
        lastSeenIssue = issue
    }

    func load() async {
        guard let url = specURL else { return }
        let raw: String
        do {
            raw = try await Task.detached(priority: .userInitiated) {
                try String(contentsOf: url, encoding: .utf8)
            }.value
        } catch {
            loadState = .failed(error.localizedDescription)
            return
        }
        applyLoaded(content: raw)
    }

    private func applyLoaded(content raw: String) {
        // Normalize CRLF for parser predictability; SpecWriter still writes
        // back the raw normalized content, so first save flips line endings
        // exactly once on Windows-tooled inputs.
        let content = raw.replacingOccurrences(of: "\r\n", with: "\n")
        loadedSpecContent = content
        loadedBodyContent = Self.extractBody(from: content)
        bodyDraft = loadedBodyContent
        // applyLoaded only runs after load()/save() in loaded mode; folderName
        // is always non-nil here. Use the kind's folderName so the parsed
        // Issue carries the right identifier.
        let resolvedFolderName = folderName ?? ""
        switch SpecParser.parse(content: content, folderName: resolvedFolderName) {
        case .success(let parsed):
            issue = parsed
            // Mirror parsed values into drafts so the view can read the same
            // sources of truth in both modes (creating uses drafts directly,
            // loaded uses drafts that are kept in sync with disk).
            titleDraft = parsed.title
            typeDraft = parsed.type
            statusDraft = parsed.status
            labelsDraft = parsed.labels
            frontmatterError = nil
        case .failure(let error):
            issue = nil
            frontmatterError = error
        }
        loadState = .loaded
    }

    var mergeSubjectPrefill: String {
        guard let issue else { return "" }
        return issue.mergeSubject ?? issue.title
    }

    func mergeToMain(mode: GitMergeMode, commitSubject: String?, deleteBranch: Bool) async -> Bool {
        guard
            let projectURL,
            let specURL,
            let currentIssue = issue
        else { return false }

        let subject = commitSubject?.trimmingCharacters(in: .whitespacesAndNewlines)
        if mode == .squash, subject?.isEmpty != false {
            return false
        }

        lastMergeError = nil
        lastMergeCriticalError = nil
        lastMergeNotice = nil
        isMerging = true
        defer { isMerging = false }

        let runner = mergeRunner
        let issueBranch = currentIssue.branch
        let mutatorFn = mutator
        let now = clock()

        // Sync read of a small TOML file — matches the established ConfigLoader-
        // on-MainActor convention.
        let defaultBranch = configLoader(projectURL)?.gitDefaultBranch ?? "main"

        let outcome: GitMergeOutcome
        do {
            outcome = try await runner.mergeIssueBranch(
                repoURL: projectURL,
                defaultBranch: defaultBranch,
                issueBranch: issueBranch,
                mode: mode,
                commitSubject: subject,
                deleteBranch: deleteBranch
            )
        } catch let error as GitMergeError {
            lastMergeError = error
            return false
        } catch {
            // Wrap unknown runner errors into a generic .mergeFailed so the
            // banner still has something to render.
            lastMergeError = .mergeFailed(mode: mode, stderr: error.localizedDescription)
            return false
        }

        // Merge has landed on disk. From here on, any failure is critical —
        // we cannot roll back the merge, so the user has to fix spec.md
        // manually via the banner instruction.
        do {
            try await Task.detached(priority: .userInitiated) {
                try mutatorFn.mutate(
                    specURL: specURL,
                    mutation: FrontmatterMutation(status: .set(.done)),
                    now: now
                )
            }.value
        } catch {
            lastMergeCriticalError =
                "Merge landed on disk, but spec status flip failed: "
                + "\(error.localizedDescription). Edit spec.md manually to flip status to done."
            return false
        }

        if let deleteErr = outcome.branchDeleteError {
            lastMergeNotice = "Merge succeeded, but branch was not deleted: \(deleteErr)"
        }
        await reloadFromDiskAfterOwnWrite()
        return true
    }

    func clearMergeError() {
        lastMergeError = nil
    }

    func clearMergeCriticalError() {
        lastMergeCriticalError = nil
    }

    func clearMergeNotice() {
        lastMergeNotice = nil
    }

    func commitTitle(_ newTitle: String) async throws {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let current = issue, current.title != trimmed else { return }
        try await runFormWrite(FrontmatterMutation(title: .set(trimmed)))
    }

    func commitType(_ newType: IssueType) async throws {
        guard let current = issue, current.type != newType else { return }
        try await runFormWrite(FrontmatterMutation(type: .set(newType)))
    }

    func commitStatus(_ newStatus: IssueStatus) async throws {
        guard let current = issue, current.status != newStatus else { return }
        try await runFormWrite(FrontmatterMutation(status: .set(newStatus)))
    }

    func commitLabels(_ newLabels: [String]) async throws {
        guard let current = issue, current.labels != newLabels else { return }
        try await runFormWrite(FrontmatterMutation(labels: .set(newLabels)))
    }

    func createIssueFromDraft() async throws {
        guard case .creating = kind else { return }
        let trimmedTitle = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { throw SaveError.emptyTitle }
        guard let allocator else { throw SaveError.missingProjectURL }

        let slug = NextIssueAllocator.slugify(trimmedTitle)
        let title = trimmedTitle
        let type = typeDraft
        let labels = labelsDraft
        let status = statusDraft
        let prompt = bodyDraft
        let mutator = self.mutator
        let now = clock()

        let allocatedURL: URL
        do {
            allocatedURL = try await Task.detached(priority: .userInitiated) {
                try allocator.allocate(
                    slug: slug, title: title, type: type, labels: labels, prompt: prompt, now: now
                )
            }.value
        } catch {
            allocationError = "\(error)"
            throw error
        }

        // Status defaults to .draft in the template — skip the mutator round-
        // trip when the chosen status already matches.
        if status != .draft {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try mutator.mutate(
                        specURL: allocatedURL,
                        mutation: FrontmatterMutation(status: .set(status)),
                        now: now
                    )
                }.value
                allocationError = nil
            } catch {
                // Allocation already produced the folder on disk; surface the
                // error to the user, but still transition to .loaded so they
                // see the allocated issue and can retry the status save.
                allocationError = "\(error)"
            }
        } else {
            allocationError = nil
        }

        specURL = allocatedURL
        let newFolderName = allocatedURL.deletingLastPathComponent().lastPathComponent
        kind = .loaded(folderName: newFolderName)
        // Seed prompt state pre-load so the Prompt tab renders the just-written
        // content immediately; load() only refreshes spec frontmatter/body.
        promptDraft = prompt
        loadedPromptContent = prompt
        await load()
    }

    private func runFormWrite(_ mutation: FrontmatterMutation) async throws {
        // Single-tail-chain: every form write awaits the prior pending one
        // before reading disk + writing back. Without this, two pickers
        // committing in the same turn would each read the same baseline,
        // mutate independently, and the second write would clobber the
        // first.
        guard let url = specURL else { return }
        let prior = pendingFormWrite
        let mutator = self.mutator
        let now = clock()
        let task = Task<Void, Error> {
            _ = try? await prior?.value
            try await Task.detached(priority: .userInitiated) {
                try mutator.mutate(specURL: url, mutation: mutation, now: now)
            }.value
        }
        pendingFormWrite = task
        // Identity-checked reset: a newer write may have replaced the slot
        // while we awaited. Leaving the finished task in place permanently
        // disabled the external-change auto-reload (it gates on nil).
        defer {
            if pendingFormWrite == task { pendingFormWrite = nil }
        }
        try await task.value
        await reloadFromDiskAfterOwnWrite()
    }

    private func readNormalized(_ url: URL) async -> String? {
        let raw = await Task.detached(priority: .utility) {
            try? String(contentsOf: url, encoding: .utf8)
        }.value
        return raw?.replacingOccurrences(of: "\r\n", with: "\n")
    }

    private func reloadFromDiskAfterOwnWrite() async {
        guard let url = specURL else { return }
        guard let normalized = await readNormalized(url) else { return }
        lastWrittenContent = normalized
        // Body could change if the user typed inside a form-write window;
        // preserve the in-flight bodyDraft so we don't drop unsaved keystrokes.
        let preservedBodyDraft = bodyDraft
        let preservedDirty = isBodyDirty
        applyLoaded(content: normalized)
        if preservedDirty {
            bodyDraft = preservedBodyDraft
        }
    }

    func saveBody() async throws {
        guard isBodyDirty else { return }
        // Don't silently overwrite an unresolved external change: the user
        // has to pick Use-disk or Keep-mine via the banner first.
        if case .externalChange = conflict {
            throw SaveError.unresolvedConflict
        }
        guard let url = specURL else { return }
        let prior = pendingBodySave
        let bodyToSave = bodyDraft
        let mutator = self.mutator
        let now = clock()

        let task = Task<Void, Error> {
            _ = try? await prior?.value
            // Single atomic write: frontmatter `updated:` stamp + body
            // splice in one mutator pass. Previously this was two writes
            // (body via SpecWriter, then a second mutator call for the
            // stamp), which could leave the file with the new body but a
            // stale `updated:` on partial failure.
            try await Task.detached(priority: .userInitiated) {
                try mutator.mutate(
                    specURL: url,
                    mutation: FrontmatterMutation(body: .set(bodyToSave)),
                    now: now
                )
            }.value
        }
        pendingBodySave = task
        try await task.value

        if let normalized = await readNormalized(url) {
            lastWrittenContent = normalized
            applyLoaded(content: normalized)
        }
    }

    var isPromptDirty: Bool { promptDraft != loadedPromptContent }

    nonisolated static func defaultTab(for status: IssueStatus) -> BodyTab {
        switch status {
        case .draft: return .prompt
        case .approved, .inProgress, .done, .blocked: return .spec
        case .waitingForReview: return .pullRequest
        }
    }

    func loadPrompt() async {
        guard let folder = folderName, let projectURL else { return }
        let url = IssueLayout.promptURL(in: projectURL, folderName: folder)
        let content = await readNormalized(url) ?? ""
        loadedPromptContent = content
        promptDraft = content
    }

    func savePrompt() async throws {
        guard isPromptDirty else { return }
        guard let folder = folderName, let projectURL else { return }
        let url = IssueLayout.promptURL(in: projectURL, folderName: folder)
        let prior = pendingPromptSave
        let contentToSave = promptDraft
        let writer = self.writer
        let task = Task<Void, Error> {
            _ = try? await prior?.value
            try await Task.detached(priority: .userInitiated) {
                try writer.write(contentToSave, to: url)
            }.value
        }
        pendingPromptSave = task
        try await task.value
        // Only bump the baseline — never overwrite promptDraft. The user may
        // have kept typing during the disk write; loadPrompt() would clobber
        // those trailing keystrokes (mirrors the body-save pattern).
        loadedPromptContent = contentToSave
    }

    func loadPR() async {
        guard let folder = folderName, let projectURL else {
            prContent = nil
            prBlocks = []
            return
        }
        let url = IssueLayout.prURL(in: projectURL, folderName: folder)
        // Read AND parse off-main so the markdown parse never runs on a view
        // body evaluation. Empty content yields no blocks (PRTabView shows the
        // empty state) while still recording prContent for state checks.
        let result: (content: String?, blocks: [PRMarkdownParser.Block]) =
            await Task.detached(priority: .utility) {
                guard let raw = try? String(contentsOf: url, encoding: .utf8) else {
                    return (nil, [])
                }
                let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")
                return (normalized, normalized.isEmpty ? [] : PRMarkdownParser.parse(normalized))
            }.value
        prContent = result.content
        prBlocks = result.blocks
    }

    func observeKanban(currentIssue: DiscoveredIssue?) {
        // Cancel any in-flight observation so a fast kanban-snapshot churn
        // doesn't race two concurrent disk reads writing to the same fields.
        // Owning the task here (instead of @State in the view) means it dies
        // with the model — no ghost writes after view pop.
        observeTask?.cancel()
        observeTask = Task { [weak self] in
            await self?.observeExternalChange(currentIssue: currentIssue)
        }
    }

    func observeExternalChange(currentIssue: DiscoveredIssue?) async {
        if let currentIssue {
            if currentIssue == lastSeenIssue { return }
            noteSeenIssue(currentIssue)
        } else {
            noteSeenIssue(nil)
        }
        guard let url = specURL else { return }
        // Probe disk in both the present-snapshot and missing-snapshot paths.
        // The kanban can briefly show our folder as missing during an
        // optimistic archive/trash before the on-disk move actually runs —
        // setting `.fileDeleted` on the kanban signal alone would flash a
        // banner that is correct only after the move lands. Reading disk
        // here turns "snapshot says gone" into "disk confirms gone".
        if let normalized = await readNormalized(url) {
            if normalized == loadedSpecContent || normalized == lastWrittenContent { return }
            await handleExternalChange(diskContent: normalized)
        } else {
            await handleExternalChange(diskContent: nil)
        }
    }

    func handleExternalChange(diskContent: String?) async {
        guard let diskContent else {
            conflict = .fileDeleted
            return
        }
        let normalized = diskContent.replacingOccurrences(of: "\r\n", with: "\n")
        if !isBodyDirty && pendingFormWrite == nil {
            applyLoaded(content: normalized)
            conflict = nil
        } else if normalized != loadedSpecContent {
            conflict = .externalChange(diskContent: normalized)
        }
    }

    func resolveConflictReload() {
        guard case .externalChange(let diskContent) = conflict else { return }
        applyLoaded(content: diskContent)
        conflict = nil
    }

    func resolveConflictKeep() {
        conflict = nil
    }

    var navigationTitle: String {
        if isCreating { return "New Issue" }
        return issue?.title ?? folderName ?? ""
    }

    func dirtyFolderName(bodyDirtyOverride: Bool? = nil, promptDirtyOverride: Bool? = nil) -> String? {
        // Creating mode never has a folder yet; never report dirty.
        guard !isCreating else { return nil }
        let bodyDirty = bodyDirtyOverride ?? isBodyDirty
        let promptDirty = promptDirtyOverride ?? isPromptDirty
        guard bodyDirty || promptDirty else { return nil }
        return folderName
    }

    func copyIDToPasteboard() {
        guard let folder = folderName else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(folder, forType: .string)
    }

    func revealInFinder() {
        guard let folder = folderName, let projectURL else { return }
        let url = IssueLayout.issueFolder(in: projectURL, folderName: folder)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    nonisolated static func extractBody(from content: String) -> String {
        // Split on the second `---` line. Anything before (frontmatter)
        // is dropped; everything after is the body, including any embedded
        // `---` lines further down. CRLF input is normalized first so the
        // function is safe to call on raw file content from any platform.
        let normalized = content.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        var seen = 0
        var bodyStart = 0
        for (index, line) in lines.enumerated() {
            if line.trimmingCharacters(in: .whitespaces) == "---" {
                seen += 1
                if seen == 2 {
                    bodyStart = index + 1
                    break
                }
            }
        }
        if seen < 2 { return "" }
        // Drop a single leading newline so users don't see a stray blank
        // line at the top of the body editor.
        if bodyStart < lines.count, lines[bodyStart].isEmpty {
            bodyStart += 1
        }
        guard bodyStart <= lines.count else { return "" }
        return lines[bodyStart..<lines.count].joined(separator: "\n")
    }
}

nonisolated protocol SpecWriting: Sendable {
    func write(_ content: String, to url: URL) throws
}

nonisolated struct DefaultSpecWriter: SpecWriting {
    func write(_ content: String, to url: URL) throws {
        try SpecWriter.write(content, to: url)
    }
}

nonisolated protocol FrontmatterMutating: Sendable {
    func mutate(specURL: URL, mutation: FrontmatterMutation, now: Date) throws
}

nonisolated struct DefaultFrontmatterMutator: FrontmatterMutating {
    func mutate(specURL: URL, mutation: FrontmatterMutation, now: Date) throws {
        try FrontmatterMutator.mutate(specURL: specURL, mutation: mutation, now: now)
    }
}

nonisolated protocol IssueAllocating: Sendable {
    func allocate(
        slug: String,
        title: String,
        type: IssueType,
        labels: [String],
        prompt: String,
        now: Date
    ) throws -> URL
}

nonisolated struct DefaultIssueAllocator: IssueAllocating {
    let projectURL: URL

    func allocate(
        slug: String,
        title: String,
        type: IssueType,
        labels: [String],
        prompt: String,
        now: Date
    ) throws -> URL {
        try NextIssueAllocator(projectURL: projectURL).allocate(
            slug: slug,
            title: title,
            type: type,
            labels: labels,
            prompt: prompt,
            now: now
        )
    }
}
