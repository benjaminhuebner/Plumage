import Foundation
import Observation

@Observable
@MainActor
final class ProjectGitModel {
    private(set) var repoState: RepoState = .notARepo

    @ObservationIgnored private var watcher: GitRepoStateWatcher?
    @ObservationIgnored private var consumeTask: Task<Void, Never>?
    @ObservationIgnored private var currentRepoURL: URL?

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
    }

    deinit {
        consumeTask?.cancel()
    }
}
