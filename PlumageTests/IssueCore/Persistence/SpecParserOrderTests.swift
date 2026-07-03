import Testing

@testable import Plumage

@Suite("SpecParser order field")
struct SpecParserOrderTests {
    @Test("order missing yields nil")
    func orderMissing() throws {
        let issue = try requireSuccess(SpecParser.parse(content: noOrderSpec(), folderName: "x"))
        #expect(issue.order == nil)
    }

    @Test("integer order parses as Double")
    func orderInteger() throws {
        let issue = try requireSuccess(SpecParser.parse(content: orderSpec("12"), folderName: "x"))
        #expect(issue.order == 12.0)
    }

    @Test("fractional order parses as Double")
    func orderFractional() throws {
        let issue = try requireSuccess(SpecParser.parse(content: orderSpec("5.25"), folderName: "x"))
        #expect(issue.order == 5.25)
    }

    @Test("negative order parses as Double")
    func orderNegative() throws {
        let issue = try requireSuccess(SpecParser.parse(content: orderSpec("-1.5"), folderName: "x"))
        #expect(issue.order == -1.5)
    }

    @Test("malformed order returns .invalidFieldType")
    func orderMalformed() throws {
        let result = SpecParser.parse(content: orderSpec("foo"), folderName: "x")
        guard case .failure(.invalidFieldType(let field, _)) = result else {
            Testing.Issue.record("expected .invalidFieldType, got \(result)")
            return
        }
        #expect(field == "order")
    }

    private func noOrderSpec() -> String {
        """
        ---
        id: 1
        title: t
        type: feature
        status: approved
        created: 2026-05-12T09:00:00Z
        updated: 2026-05-12T10:00:00Z
        branch: issue/00001-x
        labels: []
        model: null
        ---

        Body.
        """
    }

    private func orderSpec(_ value: String) -> String {
        """
        ---
        id: 1
        title: t
        type: feature
        status: approved
        created: 2026-05-12T09:00:00Z
        updated: 2026-05-12T10:00:00Z
        branch: issue/00001-x
        labels: []
        model: null
        order: \(value)
        ---

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
