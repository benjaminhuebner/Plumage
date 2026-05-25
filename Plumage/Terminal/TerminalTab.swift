import Foundation

@MainActor
struct TerminalTab: Identifiable {
    let id: UUID
    let session: TerminalClaudeSession
    var title: String

    init(id: UUID = UUID(), session: TerminalClaudeSession, title: String) {
        self.id = id
        self.session = session
        self.title = title
    }
}
