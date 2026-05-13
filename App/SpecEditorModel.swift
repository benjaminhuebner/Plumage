import CodeEditorView
import Foundation
import LanguageSupport

@MainActor
@Observable
final class SpecEditorModel {
    enum ConflictState: Equatable {
        case externalChange(diskContent: String)
        case fileDeleted
    }

    let specURL: URL
    let folderName: String

    private(set) var buffer: String = ""
    private(set) var loadedContent: String = ""
    private(set) var frontmatterError: FrontmatterError?
    private(set) var conflict: ConflictState?
    var initialCursor: CodeEditor.Position?

    private let writer: SpecWriting

    var isDirty: Bool { buffer != loadedContent }

    init(specURL: URL, folderName: String, writer: SpecWriting = DefaultSpecWriter()) {
        self.specURL = specURL
        self.folderName = folderName
        self.writer = writer
    }

    func updateBuffer(_ newValue: String) {
        buffer = newValue
    }

    func load() throws {
        let content = try String(contentsOf: specURL, encoding: .utf8)
        loadedContent = content
        buffer = content
        evaluateFrontmatterError()
        if let error = frontmatterError {
            let loc = FrontmatterMessageMap.location(for: error)
            let offset = TextOffset.offset(ofLine: loc.line, column: loc.column, in: buffer)
            initialCursor = CodeEditor.Position(
                selections: [NSRange(location: offset, length: 0)],
                verticalScrollPosition: 0
            )
        } else {
            initialCursor = nil
        }
    }

    func saveIfDirty() async throws {
        guard isDirty else { return }
        try writer.write(buffer, to: specURL)
        loadedContent = buffer
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
        try writer.write(buffer, to: specURL)
        loadedContent = buffer
        evaluateFrontmatterError()
        conflict = nil
    }

    private func evaluateFrontmatterError() {
        switch SpecParser.parse(content: buffer, folderName: folderName) {
        case .success:
            frontmatterError = nil
        case .failure(let error):
            frontmatterError = error
        }
    }
}

protocol SpecWriting: Sendable {
    func write(_ content: String, to url: URL) throws
}

struct DefaultSpecWriter: SpecWriting {
    func write(_ content: String, to url: URL) throws {
        try SpecWriter.write(content, to: url)
    }
}
