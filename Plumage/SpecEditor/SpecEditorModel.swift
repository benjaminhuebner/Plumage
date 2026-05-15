import Foundation

@MainActor
@Observable
final class SpecEditorModel {
    enum ConflictState: Equatable {
        case externalChange(diskContent: String)
        case fileDeleted
    }

    let specURL: URL
    let folderName: String

    var buffer: String = ""
    private(set) var loadedContent: String = ""
    private(set) var frontmatterError: FrontmatterError?
    private(set) var conflict: ConflictState?
    private(set) var initialCursorOffset: Int?
    private(set) var lastSeenIssue: DiscoveredIssue?
    private(set) var lastWrittenContent: String?

    private nonisolated let writer: SpecWriting

    // Serializes saveIfDirty / resolveConflictSaveAndRecreate triggers so
    // overlapping focus-loss + ⌘S + scenePhase events can't commit out of
    // order. Owned by the model (not @State in the view) so the chain dies
    // with the model — no ghost writes after view pop.
    private var pendingSave: Task<Void, Error>?
    // Latest in-flight kanban observation. Cancelled on every new snapshot
    // so a fast snapshot churn doesn't race two concurrent disk reads
    // writing to the same fields.
    private var observeTask: Task<Void, Never>?
    // Bumped on every save start and on resolveConflictReload. Save tasks
    // capture it at start and check it after writeOffActor returns — a
    // reload that lands between the two awaits invalidates the now-stale
    // snapshot, preventing the discarded local edit from resurfacing.
    private var saveGeneration: UInt64 = 0

    var isDirty: Bool { buffer != loadedContent }

    init(specURL: URL, folderName: String, writer: SpecWriting = DefaultSpecWriter()) {
        self.specURL = specURL
        self.folderName = folderName
        self.writer = writer
    }

    func noteSeenIssue(_ issue: DiscoveredIssue?) {
        lastSeenIssue = issue
    }

    func load() async throws {
        let url = specURL
        let raw = try await Task.detached(priority: .userInitiated) {
            try String(contentsOf: url, encoding: .utf8)
        }.value
        // Normalize to LF so that round-tripping a CRLF spec.md from a Windows-tooled
        // collaborator doesn't produce a noisy line-ending-only diff on first save.
        let content = raw.replacingOccurrences(of: "\r\n", with: "\n")
        loadedContent = content
        buffer = content
        evaluateFrontmatterError()
        if let error = frontmatterError {
            let loc = FrontmatterMessageMap.location(for: error)
            initialCursorOffset = TextOffset.offset(ofLine: loc.line, column: loc.column, in: buffer)
        } else {
            initialCursorOffset = nil
        }
    }

    func saveIfDirty() async throws {
        guard isDirty else { return }
        let snapshot = buffer
        let prior = pendingSave
        saveGeneration &+= 1
        let myGeneration = saveGeneration
        let task = Task<Void, Error> { [weak self] in
            _ = try? await prior?.value
            guard let self else { return }
            try await self.writeOffActor(snapshot)
            guard self.saveGeneration == myGeneration else { return }
            self.lastWrittenContent = snapshot
            self.loadedContent = snapshot
            self.evaluateFrontmatterError()
        }
        pendingSave = task
        try await task.value
    }

    func observeKanban(currentIssue: DiscoveredIssue?) {
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
        let url = specURL
        // Probe disk in both the present-snapshot and missing-snapshot paths.
        // The kanban can briefly show our folder as missing during an
        // optimistic archive/trash before the on-disk move actually runs —
        // setting `.fileDeleted` on the kanban signal alone would flash a
        // banner that is correct only after the move lands.
        let fresh = await Task.detached(priority: .utility) {
            try? String(contentsOf: url, encoding: .utf8)
        }.value
        if let fresh, fresh == loadedContent || fresh == lastWrittenContent { return }
        handleExternalChange(diskContent: fresh)
    }

    func handleExternalChange(diskContent: String?) {
        guard let diskContent else {
            conflict = .fileDeleted
            return
        }
        if !isDirty {
            loadedContent = diskContent
            buffer = diskContent
            evaluateFrontmatterError()
            conflict = nil
        } else if diskContent != loadedContent {
            conflict = .externalChange(diskContent: diskContent)
        }
    }

    func resolveConflictReload() {
        guard case .externalChange(let diskContent) = conflict else { return }
        saveGeneration &+= 1
        loadedContent = diskContent
        buffer = diskContent
        evaluateFrontmatterError()
        conflict = nil
    }

    func resolveConflictKeep() {
        conflict = nil
    }

    func resolveConflictSaveAndRecreate() async throws {
        let snapshot = buffer
        let prior = pendingSave
        saveGeneration &+= 1
        let myGeneration = saveGeneration
        let task = Task<Void, Error> { [weak self] in
            _ = try? await prior?.value
            guard let self else { return }
            try await self.writeOffActor(snapshot)
            guard self.saveGeneration == myGeneration else { return }
            self.lastWrittenContent = snapshot
            self.loadedContent = snapshot
            self.evaluateFrontmatterError()
            self.conflict = nil
        }
        pendingSave = task
        try await task.value
    }

    private func writeOffActor(_ content: String) async throws {
        let url = specURL
        let writer = self.writer
        try await Task.detached(priority: .utility) {
            try writer.write(content, to: url)
        }.value
    }

    private func evaluateFrontmatterError() {
        frontmatterError = SpecParser.validate(content: buffer)
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
