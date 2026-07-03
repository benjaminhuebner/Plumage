import Foundation

nonisolated struct ReviewFinding: Sendable, Equatable, Identifiable, Codable {
    nonisolated enum Side: String, Sendable, Codable {
        case old
        case new
    }

    nonisolated enum State: String, Sendable, Codable {
        case open
        case sent
    }

    let id: UUID
    let file: String
    let side: Side
    let line: Int
    let lineText: String
    var comment: String
    var state: State
    var round: Int?
    let createdAt: Date
    var updatedAt: Date
}

extension ReviewFinding {
    var reviewFixTaskText: String {
        let location = side == .old ? "\(file):\(line) (removed)" : "\(file):\(line)"
        let quotedLine = lineText.trimmingCharacters(in: .whitespaces)
        let quote = quotedLine.isEmpty ? "" : " (line: `\(quotedLine)`)"
        return "Review fix: \(location) — \(comment)\(quote)"
    }
}
