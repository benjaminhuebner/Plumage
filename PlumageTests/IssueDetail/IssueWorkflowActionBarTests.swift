import Testing

@testable import Plumage

@Suite("WorkflowAction.isEnabled")
struct WorkflowActionIsEnabledTests {
    @Test("plan: only enabled for draft + feature")
    func planEnabled() {
        for type in IssueType.allCases {
            for status in IssueStatus.allCases {
                let enabled = WorkflowAction.plan.isEnabled(status: status, type: type)
                let expected = (status == .draft && type == .feature)
                #expect(enabled == expected, "plan(\(status), \(type)) expected \(expected)")
            }
        }
    }

    @Test("implement: approved/in-progress always; draft for every non-feature type")
    func implementEnabled() {
        for type in IssueType.allCases {
            for status in IssueStatus.allCases {
                let enabled = WorkflowAction.implement.isEnabled(status: status, type: type)
                let expected: Bool
                switch status {
                case .approved, .inProgress: expected = true
                case .draft: expected = (type != .feature)
                case .waitingForReview, .done, .blocked: expected = false
                }
                #expect(enabled == expected, "implement(\(status), \(type)) expected \(expected)")
            }
        }
    }

    @Test("every draft issue exposes at least one enabled action")
    func draftAlwaysHasEnabledAction() {
        for type in IssueType.allCases {
            let anyEnabled = WorkflowAction.allCases.contains { action in
                action.isEnabled(status: .draft, type: type)
            }
            #expect(anyEnabled, "draft + \(type) must expose at least one action")
        }
    }

    @Test("review: only enabled for waiting-for-review")
    func reviewEnabled() {
        for type in IssueType.allCases {
            for status in IssueStatus.allCases {
                let enabled = WorkflowAction.review.isEnabled(status: status, type: type)
                let expected = (status == .waitingForReview)
                #expect(enabled == expected, "review(\(status), \(type)) expected \(expected)")
            }
        }
    }

    @Test("done and blocked disable every action")
    func terminalStatesDisableAll() {
        for status in [IssueStatus.done, .blocked] {
            for type in IssueType.allCases {
                for action in WorkflowAction.allCases {
                    #expect(
                        !action.isEnabled(status: status, type: type),
                        "\(action)(\(status), \(type)) must be disabled"
                    )
                }
            }
        }
    }
}

@Suite("WorkflowAction.slug")
struct WorkflowActionSlugTests {
    @Test("slugs match the on-disk skill folder names")
    func slugs() {
        #expect(WorkflowAction.plan.slug == "plumage-plan")
        #expect(WorkflowAction.implement.slug == "plumage-implement")
        #expect(WorkflowAction.review.slug == "plumage-review")
    }
}

@Suite("WorkflowAction.permissionMode")
struct WorkflowActionPermissionModeTests {
    @Test("maps each action to its claude --permission-mode value")
    func permissionModeMapping() {
        #expect(WorkflowAction.plan.permissionMode == .plan)
        #expect(WorkflowAction.implement.permissionMode == .acceptEdits)
        #expect(WorkflowAction.review.permissionMode == .default)
    }
}

@Suite("WorkflowAction.tabTitle")
struct WorkflowActionTabTitleTests {
    @Test("uses '<Action>: <slug>' with capitalized action")
    func tabTitleFormat() {
        #expect(WorkflowAction.plan.tabTitle(slug: "walking-skeleton") == "Plan: walking-skeleton")
        #expect(
            WorkflowAction.implement.tabTitle(slug: "00038-workflow-tabs-per-action")
                == "Implement: 00038-workflow-tabs-per-action"
        )
        #expect(WorkflowAction.review.tabTitle(slug: "foo") == "Review: foo")
    }

    @Test("slug is passed through verbatim — caller controls formatting")
    func tabTitleSlugVerbatim() {
        #expect(WorkflowAction.plan.tabTitle(slug: "") == "Plan: ")
        #expect(WorkflowAction.plan.tabTitle(slug: "weird:slug") == "Plan: weird:slug")
    }
}

@Suite("WorkflowAction.disabledTooltip")
struct WorkflowActionDisabledTooltipTests {
    @Test("done overrides every per-action tooltip")
    func doneOverride() {
        for action in WorkflowAction.allCases {
            #expect(
                action.disabledTooltip(status: .done, type: .feature)
                    == "Issue ist abgeschlossen."
            )
        }
    }

    @Test("blocked overrides every per-action tooltip")
    func blockedOverride() {
        for action in WorkflowAction.allCases {
            #expect(
                action.disabledTooltip(status: .blocked, type: .feature)
                    == "Issue ist blockiert."
            )
        }
    }

    @Test("plan tooltip surfaces non-feature draft case")
    func planNonFeatureDraft() {
        #expect(
            WorkflowAction.plan.disabledTooltip(status: .draft, type: .chore)
                .contains("Nur Feature-Issues")
        )
    }
}
