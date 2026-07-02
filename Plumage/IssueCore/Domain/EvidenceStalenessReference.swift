import Foundation

nonisolated struct EvidenceStalenessReference: Sendable, Equatable {
    let head: String
    let allowedCommitsAfter: Int

    static func reference(for evidence: RunEvidence) -> EvidenceStalenessReference? {
        if let finalGate = evidence.finalGate, finalGate.passedAt != nil, let head = finalGate.head {
            return EvidenceStalenessReference(head: head, allowedCommitsAfter: 0)
        }
        let newestPassed =
            evidence.tasks
            .filter { $0.passedAt != nil && $0.head != nil }
            .max { $0.task < $1.task }
        guard let head = newestPassed?.head else { return nil }
        // The gate runs pre-commit, so a task record's head predates the
        // task's own commit: exactly one commit after it is the gated state
        // itself, anything beyond is an ungated change.
        return EvidenceStalenessReference(head: head, allowedCommitsAfter: 1)
    }

    func isStale(commitsAfterHead: Int) -> Bool {
        commitsAfterHead > allowedCommitsAfter
    }
}
