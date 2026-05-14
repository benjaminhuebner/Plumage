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

    let specURL: URL
    let folderName: String

    private(set) var issue: Issue?
    private(set) var loadState: LoadState = .idle
    private(set) var loadedSpecContent: String = ""
    private(set) var loadedBodyContent: String = ""
    var bodyDraft: String = ""
    private(set) var conflict: ConflictState?
    private(set) var frontmatterError: FrontmatterError?
    private(set) var lastWrittenContent: String?
    private(set) var lastSeenIssue: DiscoveredIssue?

    private var pendingFormWrite: Task<Void, Error>?
    private var pendingBodySave: Task<Void, Error>?

    private nonisolated let writer: SpecWriting
    private nonisolated let mutator: FrontmatterMutating
    private nonisolated let clock: @Sendable () -> Date

    var isBodyDirty: Bool { bodyDraft != loadedBodyContent }

    init(
        specURL: URL,
        folderName: String,
        writer: SpecWriting = DefaultSpecWriter(),
        mutator: FrontmatterMutating = DefaultFrontmatterMutating(),
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.specURL = specURL
        self.folderName = folderName
        self.writer = writer
        self.mutator = mutator
        self.clock = clock
    }

    func noteSeenIssue(_ issue: DiscoveredIssue?) {
        lastSeenIssue = issue
    }

    func load() async {
        let url = specURL
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
        switch SpecParser.parse(content: content, folderName: folderName) {
        case .success(let parsed):
            issue = parsed
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

    private func runFormWrite(_ mutation: FrontmatterMutation) async throws {
        // Single-tail-chain: every form write awaits the prior pending one
        // before reading disk + writing back. Without this, two pickers
        // committing in the same turn would each read the same baseline,
        // mutate independently, and the second write would clobber the
        // first.
        let prior = pendingFormWrite
        let url = specURL
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
        let url = specURL
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
        let prior = pendingBodySave
        let url = specURL
        let writer = self.writer
        let bodyToSave = bodyDraft
        let mutator = self.mutator
        let now = clock()

        let task = Task<Void, Error> {
            _ = try? await prior?.value
            // Read disk fresh so we keep external frontmatter changes;
            // splice in the new body, then rewrite via mutator so the
            // `updated:` field is stamped consistently with form writes.
            try await Task.detached(priority: .userInitiated) {
                let current = try String(contentsOf: url, encoding: .utf8)
                let normalized = current.replacingOccurrences(of: "\r\n", with: "\n")
                let merged = Self.replaceBody(in: normalized, with: bodyToSave)
                try writer.write(merged, to: url)
                // Stamp updated separately so the frontmatter mutator and the
                // body splice agree on the timestamp.
                try mutator.mutate(specURL: url, mutation: FrontmatterMutation(), now: now)
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

    func observeExternalChange(currentIssue: DiscoveredIssue?) async {
        guard let currentIssue else {
            noteSeenIssue(nil)
            await handleExternalChange(diskContent: nil)
            return
        }
        if currentIssue == lastSeenIssue { return }
        noteSeenIssue(currentIssue)
        let url = specURL
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
        // `---` lines further down.
        let lines = content.components(separatedBy: "\n")
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
        let lines = content.components(separatedBy: "\n")
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
