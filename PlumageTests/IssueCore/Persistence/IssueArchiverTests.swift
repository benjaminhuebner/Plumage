import Foundation
import Testing

@testable import Plumage

@Suite("IssueArchiver.archive")
struct IssueArchiverArchiveTests {
    @Test("moves folder under archive root and returns destination URL")
    func happyPath() throws {
        let fixture = try ArchiverFixture()
        let folder = try fixture.makeIssueFolder(named: "00007-foo")

        let archiveRoot = fixture.archiveRoot
        let dest = try IssueArchiver.archive(folderURL: folder, archiveRoot: archiveRoot)

        #expect(dest.lastPathComponent == "00007-foo")
        #expect(dest.deletingLastPathComponent().standardizedFileURL == archiveRoot.standardizedFileURL)
        #expect(FileManager.default.fileExists(atPath: dest.path))
        #expect(!FileManager.default.fileExists(atPath: folder.path))
    }

    @Test("creates the archive root lazily when missing")
    func createsArchiveRoot() throws {
        let fixture = try ArchiverFixture()
        let folder = try fixture.makeIssueFolder(named: "00008-bar")
        let archiveRoot = fixture.archiveRoot
        // Sanity: archive root doesn't exist yet.
        #expect(!FileManager.default.fileExists(atPath: archiveRoot.path))

        let dest = try IssueArchiver.archive(folderURL: folder, archiveRoot: archiveRoot)

        #expect(FileManager.default.fileExists(atPath: dest.path))
        var isDir: ObjCBool = false
        let archiveExists = FileManager.default.fileExists(atPath: archiveRoot.path, isDirectory: &isDir)
        #expect(archiveExists && isDir.boolValue)
    }

    @Test("collision appends numeric suffix, returns suffixed destination")
    func collisionAppendsSuffix() throws {
        let fixture = try ArchiverFixture()
        // Seed archive with the same name.
        let preexisting = try fixture.makeArchivedFolder(named: "00009-baz")
        #expect(FileManager.default.fileExists(atPath: preexisting.path))

        let fresh = try fixture.makeIssueFolder(named: "00009-baz")
        let dest = try IssueArchiver.archive(folderURL: fresh, archiveRoot: fixture.archiveRoot)

        #expect(dest.lastPathComponent == "00009-baz-1")
        #expect(FileManager.default.fileExists(atPath: dest.path))
        // The pre-existing one is still there at the original name.
        #expect(FileManager.default.fileExists(atPath: preexisting.path))
    }

    @Test("collision walks suffixes 1, 2, ... until a free slot")
    func collisionWalksMultipleSuffixes() throws {
        let fixture = try ArchiverFixture()
        _ = try fixture.makeArchivedFolder(named: "00010-qux")
        _ = try fixture.makeArchivedFolder(named: "00010-qux-1")
        _ = try fixture.makeArchivedFolder(named: "00010-qux-2")

        let fresh = try fixture.makeIssueFolder(named: "00010-qux")
        let dest = try IssueArchiver.archive(folderURL: fresh, archiveRoot: fixture.archiveRoot)

        #expect(dest.lastPathComponent == "00010-qux-3")
        #expect(FileManager.default.fileExists(atPath: dest.path))
    }

    @Test("missing source folder throws")
    func missingSourceThrows() throws {
        let fixture = try ArchiverFixture()
        let nonExistent = fixture.issuesRoot.appendingPathComponent("00011-ghost")
        #expect(throws: (any Error).self) {
            _ = try IssueArchiver.archive(folderURL: nonExistent, archiveRoot: fixture.archiveRoot)
        }
    }

    @Test("suffix walk past the hard cap throws fileWriteFileExists")
    func suffixCapEnforced() throws {
        let fixture = try ArchiverFixture()
        // Saturate the suffix space: the unsuffixed slot plus every -1...-cap.
        _ = try fixture.makeArchivedFolder(named: "00099-spam")
        for suffix in 1...IssueArchiver.maxArchiveSuffix {
            _ = try fixture.makeArchivedFolder(named: "00099-spam-\(suffix)")
        }

        let fresh = try fixture.makeIssueFolder(named: "00099-spam")
        #expect(throws: CocoaError.self) {
            _ = try IssueArchiver.archive(folderURL: fresh, archiveRoot: fixture.archiveRoot)
        }
    }
}

@Suite("IssueArchiver.unarchive")
struct IssueArchiverUnarchiveTests {
    @Test("moves an archived folder back under the issues root")
    func movesBack() throws {
        let fixture = try ArchiverFixture()
        let archived = try fixture.makeArchivedFolder(named: "00020-restore")

        let dest = try IssueArchiver.unarchive(
            folderURL: archived, issuesRoot: fixture.issuesRoot)

        #expect(dest.lastPathComponent == "00020-restore")
        #expect(
            dest.deletingLastPathComponent().standardizedFileURL
                == fixture.issuesRoot.standardizedFileURL)
        #expect(FileManager.default.fileExists(atPath: dest.path))
        #expect(!FileManager.default.fileExists(atPath: archived.path))
    }

    @Test("collision with an active folder appends a numeric suffix")
    func collisionAppendsSuffix() throws {
        let fixture = try ArchiverFixture()
        let active = try fixture.makeIssueFolder(named: "00021-clash")
        let archived = try fixture.makeArchivedFolder(named: "00021-clash")

        let dest = try IssueArchiver.unarchive(
            folderURL: archived, issuesRoot: fixture.issuesRoot)

        #expect(dest.lastPathComponent == "00021-clash-1")
        #expect(FileManager.default.fileExists(atPath: dest.path))
        #expect(FileManager.default.fileExists(atPath: active.path))
    }

    @Test("collision walks suffixes 1, 2, ... until a free slot")
    func collisionWalksMultipleSuffixes() throws {
        let fixture = try ArchiverFixture()
        _ = try fixture.makeIssueFolder(named: "00022-clash")
        _ = try fixture.makeIssueFolder(named: "00022-clash-1")
        _ = try fixture.makeIssueFolder(named: "00022-clash-2")
        let archived = try fixture.makeArchivedFolder(named: "00022-clash")

        let dest = try IssueArchiver.unarchive(
            folderURL: archived, issuesRoot: fixture.issuesRoot)

        #expect(dest.lastPathComponent == "00022-clash-3")
        #expect(FileManager.default.fileExists(atPath: dest.path))
    }

    @Test("missing source folder throws")
    func missingSourceThrows() throws {
        let fixture = try ArchiverFixture()
        let nonExistent = fixture.archiveRoot.appendingPathComponent("00023-ghost")
        #expect(throws: (any Error).self) {
            _ = try IssueArchiver.unarchive(
                folderURL: nonExistent, issuesRoot: fixture.issuesRoot)
        }
    }

    @Test("move-only: the id and folder name survive the round trip")
    func idPreserved() throws {
        let fixture = try ArchiverFixture()
        let spec = """
            ---
            id: 42
            title: Preserve me
            type: feature
            status: done
            created: 2026-01-01T00:00:00Z
            updated: 2026-01-01T00:00:00Z
            branch: issue/00042-preserve
            labels: []
            ---

            Body.
            """
        let archived = try fixture.makeArchivedFolder(named: "00042-preserve", content: spec)

        let dest = try IssueArchiver.unarchive(
            folderURL: archived, issuesRoot: fixture.issuesRoot)

        #expect(dest.lastPathComponent == "00042-preserve")
        let moved = try String(
            contentsOf: dest.appendingPathComponent("spec.md"), encoding: .utf8)
        #expect(moved == spec)
    }
}

@Suite("IssueArchiver.trash")
struct IssueArchiverTrashTests {
    @Test("moves folder to system trash and returns resulting URL")
    func happyPath() throws {
        let fixture = try ArchiverFixture()
        let folder = try fixture.makeIssueFolder(named: "00012-rubbish")

        // defer the registration so ~/.Trash doesn't leak if a later
        // assertion throws before teardown.
        var trashed: URL?
        defer { trashed.map(fixture.trackTrashedURL) }
        trashed = try IssueArchiver.trash(folderURL: folder)
        let url = try #require(trashed)

        #expect(!FileManager.default.fileExists(atPath: folder.path))
        #expect(FileManager.default.fileExists(atPath: url.path))
        // Prefix-match: the system may suffix " 2" / " 3" on Trash conflict.
        #expect(url.lastPathComponent.hasPrefix("00012-rubbish"))
    }

    @Test("missing source folder throws")
    func missingSourceThrows() throws {
        let fixture = try ArchiverFixture()
        let nonExistent = fixture.issuesRoot.appendingPathComponent("00013-ghost")
        #expect(throws: (any Error).self) {
            _ = try IssueArchiver.trash(folderURL: nonExistent)
        }
    }
}

private final class ArchiverFixture {
    let root: URL
    let issuesRoot: URL
    let archiveRoot: URL

    // URLs the test moved into the system Trash. Removed in deinit so a CI
    // run doesn't leave a growing pile of test folders in ~/.Trash.
    private var trashedURLs: [URL] = []

    init() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlumageIssueArchiver-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        self.root = tmp
        self.issuesRoot = tmp.appendingPathComponent(".claude/issues", isDirectory: true)
        self.archiveRoot = self.issuesRoot.appendingPathComponent("archive", isDirectory: true)
        try FileManager.default.createDirectory(at: issuesRoot, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
        for url in trashedURLs {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func makeIssueFolder(named name: String, content: String = "stub") throws -> URL {
        let folder = issuesRoot.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let spec = folder.appendingPathComponent("spec.md")
        try content.write(to: spec, atomically: true, encoding: .utf8)
        return folder
    }

    func makeArchivedFolder(named name: String, content: String = "pre") throws -> URL {
        try FileManager.default.createDirectory(at: archiveRoot, withIntermediateDirectories: true)
        let folder = archiveRoot.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try content.write(
            to: folder.appendingPathComponent("spec.md"), atomically: true, encoding: .utf8)
        return folder
    }

    func trackTrashedURL(_ url: URL) {
        trashedURLs.append(url)
    }
}
