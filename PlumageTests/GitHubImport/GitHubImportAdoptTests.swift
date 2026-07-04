import Foundation
import Testing

@testable import Plumage

@MainActor
@Suite("GitHubImportModel adopt")
struct GitHubImportAdoptTests {
    @MainActor final class Recorder {
        var folders: [String] = []
    }

    private func makeProject() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "GHImport-\(UUID().uuidString)")
        let issues = root.appending(path: ".claude/issues")
        try FileManager.default.createDirectory(at: issues, withIntermediateDirectories: true)
        let template = """
            ---
            id: <<<ID>>>
            title: <<<TITLE>>>
            type: feature
            status: draft
            created: <<<CREATED>>>
            updated: <<<CREATED>>>
            branch: issue/<<<ID_PADDED>>>-<<<SLUG>>>
            labels: []
            ---
            """
        try template.write(
            to: issues.appending(path: "_TEMPLATE.md"), atomically: true, encoding: .utf8)
        return root
    }

    private func makeModel(project: URL, recorder: Recorder) -> GitHubImportModel {
        GitHubImportModel(
            projectURL: project,
            boundAccountID: nil,
            allocator: NextIssueAllocator(projectURL: project),
            openInEditor: { recorder.folders.append($0) })
    }

    private func issue(
        number: Int, title: String, body: String? = "Body text", labels: [String] = ["bug"]
    ) throws -> GitHubIssue {
        GitHubIssue(
            number: number, title: title, body: body,
            htmlURL: try #require(URL(string: "https://github.com/o/r/issues/\(number)")),
            labels: labels, updatedAt: Date(timeIntervalSince1970: 0), authorLogin: "octocat")
    }

    @Test("adopt writes a spec with the github cross-ref, prompt, and labels, then navigates")
    func adoptCreatesSpec() async throws {
        let project = try makeProject()
        defer { try? FileManager.default.removeItem(at: project) }
        let recorder = Recorder()
        let model = makeModel(project: project, recorder: recorder)

        model.adopt(
            try issue(number: 42, title: "Fix the parser", body: "Steps to repro", labels: ["bug", "v0.5"]))

        #expect(model.justAdopted.contains(42))
        #expect(model.adoptError == nil)
        let folder = try #require(recorder.folders.first)
        let specURL = project.appending(path: ".claude/issues/\(folder)/spec.md")
        let spec = try String(contentsOf: specURL, encoding: .utf8)
        #expect(spec.contains("github: 42\n"))
        #expect(spec.contains("title: Fix the parser"))
        #expect(spec.contains("labels: [bug, v0.5]"))
        let prompt = try String(
            contentsOf: project.appending(path: ".claude/issues/\(folder)/prompt.md"), encoding: .utf8)
        #expect(prompt == "Steps to repro")
        let parsed = try SpecParser.parse(content: spec, folderName: folder).get()
        #expect(parsed.github == 42)
        #expect(parsed.labels == ["bug", "v0.5"])
    }

    @Test("adopting the same number twice creates only one issue")
    func doubleAdoptGuard() async throws {
        let project = try makeProject()
        defer { try? FileManager.default.removeItem(at: project) }
        let recorder = Recorder()
        let model = makeModel(project: project, recorder: recorder)

        model.adopt(try issue(number: 7, title: "Once"))
        model.adopt(try issue(number: 7, title: "Once"))

        #expect(recorder.folders.count == 1)
        let issuesDir = project.appending(path: ".claude/issues")
        let entries = try FileManager.default.contentsOfDirectory(atPath: issuesDir.path)
            .filter { $0 != "_TEMPLATE.md" && !$0.hasPrefix(".") }
        #expect(entries.count == 1)
    }

    @Test("slug collision retries with a -gh<number> suffix")
    func slugCollisionRetry() async throws {
        let project = try makeProject()
        defer { try? FileManager.default.removeItem(at: project) }
        let issuesDir = project.appending(path: ".claude/issues")
        let existing = issuesDir.appending(path: "00001-dup")
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)
        try "placeholder".write(to: existing.appending(path: "spec.md"), atomically: true, encoding: .utf8)

        let recorder = Recorder()
        let model = makeModel(project: project, recorder: recorder)
        model.adopt(try issue(number: 99, title: "Dup"))

        let folder = try #require(recorder.folders.first)
        #expect(folder.hasSuffix("-dup-gh99"))
        #expect(model.justAdopted.contains(99))
        #expect(model.adoptError == nil)
    }
}
