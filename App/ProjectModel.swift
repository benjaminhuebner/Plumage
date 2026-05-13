import Foundation
import Observation

@Observable
@MainActor
final class ProjectModel {
    enum LoadState: Sendable {
        case loading
        case loaded(ProjectConfig)
        case failed(ConfigLoader.LoadError)
    }

    private(set) var state: LoadState = .loading
    private(set) var issues: [DiscoveredIssue] = []

    func reload(at url: URL) async {
        // Hop off MainActor: disk I/O (config + spec.md reads) plus YAML parsing
        // would otherwise block UI. computeLoad is nonisolated; detach is required to
        // run synchronously on a background executor. See notes.md (#00004-frontmatter-errors).
        let (newState, newIssues) = await Task.detached(priority: .userInitiated) {
            Self.computeLoad(at: url)
        }.value
        self.state = newState
        self.issues = newIssues
    }

    private nonisolated static func computeLoad(at url: URL) -> (LoadState, [DiscoveredIssue]) {
        do {
            let config = try ConfigLoader.load(at: url)
            let issues = IssueDiscovery.discoverIssues(in: url)
            return (.loaded(config), issues)
        } catch let error as ConfigLoader.LoadError {
            return (.failed(error), [])
        } catch {
            return (.failed(.invalidJSON(message: error.localizedDescription)), [])
        }
    }
}
