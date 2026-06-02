import Foundation
import Observation

@Observable
@MainActor
final class GitCommitModel {
    enum LoadState: Sendable, Equatable {
        case loading
        case loaded
        case error(String)
    }

    enum CommitState: Sendable, Equatable {
        case idle
        case committing
        case done
        case error(String)
    }

    private(set) var files: [GitFileStatus] = []
    private(set) var loadState: LoadState = .loading
    var stagedPaths: Set<String> = []
    var selectedPath: String?
    var message: String = ""
    private(set) var diffPreview: [FileDiff] = []
    private(set) var commitState: CommitState = .idle

    let repoURL: URL
    private let statusRunner: any GitStatusRunning
    private let diffRunner: any GitWorkingDiffRunning
    private let stageRunner: any GitStaging
    private let commitRunner: any GitCommitting
    private let watcher: GitRepoWatcher?

    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var diffTask: Task<Void, Never>?
    @ObservationIgnored private var watcherTask: Task<Void, Never>?
    @ObservationIgnored private var didSeedStagedPaths = false
    // Monotonically incremented on every diff reload — same generation
    // guard as DiffTabModel so a stale per-file diff load can't clobber the
    // selection the user moved to in the meantime.
    @ObservationIgnored private var diffGeneration: UInt64 = 0

    init(
        repoURL: URL,
        statusRunner: any GitStatusRunning = GitStatusRunner(),
        diffRunner: any GitWorkingDiffRunning = GitWorkingDiffRunner(),
        stageRunner: any GitStaging = GitStageRunner(),
        commitRunner: any GitCommitting = GitCommitRunner(),
        watcher: GitRepoWatcher? = nil
    ) {
        self.repoURL = repoURL
        self.statusRunner = statusRunner
        self.diffRunner = diffRunner
        self.stageRunner = stageRunner
        self.commitRunner = commitRunner
        self.watcher = watcher
    }

    isolated deinit {
        loadTask?.cancel()
        diffTask?.cancel()
        watcherTask?.cancel()
    }

    func start() {
        observeWatcher()
        // Tracked so stop()/isolated deinit can cancel the initial load.
        loadTask = Task { await runRefreshFiles() }
    }

    func stop() {
        loadTask?.cancel()
        loadTask = nil
        diffTask?.cancel()
        diffTask = nil
        watcherTask?.cancel()
        watcherTask = nil
    }

    func toggleStaged(_ path: String) {
        if stagedPaths.contains(path) {
            stagedPaths.remove(path)
        } else {
            stagedPaths.insert(path)
        }
    }

    func selectFile(_ path: String?) {
        selectedPath = path
        reloadDiff()
    }

    var canCommit: Bool {
        if case .committing = commitState { return false }
        if message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
        return !stagedPaths.isEmpty
    }

    func refreshFiles() async {
        loadTask?.cancel()
        loadTask = Task {
            await runRefreshFiles()
        }
        await loadTask?.value
    }

    private func runRefreshFiles() async {
        // Only show the spinner on the initial load (or when recovering from
        // an error). FSEvent-triggered refreshes on an already-loaded view
        // run silently — otherwise a clean working tree flickers between
        // "Loading…" and "Nothing to commit" on every filesystem ping.
        if case .loaded = loadState {
            // keep current view, refresh in place
        } else {
            loadState = .loading
        }
        do {
            let fresh = try await statusRunner.run(repoURL: repoURL)
            if Task.isCancelled { return }
            files = fresh
            // Seed staged-paths from the index on the very first load only.
            // Subsequent refreshes (after an external edit) must preserve
            // the user's checkbox toggles, otherwise an unchecked file
            // would bounce right back on the next FSEvent-triggered
            // `.changed` ping. didSeedStagedPaths gates that — empty
            // stagedPaths after the seed means the user unchecked everything.
            if !didSeedStagedPaths {
                stagedPaths = Set(fresh.filter(\.isStaged).map(\.path))
                didSeedStagedPaths = true
            } else {
                // Drop entries that no longer appear in `files` (file got
                // committed/deleted externally). Do NOT re-add rows that the
                // index now lists as staged but the user previously unchecked.
                let pathsNow = Set(fresh.map(\.path))
                stagedPaths = stagedPaths.intersection(pathsNow)
            }
            // Keep the current selection if still present, otherwise pick
            // the first row (or nil for empty state).
            if let current = selectedPath, fresh.contains(where: { $0.path == current }) {
                // selection survives
            } else {
                selectedPath = fresh.first?.path
            }
            loadState = .loaded
            reloadDiff()
        } catch let error as GitStatusError {
            if Task.isCancelled { return }
            loadState = .error(error.displayMessage)
        } catch {
            if Task.isCancelled { return }
            loadState = .error(error.localizedDescription)
        }
    }

    private func reloadDiff() {
        guard let path = selectedPath else {
            diffPreview = []
            return
        }
        diffTask?.cancel()
        diffGeneration &+= 1
        let generation = diffGeneration
        let runner = diffRunner
        let repo = repoURL
        let staged = stagedPaths.contains(path)
        diffTask = Task { [weak self] in
            do {
                let raw: String
                // Pick the side the user is staging from: if the file is in
                // the stagedPaths set show the staged diff (what they're
                // about to commit), otherwise show the working-tree diff
                // (what they haven't staged yet).
                if staged {
                    raw = try await runner.diffStaged(repoURL: repo, path: path)
                } else {
                    raw = try await runner.diffWorking(repoURL: repo, path: path)
                }
                if Task.isCancelled { return }
                let parsed = DiffParser.parse(unifiedDiff: raw)
                guard let self, self.diffGeneration == generation else { return }
                self.diffPreview = parsed
            } catch is CancellationError {
                return
            } catch {
                // A per-file diff failure shouldn't blow up the whole sheet;
                // surface as an empty preview. The list still works.
                guard let self, self.diffGeneration == generation else { return }
                self.diffPreview = []
            }
        }
    }

    private func observeWatcher() {
        guard let watcher else { return }
        watcherTask?.cancel()
        watcherTask = Task { [weak self, events = watcher.events] in
            for await _ in events {
                guard let self else { return }
                await self.refreshFiles()
            }
        }
    }

    func commit() async {
        guard canCommit else { return }
        commitState = .committing
        let stagedPathsForCommit = stagedPaths.sorted()
        let messageForCommit = message
        do {
            try await stageRunner.stage(repoURL: repoURL, paths: stagedPathsForCommit)
            // Unstage anything that was indexed before but is not in the
            // stagedPaths set anymore — covers the user-unchecks-row case.
            // We only need to unstage rows that the index currently lists
            // as staged; otherwise `git reset HEAD --` would noop with a
            // confusing exit code on the path.
            let unstagePaths =
                files
                .filter { $0.isStaged && !stagedPaths.contains($0.path) }
                .map(\.path)
            if !unstagePaths.isEmpty {
                try await stageRunner.unstage(repoURL: repoURL, paths: unstagePaths)
            }
            try await commitRunner.commit(repoURL: repoURL, message: messageForCommit)
            commitState = .done
        } catch let error as GitStageError {
            commitState = .error(error.displayMessage)
        } catch let error as GitCommitError {
            commitState = .error(error.displayMessage)
        } catch {
            commitState = .error(error.localizedDescription)
        }
    }
}
