import Foundation
import Observation

@Observable
@MainActor
final class ProjectGitModel {
    private(set) var repoState: RepoState = .notARepo
    private(set) var branches: [String] = []
    private(set) var branchActionError: String?

    @ObservationIgnored private var watcher: GitRepoStateWatcher?
    @ObservationIgnored private var consumeTask: Task<Void, Never>?
    @ObservationIgnored private var currentRepoURL: URL?
    @ObservationIgnored private let branchLister: GitBranchLister
    @ObservationIgnored private let checkoutRunner: GitCheckoutRunner

    init(
        branchLister: GitBranchLister = GitBranchLister(),
        checkoutRunner: GitCheckoutRunner = GitCheckoutRunner()
    ) {
        self.branchLister = branchLister
        self.checkoutRunner = checkoutRunner
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
    }

    deinit {
        consumeTask?.cancel()
    }
}
