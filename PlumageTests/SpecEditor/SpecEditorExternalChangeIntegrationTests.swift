import Foundation
import Testing

@testable import Plumage

@Suite("SpecEditorExternalChange")
@MainActor
struct SpecEditorExternalChangeIntegrationTests {
    @Test("Clean buffer silently reloads when disk content changes")
    func cleanReload() async throws {
        let url = try makeSpec(content: "version one")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let model = SpecEditorModel(specURL: url, folderName: "00042-feature")
        try await model.load()
        #expect(!model.isDirty)

        // External writes "version two"
        try "version two".write(to: url, atomically: true, encoding: .utf8)
        let fresh = try String(contentsOf: url, encoding: .utf8)
        model.handleExternalChange(diskContent: fresh)

        #expect(model.buffer == "version two")
        #expect(model.loadedContent == "version two")
        #expect(model.conflict == nil)
    }

    @Test("Dirty buffer surfaces externalChange conflict")
    func dirtyConflict() async throws {
        let url = try makeSpec(content: "version one")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let model = SpecEditorModel(specURL: url, folderName: "00042-feature")
        try await model.load()
        model.buffer = "my edit"
        #expect(model.isDirty)

        try "external edit".write(to: url, atomically: true, encoding: .utf8)
        let fresh = try String(contentsOf: url, encoding: .utf8)
        model.handleExternalChange(diskContent: fresh)

        guard case .externalChange(let disk) = model.conflict else {
            Issue.record("expected externalChange, got \(String(describing: model.conflict))")
            return
        }
        #expect(disk == "external edit")
        #expect(model.buffer == "my edit")
    }

    @Test("Folder removal yields fileDeleted")
    func removedFileDeleted() async throws {
        let url = try makeSpec(content: "version one")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let model = SpecEditorModel(specURL: url, folderName: "00042-feature")
        try await model.load()
        model.buffer = "user edit"

        try FileManager.default.removeItem(at: url)
        model.handleExternalChange(diskContent: nil)

        #expect(model.conflict == .fileDeleted)
    }

    // Kanban can report the issue as missing during an optimistic archive/trash
    // before the on-disk move actually runs. observeExternalChange must probe
    // disk in that case and stay quiet until the file is actually gone —
    // otherwise the banner flashes for a frame on every removal.
    @Test("kanban-missing snapshot does not flag fileDeleted while disk still has the file")
    func kanbanMissingButDiskPresentIsNoConflict() async throws {
        let url = try makeSpec(content: "version one")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let model = SpecEditorModel(specURL: url, folderName: "00042-feature")
        try await model.load()
        // currentIssue: nil simulates "card disappeared from kanban".
        await model.observeExternalChange(currentIssue: nil)

        #expect(model.conflict == nil)
    }

    @Test("kanban-missing snapshot AND disk gone yields fileDeleted")
    func kanbanMissingAndDiskGoneFlagsDeleted() async throws {
        let url = try makeSpec(content: "version one")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let model = SpecEditorModel(specURL: url, folderName: "00042-feature")
        try await model.load()
        try FileManager.default.removeItem(at: url)

        await model.observeExternalChange(currentIssue: nil)

        #expect(model.conflict == .fileDeleted)
    }

    private func makeSpec(content: String) throws -> URL {
        let dir = URL(filePath: NSTemporaryDirectory())
            .appendingPathComponent("SpecEditorExternalChangeTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("spec.md")
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
