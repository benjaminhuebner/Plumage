import Foundation
import os

nonisolated enum ImplementLaunchMode: Sendable {
    case worktree
    case wait
}

struct PendingImplementLaunch: Identifiable {
    let id = UUID()
    let slug: String
    let blocker: String
}

// The find-or-create-tab + inject sequence behind the Plan/Implement/Review
// buttons, kept out of ProjectWindow so validation, dedupe and failure
// handling are testable without a view.
@MainActor
@Observable
final class WorkflowLauncher {
    private(set) var workflowTask: Task<Void, Never>?
    private(set) var pendingImplement: PendingImplementLaunch?
    private var pendingRequest: LaunchRequest?

    // Detection and provisioning seams; production defaults talk to git and
    // the file system, tests swap in fixtures.
    var listWorktreeRoots: @MainActor (URL) async -> [URL] = { projectURL in
        let worktrees = (try? await GitWorktreeLister().worktrees(repoURL: projectURL)) ?? []
        return worktrees.isEmpty ? [projectURL] : worktrees.map(\.path)
    }
    var scanLiveRuns: @MainActor ([URL]) -> [WorktreeImplementRun] = {
        ImplementRunScanner.liveImplementRuns(acrossWorktreeRoots: $0)
    }
    var scanQueuedRuns: @MainActor (URL) -> [QueuedImplementRun] = {
        ImplementRunScanner.queuedImplementRuns(in: $0)
    }
    var provisionWorktree: @MainActor (String, URL) async throws -> WorktreeProvisionResult = {
        try await WorktreeProvisioner().provision(slug: $0, projectRoot: $1)
    }
    var runStateExists: @MainActor (URL, String) -> Bool = {
        ImplementRunScanner.runStateExists(for: $1, in: $0)
    }

    // Implement tabs whose session hasn't written run-state or a queue entry
    // yet — the file-based scan is blind for the first ~minute after launch,
    // so a second quick click would sail past the busy dialog.
    private var startingImplements: [String: UUID] = [:]

    private static let log = Logger(subsystem: "com.plumage", category: "runWorkflow")

    private struct LaunchRequest {
        let action: WorkflowAction
        let folderName: String
        let issueType: IssueType
        let projectURL: URL
        let override: WorkflowOverride?
        let lines: [String]
        let tabs: TerminalTabsModel
        let openInspector: @MainActor () -> Void
        let showBanner: @MainActor (String) -> Void
    }

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

        // Find-or-create a per-workflow tab so each Plan/Implement/Review
        // gets its own claude subprocess with the right --permission-mode and
        // leaves the main terminal free. A repeat click on the same
        // action+issue selects the existing tab without a second inject.
        if let existing = tabs.findWorkflowTab(action: action, slug: folderName) {
            openInspector()
            tabs.selectedTabID = existing.id
            return
        }

        // Resolve the template (default or per-project override) into the
        // sequence of lines that need to be injected into claude's REPL.
        // Resolving before tab creation: a template whose `#if` blocks filter
        // to empty for this issue type must not leave a dead tab behind.
        let lines = WorkflowCommandResolver.resolve(
            action: action,
            slug: folderName,
            type: issueType,
            specURL: IssueLayout.specURL(in: projectURL, folderName: folderName),
            promptURL: IssueLayout.promptURL(in: projectURL, folderName: folderName),
            override: override
        )
        guard !lines.isEmpty else {
            Self.log.info(
                "runWorkflow: template resolved to no lines for \(action.slug, privacy: .public) (type \(issueType.rawValue, privacy: .public)); not starting."
            )
            showBanner("Workflow \(action.slug) didn't start: no command for this issue type.")
            return
        }

        let request = LaunchRequest(
            action: action,
            folderName: folderName,
            issueType: issueType,
            projectURL: projectURL,
            override: override,
            lines: lines,
            tabs: tabs,
            openInspector: openInspector,
            showBanner: showBanner
        )
        if action == .implement {
            workflowTask = Task { @MainActor [weak self] in
                await self?.routeImplement(request)
            }
        } else {
            startTab(request, worktreeRoot: nil)
        }
    }

    // Implement launches are worktree-aware: a busy primary checkout (live
    // run or queued waiters) asks the user once — parallel worktree or FIFO
    // queue. The same issue live or queued anywhere is refused outright.
    private func routeImplement(_ request: LaunchRequest) async {
        let roots = await listWorktreeRoots(request.projectURL)
        if Task.isCancelled { return }
        let live = scanLiveRuns(roots)
        let queued = scanQueuedRuns(request.projectURL)
        reconcileStartingImplements(
            tabs: request.tabs, projectURL: request.projectURL, queued: queued)

        if let owner = live.first(where: { $0.run.issue == request.folderName }) {
            request.showBanner(
                "\(request.folderName) is already being implemented in \(owner.checkoutRoot.lastPathComponent)."
            )
            return
        }
        if queued.contains(where: { $0.issue == request.folderName }) {
            request.showBanner("\(request.folderName) is already waiting in the implement queue.")
            return
        }

        let primaryLive = live.first { Self.sameLocation($0.checkoutRoot, request.projectURL) }
        let starting = startingImplements.keys.first { $0 != request.folderName }
        guard primaryLive != nil || !queued.isEmpty || starting != nil else {
            startTab(request, worktreeRoot: nil)
            return
        }
        pendingRequest = request
        pendingImplement = PendingImplementLaunch(
            slug: request.folderName,
            blocker: primaryLive?.run.issue ?? starting ?? queued.first?.issue ?? "another issue"
        )
    }

    // A starting tab stops being a blocker once its run shows up in the
    // file-based scan (run-state or queue entry), or once its tab is closed.
    private func reconcileStartingImplements(
        tabs: TerminalTabsModel, projectURL: URL, queued: [QueuedImplementRun]
    ) {
        startingImplements = startingImplements.filter { slug, tabID in
            guard tabs.tabs.contains(where: { $0.id == tabID }) else { return false }
            if runStateExists(projectURL, slug) { return false }
            return !queued.contains { $0.issue == slug }
        }
    }

    func confirmPendingImplement(_ mode: ImplementLaunchMode) {
        guard let request = pendingRequest else { return }
        pendingRequest = nil
        pendingImplement = nil
        switch mode {
        case .wait:
            // A normal tab; the skill's fresh-start queue does the waiting and
            // starts the run when it is first in line.
            startTab(request, worktreeRoot: nil)
        case .worktree:
            workflowTask?.cancel()
            workflowTask = Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let result = try await self.provisionWorktree(
                        request.folderName, request.projectURL)
                    if Task.isCancelled { return }
                    request.showBanner(
                        "Implement runs in worktree \(result.worktreeRoot.path)")
                    self.startTab(request, worktreeRoot: result.worktreeRoot)
                } catch let error as WorktreeProvisionError {
                    request.showBanner(error.displayMessage)
                } catch {
                    request.showBanner("Worktree setup failed: \(error.localizedDescription)")
                }
            }
        }
    }

    func cancelPendingImplement() {
        pendingRequest = nil
        pendingImplement = nil
    }

    private func startTab(_ request: LaunchRequest, worktreeRoot: URL?) {
        request.openInspector()
        let workflowTab = request.tabs.addWorkflowTab(
            action: request.action,
            slug: request.folderName,
            type: request.issueType,
            override: request.override,
            worktreeRoot: worktreeRoot
        )
        if request.action == .implement, worktreeRoot == nil {
            startingImplements[request.folderName] = workflowTab.id
        }

        let session = workflowTab.session
        let slug = request.action.slug
        let failedTabID = workflowTab.id
        let tabs = request.tabs
        let showBanner = request.showBanner
        let lines = request.lines
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

    private static func sameLocation(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.resolvingSymlinksInPath().standardizedFileURL.path
            == rhs.resolvingSymlinksInPath().standardizedFileURL.path
    }
}
