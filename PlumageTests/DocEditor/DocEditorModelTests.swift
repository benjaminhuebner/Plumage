import Foundation
import Testing

@testable import Plumage

@Suite("DocEditorModel")
@MainActor
struct DocEditorModelTests {
    @Test("load reads file content from disk and clears dirty state")
    func loadHappyPath() async throws {
        let fixture = try DocFixture()
        let url = try fixture.writeFile(named: "PROJECT.md", content: "hello world")
        let model = DocEditorModel(fileURL: url)
        try await model.load()
        #expect(model.buffer == "hello world")
        #expect(model.loadedContent == "hello world")
        #expect(model.isDirty == false)
        #expect(model.fileExistsOnDisk == true)
    }

    @Test("load on a missing file yields an empty buffer without throwing")
    func loadMissingFile() async throws {
        let fixture = try DocFixture()
        let url = fixture.root.appendingPathComponent("never-written.md")
        let model = DocEditorModel(fileURL: url)
        try await model.load()
        #expect(model.buffer.isEmpty)
        #expect(model.loadedContent.isEmpty)
        #expect(model.fileExistsOnDisk == false)
    }

    @Test("load normalizes CRLF to LF")
    func loadNormalizesCRLF() async throws {
        let fixture = try DocFixture()
        let url = try fixture.writeFile(named: "win.md", content: "line one\r\nline two\r\n")
        let model = DocEditorModel(fileURL: url)
        try await model.load()
        #expect(model.buffer == "line one\nline two\n")
        #expect(model.loadedContent == "line one\nline two\n")
        #expect(model.isDirty == false)
    }

    @Test("saveIfDirty writes buffer to disk and updates loadedContent")
    func saveWritesAndUpdates() async throws {
        let fixture = try DocFixture()
        let url = try fixture.writeFile(named: "edit.md", content: "original")
        let model = DocEditorModel(fileURL: url)
        try await model.load()
        model.buffer = "edited"
        #expect(model.isDirty)
        try await model.saveIfDirty()
        #expect(model.loadedContent == "edited")
        #expect(model.isDirty == false)
        let onDisk = try String(contentsOf: url, encoding: .utf8)
        #expect(onDisk == "edited")
    }

    @Test("saveIfDirty creates the file when it didn't exist before")
    func saveCreatesMissingFile() async throws {
        let fixture = try DocFixture()
        let url = fixture.root.appendingPathComponent("fresh.json")
        let model = DocEditorModel(fileURL: url)
        try await model.load()
        model.buffer = "{}"
        try await model.saveIfDirty()
        #expect(model.fileExistsOnDisk == true)
        let onDisk = try String(contentsOf: url, encoding: .utf8)
        #expect(onDisk == "{}")
    }

    @Test("saveIfDirty does nothing when buffer matches loadedContent")
    func saveSkipsWhenClean() async throws {
        let fixture = try DocFixture()
        let url = try fixture.writeFile(named: "clean.md", content: "same")
        let model = DocEditorModel(fileURL: url)
        try await model.load()
        let writtenBefore = model.lastWrittenContent
        try await model.saveIfDirty()
        #expect(model.lastWrittenContent == writtenBefore)
    }

    @Test("clean buffer silently reloads on external change")
    func cleanReload() async throws {
        let fixture = try DocFixture()
        let url = try fixture.writeFile(named: "follow.md", content: "v1")
        let model = DocEditorModel(fileURL: url)
        try await model.load()
        #expect(!model.isDirty)
        try "v2".write(to: url, atomically: true, encoding: .utf8)
        let fresh = try String(contentsOf: url, encoding: .utf8)
        model.handleExternalChange(diskContent: fresh)
        #expect(model.buffer == "v2")
        #expect(model.loadedContent == "v2")
        #expect(model.conflict == nil)
    }

    @Test("dirty buffer surfaces externalChange conflict with the disk content")
    func dirtyConflict() async throws {
        let fixture = try DocFixture()
        let url = try fixture.writeFile(named: "fight.md", content: "v1")
        let model = DocEditorModel(fileURL: url)
        try await model.load()
        model.buffer = "my edit"
        try "external".write(to: url, atomically: true, encoding: .utf8)
        let fresh = try String(contentsOf: url, encoding: .utf8)
        model.handleExternalChange(diskContent: fresh)
        guard case .externalChange(let disk) = model.conflict else {
            Issue.record("expected externalChange, got \(String(describing: model.conflict))")
            return
        }
        #expect(disk == "external")
        #expect(model.buffer == "my edit")
    }

    @Test("file deletion yields fileDeleted when the file previously existed")
    func deletedFlagsConflict() async throws {
        let fixture = try DocFixture()
        let url = try fixture.writeFile(named: "gone.md", content: "v1")
        let model = DocEditorModel(fileURL: url)
        try await model.load()
        try FileManager.default.removeItem(at: url)
        model.handleExternalChange(diskContent: nil)
        #expect(model.conflict == .fileDeleted)
    }

    @Test("file that never existed stays quiet when disk probe returns nil")
    func neverExistedStaysQuiet() async throws {
        let fixture = try DocFixture()
        let url = fixture.root.appendingPathComponent("scratch.json")
        let model = DocEditorModel(fileURL: url)
        try await model.load()
        model.buffer = "draft"
        model.handleExternalChange(diskContent: nil)
        #expect(model.conflict == nil)
    }

    @Test("resolveConflictReload picks disk content and clears conflict")
    func resolveReloadPicksDisk() async throws {
        let fixture = try DocFixture()
        let url = try fixture.writeFile(named: "reload.md", content: "v1")
        let model = DocEditorModel(fileURL: url)
        try await model.load()
        model.buffer = "my draft"
        model.handleExternalChange(diskContent: "disk wins")
        model.resolveConflictReload()
        #expect(model.buffer == "disk wins")
        #expect(model.loadedContent == "disk wins")
        #expect(model.conflict == nil)
        #expect(model.isDirty == false)
    }

    @Test("resolveConflictKeep clears banner without touching buffer")
    func resolveKeepKeepsBuffer() async throws {
        let fixture = try DocFixture()
        let url = try fixture.writeFile(named: "keep.md", content: "v1")
        let model = DocEditorModel(fileURL: url)
        try await model.load()
        model.buffer = "my draft"
        model.handleExternalChange(diskContent: "disk version")
        model.resolveConflictKeep()
        #expect(model.buffer == "my draft")
        #expect(model.loadedContent == "v1")
        #expect(model.conflict == nil)
    }

    @Test("probeExternalChange reads disk and updates conflict state")
    func probeDetectsExternalChange() async throws {
        let fixture = try DocFixture()
        let url = try fixture.writeFile(named: "probe.md", content: "v1")
        let model = DocEditorModel(fileURL: url)
        try await model.load()
        model.buffer = "my changes"
        try "newer".write(to: url, atomically: true, encoding: .utf8)
        await model.probeExternalChange()
        guard case .externalChange(let disk) = model.conflict else {
            Issue.record("expected externalChange after disk write")
            return
        }
        #expect(disk == "newer")
    }

    @Test("saveAndRecreate writes through after fileDeleted")
    func saveAndRecreateAfterDelete() async throws {
        let fixture = try DocFixture()
        let url = try fixture.writeFile(named: "recreate.md", content: "v1")
        let model = DocEditorModel(fileURL: url)
        try await model.load()
        model.buffer = "rebuilt"
        try FileManager.default.removeItem(at: url)
        model.handleExternalChange(diskContent: nil)
        try await model.resolveConflictSaveAndRecreate()
        #expect(model.conflict == nil)
        let onDisk = try String(contentsOf: url, encoding: .utf8)
        #expect(onDisk == "rebuilt")
    }
}

private final class DocFixture {
    let root: URL

    init() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlumageDocEditor-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        self.root = tmp
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    func writeFile(named name: String, content: String) throws -> URL {
        let url = root.appendingPathComponent(name)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
