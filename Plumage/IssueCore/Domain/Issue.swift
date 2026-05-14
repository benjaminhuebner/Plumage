import Foundation

nonisolated struct Issue: Hashable, Sendable {
    let id: Int
    let folderName: String
    let title: String
    let type: IssueType
    let status: IssueStatus
    let created: Date
    let updated: Date
    let branch: String
    let labels: [String]
    let model: String?
    let goal: String?

    init(
        id: Int,
        folderName: String,
        title: String,
        type: IssueType,
        status: IssueStatus,
        created: Date,
        updated: Date,
        branch: String,
        labels: [String],
        model: String?,
        goal: String? = nil
    ) {
        self.id = id
        self.folderName = folderName
        self.title = title
        self.type = type
        self.status = status
        self.created = created
        self.updated = updated
        self.branch = branch
        self.labels = labels
        self.model = model
        self.goal = goal
    }
}
