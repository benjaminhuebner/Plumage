import Testing

@testable import Plumage

@Suite("SpecParser github field")
struct SpecParserGithubTests {
    @Test("github missing yields nil")
    func githubMissing() throws {
        let issue = try requireSuccess(SpecParser.parse(content: spec(github: nil), folderName: "x"))
        #expect(issue.github == nil)
    }

    @Test("github number parses as Int")
    func githubPresent() throws {
        let issue = try requireSuccess(SpecParser.parse(content: spec(github: "42"), folderName: "x"))
        #expect(issue.github == 42)
    }

    @Test("malformed github returns .invalidFieldType")
    func githubMalformed() throws {
        let result = SpecParser.parse(content: spec(github: "not-a-number"), folderName: "x")
        guard case .failure(.invalidFieldType(let field, _)) = result else {
            Testing.Issue.record("expected .invalidFieldType, got \(result)")
            return
        }
        #expect(field == "github")
    }

    private func spec(github value: String?) -> String {
        let line = value.map { "github: \($0)\n" } ?? ""
        return """
            ---
            id: 1
            title: t
            type: feature
            status: approved
            created: 2026-05-12T09:00:00Z
            updated: 2026-05-12T10:00:00Z
            branch: issue/00001-x
            labels: []
            \(line)---

            Body.
            """
    }

    private func requireSuccess(
        _ result: Result<Plumage.Issue, FrontmatterError>
    ) throws -> Plumage.Issue {
        switch result {
        case .success(let issue): issue
        case .failure(let err):
            throw RequireFailure(message: "expected success, got \(err)")
        }
    }

    private struct RequireFailure: Error, CustomStringConvertible {
        let message: String
        var description: String { message }
    }
}
