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
    private(set) var conflict: ConflictState?
    private(set) var frontmatterError: FrontmatterError?
    private(set) var lastWrittenContent: String?
    private(set) var lastSeenIssue: DiscoveredIssue?
    private(set) var allocationError: String?

    private var pendingFormWrite: Task<Void, Error>?
    private var pendingBodySave: Task<Void, Error>?
    private var observeTask: Task<Void, Never>?

    private nonisolated let allocator: IssueAllocating?
    private nonisolated let writer: SpecWriting
    private nonisolated let mutator: FrontmatterMutating
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
        mutator: FrontmatterMutating = DefaultFrontmatterMutating(),
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.kind = .loaded(folderName: folderName)
        self.specURL = specURL
        self.projectURL = projectURL
        self.allocator = allocator
        self.writer = writer
        self.mutator = mutator
        self.clock = clock
    }

    init(
        creatingInitialStatus: IssueStatus,
        projectURL: URL,
        allocator: IssueAllocating? = nil,
        writer: SpecWriting = DefaultSpecWriter(),
        mutator: FrontmatterMutating = DefaultFrontmatterMutating(),
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.kind = .creating(initialStatus: creatingInitialStatus)
        self.specURL = nil
        self.projectURL = projectURL
        self.allocator = allocator ?? DefaultIssueAllocating(projectURL: projectURL)
        self.writer = writer
        self.mutator = mutator
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
        let body = bodyDraft
        let mutator = self.mutator
        let now = clock()

        let allocatedURL: URL
        do {
            allocatedURL = try await Task.detached(priority: .userInitiated) {
                try allocator.allocate(
                    slug: slug, title: title, type: type, labels: labels, now: now
                )
            }.value
        } catch {
            allocationError = "\(error)"
            throw error
        }

        let mutation = FrontmatterMutation(
            status: .set(status),
            body: body.isEmpty ? .keep : .set(body)
        )
        do {
            try await Task.detached(priority: .userInitiated) {
                try mutator.mutate(specURL: allocatedURL, mutation: mutation, now: now)
            }.value
        } catch {
            // Allocation already produced the folder on disk; surface the
            // error to the user, but still transition to .loaded so they
            // see the allocated issue and can retry the body/status save.
            allocationError = "\(error)"
        }

        allocationError = nil
        specURL = allocatedURL
        let newFolderName = allocatedURL.deletingLastPathComponent().lastPathComponent
        kind = .loaded(folderName: newFolderName)
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
        try await task.value
        await reloadFromDiskAfterOwnWrite()
    }

    private func reloadFromDiskAfterOwnWrite() async {
        guard let url = specURL else { return }
        let fresh = await Task.detached(priority: .utility) {
            try? String(contentsOf: url, encoding: .utf8)
        }.value
        guard let fresh else { return }
        let normalized = fresh.replacingOccurrences(of: "\r\n", with: "\n")
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

        let fresh = await Task.detached(priority: .utility) {
            try? String(contentsOf: url, encoding: .utf8)
        }.value
        if let fresh {
            let normalized = fresh.replacingOccurrences(of: "\r\n", with: "\n")
            lastWrittenContent = normalized
            applyLoaded(content: normalized)
        }
    }

    func saveRaw(_ rawContent: String) async throws {
        if case .externalChange = conflict {
            throw SaveError.unresolvedConflict
        }
        guard let url = specURL else { return }
        let prior = pendingBodySave
        let writer = self.writer
        let task = Task<Void, Error> {
            _ = try? await prior?.value
            let normalized = rawContent.replacingOccurrences(of: "\r\n", with: "\n")
            try await Task.detached(priority: .userInitiated) {
                try writer.write(normalized, to: url)
            }.value
        }
        pendingBodySave = task
        try await task.value

        let fresh = await Task.detached(priority: .utility) {
            try? String(contentsOf: url, encoding: .utf8)
        }.value
        if let fresh {
            let normalized = fresh.replacingOccurrences(of: "\r\n", with: "\n")
            lastWrittenContent = normalized
            applyLoaded(content: normalized)
        }
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
        guard let currentIssue else {
            noteSeenIssue(nil)
            await handleExternalChange(diskContent: nil)
            return
        }
        if currentIssue == lastSeenIssue { return }
        noteSeenIssue(currentIssue)
        guard let url = specURL else { return }
        let fresh = await Task.detached(priority: .utility) {
            try? String(contentsOf: url, encoding: .utf8)
        }.value
        if let fresh {
            let normalized = fresh.replacingOccurrences(of: "\r\n", with: "\n")
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

    nonisolated static func replaceBody(in content: String, with newBody: String) -> String {
        // CRLF input is normalized first so the function is safe to call on
        // raw file content from any platform.
        let normalized = content.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        var seen = 0
        var splitIndex: Int?
        for (index, line) in lines.enumerated() {
            if line.trimmingCharacters(in: .whitespaces) == "---" {
                seen += 1
                if seen == 2 {
                    splitIndex = index
                    break
                }
            }
        }
        guard let splitIndex else {
            // No frontmatter: return the new body verbatim.
            return newBody
        }
        let frontmatter = lines[0...splitIndex].joined(separator: "\n")
        // Preserve a single blank-line separator between frontmatter and body
        // (matches how spec.md is conventionally formatted). The new body
        // already carries its own internal newlines.
        return frontmatter + "\n\n" + newBody
    }
}

nonisolated protocol FrontmatterMutating: Sendable {
    func mutate(specURL: URL, mutation: FrontmatterMutation, now: Date) throws
}

nonisolated struct DefaultFrontmatterMutating: FrontmatterMutating {
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
        now: Date
    ) throws -> URL
}

nonisolated struct DefaultIssueAllocating: IssueAllocating {
    let projectURL: URL

    func allocate(
        slug: String,
        title: String,
        type: IssueType,
        labels: [String],
        now: Date
    ) throws -> URL {
        try NextIssueAllocator(projectURL: projectURL).allocate(
            slug: slug,
            title: title,
            type: type,
            labels: labels,
            now: now
        )
    }
}
