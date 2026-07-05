import Foundation
import Observation

@MainActor
@Observable
final class GitInitModel {
    let repoURL: URL
    let projectName: String

    var plumageInGit = false
    var claudeInGit = false
    var createGitignore = true

    private(set) var isWorking = false
    private(set) var error: String?
    private(set) var didFinish = false

    private let service: GitInitService

    init(repoURL: URL, projectName: String, service: GitInitService = GitInitService()) {
        self.repoURL = repoURL
        self.projectName = projectName
        self.service = service
    }

    func submit() async {
        guard !isWorking else { return }
        error = nil
        isWorking = true
        defer { isWorking = false }
        do {
            // Compose before touching the repo so a missing asset fails fast.
            let gitignore = createGitignore ? try composeGitignore() : nil
            try await service.initializeRepo(
                at: repoURL, name: projectName,
                plumageInGit: plumageInGit, claudeInGit: claudeInGit)
            if let gitignore {
                let dest = repoURL.appendingPathComponent(".gitignore")
                if !FileManager.default.fileExists(atPath: dest.path) {
                    try? gitignore.write(to: dest, atomically: true, encoding: .utf8)
                }
            }
            didFinish = true
        } catch is CancellationError {
        } catch {
            self.error = Self.describe(error, fallback: "Couldn't initialize the repository.")
        }
    }

    // No stack is recorded for an existing project, so the generic default
    // (macOS block) is composed rather than a language-specific ignore.
    private func composeGitignore() throws -> String {
        try GitignoreComposer(overrides: ScaffoldOverrides.standard(), catalog: .bundledDefault)
            .compose(for: .other)
    }

    nonisolated static func describe(_ error: any Error, fallback: String) -> String {
        (error as? LocalizedError)?.errorDescription ?? fallback
    }
}
