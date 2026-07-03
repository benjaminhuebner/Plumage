import Foundation
import Testing

@testable import Plumage

@Suite("ReviewFindingsStore")
struct ReviewFindingsStoreTests {
    private static func finding(
        id: UUID = UUID(),
        file: String = "Sources/App.swift",
        side: ReviewFinding.Side = .new,
        line: Int = 42,
        lineText: String = "let answer = 42",
        comment: String = "Magic number",
        state: ReviewFinding.State = .open,
        round: Int? = nil
    ) -> ReviewFinding {
        ReviewFinding(
            id: id,
            file: file,
            side: side,
            line: line,
            lineText: lineText,
            comment: comment,
            state: state,
            round: round,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    private func temporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("review-findings-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("review-findings.json")
    }

    @Test("save and load round-trips all fields")
    func roundTrip() throws {
        let url = temporaryFileURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        var findings = ReviewFindings.empty
        findings.add(Self.finding(comment: "Magic number"))
        findings.add(Self.finding(side: .old, line: 7, state: .sent, round: 1))
        try ReviewFindingsStore.save(findings, to: url)

        let loaded = try ReviewFindingsStore.load(from: url).get()
        #expect(loaded == findings)
    }

    @Test("missing file loads as empty findings")
    func missingFile() throws {
        let url = temporaryFileURL()
        let loaded = try ReviewFindingsStore.load(from: url).get()
        #expect(loaded == .empty)
    }

    @Test("truncated file is invalid JSON")
    func truncatedFile() throws {
        let error = try #require(failure(#"{"version": 1, "findings": [{"id":"#))
        guard case .invalidJSON = error else {
            Issue.record("expected invalidJSON, got \(error)")
            return
        }
    }

    @Test("missing required field is a typed error")
    func missingField() throws {
        let json = """
            {"version": 1, "findings": [{"id": "9C4A1B9E-52C2-4C4B-8E4E-000000000001"}]}
            """
        let error = try #require(failure(json))
        guard case .missingRequiredField = error else {
            Issue.record("expected missingRequiredField, got \(error)")
            return
        }
    }

    @Test("invalid date value is a typed field error")
    func invalidDate() throws {
        let json = """
            {"version": 1, "findings": [{
              "id": "9C4A1B9E-52C2-4C4B-8E4E-000000000001",
              "file": "a.swift", "side": "new", "line": 1, "lineText": "x",
              "comment": "c", "state": "open",
              "createdAt": "not-a-date", "updatedAt": "not-a-date"
            }]}
            """
        let error = try #require(failure(json))
        guard case .invalidFieldValue(let field, _) = error else {
            Issue.record("expected invalidFieldValue, got \(error)")
            return
        }
        #expect(field == "createdAt")
    }

    @Test("markOpenFindingsSent flips only open findings and stamps round")
    func markSent() {
        let now = Date(timeIntervalSince1970: 1_700_000_500)
        var findings = ReviewFindings.empty
        let open = Self.finding()
        let alreadySent = Self.finding(state: .sent, round: 1)
        findings.add(open)
        findings.add(alreadySent)

        findings.markOpenFindingsSent(round: findings.nextRound, at: now)

        #expect(findings.openFindings.isEmpty)
        #expect(findings.findings[0].state == .sent)
        #expect(findings.findings[0].round == 2)
        #expect(findings.findings[0].updatedAt == now)
        #expect(findings.findings[1].round == 1)
        #expect(findings.findings[1].updatedAt != now)
    }

    @Test("nextRound is 1 for a clean slate and max sent round + 1 afterwards")
    func nextRound() {
        var findings = ReviewFindings.empty
        #expect(findings.nextRound == 1)
        findings.add(Self.finding(state: .sent, round: 3))
        findings.add(Self.finding())
        #expect(findings.nextRound == 4)
    }

    @Test("updateComment edits open findings and refuses sent ones")
    func updateComment() {
        let now = Date(timeIntervalSince1970: 1_700_000_500)
        let openID = UUID()
        let sentID = UUID()
        var findings = ReviewFindings.empty
        findings.add(Self.finding(id: openID))
        findings.add(Self.finding(id: sentID, state: .sent, round: 1))

        findings.updateComment(id: openID, to: "Edited", at: now)
        findings.updateComment(id: sentID, to: "Edited", at: now)

        #expect(findings.findings[0].comment == "Edited")
        #expect(findings.findings[0].updatedAt == now)
        #expect(findings.findings[1].comment == "Magic number")
    }

    @Test("remove deletes open findings and keeps sent history")
    func remove() {
        let openID = UUID()
        let sentID = UUID()
        var findings = ReviewFindings.empty
        findings.add(Self.finding(id: openID))
        findings.add(Self.finding(id: sentID, state: .sent, round: 1))

        findings.remove(id: openID)
        findings.remove(id: sentID)

        #expect(findings.findings.count == 1)
        #expect(findings.findings[0].id == sentID)
    }

    private func failure(_ json: String) -> ReviewFindingsParseError? {
        switch ReviewFindingsStore.parse(data: Data(json.utf8)) {
        case .success:
            nil
        case .failure(let error):
            error
        }
    }
}
