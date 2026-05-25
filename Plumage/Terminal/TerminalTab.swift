import Foundation

@MainActor
struct TerminalTab: Identifiable {
    let id: UUID
    let session: TerminalClaudeSession
    var title: String
    // Workflow tabs carry a user-meaningful title ("Plan: <slug>") that must
    // survive closeTab's reindex. Generic tabs get their title from the
    // running index ("Terminal N") and are safe to overwrite.
    let isWorkflow: Bool

    init(
        id: UUID = UUID(),
        session: TerminalClaudeSession,
        title: String,
        isWorkflow: Bool = false
    ) {
        self.id = id
        self.session = session
        self.title = title
        self.isWorkflow = isWorkflow
    }
}
