import SwiftUI

extension EnvironmentValues {
    // Injected by ProjectWindow. The view layer (IssueDetailView) calls this
    // with the issue's folderName; the implementation opens the terminal
    // inspector and feeds the workflow's resolved lines into the running
    // claude session via TerminalClaudeSession's pendingInput queue. The
    // WorkflowCommandResolver reads spec.md / prompt.md off disk, so callers
    // must flush dirty buffers first. Default is a no-op so preview/test
    // contexts work unwired.
    @Entry var runWorkflow: (WorkflowAction, String) -> Void = { _, _ in }
}
