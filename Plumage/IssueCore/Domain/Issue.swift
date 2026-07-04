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
    let blockedBy: [String]
    let mergeSubject: String?
    let order: Double?
    let goal: String?
    // Cross-ref only — never a Plumage id or a sort/identity key.
    let github: Int?
    // Fingerprint of the sibling evidence.json, set during discovery — makes
    // snapshot equality notice evidence-only changes the spec text can't show.
    var evidenceStamp: String?

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
        blockedBy: [String] = [],
        mergeSubject: String? = nil,
        order: Double? = nil,
        goal: String? = nil,
        github: Int? = nil
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
        self.blockedBy = blockedBy
        self.mergeSubject = mergeSubject
        self.order = order
        self.goal = goal
        self.github = github
    }

    // Copy for status/order patches that must keep every other field —
    // rebuilding via the initializer silently dropped blockedBy, mergeSubject,
    // and evidenceStamp (a var outside the initializer) at the drop sites.
    func with(status: IssueStatus, order: Double?, updated: Date) -> Issue {
        var copy = Issue(
            id: id,
            folderName: folderName,
            title: title,
            type: type,
            status: status,
            created: created,
            updated: updated,
            branch: branch,
            labels: labels,
            blockedBy: blockedBy,
            mergeSubject: mergeSubject,
            order: order,
            goal: goal,
            github: github
        )
        copy.evidenceStamp = evidenceStamp
        return copy
    }
}
