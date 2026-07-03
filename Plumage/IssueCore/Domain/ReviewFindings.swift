import Foundation

nonisolated struct ReviewFindings: Sendable, Equatable, Codable {
    static let currentVersion = 1
    static let empty = ReviewFindings(version: currentVersion, findings: [])

    var version: Int
    var findings: [ReviewFinding]

    var openFindings: [ReviewFinding] {
        findings.filter { $0.state == .open }
    }

    var sentFindings: [ReviewFinding] {
        findings.filter { $0.state == .sent }
    }

    var nextRound: Int {
        (findings.compactMap(\.round).max() ?? 0) + 1
    }

    mutating func add(_ finding: ReviewFinding) {
        findings.append(finding)
    }

    mutating func updateComment(id: UUID, to comment: String, at now: Date) {
        guard let index = findings.firstIndex(where: { $0.id == id }),
            findings[index].state == .open
        else { return }
        findings[index].comment = comment
        findings[index].updatedAt = now
    }

    mutating func remove(id: UUID) {
        findings.removeAll { $0.id == id && $0.state == .open }
    }

    mutating func markOpenFindingsSent(round: Int, at now: Date) {
        for index in findings.indices where findings[index].state == .open {
            findings[index].state = .sent
            findings[index].round = round
            findings[index].updatedAt = now
        }
    }
}
