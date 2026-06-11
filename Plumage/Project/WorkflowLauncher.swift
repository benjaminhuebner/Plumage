import Foundation
import os

// The find-or-create-tab + inject sequence behind the Plan/Implement/Review
// buttons, kept out of ProjectWindow so validation, dedupe and failure
// handling are testable without a view.
@MainActor
@Observable
final class WorkflowLauncher {
    private var workflowTask: Task<Void, Never>?

    private static let log = Logger(subsystem: "com.plumage", category: "runWorkflow")

    // Single in-flight workflow inject. Replacing it cancels the prior task
    // so a quick second button-press doesn't leave the prior task's body
    // enqueue stranded.
    func cancel() {
        workflowTask?.cancel()
    }

    func run(
        action: WorkflowAction,
        folderName: String,
        issueType: IssueType,
        projectURL: URL,
        override: WorkflowOverride?,
        tabs: TerminalTabsModel,
        openInspector: @escaping @MainActor () -> Void,
        showBanner: @escaping @MainActor (String) -> Void
    ) {
        // Reject folder names that would corrupt the inject: \r submits in
        // claude's REPL, \n splits, \0 is undefined. isShellSafe checks
        // exactly these three. Folder names are user-controlled via Finder
        // rename, so this is a real attack surface, not just defense in depth.
        guard TerminalClaudeSession.isShellSafe(folderName) else {
            Self.log.warning(
                "runWorkflow: refusing inject for \(action.slug, privacy: .public) — folderName contains control chars."
            )
            showBanner("Can't run workflow: issue folder name contains control characters.")
            return
        }

        workflowTask?.cancel()
        openInspector()

        // Find-or-create a per-workflow tab so each Plan/Implement/Review
        // gets its own claude subprocess with the right --permission-mode and
        // leaves the main terminal free. Title match is exact ("<Action>:
        // <slug>"); a repeat click on the same action+issue selects the
        // existing tab without a second inject.
        if let existing = tabs.findWorkflowTab(action: action, slug: folderName) {
            tabs.selectedTabID = existing.id
            return
        }
        let workflowTab = tabs.addWorkflowTab(
            action: action,
            slug: folderName,
            type: issueType,
            override: override
        )

        // Resolve the template (default or per-project override) into the
        // sequence of lines that need to be injected into claude's REPL.
        let lines = WorkflowCommandResolver.resolve(
            action: action,
            slug: folderName,
            specURL: IssueLayout.specURL(in: projectURL, folderName: folderName),
            promptURL: IssueLayout.promptURL(in: projectURL, folderName: folderName),
            override: override
        )
        guard !lines.isEmpty else { return }

        let session = workflowTab.session
        let slug = action.slug
        let failedTabID = workflowTab.id
        workflowTask = Task { @MainActor in
            let result = await session.injectCommands(lines)
            switch result {
            case .sessionExited:
                Self.log.info(
                    "runWorkflow: session exited mid-inject for \(slug, privacy: .public)."
                )
                // Close the dead tab: find-or-create would keep returning it,
                // silently blocking every retry of this action+issue.
                tabs.closeTab(id: failedTabID)
                showBanner(
                    "Workflow \(slug) didn't start: claude exited during launch. Try again.")
            case .timedOut:
                Self.log.warning(
                    "runWorkflow: session never reached .running within 5s; abort inject for \(slug, privacy: .public)."
                )
                tabs.closeTab(id: failedTabID)
                showBanner(
                    "Workflow \(slug) didn't start: claude wasn't ready within 5s. Try again.")
            case .injected, .cancelled:
                break
            }
        }
    }
}
