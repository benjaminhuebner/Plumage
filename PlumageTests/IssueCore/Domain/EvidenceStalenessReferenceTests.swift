import Foundation
import Testing

@testable import Plumage

@Suite("EvidenceStalenessReference")
struct EvidenceStalenessReferenceTests {
    private let passedAt = Date(timeIntervalSince1970: 1_780_000_000)

    @Test("passed final gate is the reference and allows zero commits after")
    func finalGateReference() throws {
        let evidence = makeEvidence(
            tasks: [taskRecord(task: 1, passed: true, head: "aaa1111")],
            finalGate: RunEvidence.FinalGateRecord(
                attempts: 1, passedAt: passedAt, head: "fff9999", flags: ["--full"])
        )
        let reference = try #require(EvidenceStalenessReference.reference(for: evidence))
        #expect(reference.head == "fff9999")
        #expect(!reference.isStale(commitsAfterHead: 0))
        #expect(reference.isStale(commitsAfterHead: 1))
    }

    @Test("without a final gate the newest passed task allows exactly its own commit")
    func newestTaskReference() throws {
        let evidence = makeEvidence(
            tasks: [
                taskRecord(task: 1, passed: true, head: "aaa1111"),
                taskRecord(task: 3, passed: true, head: "ccc3333"),
                taskRecord(task: 2, passed: true, head: "bbb2222"),
            ],
            finalGate: nil
        )
        let reference = try #require(EvidenceStalenessReference.reference(for: evidence))
        #expect(reference.head == "ccc3333")
        #expect(!reference.isStale(commitsAfterHead: 1))
        #expect(reference.isStale(commitsAfterHead: 2))
    }

    @Test("a final gate that has not passed falls back to task records")
    func unpassedFinalGateFallsBack() throws {
        let evidence = makeEvidence(
            tasks: [taskRecord(task: 1, passed: true, head: "aaa1111")],
            finalGate: RunEvidence.FinalGateRecord(
                attempts: 2, passedAt: nil, head: nil, flags: [])
        )
        let reference = try #require(EvidenceStalenessReference.reference(for: evidence))
        #expect(reference.head == "aaa1111")
        #expect(reference.allowedCommitsAfter == 1)
    }

    @Test("a passed final gate without a head falls back to task records")
    func headlessFinalGateFallsBack() throws {
        let evidence = makeEvidence(
            tasks: [taskRecord(task: 1, passed: true, head: "aaa1111")],
            finalGate: RunEvidence.FinalGateRecord(
                attempts: 1, passedAt: passedAt, head: nil, flags: [])
        )
        let reference = try #require(EvidenceStalenessReference.reference(for: evidence))
        #expect(reference.head == "aaa1111")
    }

    @Test("attempts-only and headless task records yield no reference")
    func noUsableRecords() {
        let attemptsOnly = makeEvidence(
            tasks: [taskRecord(task: 1, passed: false, head: nil)], finalGate: nil)
        #expect(EvidenceStalenessReference.reference(for: attemptsOnly) == nil)

        let headless = makeEvidence(
            tasks: [taskRecord(task: 1, passed: true, head: nil)], finalGate: nil)
        #expect(EvidenceStalenessReference.reference(for: headless) == nil)

        let empty = makeEvidence(tasks: [], finalGate: nil)
        #expect(EvidenceStalenessReference.reference(for: empty) == nil)
    }

    @Test("an unpassed newer attempt does not displace the newest passed task")
    func unpassedAttemptIgnored() throws {
        let evidence = makeEvidence(
            tasks: [
                taskRecord(task: 1, passed: true, head: "aaa1111"),
                taskRecord(task: 2, passed: false, head: nil),
            ],
            finalGate: nil
        )
        let reference = try #require(EvidenceStalenessReference.reference(for: evidence))
        #expect(reference.head == "aaa1111")
    }

    private func makeEvidence(
        tasks: [RunEvidence.TaskRecord], finalGate: RunEvidence.FinalGateRecord?
    ) -> RunEvidence {
        RunEvidence(
            version: 1,
            issue: "00042-add-user-auth",
            branch: "issue/00042-add-user-auth",
            totalTasks: tasks.count,
            tasks: tasks,
            finalGate: finalGate
        )
    }

    private func taskRecord(task: Int, passed: Bool, head: String?) -> RunEvidence.TaskRecord {
        RunEvidence.TaskRecord(
            task: task,
            attempts: 1,
            passedAt: passed ? passedAt : nil,
            head: head,
            flags: []
        )
    }
}
