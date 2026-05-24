import SwiftUI

extension EnvironmentValues {
    // Injected by ProjectWindow. The view layer (IssueDetailView) calls this
    // with the issue's folderName and optional spec body; the implementation
    // opens the terminal inspector and feeds the matching slash command into
    // the running claude session via TerminalClaudeSession's pendingInput
    // queue. Default is a no-op so preview/test contexts work unwired.
    @Entry var runWorkflow: (WorkflowAction, String, String?) -> Void = { _, _, _ in }
}
