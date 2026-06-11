import SwiftUI

extension EnvironmentValues {
    // WorkflowCommandResolver reads spec.md/prompt.md off disk, so callers must
    // flush dirty buffers first. No-op default keeps previews/tests unwired.
    @Entry var runWorkflow: (WorkflowAction, String, IssueType) -> Void = { _, _, _ in }
}
