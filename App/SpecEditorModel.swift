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
        try await writeOffActor(snapshot)
        lastWrittenContent = snapshot
        loadedContent = snapshot
        evaluateFrontmatterError()
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
        try await writeOffActor(snapshot)
        lastWrittenContent = snapshot
        loadedContent = snapshot
        evaluateFrontmatterError()
        conflict = nil
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
