import Foundation

@MainActor
@Observable
final class DiffTabModel {
    enum State: Equatable {
        case idle
        case loading
        case empty
        case diff([FileDiff])
        case error(GitDiffError)
    }

    private(set) var state: State = .idle

    let repoURL: URL
    let baseBranch: String

    private let runner: GitDiffRunner
    private var loadTask: Task<Void, Never>?
    private var watcherTask: Task<Void, Never>?
    private let watcher: GitRepoWatcher?

    init(
        repoURL: URL,
        baseBranch: String = "main",
        runner: GitDiffRunner = GitDiffRunner(runner: ProductionGitProcessRunner()),
        watcher: GitRepoWatcher? = nil
    ) {
        self.repoURL = repoURL
        self.baseBranch = baseBranch
        self.runner = runner
        self.watcher = watcher
    }

    isolated deinit {
        loadTask?.cancel()
        watcherTask?.cancel()
    }

    func start() {
        observeWatcher()
        reload()
    }

    func stop() {
        loadTask?.cancel()
        loadTask = nil
        watcherTask?.cancel()
        watcherTask = nil
    }

    func reload() {
        // Cancel any in-flight load before starting a new one so a fast
        // succession of FSEvents pings doesn't pile up parallel diffs.
        loadTask?.cancel()
        let runner = self.runner
        let repo = self.repoURL
        let base = self.baseBranch
        state = .loading
        loadTask = Task { [weak self] in
            do {
                let rawDiff = try await runner.run(repoURL: repo, base: base)
                if Task.isCancelled { return }
                let parsed = DiffParser.parse(unifiedDiff: rawDiff)
                guard let self else { return }
                if parsed.isEmpty {
                    self.state = .empty
                } else {
                    self.state = .diff(parsed)
                }
            } catch is CancellationError {
                return
            } catch let error as GitDiffError {
                guard let self else { return }
                self.state = .error(error)
            } catch {
                guard let self else { return }
                self.state = .error(.spawnFailed(error.localizedDescription))
            }
        }
    }

    private func observeWatcher() {
        guard let watcher else { return }
        watcherTask?.cancel()
        watcherTask = Task { [weak self, events = watcher.events] in
            for await _ in events {
                guard let self else { return }
                self.reload()
            }
        }
    }
}
