import Foundation
import Testing

@testable import Plumage

@Suite("TemplateArchiveZip entry validation")
struct TemplateArchiveZipValidationTests {
    @Test("Plain relative entries pass")
    func relativeEntriesPass() throws {
        try TemplateArchiveZip.validateEntryNames([
            "archive-manifest.json",
            "templates/macOS/CLAUDE.md",
            "components/swift-shared/hooks/format swift.sh",
            "template-images/",
        ])
    }

    @Test("A leading-slash entry is rejected")
    func absoluteEntryRejected() {
        #expect(throws: TemplateArchiveZipError.entryEscapesDestination("/etc/passwd")) {
            try TemplateArchiveZip.validateEntryNames(["ok.txt", "/etc/passwd"])
        }
    }

    @Test(
        "A parent-directory component is rejected",
        arguments: [
            "../evil.txt",
            "templates/../../evil.txt",
            "a/b/../../../c",
        ])
    func traversalEntryRejected(_ name: String) {
        #expect(throws: TemplateArchiveZipError.entryEscapesDestination(name)) {
            try TemplateArchiveZip.validateEntryNames([name])
        }
    }

    @Test("A traversal entry stops unpack before ditto runs")
    func traversalStopsBeforeExtraction() async throws {
        let mock = MockTemplateArchiveProcessRunner()
        let archive = URL(filePath: "/tmp/fake.plumagetemplates")
        mock.stdoutForArgs[["-1", archive.path]] = "ok.txt\n../evil.txt\n"
        let zip = TemplateArchiveZip(runner: mock)
        await #expect(throws: TemplateArchiveZipError.entryEscapesDestination("../evil.txt")) {
            try await zip.unpack(archive: archive, to: URL(filePath: "/tmp/dest"))
        }
        #expect(mock.recordedCalls == [["-1", archive.path]])
    }

    @Test("A failing listing surfaces corruptArchive without extraction")
    func corruptListingStopsUnpack() async throws {
        let mock = MockTemplateArchiveProcessRunner()
        let archive = URL(filePath: "/tmp/garbage.plumagetemplates")
        mock.exitCodeForArgs[["-1", archive.path]] = 9
        let zip = TemplateArchiveZip(runner: mock)
        await #expect(throws: TemplateArchiveZipError.corruptArchive("")) {
            try await zip.unpack(archive: archive, to: URL(filePath: "/tmp/dest"))
        }
        #expect(mock.recordedCalls.count == 1)
    }
}

@Suite("TemplateArchiveZip (integration)", .tags(.integration))
struct TemplateArchiveZipIntegrationTests {
    private func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "archive-zip-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("Pack → unpack reproduces the staged tree byte-identically")
    func roundTrip() async throws {
        let root = try tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appending(path: "stage")
        let nested = source.appending(path: "templates/macOS")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data("manifest".utf8).write(to: source.appending(path: "archive-manifest.json"))
        try Data("layer-content".utf8).write(to: nested.appending(path: "CLAUDE.md"))

        let archive = root.appending(path: "export.plumagetemplates")
        let zip = TemplateArchiveZip()
        try await zip.pack(directory: source, to: archive)
        #expect(FileManager.default.fileExists(atPath: archive.path))

        let destination = root.appending(path: "unpacked")
        try await zip.unpack(archive: archive, to: destination)
        let manifest = try Data(contentsOf: destination.appending(path: "archive-manifest.json"))
        let layer = try Data(contentsOf: destination.appending(path: "templates/macOS/CLAUDE.md"))
        #expect(manifest == Data("manifest".utf8))
        #expect(layer == Data("layer-content".utf8))
    }

    @Test("Garbage bytes are rejected as corruptArchive")
    func corruptInputRejected() async throws {
        let root = try tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let garbage = root.appending(path: "garbage.plumagetemplates")
        try Data("definitely not a zip".utf8).write(to: garbage)

        let zip = TemplateArchiveZip()
        let destination = root.appending(path: "unpacked")
        await #expect(throws: TemplateArchiveZipError.self) {
            try await zip.unpack(archive: garbage, to: destination)
        }
    }

    @Test("An archive containing a symlink is rejected after staging")
    func symlinkRejected() async throws {
        let root = try tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appending(path: "stage")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: source.appending(path: "real.txt"))
        try FileManager.default.createSymbolicLink(
            at: source.appending(path: "link"),
            withDestinationURL: URL(filePath: "/etc")
        )

        let archive = root.appending(path: "export.plumagetemplates")
        let zip = TemplateArchiveZip()
        try await zip.pack(directory: source, to: archive)

        let destination = root.appending(path: "unpacked")
        await #expect(throws: TemplateArchiveZipError.symlinkEntry("link")) {
            try await zip.unpack(archive: archive, to: destination)
        }
    }
}
