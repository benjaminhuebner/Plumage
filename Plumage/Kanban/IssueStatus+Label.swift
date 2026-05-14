import Foundation

extension IssueStatus {
    var label: String {
        switch self {
        case .draft: "Draft"
        case .approved: "Approved"
        case .inProgress: "In Progress"
        case .waitingForReview: "Waiting for Review"
        case .done: "Done"
        case .blocked: "Blocked"
        }
    }
}
