import SwiftUI

extension EnvironmentValues {
    // WorkflowCommandResolver reads spec.md/prompt.md off disk, so callers must
    // flush dirty buffers first. No-op default keeps previews/tests unwired.
    @Entry var runWorkflow: (WorkflowAction, String, IssueType) -> Void = { _, _, _ in }
    // True when the action's command template filters to nothing for the type
    // (`#if` blocks). Default false keeps previews/tests enabled.
    @Entry var workflowCommandIsEmpty: (WorkflowAction, IssueType) -> Bool = { _, _ in false }
    // Jump-only: selects an existing workflow tab, never launches a run.
    @Entry var jumpToRunTerminal: (String) -> Void = { _ in }
}
