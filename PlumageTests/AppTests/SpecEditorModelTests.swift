import CodeEditorView
import Foundation
import Testing

@testable import Plumage

@Suite("SpecEditorModel")
@MainActor
struct SpecEditorModelTests {
    @Test("load reads file content into buffer and loadedContent")
    func loadHappy() throws {
        let url = try makeSpec(content: validSpec)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let model = SpecEditorModel(specURL: url, folderName: "00042-feature")
        try model.load()

        #expect(model.buffer == validSpec)
        #expect(model.loadedContent == validSpec)
        #expect(model.frontmatterError == nil)
        #expect(!model.isDirty)
    }

    @Test("isDirty flips when buffer is mutated")
    func isDirtyFlips() throws {
        let url = try makeSpec(content: validSpec)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let model = SpecEditorModel(specURL: url, folderName: "00042-feature")
        try model.load()
        #expect(!model.isDirty)

        model.updateBuffer(validSpec + "\nedit")
        #expect(model.isDirty)
    }

    @Test("saveIfDirty is no-op when clean")
    func saveIfDirtyNoOp() async throws {
        let url = try makeSpec(content: validSpec)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let writer = RecordingWriter()
        let model = SpecEditorModel(specURL: url, folderName: "00042-feature", writer: writer)
        try model.load()

        try await model.saveIfDirty()

        #expect(writer.writeCount == 0)
    }

    @Test("saveIfDirty writes and updates loadedContent")
    func saveIfDirtyWrites() async throws {
        let url = try makeSpec(content: validSpec)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let writer = RecordingWriter()
        let model = SpecEditorModel(specURL: url, folderName: "00042-feature", writer: writer)
        try model.load()
        model.updateBuffer(validSpec + "\n\nedit")

        try await model.saveIfDirty()

        #expect(writer.writeCount == 1)
        #expect(model.loadedContent == validSpec + "\n\nedit")
        #expect(!model.isDirty)
    }

    @Test("saveIfDirty rethrows writer error and leaves loadedContent unchanged")
    func saveIfDirtyThrows() async throws {
        let url = try makeSpec(content: validSpec)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let writer = ThrowingWriter()
        let model = SpecEditorModel(specURL: url, folderName: "00042-feature", writer: writer)
        try model.load()
        model.updateBuffer(validSpec + "\nedit")

        do {
            try await model.saveIfDirty()
            Issue.record("expected throw")
        } catch {
            // expected
        }
        #expect(model.loadedContent == validSpec)
        #expect(model.isDirty)
    }

    @Test("handleExternalChange on clean buffer silently reloads")
    func externalChangeWhenClean() throws {
        let url = try makeSpec(content: validSpec)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let model = SpecEditorModel(specURL: url, folderName: "00042-feature")
        try model.load()

        let updated = validSpec.replacingOccurrences(of: "Feature Issue", with: "Renamed")
        model.handleExternalChange(diskContent: updated)

        #expect(model.buffer == updated)
        #expect(model.loadedContent == updated)
        #expect(model.conflict == nil)
    }

    @Test("handleExternalChange on dirty buffer raises externalChange conflict")
    func externalChangeWhenDirty() throws {
        let url = try makeSpec(content: validSpec)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let model = SpecEditorModel(specURL: url, folderName: "00042-feature")
        try model.load()
        model.updateBuffer(validSpec + "\nuser edit")
        let diskUpdate = validSpec + "\nexternal edit"

        model.handleExternalChange(diskContent: diskUpdate)

        guard case .externalChange(let disk) = model.conflict else {
            Issue.record("expected externalChange, got \(String(describing: model.conflict))")
            return
        }
        #expect(disk == diskUpdate)
        // Buffer is preserved
        #expect(model.buffer == validSpec + "\nuser edit")
    }

    @Test("handleExternalChange with nil disk content yields fileDeleted")
    func externalChangeFileDeleted() throws {
        let url = try makeSpec(content: validSpec)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let model = SpecEditorModel(specURL: url, folderName: "00042-feature")
        try model.load()
        model.updateBuffer(validSpec + "\nuser edit")

        model.handleExternalChange(diskContent: nil)

        #expect(model.conflict == .fileDeleted)
    }

    @Test("resolveConflictReload replaces buffer with disk content and clears conflict")
    func resolveReload() throws {
        let url = try makeSpec(content: validSpec)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let model = SpecEditorModel(specURL: url, folderName: "00042-feature")
        try model.load()
        model.updateBuffer("user edit")
        model.handleExternalChange(diskContent: "disk edit")

        model.resolveConflictReload()

        #expect(model.buffer == "disk edit")
        #expect(model.loadedContent == "disk edit")
        #expect(model.conflict == nil)
    }

    @Test("resolveConflictKeep clears conflict but keeps buffer")
    func resolveKeep() throws {
        let url = try makeSpec(content: validSpec)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let model = SpecEditorModel(specURL: url, folderName: "00042-feature")
        try model.load()
        model.updateBuffer("user edit")
        model.handleExternalChange(diskContent: "disk edit")

        model.resolveConflictKeep()

        #expect(model.buffer == "user edit")
        #expect(model.conflict == nil)
    }

    @Test("resolveConflictSaveAndRecreate writes buffer and clears conflict")
    func resolveSaveAndRecreate() async throws {
        let url = try makeSpec(content: validSpec)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let writer = RecordingWriter()
        let model = SpecEditorModel(specURL: url, folderName: "00042-feature", writer: writer)
        try model.load()
        model.updateBuffer("recreated")
        model.handleExternalChange(diskContent: nil)

        try await model.resolveConflictSaveAndRecreate()

        #expect(writer.writeCount == 1)
        #expect(model.conflict == nil)
        #expect(model.loadedContent == "recreated")
    }

    @Test("initialCursor is set when loaded content has frontmatter error")
    func initialCursorOnError() throws {
        let url = try makeSpec(content: brokenYAMLSpec)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let model = SpecEditorModel(specURL: url, folderName: "00042-feature")

        try model.load()

        #expect(model.frontmatterError != nil)
        #expect(model.initialCursor != nil)
        let selection = try #require(model.initialCursor?.selections.first)
        #expect(selection.length == 0)
        #expect(selection.location >= 0)
    }

    @Test("initialCursor is nil for valid content")
    func initialCursorOnValid() throws {
        let url = try makeSpec(content: validSpec)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let model = SpecEditorModel(specURL: url, folderName: "00042-feature")

        try model.load()

        #expect(model.frontmatterError == nil)
        #expect(model.initialCursor == nil)
    }

    private func makeSpec(content: String) throws -> URL {
        let dir = URL(filePath: NSTemporaryDirectory())
            .appendingPathComponent("SpecEditorModelTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("spec.md")
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private let validSpec = """
        ---
        id: 42
        title: Feature Issue
        type: feature
        status: approved
        created: 2026-05-12T09:00:00Z
        updated: 2026-05-12T10:30:00Z
        branch: issue/00042-feature
        labels: [feature, v0.1]
        model: null
        ---

        # Body
        """

    private let brokenYAMLSpec = """
        ---
        id: 1
        title: "Broken with unclosed quote
        type: feature
        status: approved
        created: 2026-05-12T09:00:00Z
        updated: 2026-05-12T10:00:00Z
        branch: issue/00001-broken
        labels: [feature]
        model: null
        ---
        """
}

final class RecordingWriter: SpecWriting, @unchecked Sendable {
    private let lock = NSLock()
    private var count: Int = 0

    var writeCount: Int { lock.withLock { count } }

    func write(_ content: String, to url: URL) throws {
        lock.withLock { count += 1 }
    }
}

struct ThrowingWriter: SpecWriting {
    struct WriteFailure: Error {}
    func write(_ content: String, to url: URL) throws {
        throw WriteFailure()
    }
}
