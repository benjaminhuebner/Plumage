import Foundation

nonisolated struct GitInitService {
    let gitInitRunner: any GitInitializing

    init(gitInitRunner: any GitInitializing = GitInitRunner()) {
        self.gitInitRunner = gitInitRunner
    }

    func initializeRepo(
        at root: URL, name: String, plumageInGit: Bool, claudeInGit: Bool
    ) async throws {
        try await gitInitRunner.initRepo(at: root, defaultBranch: "main")
        try ProjectGitHygiene.applyExcludes(
            name: name, plumageInGit: plumageInGit, claudeInGit: claudeInGit, root: root)
    }
}
