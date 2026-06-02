import SwiftUI

// Lives here, not next to IssueType, so the IssueCore domain module stays
// SwiftUI-free (architecture.md module-boundary rule).
extension IssueType {
    var color: Color {
        switch self {
        case .feature: .green
        case .chore: .yellow
        case .spike: .orange
        case .refactor: .cyan
        }
    }
}
