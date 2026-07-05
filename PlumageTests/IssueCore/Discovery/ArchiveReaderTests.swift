import Foundation
import Testing

@testable import Plumage

@Suite("ArchiveReader.discoverArchivedIssues")
struct ArchiveReaderTests {
    private func makeProject() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "ArchiveReader-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appending(path: ".claude/issues"), withIntermediateDirectories: true)
        return root
    }

    private func writeArchived(in project: URL, folder: String, content: String) throws {
        let dir = project.appending(path: ".claude/issues/archive/\(folder)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try content.write(to: dir.appending(path: "spec.md"), atomically: true, encoding: .utf8)
    }

    private func validSpec(id: Int, folder: String) -> String {
        """
        ---
        id: \(id)
        title: Archived \(id)
        type: feature
        status: done
        created: 2026-01-01T00:00:00Z
        updated: 2026-01-01T00:00:00Z
        branch: issue/\(folder)
        labels: []
        ---

        Body.
        """
    }

    @Test("missing archive directory returns empty")
    func missingDirectory() throws {
        let project = try makeProject()
        defer { try? FileManager.default.removeItem(at: project) }

        let issues = ArchiveReader.discoverArchivedIssues(
            inArchive: IssueLayout.archiveDirectory(in: project))
        #expect(issues.isEmpty)
    }

    @Test("empty archive directory returns empty")
    func emptyDirectory() throws {
        let project = try makeProject()
        defer { try? FileManager.default.removeItem(at: project) }
        try FileManager.default.createDirectory(
            at: IssueLayout.archiveDirectory(in: project), withIntermediateDirectories: true)

        let issues = ArchiveReader.discoverArchivedIssues(
            inArchive: IssueLayout.archiveDirectory(in: project))
        #expect(issues.isEmpty)
    }

    @Test("valid specs parse into valid issues")
    func validSpecs() throws {
        let project = try makeProject()
        defer { try? FileManager.default.removeItem(at: project) }
        try writeArchived(in: project, folder: "00101-a", content: validSpec(id: 101, folder: "00101-a"))
        try writeArchived(in: project, folder: "00102-b", content: validSpec(id: 102, folder: "00102-b"))

        let issues = ArchiveReader.discoverArchivedIssues(
            inArchive: IssueLayout.archiveDirectory(in: project))

        #expect(issues.count == 2)
        #expect(issues.allSatisfy { if case .valid = $0 { true } else { false } })
        #expect(Set(issues.map(\.id)) == ["00101-a", "00102-b"])
    }

    @Test("a broken spec is surfaced as an invalid card")
    func invalidSpec() throws {
        let project = try makeProject()
        defer { try? FileManager.default.removeItem(at: project) }
        try writeArchived(in: project, folder: "00103-c", content: validSpec(id: 103, folder: "00103-c"))
        try writeArchived(in: project, folder: "00104-broken", content: "not a spec at all")

        let issues = ArchiveReader.discoverArchivedIssues(
            inArchive: IssueLayout.archiveDirectory(in: project))

        #expect(issues.count == 2)
        let broken = try #require(issues.first { $0.id == "00104-broken" })
        #expect(
            {
                guard case .invalid = broken else { return false }
                return true
            }())
    }
}
