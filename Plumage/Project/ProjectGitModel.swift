import Foundation
import Observation

nonisolated struct BranchMergeRequest: Identifiable, Sendable, Hashable {
    let source: String
    let target: String
    var id: String { "\(source)->\(target)" }
}

@Observable
@MainActor
final class ProjectGitModel {
    private(set) var repoState: RepoState = .notARepo
    private(set) var branches: [String] = []
    private(set) var branchActionError: String?
    var pendingBranchMerge: BranchMergeRequest?
    private(set) var isMerging = false
    private(set) var lastMergeError: GitMergeError?
    private(set) var lastMergeNotice: String?

    @ObservationIgnored private var watcher: GitRepoStateWatcher?
    @ObservationIgnored private var consumeTask: Task<Void, Never>?
    @ObservationIgnored private var currentRepoURL: URL?
    @ObservationIgnored private let branchLister: GitBranchLister
    @ObservationIgnored private let checkoutRunner: GitCheckoutRunner
    @ObservationIgnored private let mergeRunner: any GitMergeRunning

    init(
        branchLister: GitBranchLister = GitBranchLister(),
        checkoutRunner: GitCheckoutRunner = GitCheckoutRunner(),
        mergeRunner: any GitMergeRunning = GitMergeRunner()
    ) {
        self.branchLister = branchLister
        self.checkoutRunner = checkoutRunner
        self.mergeRunner = mergeRunner
    }

    func loadBranches() async {
        guard let repoURL = currentRepoURL else { return }
        do {
            branches = try await branchLister.branches(repoURL: repoURL)
            branchActionError = nil
        } catch {
            branches = []
            branchActionError = error.localizedDescription
        }
    }

    func checkout(_ branch: String) async -> Bool {
        guard let repoURL = currentRepoURL else { return false }
        guard repoState.branchName != branch else { return true }
        do {
            try await checkoutRunner.checkout(repoURL: repoURL, branch: branch)
            branchActionError = nil
            // Optimistic: the .git/HEAD watcher re-emits with ~250 ms debounce.
            repoState = .branch(branch)
            return true
        } catch {
            branchActionError = error.localizedDescription
            return false
        }
    }

    func createBranch(_ name: String) async -> Bool {
        guard let repoURL = currentRepoURL else { return false }
        do {
            try await checkoutRunner.createBranch(repoURL: repoURL, name: name)
            branchActionError = nil
            repoState = .branch(name)
            return true
        } catch {
            branchActionError = error.localizedDescription
            return false
        }
    }

    func clearBranchActionError() {
        branchActionError = nil
    }

    func requestBranchMerge(source: String, target: String) {
        guard source != target else { return }
        guard branches.contains(source), branches.contains(target) else { return }
        lastMergeError = nil
        lastMergeNotice = nil
        pendingBranchMerge = BranchMergeRequest(source: source, target: target)
    }

    func mergeBranch(
        source: String, target: String, mode: GitMergeMode,
        subject: String?, deleteSource: Bool
    ) async -> Bool {
        guard let repoURL = currentRepoURL, source != target else { return false }
        isMerging = true
        defer { isMerging = false }
        lastMergeError = nil
        lastMergeNotice = nil
        do {
            let outcome = try await mergeRunner.mergeBranch(
                repoURL: repoURL, targetBranch: target, sourceBranch: source,
                mode: mode, commitSubject: subject, deleteBranch: deleteSource)
            if let cleanupNotice = outcome.worktreeCleanupNotice {
                lastMergeNotice = "Merge succeeded, but \(cleanupNotice)."
            } else if let deleteError = outcome.branchDeleteError {
                lastMergeNotice = "Merge succeeded, but branch was not deleted: \(deleteError)"
            }
            await loadBranches()
            return true
        } catch let error as GitMergeError {
            lastMergeError = error
            return false
        } catch {
            lastMergeError = .mergeFailed(mode: mode, stderr: error.localizedDescription)
            return false
        }
    }

    func clearMergeError() {
        lastMergeError = nil
    }

    func clearMergeNotice() {
        lastMergeNotice = nil
    }

    func start(repoURL: URL) {
        // Skip the no-op rebuild when the window is reused for the same
        // project — otherwise scenePhase changes would tear the watcher down
        // and up again, briefly emitting `.notARepo`.
        if currentRepoURL == repoURL, watcher != nil { return }
        stop()
        currentRepoURL = repoURL
        let watcher = GitRepoStateWatcher(repoURL: repoURL)
        self.watcher = watcher
        consumeTask = Task { [states = watcher.states] in
            for await state in states {
                if Task.isCancelled { return }
                self.repoState = state
            }
        }
    }

    func stop() {
        consumeTask?.cancel()
        consumeTask = nil
        watcher = nil
        currentRepoURL = nil
        repoState = .notARepo
        branches = []
        branchActionError = nil
        pendingBranchMerge = nil
        isMerging = false
        lastMergeError = nil
        lastMergeNotice = nil
    }

    // A `git init` in a folder the watcher armed as a non-repo is invisible to
    // its FSEvents stream (bound to an absent `.git`); rebuild it and read HEAD
    // synchronously so the menu flips without the debounce.
    func rescan(repoURL: URL) {
        stop()
        start(repoURL: repoURL)
        repoState = RepoStateReader().read(repoURL: repoURL)
    }

    func _setRepoURLForTesting(_ url: URL) {
        currentRepoURL = url
    }

    deinit {
        consumeTask?.cancel()
    }
}
