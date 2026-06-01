import Testing

@testable import Plumage

@Suite("WorkflowAction permission mode")
struct WorkflowActionTests {
    @Test("each action maps to its built-in, model-independent permission mode")
    func permissionModeMapping() {
        #expect(WorkflowAction.plan.permissionMode == .plan)
        #expect(WorkflowAction.implement.permissionMode == .acceptEdits)
        #expect(WorkflowAction.review.permissionMode == .default)
    }
}
