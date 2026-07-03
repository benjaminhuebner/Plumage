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
                    == "Issue is done."
            )
        }
    }

    @Test("blocked overrides every per-action tooltip")
    func blockedOverride() {
        for action in WorkflowAction.allCases {
            #expect(
                action.disabledTooltip(status: .blocked, type: .feature)
                    == "Issue is blocked."
            )
        }
    }

    @Test("plan tooltip surfaces non-feature draft case")
    func planNonFeatureDraft() {
        #expect(
            WorkflowAction.plan.disabledTooltip(status: .draft, type: .chore)
                .contains("Only feature issues")
        )
    }

    @Test("plan tooltip falls back to the 'already approved' line outside non-feature draft")
    func planAlreadyApprovedFallback() {
        #expect(
            WorkflowAction.plan.disabledTooltip(status: .approved, type: .feature)
                == "Issue is already approved or further along."
        )
    }

    @Test("implement tooltip pins the must-be-planned-first copy")
    func implementMustBePlanned() {
        #expect(
            WorkflowAction.implement.disabledTooltip(status: .draft, type: .feature)
                == "Issue must be planned first (Plan button)."
        )
    }

    @Test("review tooltip pins the not-yet-implemented copy")
    func reviewNotYetImplemented() {
        #expect(
            WorkflowAction.review.disabledTooltip(status: .inProgress, type: .feature)
                == "Issue is not yet implemented."
        )
    }
}

@Suite("WorkflowAction.available")
struct WorkflowActionAvailableTests {
    @Test("at most one action is enabled for every status and type combination")
    func atMostOneEnabled() {
        for status in IssueStatus.allCases {
            for type in IssueType.allCases {
                let enabled = WorkflowAction.allCases.filter {
                    $0.isEnabled(status: status, type: type)
                }
                #expect(enabled.count <= 1, "\(status)+\(type) enables \(enabled)")
                #expect(WorkflowAction.available(status: status, type: type) == enabled.first)
            }
        }
    }

    @Test("maps statuses to the expected card action")
    func expectedMapping() {
        #expect(WorkflowAction.available(status: .draft, type: .feature) == .plan)
        #expect(WorkflowAction.available(status: .draft, type: .chore) == .implement)
        #expect(WorkflowAction.available(status: .approved, type: .feature) == .implement)
        #expect(WorkflowAction.available(status: .inProgress, type: .feature) == .implement)
        #expect(WorkflowAction.available(status: .waitingForReview, type: .feature) == .review)
        #expect(WorkflowAction.available(status: .done, type: .feature) == nil)
        #expect(WorkflowAction.available(status: .blocked, type: .feature) == nil)
    }
}

@Suite("IssueWorkflowActionBar.blockedWarning")
struct BlockedWarningTests {
    private let open = ResolvedBlocker(
        folderName: "00042-auth", state: .open, id: 42, title: "User auth")

    @Test("implement with open blockers names them by padded id")
    func implementWarns() {
        let warning = IssueWorkflowActionBar.blockedWarning(for: .implement, openBlockers: [open])
        #expect(warning == "Blocked by #00042 — still open.")
    }

    @Test("multiple blockers are comma-joined")
    func multipleBlockers() {
        let second = ResolvedBlocker(folderName: "00043-api", state: .open, id: 43, title: "API")
        let warning = IssueWorkflowActionBar.blockedWarning(
            for: .implement, openBlockers: [open, second])
        #expect(warning == "Blocked by #00042, #00043 — still open.")
    }

    @Test("blocker without id falls back to the folder name")
    func invalidBlockerFallsBackToFolder() {
        let broken = ResolvedBlocker(folderName: "00005-broken", state: .open, id: nil, title: nil)
        let warning = IssueWorkflowActionBar.blockedWarning(for: .implement, openBlockers: [broken])
        #expect(warning == "Blocked by 00005-broken — still open.")
    }

    @Test("no open blockers yields no warning")
    func noBlockersNoWarning() {
        #expect(IssueWorkflowActionBar.blockedWarning(for: .implement, openBlockers: []) == nil)
    }

    @Test(
        "only implement warns",
        arguments: [WorkflowAction.plan, WorkflowAction.review]
    )
    func otherActionsStaySilent(action: WorkflowAction) {
        #expect(IssueWorkflowActionBar.blockedWarning(for: action, openBlockers: [open]) == nil)
    }
}
