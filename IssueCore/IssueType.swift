import SwiftUI

nonisolated enum IssueType: String, CaseIterable, Codable, Sendable {
    case feature
    case chore
    case spike

    var color: Color {
        switch self {
        case .feature: .green
        case .chore: .yellow
        case .spike: .orange
        }
    }
}
