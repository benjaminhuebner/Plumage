import AppKit
import Foundation
import SwiftUI
import os

@MainActor
@Observable
final class IssueDetailModel {
    enum ConflictState: Equatable {
        case externalChange(diskContent: String)
        case fileDeleted
    }

    enum LoadState: Equatable {
        case idle
        case loaded
        case failed(String)
    }

    enum SaveError: Error, Equatable {
        case unresolvedConflict
        case emptyTitle
    }

    enum Kind: Equatable, Sendable {
        case creating(initialStatus: IssueStatus)
        case loaded(folderName: String)
    }

    enum AutoSaveStatus: Equatable, Sendable {
        case idle
        case saving
        case saved
        case error(message: String)
    }

    private static let logger = Logger(subsystem: "com.plumage", category: "IssueDetailModel")

    private(set) var kind: Kind
    private(set) var specURL: URL?
    let projectURL: URL?

    var folderName: String? {
        switch kind {
        case .creating: nil
        case .loaded(let folderName): folderName
        }
    }

    // Drafts used in creating mode. In loaded mode the existing form-commit
    // path writes directly through to disk and these stay untouched.
    var titleDraft: String = ""
    var typeDraft: IssueType = .feature
    var statusDraft: IssueStatus = .draft
    var labelsDraft: [String] = []
    var blockedByDraft: [String] = []

    private(set) var issue: Issue?
    private(set) var loadState: LoadState = .idle
    private(set) var autoSaveStatus: AutoSaveStatus = .idle
    private(set) var loadedSpecContent: String = ""
    private(set) var loadedBodyContent: String = ""
    var bodyDraft: String = ""
    private(set) var loadedPromptContent: String = ""
    var promptDraft: String = ""
    private(set) var prContent: String?
    // Pre-parsed PR.md blocks so PRTabView renders without re-parsing on every
    // body evaluation. Populated together with prContent in loadPR().
    private(set) var prBlocks: [PRMarkdownParser.Block] = []
    private(set) var evidence: EvidenceState = .missing
    private(set) var evidenceIsStale: Bool = false
    private(set) var runHistory: RunHistoryReader.Page = .empty
    private(set) var doneWhenCriteria: [DoneWhenCriterion] = []
    var selectedBodyTab: BodyTab = .spec
    private(set) var conflict: ConflictState?
    private(set) var frontmatterError: FrontmatterError?
    private(set) var lastWrittenContent: String?
    private(set) var lastSeenIssue: DiscoveredIssue?
    private(set) var isMerging: Bool = false
    private(set) var isRequestingChanges: Bool = false
    private(set) var lastRequestChangesError: String?
    // Live implement run owning this checkout — merging would switch the
    // run's branch underneath it, so the UI disables merge while set.
    private(set) var blockingImplementRun: LiveImplementRun?
    private(set) var lastMergeError: GitMergeError?
    // Survives the error banner's dismiss: the branch stays diverged until a
    // rebase or merge succeeds, so the recovery action must outlive the banner.
    private(set) var rebaseRecoveryAvailable = false
    // Set when the merge wrote to disk but the spec-status flip failed afterwards —
    // surfaced as a critical banner so the user knows to fix spec.md manually.
    // Distinct from lastMergeError because the git side already succeeded.
    private(set) var lastMergeCriticalError: String?
    // Non-fatal info after a successful merge — e.g. the branch delete
    // failed but the merge itself landed.
    private(set) var lastMergeNotice: String?
    private(set) var mergeTargets: [String] = []
    var selectedMergeTarget: String?

    // Single tail-chain for every spec.md write (form commits, body saves,
    // done-when toggles): each writer awaits the prior one, so two
    // read-transform-write passes can never interleave and lose a mutation.
    private var pendingSpecWrite: Task<Void, Error>?
    private var pendingPromptSave: Task<Void, Error>?
    private var observeTask: Task<Void, Never>?

    // Writes go through saveBody()/savePrompt() so their in-flight
    // serialization and the external-change conflict guard still hold.
    static let autoSaveDebounce: Duration = .milliseconds(500)
    private var pendingAutoSave: Task<Void, Never>?

    // Cancels the in-flight save chain and kanban observation so state mutations
    // that would land on a popped view stop firing. The inner synchronous mutator
    // has no cancellation point — an in-progress disk write still completes (autosave semantics).
    func cancelPendingWork() {
        pendingSpecWrite?.cancel()
        pendingSpecWrite = nil
        pendingPromptSave?.cancel()
        pendingPromptSave = nil
        pendingAutoSave?.cancel()
        pendingAutoSave = nil
        observeTask?.cancel()
        observeTask = nil
    }

    private static let preloadByteCap = 64 * 1024

    private nonisolated let allocator: IssueAllocating?
    private nonisolated let writer: SpecWriting
    private nonisolated let mutator: FrontmatterMutating
    private nonisolated let mergeRunner: any GitMergeRunning
    private nonisolated let liveRunChecker: @Sendable (URL) -> LiveImplementRun?
    private nonisolated let mergedIssueRunLocator: @Sendable (URL, String) async -> String?
    private nonisolated let configLoader: @Sendable (URL) -> ProjectConfig?
    private nonisolated let clock: @Sendable () -> Date
    private nonisolated let discoverer: @Sendable (URL) -> [DiscoveredIssue]
    private nonisolated let evidenceCommitCounter: @Sendable (URL, String, String) async -> Int?
    private nonisolated let localBranchLister: @Sendable (URL) async -> [String]
    private nonisolated let storedMergeTargetLoader: @Sendable (URL) -> String?
    private nonisolated let storedMergeTargetSaver: @Sendable (URL, String) -> Void
    private nonisolated let mergedDiffCapturer: @Sendable (URL, String, String) async -> String?
    private nonisolated let mergedDiffWriter: @Sendable (URL, String) -> Void

    var isBodyDirty: Bool { bodyDraft != loadedBodyContent }

    var isCreating: Bool {
        if case .creating = kind { true } else { false }
    }

    var canSaveInCreatingMode: Bool {
        isCreating && !titleDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // A tiny synchronous config.json read — startDiffTab needs the base now,
    // not via an async hop.
    var gitDefaultBranch: String {
        guard let projectURL else { return "main" }
        return configLoader(projectURL)?.gitDefaultBranch ?? "main"
    }

    init(
        specURL: URL,
        folderName: String,
        projectURL: URL? = nil,
        allocator: IssueAllocating? = nil,
        writer: SpecWriting = DefaultSpecWriter(),
        mutator: FrontmatterMutating = DefaultFrontmatterMutator(),
        mergeRunner: any GitMergeRunning = GitMergeRunner(),
        liveRunChecker: @escaping @Sendable (URL) -> LiveImplementRun? = {
            ImplementRunScanner.liveImplementRun(in: $0)
        },
        mergedIssueRunLocator: @escaping @Sendable (URL, String) async -> String? = {
            await IssueDetailModel.locateIssueRun(projectURL: $0, folderName: $1)
        },
        configLoader: @escaping @Sendable (URL) -> ProjectConfig? = {
            try? ConfigLoader.load(at: $0)
        },
        clock: @escaping @Sendable () -> Date = { Date() },
        discoverer: @escaping @Sendable (URL) -> [DiscoveredIssue] = {
            IssueDiscovery.discoverIssues(in: $0)
        },
        evidenceCommitCounter: @escaping @Sendable (URL, String, String) async -> Int? = {
            try? await GitRevListRunner().countCommits(repoURL: $0, from: $1, to: $2)
        },
        localBranchLister: @escaping @Sendable (URL) async -> [String] = {
            (try? await GitBranchLister().branches(repoURL: $0)) ?? []
        },
        storedMergeTargetLoader: @escaping @Sendable (URL) -> String? = {
            guard let bundle = try? BundleResolver.resolve(from: $0).bundle else { return nil }
            return MergeTargetStore.load(bundle: bundle)
        },
        storedMergeTargetSaver: @escaping @Sendable (URL, String) -> Void = {
            guard let bundle = try? BundleResolver.resolve(from: $0).bundle else { return }
            try? MergeTargetStore.save($1, bundle: bundle)
        },
        mergedDiffCapturer: @escaping @Sendable (URL, String, String) async -> String? = {
            repoURL, base, tip in
            try? await GitDiffRunner(runner: ProductionGitProcessRunner())
                .run(repoURL: repoURL, base: base, tip: tip)
        },
        mergedDiffWriter: @escaping @Sendable (URL, String) -> Void = { url, text in
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    ) {
        self.kind = .loaded(folderName: folderName)
        self.specURL = specURL
        self.projectURL = projectURL
        self.allocator = allocator
        self.writer = writer
        self.mutator = mutator
        self.mergeRunner = mergeRunner
        self.liveRunChecker = liveRunChecker
        self.mergedIssueRunLocator = mergedIssueRunLocator
        self.configLoader = configLoader
        self.clock = clock
        self.discoverer = discoverer
        self.evidenceCommitCounter = evidenceCommitCounter
        self.localBranchLister = localBranchLister
        self.storedMergeTargetLoader = storedMergeTargetLoader
        self.storedMergeTargetSaver = storedMergeTargetSaver
        self.mergedDiffCapturer = mergedDiffCapturer
        self.mergedDiffWriter = mergedDiffWriter
        // Pre-load synchronously so first mount renders without a ProgressView
        // flash. Local volumes only — even the stat can stall on a network mount;
        // remote specs take async load(). 64 KB cap so a pathological spec can't stall construction.
        if Self.volumeIsLocal(specURL),
            let attrs = try? FileManager.default.attributesOfItem(atPath: specURL.path),
            let size = attrs[.size] as? Int, size <= Self.preloadByteCap,
            let content = try? String(contentsOf: specURL, encoding: .utf8)
        {
            applyLoaded(content: content)
            // Status is known before the first frame, so the status-driven
            // tab must be too — deferring it to the async load path flashed
            // the spec tab before snapping to the pull-request tab.
            if let issue {
                selectedBodyTab = Self.defaultTab(for: issue.status)
            }
        }
    }

    private nonisolated static func volumeIsLocal(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.volumeIsLocalKey])
        return values?.volumeIsLocal ?? false
    }

    nonisolated static func locateIssueRun(projectURL: URL, folderName: String) async -> String? {
        let worktrees = (try? await GitWorktreeLister().worktrees(repoURL: projectURL)) ?? []
        let roots = worktrees.isEmpty ? [projectURL] : worktrees.map(\.path)
        if let owner = ImplementRunScanner.liveImplementRuns(acrossWorktreeRoots: roots)
            .first(where: { $0.run.issue == folderName })
        {
            return "active in \(owner.checkoutRoot.lastPathComponent)"
        }
        if ImplementRunScanner.queuedImplementRuns(in: projectURL)
            .contains(where: { $0.issue == folderName })
        {
            return "queued in this checkout"
        }
        return nil
    }

    // Safety net for abnormal teardown paths where .onDisappear is skipped.
    // Primary cleanup remains the view's .onDisappear → cancelPendingWork.
    // isolated deinit (Swift 6.2) so we can touch the @MainActor state.
    isolated deinit {
        pendingSpecWrite?.cancel()
        pendingPromptSave?.cancel()
        pendingAutoSave?.cancel()
        observeTask?.cancel()
    }

    init(
        creatingInitialStatus: IssueStatus,
        projectURL: URL,
        allocator: IssueAllocating? = nil,
        writer: SpecWriting = DefaultSpecWriter(),
        mutator: FrontmatterMutating = DefaultFrontmatterMutator(),
        mergeRunner: any GitMergeRunning = GitMergeRunner(),
        liveRunChecker: @escaping @Sendable (URL) -> LiveImplementRun? = {
            ImplementRunScanner.liveImplementRun(in: $0)
        },
        mergedIssueRunLocator: @escaping @Sendable (URL, String) async -> String? = {
            await IssueDetailModel.locateIssueRun(projectURL: $0, folderName: $1)
        },
        configLoader: @escaping @Sendable (URL) -> ProjectConfig? = {
            try? ConfigLoader.load(at: $0)
        },
        clock: @escaping @Sendable () -> Date = { Date() },
        discoverer: @escaping @Sendable (URL) -> [DiscoveredIssue] = {
            IssueDiscovery.discoverIssues(in: $0)
        },
        evidenceCommitCounter: @escaping @Sendable (URL, String, String) async -> Int? = {
            try? await GitRevListRunner().countCommits(repoURL: $0, from: $1, to: $2)
        },
        localBranchLister: @escaping @Sendable (URL) async -> [String] = {
            (try? await GitBranchLister().branches(repoURL: $0)) ?? []
        },
        storedMergeTargetLoader: @escaping @Sendable (URL) -> String? = {
            guard let bundle = try? BundleResolver.resolve(from: $0).bundle else { return nil }
            return MergeTargetStore.load(bundle: bundle)
        },
        storedMergeTargetSaver: @escaping @Sendable (URL, String) -> Void = {
            guard let bundle = try? BundleResolver.resolve(from: $0).bundle else { return }
            try? MergeTargetStore.save($1, bundle: bundle)
        },
        mergedDiffCapturer: @escaping @Sendable (URL, String, String) async -> String? = {
            repoURL, base, tip in
            try? await GitDiffRunner(runner: ProductionGitProcessRunner())
                .run(repoURL: repoURL, base: base, tip: tip)
        },
        mergedDiffWriter: @escaping @Sendable (URL, String) -> Void = { url, text in
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    ) {
        self.kind = .creating(initialStatus: creatingInitialStatus)
        self.specURL = nil
        self.projectURL = projectURL
        self.allocator = allocator ?? DefaultIssueAllocator(projectURL: projectURL)
        self.writer = writer
        self.mutator = mutator
        self.mergeRunner = mergeRunner
        self.liveRunChecker = liveRunChecker
        self.mergedIssueRunLocator = mergedIssueRunLocator
        self.configLoader = configLoader
        self.clock = clock
        self.discoverer = discoverer
        self.evidenceCommitCounter = evidenceCommitCounter
        self.localBranchLister = localBranchLister
        self.storedMergeTargetLoader = storedMergeTargetLoader
        self.storedMergeTargetSaver = storedMergeTargetSaver
        self.mergedDiffCapturer = mergedDiffCapturer
        self.mergedDiffWriter = mergedDiffWriter
        self.statusDraft = creatingInitialStatus
        // In creating mode the form must render immediately — there is
        // nothing on disk to load. Mark loaded so the view skips the
        // ProgressView path.
        self.loadState = .loaded
    }

    private func noteSeenIssue(_ issue: DiscoveredIssue?) {
        lastSeenIssue = issue
    }

    func load() async {
        guard let url = specURL else { return }
        let folder = folderName ?? ""
        let parsed: ParsedSpec
        do {
            parsed = try await Task.detached(priority: .userInitiated) {
                let raw = try String(contentsOf: url, encoding: .utf8)
                return Self.parseSpec(rawContent: raw, folderName: folder)
            }.value
        } catch {
            loadState = .failed(error.localizedDescription)
            return
        }
        apply(parsed, keepBodyDraft: false)
    }

    nonisolated struct ParsedSpec: Sendable {
        let content: String
        let body: String
        let criteria: [DoneWhenCriterion]
        let result: Result<Issue, FrontmatterError>
    }

    // Normalizes CRLF for parser predictability; SpecWriter still writes
    // back the raw normalized content, so first save flips line endings
    // exactly once on Windows-tooled inputs.
    private nonisolated static func parseSpec(rawContent: String, folderName: String) -> ParsedSpec {
        let content = rawContent.replacingOccurrences(of: "\r\n", with: "\n")
        return ParsedSpec(
            content: content,
            body: SpecParser.extractBody(from: content),
            criteria: DoneWhenParser.criteria(in: content),
            result: SpecParser.parse(content: content, folderName: folderName)
        )
    }

    private func applyLoaded(content raw: String) {
        apply(Self.parseSpec(rawContent: raw, folderName: folderName ?? ""), keepBodyDraft: false)
    }

    // Every assignment is change-guarded: @Observable invalidates readers on
    // every set even when the value is identical, and this runs after each
    // 500 ms auto-save — unguarded sets made the spec editor stutter while typing.
    private func apply(_ parsed: ParsedSpec, keepBodyDraft: Bool) {
        if loadedSpecContent != parsed.content { loadedSpecContent = parsed.content }
        if loadedBodyContent != parsed.body { loadedBodyContent = parsed.body }
        if !keepBodyDraft, bodyDraft != parsed.body { bodyDraft = parsed.body }
        if doneWhenCriteria != parsed.criteria { doneWhenCriteria = parsed.criteria }
        switch parsed.result {
        case .success(let parsedIssue):
            if issue != parsedIssue { issue = parsedIssue }
            // Mirror parsed values into drafts so the view can read the same
            // sources of truth in both modes (creating uses drafts directly,
            // loaded uses drafts that are kept in sync with disk).
            if titleDraft != parsedIssue.title { titleDraft = parsedIssue.title }
            if typeDraft != parsedIssue.type { typeDraft = parsedIssue.type }
            if statusDraft != parsedIssue.status { statusDraft = parsedIssue.status }
            if labelsDraft != parsedIssue.labels { labelsDraft = parsedIssue.labels }
            if blockedByDraft != parsedIssue.blockedBy { blockedByDraft = parsedIssue.blockedBy }
            if frontmatterError != nil { frontmatterError = nil }
        case .failure(let error):
            if issue != nil { issue = nil }
            if frontmatterError != error { frontmatterError = error }
        }
        if loadState != .loaded { loadState = .loaded }
    }

    var mergeSubjectPrefill: String {
        guard let issue else { return "" }
        return issue.mergeSubject ?? issue.title
    }

    func mergeToTarget(mode: GitMergeMode, commitSubject: String?, deleteBranch: Bool) async -> Bool {
        isMerging = true
        defer { isMerging = false }
        guard let context = await prepareMerge(mode: mode, commitSubject: commitSubject) else {
            return false
        }
        return await executeMerge(context, mode: mode, deleteBranch: deleteBranch)
    }

    private struct MergeContext {
        let projectURL: URL
        let specURL: URL
        let issue: Issue
        let subject: String?
        let targetBranch: String
    }

    // Shared preamble of mergeToTarget and rebaseAndMergeToTarget: validation,
    // error reset, live-run blocker check, and target resolution run exactly
    // once per attempt — the rebase path must not re-run them for its merge.
    private func prepareMerge(mode: GitMergeMode, commitSubject: String?) async -> MergeContext? {
        guard
            let projectURL,
            let specURL,
            let currentIssue = issue
        else { return nil }

        let subject = commitSubject?.trimmingCharacters(in: .whitespacesAndNewlines)
        if mode == .squash, subject?.isEmpty != false {
            return nil
        }

        lastMergeError = nil
        lastMergeCriticalError = nil
        lastMergeNotice = nil

        if let blocked = await blockingLiveRun(projectURL: projectURL) {
            lastMergeError = blocked
            return nil
        }

        let targetBranch = await resolveMergeTarget(
            projectURL: projectURL, issueBranch: currentIssue.branch)
        return MergeContext(
            projectURL: projectURL,
            specURL: specURL,
            issue: currentIssue,
            subject: subject,
            targetBranch: targetBranch
        )
    }

    func loadMergeTargets() async {
        guard let projectURL, let currentIssue = issue else { return }
        let candidates = await localBranchLister(projectURL).filter { $0 != currentIssue.branch }
        mergeTargets = candidates
        if let selected = selectedMergeTarget, candidates.contains(selected) { return }
        selectedMergeTarget = await resolveMergeTarget(
            projectURL: projectURL, issueBranch: currentIssue.branch)
    }

    // A stored target that was deleted (or names the source) falls back to
    // the repo default instead of failing the merge.
    private func resolveMergeTarget(projectURL: URL, issueBranch: String) async -> String {
        if let selected = selectedMergeTarget { return selected }
        let branches = await localBranchLister(projectURL)
        let candidates = branches.filter { $0 != issueBranch }
        let storedLoader = storedMergeTargetLoader
        let loader = configLoader
        let (stored, fallback) = await Task.detached {
            (storedLoader(projectURL), loader(projectURL)?.gitDefaultBranch ?? "main")
        }.value
        if let stored, candidates.contains(stored) { return stored }
        return fallback
    }

    private func executeMerge(
        _ context: MergeContext, mode: GitMergeMode, deleteBranch: Bool
    ) async -> Bool {
        let runner = mergeRunner
        let issueBranch = context.issue.branch
        let mutatorFn = mutator
        let now = clock()
        let specURL = context.specURL

        // Read the branch's committed contribution now — mergeIssueBranch may
        // delete the branch, so a post-merge diff would have nothing to diff.
        let snapshotText = await mergedDiffCapturer(
            context.projectURL, gitDefaultBranch, issueBranch)

        let outcome: GitMergeOutcome
        do {
            outcome = try await runner.mergeIssueBranch(
                repoURL: context.projectURL,
                targetBranch: context.targetBranch,
                issueBranch: issueBranch,
                mode: mode,
                commitSubject: context.subject,
                deleteBranch: deleteBranch
            )
        } catch let error as GitMergeError {
            lastMergeError = error
            if case .notFastForward = error { rebaseRecoveryAvailable = true }
            return false
        } catch {
            // Wrap unknown runner errors into a generic .mergeFailed so the
            // banner still has something to render.
            lastMergeError = .mergeFailed(mode: mode, stderr: error.localizedDescription)
            return false
        }

        // Merge landed: freeze the captured diff so the tab survives the
        // branch's deletion. Best-effort — a write failure never fails a merge.
        if let snapshotText, let folder = folderName {
            mergedDiffWriter(
                IssueLayout.mergedDiffURL(in: context.projectURL, folderName: folder),
                snapshotText)
        }

        let saver = storedMergeTargetSaver
        let mergedProjectURL = context.projectURL
        let mergedTarget = context.targetBranch
        await Task.detached { saver(mergedProjectURL, mergedTarget) }.value

        // Merge has landed on disk. From here on, any failure is critical —
        // we cannot roll back the merge, so the user has to fix spec.md
        // manually via the banner instruction.
        let doneOrder = await topEntryOrder(movingTo: .done, for: context.issue)
        do {
            try await Task.detached(priority: .userInitiated) {
                try mutatorFn.mutate(
                    specURL: specURL,
                    mutation: FrontmatterMutation(status: .set(.done), order: doneOrder),
                    now: now
                )
            }.value
        } catch {
            lastMergeCriticalError =
                "Merge landed on disk, but spec status flip failed: "
                + "\(error.localizedDescription). Edit spec.md manually to flip status to done."
            return false
        }

        if let cleanupNotice = outcome.worktreeCleanupNotice {
            lastMergeNotice = "Merge succeeded, but \(cleanupNotice)."
        } else if let deleteErr = outcome.branchDeleteError {
            lastMergeNotice = "Merge succeeded, but branch was not deleted: \(deleteErr)"
        }
        rebaseRecoveryAvailable = false
        await reloadFromDiskAfterOwnWrite()
        return true
    }

    // Merging (or rebasing) moves branches underneath a live implement run,
    // so both entry points refuse while one owns the checkout. Racy by
    // design — a run starting after this check is accepted.
    private func blockingLiveRun(projectURL: URL) async -> GitMergeError? {
        let checker = liveRunChecker
        let liveRun = await Task.detached(priority: .userInitiated) {
            checker(projectURL)
        }.value
        blockingImplementRun = liveRun
        if let liveRun {
            return .implementRunActive(issue: liveRun.issue)
        }
        // The merged issue's own run may live outside the primary checkout:
        // active in a parallel worktree, or still waiting in the queue.
        if let folder = folderName,
            let location = await mergedIssueRunLocator(projectURL, folder)
        {
            return .mergedIssueRunActive(issue: folder, location: location)
        }
        return nil
    }

    func rebaseAndMergeToTarget(
        mode: GitMergeMode, commitSubject: String?, deleteBranch: Bool
    ) async -> Bool {
        isMerging = true
        defer { isMerging = false }
        guard let context = await prepareMerge(mode: mode, commitSubject: commitSubject) else {
            return false
        }

        let runner = mergeRunner
        do {
            try await runner.rebaseIssueBranch(
                repoURL: context.projectURL,
                targetBranch: context.targetBranch,
                issueBranch: context.issue.branch)
        } catch let error as GitMergeError {
            lastMergeError = error
            return false
        } catch {
            lastMergeError = .rebaseFailed(stderr: error.localizedDescription)
            return false
        }
        return await executeMerge(context, mode: mode, deleteBranch: deleteBranch)
    }

    func refreshMergeBlocker() async {
        guard let projectURL else { return }
        let checker = liveRunChecker
        blockingImplementRun = await Task.detached(priority: .utility) {
            checker(projectURL)
        }.value
    }

    func clearMergeError() {
        lastMergeError = nil
    }

    func clearMergeCriticalError() {
        lastMergeCriticalError = nil
    }

    func clearMergeNotice() {
        lastMergeNotice = nil
    }

    func commitTitle(_ newTitle: String) async throws {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let current = issue, current.title != trimmed else { return }
        try await runFormWrite(FrontmatterMutation(title: .set(trimmed)))
    }

    func commitType(_ newType: IssueType) async throws {
        guard let current = issue, current.type != newType else { return }
        try await runFormWrite(FrontmatterMutation(type: .set(newType)))
    }

    func commitStatus(_ newStatus: IssueStatus) async throws {
        guard let current = issue, current.status != newStatus else { return }
        let order = await topEntryOrder(movingTo: newStatus, for: current)
        try await runFormWrite(FrontmatterMutation(status: .set(newStatus), order: order))
    }

    // .keep inside the same column so manual ordering survives a
    // draft→approved flip; on column entry the card goes top, .set(nil)
    // clears a stale order in an empty column (ID fallback takes over).
    private func topEntryOrder(
        movingTo newStatus: IssueStatus, for current: Issue
    ) async -> SetValue<Double?> {
        guard let projectURL, newStatus.column != current.column else { return .keep }
        let discoverer = self.discoverer
        let targetColumn = newStatus.column
        let folderName = current.folderName
        let columnItems = await Task.detached(priority: .userInitiated) {
            discoverer(projectURL).filter { $0.column == targetColumn }
        }.value
        return .set(IssueSortKey.topOrder(in: columnItems, excludingFolderName: folderName))
    }

    func commitLabels(_ newLabels: [String]) async throws {
        guard let current = issue, current.labels != newLabels else { return }
        try await runFormWrite(FrontmatterMutation(labels: .set(newLabels)))
    }

    func commitBlockedBy(_ newBlockedBy: [String]) async throws {
        guard let current = issue, current.blockedBy != newBlockedBy else { return }
        try await runFormWrite(FrontmatterMutation(blockedBy: .set(newBlockedBy)))
    }

    // Ordering is the contract: tasks land in the spec before the status
    // flips, and the caller marks findings sent only after both succeeded —
    // a failure at any step leaves the findings open, never half-sent.
    func requestChanges(taskTexts: [String]) async -> Bool {
        guard !taskTexts.isEmpty, let url = specURL else { return false }
        isRequestingChanges = true
        defer { isRequestingChanges = false }
        lastRequestChangesError = nil
        do {
            try await Task.detached(priority: .userInitiated) {
                try SpecTaskAppender.appendReviewFixTasks(specURL: url, taskTexts: taskTexts)
            }.value
            try await commitStatus(.inProgress)
            return true
        } catch {
            lastRequestChangesError = error.localizedDescription
            return false
        }
    }

    func clearRequestChangesError() {
        lastRequestChangesError = nil
    }

    func createIssueFromDraft() async throws {
        // The creating-init always builds an allocator, so the unwrap can
        // only bail in loaded mode — same silent no-op as the kind guard.
        guard case .creating = kind, let allocator else { return }
        let trimmedTitle = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { throw SaveError.emptyTitle }

        let slug = NextIssueAllocator.slugify(trimmedTitle)
        let title = trimmedTitle
        let type = typeDraft
        let labels = labelsDraft
        let blockedBy = blockedByDraft
        let status = statusDraft
        let prompt = bodyDraft
        let mutator = self.mutator
        let now = clock()

        let allocatedURL = try await Task.detached(priority: .userInitiated) {
            try allocator.allocate(
                slug: slug, title: title, type: type, labels: labels, prompt: prompt, now: now
            )
        }.value

        // Status defaults to .draft in the template — skip the mutator round-
        // trip when nothing beyond the template needs writing.
        var postMutation = FrontmatterMutation()
        if status != .draft { postMutation.status = .set(status) }
        if !blockedBy.isEmpty { postMutation.blockedBy = .set(blockedBy) }
        var postMutationError: Error?
        if postMutation.status != .keep || postMutation.blockedBy != .keep {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try mutator.mutate(
                        specURL: allocatedURL,
                        mutation: postMutation,
                        now: now
                    )
                }.value
            } catch {
                // Allocation already produced the folder on disk; still
                // transition to .loaded so the user sees the allocated issue
                // and can retry, then rethrow into the view's save alert.
                postMutationError = error
            }
        }

        specURL = allocatedURL
        let newFolderName = allocatedURL.deletingLastPathComponent().lastPathComponent
        kind = .loaded(folderName: newFolderName)
        // Seed prompt state pre-load so the Prompt tab renders the just-written
        // content immediately; load() only refreshes spec frontmatter/body.
        promptDraft = prompt
        loadedPromptContent = prompt
        await load()
        if let postMutationError { throw postMutationError }
    }

    private func runFormWrite(_ mutation: FrontmatterMutation) async throws {
        // Awaiting the prior spec write matters here: two pickers committing in
        // the same turn would otherwise read the same baseline and the second
        // would clobber the first.
        guard let url = specURL else { return }
        let prior = pendingSpecWrite
        let mutator = self.mutator
        let now = clock()
        let task = Task<Void, Error> {
            _ = try? await prior?.value
            try await Task.detached(priority: .userInitiated) {
                try mutator.mutate(specURL: url, mutation: mutation, now: now)
            }.value
        }
        pendingSpecWrite = task
        // Identity-checked reset: a newer write may have replaced the slot
        // while we awaited. Leaving the finished task in place permanently
        // disabled the external-change auto-reload (it gates on nil).
        defer {
            if pendingSpecWrite == task { pendingSpecWrite = nil }
        }
        try await task.value
        await reloadFromDiskAfterOwnWrite()
    }

    private func readNormalized(_ url: URL) async -> String? {
        await Task.detached(priority: .utility) {
            guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return raw.replacingOccurrences(of: "\r\n", with: "\n")
        }.value
    }

    private func parseFromDisk(_ url: URL) async -> ParsedSpec? {
        let folder = folderName ?? ""
        return await Task.detached(priority: .userInitiated) {
            guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return Self.parseSpec(rawContent: raw, folderName: folder)
        }.value
    }

    private func reloadFromDiskAfterOwnWrite() async {
        guard let url = specURL else { return }
        guard let parsed = await parseFromDisk(url) else { return }
        lastWrittenContent = parsed.content
        // Body could change if the user typed inside a form-write window;
        // keep the in-flight bodyDraft so we don't drop unsaved keystrokes.
        apply(parsed, keepBodyDraft: isBodyDirty)
    }

    func saveBody() async throws {
        guard isBodyDirty else { return }
        // Don't silently overwrite an unresolved external change: the user
        // has to pick Use-disk or Keep-mine via the banner first.
        if case .externalChange = conflict {
            throw SaveError.unresolvedConflict
        }
        guard let url = specURL else { return }
        let prior = pendingSpecWrite
        let bodyToSave = bodyDraft
        let mutator = self.mutator
        let now = clock()

        let task = Task<Void, Error> {
            _ = try? await prior?.value
            // Single atomic write: `updated:` stamp + body splice in one mutator
            // pass — two separate writes could leave the file with the new body
            // but a stale `updated:` on partial failure.
            try await Task.detached(priority: .userInitiated) {
                try mutator.mutate(
                    specURL: url,
                    mutation: FrontmatterMutation(body: .set(bodyToSave)),
                    now: now
                )
            }.value
        }
        pendingSpecWrite = task
        defer {
            if pendingSpecWrite == task { pendingSpecWrite = nil }
        }
        try await task.value

        if let parsed = await parseFromDisk(url) {
            lastWrittenContent = parsed.content
            // Auto-save fires mid-edit; applying the written body would drop
            // keystrokes typed during the write, so the draft stays untouched.
            apply(parsed, keepBodyDraft: true)
        }
    }

    func scheduleAutoSave() {
        guard !isCreating else { return }
        pendingAutoSave?.cancel()
        // Clear a stale "Saved" badge while the user is mid-edit. Change-guarded:
        // this runs per keystroke and an unguarded set invalidates the badge's
        // whole reader subtree every time.
        if autoSaveStatus != .idle { autoSaveStatus = .idle }
        pendingAutoSave = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.autoSaveDebounce)
            guard !Task.isCancelled else { return }
            await self?.performAutoSave()
        }
    }

    func autoSaveNow() async {
        pendingAutoSave?.cancel()
        pendingAutoSave = nil
        await performAutoSave()
    }

    var bodyTabBinding: Binding<BodyTab> {
        Binding(
            get: { self.selectedBodyTab },
            set: { newTab in
                // Flush the edited buffer before switching away from it.
                Task { [weak self] in await self?.autoSaveNow() }
                self.selectedBodyTab = newTab
            }
        )
    }

    private func performAutoSave() async {
        guard !isCreating else { return }
        // A blind write under an unresolved conflict would clobber the disk copy.
        if case .externalChange = conflict { return }
        // Skip a no-op debounce so it doesn't churn the badge.
        guard isBodyDirty || isPromptDirty else { return }
        autoSaveStatus = .saving
        var failure: String?
        do { try await saveBody() } catch { failure = error.localizedDescription }
        do { try await savePrompt() } catch { failure = error.localizedDescription }
        if let failure {
            Self.logger.warning("auto-save failed: \(failure, privacy: .public)")
            autoSaveStatus = .error(message: failure)
        } else {
            autoSaveStatus = .saved
        }
    }

    var isPromptDirty: Bool { promptDraft != loadedPromptContent }

    nonisolated static func defaultTab(for status: IssueStatus) -> BodyTab {
        switch status {
        case .draft: .prompt
        case .approved, .inProgress, .done, .blocked: .spec
        case .waitingForReview: .pullRequest
        }
    }

    func loadPrompt() async {
        guard let folder = folderName, let projectURL else { return }
        let url = IssueLayout.promptURL(in: projectURL, folderName: folder)
        let content = await readNormalized(url) ?? ""
        loadedPromptContent = content
        promptDraft = content
    }

    func savePrompt() async throws {
        guard isPromptDirty else { return }
        guard let folder = folderName, let projectURL else { return }
        let url = IssueLayout.promptURL(in: projectURL, folderName: folder)
        let prior = pendingPromptSave
        let contentToSave = promptDraft
        let writer = self.writer
        let task = Task<Void, Error> {
            _ = try? await prior?.value
            try await Task.detached(priority: .userInitiated) {
                try writer.write(contentToSave, to: url)
            }.value
        }
        pendingPromptSave = task
        try await task.value
        // Only bump the baseline — never overwrite promptDraft. The user may
        // have kept typing during the disk write; loadPrompt() would clobber
        // those trailing keystrokes (mirrors the body-save pattern).
        loadedPromptContent = contentToSave
    }

    func loadPR() async {
        guard let folder = folderName, let projectURL else {
            prContent = nil
            prBlocks = []
            return
        }
        let url = IssueLayout.prURL(in: projectURL, folderName: folder)
        // Read AND parse off-main so the markdown parse never runs on a view
        // body evaluation. Empty content yields no blocks (PRTabView shows the
        // empty state) while still recording prContent for state checks.
        let result: (content: String?, blocks: [PRMarkdownParser.Block]) =
            await Task.detached(priority: .utility) {
                guard let raw = try? String(contentsOf: url, encoding: .utf8) else {
                    return (nil, [])
                }
                let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")
                return (normalized, normalized.isEmpty ? [] : PRMarkdownParser.parse(normalized))
            }.value
        prContent = result.content
        prBlocks = result.blocks
    }

    func loadRunHistory(roots: [URL]) async {
        guard let folder = folderName else {
            runHistory = .empty
            return
        }
        runHistory = await Task.detached(priority: .utility) {
            RunHistoryReader.page(forSlug: folder, acrossRoots: roots)
        }.value
    }

    func loadEvidence() async {
        guard let folder = folderName, let projectURL else {
            evidence = .missing
            return
        }
        let url = IssueLayout.evidenceURL(in: projectURL, folderName: folder)
        evidence = await Task.detached(priority: .utility) { () -> EvidenceState in
            let data: Data
            do {
                data = try Data(contentsOf: url)
            } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
                return .missing
            } catch {
                return .unreadable(.unreadable(message: error.localizedDescription))
            }
            switch EvidenceParser.parse(data: data) {
            case .success(let evidence): return .loaded(evidence)
            case .failure(let error): return .unreadable(error)
            }
        }.value
        await refreshEvidenceStaleness()
    }

    func doneWhenBinding(at index: Int) -> Binding<Bool> {
        Binding(
            get: { [weak self] in
                guard let self, self.doneWhenCriteria.indices.contains(index) else { return false }
                return self.doneWhenCriteria[index].isChecked
            },
            set: { [weak self] newValue in
                Task { await self?.toggleDoneWhenCriterion(at: index, to: newValue) }
            }
        )
    }

    func toggleDoneWhenCriterion(at index: Int, to isChecked: Bool) async {
        if case .externalChange = conflict { return }
        guard let url = specURL else { return }
        let prior = pendingSpecWrite
        let task = Task<Void, Error> {
            _ = try? await prior?.value
            try await Task.detached(priority: .userInitiated) {
                try DoneWhenMutator.mutate(specURL: url, criterionIndex: index, isChecked: isChecked)
            }.value
        }
        pendingSpecWrite = task
        defer {
            if pendingSpecWrite == task { pendingSpecWrite = nil }
        }
        do {
            try await task.value
        } catch {
            autoSaveStatus = .error(message: "Could not update criterion: \(error)")
            return
        }
        // A dirty draft still holds the pre-tick checkbox; patch it so a later
        // auto-save doesn't write the tick back out of spec.md.
        if isBodyDirty {
            bodyDraft =
                (try? DoneWhenMutator.transform(
                    content: bodyDraft, criterionIndex: index, isChecked: isChecked)) ?? bodyDraft
        }
        await reloadFromDiskAfterOwnWrite()
    }

    private func refreshEvidenceStaleness() async {
        guard case .loaded(let loadedEvidence) = evidence,
            let reference = EvidenceStalenessReference.reference(for: loadedEvidence),
            let branch = loadedEvidence.branch ?? issue?.branch,
            let projectURL
        else {
            evidenceIsStale = false
            return
        }
        let count = await evidenceCommitCounter(projectURL, reference.head, branch)
        evidenceIsStale = count.map { reference.isStale(commitsAfterHead: $0) } ?? false
    }

    func observeKanban(currentIssue: DiscoveredIssue?) {
        // Cancel any in-flight observation so fast kanban-snapshot churn doesn't
        // race two concurrent disk reads writing the same fields. Owning the task
        // here means it dies with the model — no ghost writes after view pop.
        observeTask?.cancel()
        observeTask = Task { [weak self] in
            await self?.observeExternalChange(currentIssue: currentIssue)
            await self?.refreshReviewArtifacts()
        }
    }

    // The kanban snapshot pokes this model for every change in the issue's
    // folder (evidence stamp included), so PR.md and evidence.json stay live
    // without a watcher of their own.
    private func refreshReviewArtifacts() async {
        await loadPR()
        await loadEvidence()
    }

    func observeExternalChange(currentIssue: DiscoveredIssue?) async {
        if let currentIssue {
            if currentIssue == lastSeenIssue { return }
            noteSeenIssue(currentIssue)
        } else {
            noteSeenIssue(nil)
        }
        guard let url = specURL else { return }
        // Probe disk in both snapshot paths: the kanban can briefly show our folder
        // as missing during an optimistic archive/trash before the on-disk move runs,
        // so reading disk turns "snapshot says gone" into "disk confirms gone".
        if let normalized = await readNormalized(url) {
            if normalized == loadedSpecContent || normalized == lastWrittenContent { return }
            await handleExternalChange(diskContent: normalized)
        } else {
            await handleExternalChange(diskContent: nil)
        }
    }

    func handleExternalChange(diskContent: String?) async {
        guard let diskContent else {
            conflict = .fileDeleted
            return
        }
        let folder = folderName ?? ""
        let parsed = await Task.detached(priority: .userInitiated) {
            Self.parseSpec(rawContent: diskContent, folderName: folder)
        }.value
        // Dirtiness is checked after the parse hop on purpose: a keystroke
        // landing during the parse must flip this into the conflict branch,
        // not get overwritten by apply().
        if !isBodyDirty && pendingSpecWrite == nil {
            apply(parsed, keepBodyDraft: false)
            conflict = nil
        } else if parsed.content != loadedSpecContent {
            conflict = .externalChange(diskContent: parsed.content)
        }
    }

    func resolveConflictReload() {
        guard case .externalChange(let diskContent) = conflict else { return }
        applyLoaded(content: diskContent)
        conflict = nil
    }

    func resolveConflictKeep() {
        conflict = nil
    }

    var navigationTitle: String {
        if isCreating { return "New Issue" }
        return issue?.title ?? folderName ?? ""
    }

    func dirtyFolderName() -> String? {
        // Creating mode never has a folder yet; never report dirty.
        guard !isCreating else { return nil }
        guard isBodyDirty || isPromptDirty else { return nil }
        return folderName
    }

    func copyIDToPasteboard() {
        guard let folder = folderName else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(folder, forType: .string)
    }
}

nonisolated protocol SpecWriting: Sendable {
    func write(_ content: String, to url: URL) throws
}

nonisolated struct DefaultSpecWriter: SpecWriting {
    func write(_ content: String, to url: URL) throws {
        try SpecWriter.write(content, to: url)
    }
}

nonisolated protocol FrontmatterMutating: Sendable {
    func mutate(specURL: URL, mutation: FrontmatterMutation, now: Date) throws
}

nonisolated struct DefaultFrontmatterMutator: FrontmatterMutating {
    func mutate(specURL: URL, mutation: FrontmatterMutation, now: Date) throws {
        try FrontmatterMutator.mutate(specURL: specURL, mutation: mutation, now: now)
    }
}

nonisolated protocol IssueAllocating: Sendable {
    func allocate(
        slug: String,
        title: String,
        type: IssueType,
        labels: [String],
        prompt: String,
        now: Date
    ) throws -> URL
}

nonisolated struct DefaultIssueAllocator: IssueAllocating {
    let projectURL: URL

    func allocate(
        slug: String,
        title: String,
        type: IssueType,
        labels: [String],
        prompt: String,
        now: Date
    ) throws -> URL {
        try NextIssueAllocator(projectURL: projectURL).allocate(
            slug: slug,
            title: title,
            type: type,
            labels: labels,
            prompt: prompt,
            now: now
        )
    }
}
