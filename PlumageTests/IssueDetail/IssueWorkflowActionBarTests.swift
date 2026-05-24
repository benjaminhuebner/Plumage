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

    @Test("implement: approved/in-progress always; draft only for chore/spike")
    func implementEnabled() {
        for type in IssueType.allCases {
            for status in IssueStatus.allCases {
                let enabled = WorkflowAction.implement.isEnabled(status: status, type: type)
                let expected: Bool
                switch status {
                case .approved, .inProgress: expected = true
                case .draft: expected = (type == .chore || type == .spike)
                case .waitingForReview, .done, .blocked: expected = false
                }
                #expect(enabled == expected, "implement(\(status), \(type)) expected \(expected)")
            }
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
